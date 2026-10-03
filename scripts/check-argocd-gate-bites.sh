#!/usr/bin/env bash
# Mutate temporary module copies and assert each fence’s diagnostic and exit code.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
module_dir="${repo_root}/tofu/modules/talos-cluster"
shape_gate="${repo_root}/scripts/check-argocd-day0-apply-shape.sh"
det_gate="${repo_root}/scripts/check-render-determinism.sh"

for f in "$module_dir/main.tf" "$shape_gate" "$det_gate"; do
  [ -f "$f" ] || { echo "ERROR: $f missing" >&2; exit 2; }
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
src="${work}/module.tf"
cat "$module_dir"/*.tf > "$src"

rc=0

mut_force_conflicts() {
  perl -0pi -e 's/(command\s*=\s*"kubectl apply --server-side)/$1 --force-conflicts/' "$1"
}

mut_client_side() {
  perl -0pi -e 's/(command\s*=\s*"kubectl apply) --server-side/$1/' "$1"
}

mut_drop_freeze_precondition() {
  awk '
    index($0, "resource \"terraform_data\" \"argocd_crds_render\"") == 1 { inb = 1 }
    inb && /^[[:space:]]*precondition[[:space:]]*\{/ { inpre = 1; depth = 1; next }
    inpre {
      n = gsub(/\{/, "{"); depth += n
      n = gsub(/\}/, "}"); depth -= n
      if (depth <= 0) { inpre = 0 }
      next
    }
    { print }
    inb && /^\}/ { inb = 0 }
  ' "$1" > "$1.next" && mv "$1.next" "$1"
}

mut_hollow_freeze_condition() {
  perl -0pi -e 's/(resource "terraform_data" "argocd_crds_render".*?condition\s+= )[^\n]*/${1}var.deploy_argocd/s' "$1"
}

# Buffer each precondition and track braces to remove only the exclusivity guard.
mut_drop_exclusivity_precondition() {
  awk '
    index($0, "resource \"terraform_data\" \"argocd_crds_render\"") == 1 { inb = 1 }
    inb && /^[[:space:]]*precondition[[:space:]]*\{/ {
      inpre = 1; depth = 1; buf = $0 ORS; hit = 0; next
    }
    inpre {
      buf = buf $0 ORS
      if (index($0, "argocd_crd_kinds") > 0) { hit = 1 }
      n = gsub(/\{/, "{"); depth += n
      n = gsub(/\}/, "}"); depth -= n
      if (depth <= 0) { inpre = 0; if (!hit) printf "%s", buf }
      next
    }
    { print }
    inb && /^\}/ { inb = 0 }
  ' "$1" > "$1.next" && mv "$1.next" "$1"
}

mut_drop_ignore_changes() {
  perl -0pi -e 's/(resource "terraform_data" "argocd_crds_render".*?)^\s*ignore_changes\s*=\s*\[input\]\n/$1/ms' "$1"
}

mut_drop_triggers_replace() {
  perl -0pi -e 's/(resource "terraform_data" "argocd_crds_render".*?)^\s*triggers_replace\s*=\s*\[.*?\n\s*\]\n/$1/ms' "$1"
}

mut_sink_content() {
  printf '\nresource "local_file" "bite_bypass" {\n  content  = local.argocd_crd_manifest\n  filename = "/tmp/bite"\n}\n' >> "$1"
}

mut_sink_sha256() {
  printf '\nresource "null_resource" "bite_bypass" {\n  triggers = {\n    h = sha256(local.argocd_crd_manifest)\n  }\n}\n' >> "$1"
}

mut_sink_indirect_freeze() {
  printf '\nresource "terraform_data" "bite_bypass_freeze" {\n  input = local.argocd_crd_manifest\n}\n\nresource "local_file" "bite_bypass_indirect" {\n  content  = terraform_data.bite_bypass_freeze.output\n  filename = "/tmp/bite-indirect"\n}\n' >> "$1"
}

mut_drop_field_manager() {
  perl -0pi -e 's/ --field-manager=[^ "]+//' "$1"
}

mut_generic_field_manager() {
  perl -0pi -e 's/--field-manager=[^ "]+/--field-manager=kubectl/' "$1"
}

mut_drop_kind_filter() {
  perl -0pi -e 's/\n\s*doc if try\(yamldecode\(doc\)\.kind, ""\) == "CustomResourceDefinition"/\n    doc/' "$1"
}

mut_readd_kubernetes_version_trigger() {
  perl -0pi -e 's/(resource "terraform_data" "argocd_crds_render".*?triggers_replace = \[\n)/${1}    var.kubernetes_version,\n/s' "$1"
}

# scenario <gate> <expected-exit> <expected-output-pattern> <mutator|-> <label>
scenario() {
  local gate="$1" want_exit="$2" pattern="$3" mutator="$4" label="$5"
  local copy="${work}/main.tf" out got=0

  cp "$src" "$copy"
  if [ "$mutator" != "-" ]; then
    "$mutator" "$copy"
    if cmp -s "$src" "$copy"; then
      echo "  SETUP BROKEN: ${mutator} changed nothing — the anchor it edits moved in the module"
      rc=1
      return
    fi
  fi

  out="$(cd "$work" && bash "$gate" "$copy" 2>&1)" || got=$?

  if [ "$got" != "$want_exit" ]; then
    echo "  FAIL  ${label} (exit ${got}, expected ${want_exit})"
    printf '%s\n' "$out" | sed 's/^/          /'
    rc=1
    return
  fi
  if ! printf '%s\n' "$out" | grep -qF "$pattern"; then
    echo "  FAIL  ${label} (exit ${got} as expected, but no '${pattern}' in the output)"
    printf '%s\n' "$out" | sed 's/^/          /'
    rc=1
    return
  fi
  echo "  PASS  ${label}"
}

echo "== controls: both fences green on the unmutated module =="
scenario "$shape_gate" 0 "check-argocd-day0-apply-shape: OK" - \
  "apply-shape fence passes the module source"
scenario "$det_gate" 0 "check-render-determinism: OK" - \
  "render-determinism fence passes the module source"

# A scan confined to the render's file must not miss a consumer in a sibling file.
mkdir "$work/split"
cp "$module_dir"/*.tf "$work/split/"
out="$(bash "$det_gate" "$work/split" 2>&1)" || rc=1
if ! printf '%s\n' "$out" | grep -qF 'check-render-determinism: OK'; then
  printf '  FAIL  directory control\n%s\n' "$out"
  rc=1
else
  echo '  PASS  render-determinism scans the split module'
fi
mut_sink_content "$work/split/bypass.tf"
got=0
out="$(bash "$det_gate" "$work/split" 2>&1)" || got=$?
if [ "$got" -eq 1 ] && printf '%s\n' "$out" | grep -qF 'reaches an apply-path sink'; then
  echo '  PASS  a projection consumer in a sibling file is rejected'
else
  printf '  FAIL  sibling-file bypass (exit %s)\n%s\n' "$got" "$out"
  rc=1
fi

echo "== check-argocd-day0-apply-shape =="
scenario "$shape_gate" 3 "A1 —" mut_client_side \
  "A1 bites when the apply stops being server-side"
scenario "$shape_gate" 3 "A2 —" mut_force_conflicts \
  "A2 bites when --force-conflicts comes back"
scenario "$shape_gate" 3 "carries no precondition" mut_drop_freeze_precondition \
  "A3 bites when the FREEZE's precondition is deleted"
scenario "$shape_gate" 3 "no precondition referencing local.argocd_crd_names" mut_hollow_freeze_condition \
  "A3 bites when the by-name guard is hollowed out, even though the sibling precondition survives"
scenario "$shape_gate" 3 "no precondition referencing local.argocd_crd_kinds" mut_drop_exclusivity_precondition \
  "A3 bites when the plan-time exclusivity guard is deleted"
scenario "$shape_gate" 3 "A4 — the Day-0 apply names no --field-manager" mut_drop_field_manager \
  "A4 bites when the dedicated field manager is removed"
scenario "$shape_gate" 3 "A4 — the Day-0 apply passes --field-manager=kubectl" mut_generic_field_manager \
  "A4 bites when the field manager is the generic default"
scenario "$shape_gate" 3 "A5 — the CRD projection no longer filters" mut_drop_kind_filter \
  "A5 bites when the projection stops filtering on kind (the #218 defect itself)"
scenario "$shape_gate" 3 "A6 — triggers_replace names kubernetes_version" mut_readd_kubernetes_version_trigger \
  "A6 bites when a Kubernetes bump would re-fire the apply again"

echo "== check-render-determinism =="
# Match the resource-specific diagnostic so an unrelated failure cannot satisfy the scenario.
scenario "$det_gate" 1 "reaches an apply-path sink" mut_sink_content \
  "the projection cannot be handed to a content= sink"
scenario "$det_gate" 1 "reaches an apply-path sink" mut_sink_sha256 \
  "the projection cannot be handed to a sha256() trigger"
scenario "$det_gate" 1 "may be captured only by terraform_data.argocd_crds_render" mut_sink_indirect_freeze \
  "the projection cannot be laundered through a second, unsanctioned freeze"
scenario "$det_gate" 1 "terraform_data.argocd_crds_render block lacks lifecycle" mut_drop_ignore_changes \
  "a broken freeze is caught, on the right resource"
scenario "$det_gate" 1 "terraform_data.argocd_crds_render (a Day-2 CRD kubectl-apply path) must carry triggers_replace" mut_drop_triggers_replace \
  "a deleted re-apply trigger is caught, on the right resource"

if [ "$rc" = 0 ]; then
  echo "argocd gate bite-check OK: both fences bite on every regression above and stay quiet on the real module"
else
  echo "ERROR: argocd gate bite-check — a fence no longer catches the regression it exists for" >&2
fi
exit "$rc"
