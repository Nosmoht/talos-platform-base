#!/usr/bin/env bash
# Bite-check for the two static fences that guard the Day-0 ArgoCD apply:
#   scripts/check-argocd-day0-apply-shape.sh   (A1 server-side, A2 no force, A3 guard)
#   scripts/check-render-determinism.sh        (#123 freeze, incl. the #218 PROJECTED shape)
#
# Why this exists. Both fences are static text analysis over main.tf, and the
# module has exactly ONE shape at a time — the compliant one. A fence that
# matched nothing, or matched the wrong block, would report OK on today's file
# forever and would be indistinguishable from a working one. During #218 that
# was not hypothetical twice over:
#
#   * the first version of check-render-determinism.sh accepted the projection
#     while a one-line `content = local.<projection>` handed the live,
#     non-byte-stable render straight to kubectl — the exact #121/#123 defect
#     the fence exists to prevent;
#   * a hand-run A3 check removed the FIRST precondition in the file (the
#     age-key one on a different resource) instead of the freeze's, so it
#     "passed" against a mutation that never touched the guarded block.
#
# So each scenario mutates a COPY of the real main.tf and asserts the fence's
# verdict. Following scripts/check-staleness-gate-bite.sh, three disciplines:
#
#   1. every scenario asserts its mutation actually changed the file before
#      reading a verdict, so it cannot pass because its setup silently failed;
#   2. every scenario asserts the ERROR MESSAGE, not just the exit code — both
#      fences emit one exit code for several distinct assertions, so an exit
#      check alone cannot tell which one bit (that is how the A3 mistake above
#      went unnoticed);
#   3. a control run over the UNMUTATED file must be green, so a fence that
#      fails on everything cannot be mistaken for a fence that discriminates.
#
# Mutating a copy of the real file rather than shipping frozen fixtures is
# deliberate: fixtures rot silently as main.tf evolves, and a rotted fixture
# tests the fence against a module that no longer exists. Both fences already
# take the file as an argument, so no test-only code path is added to them.
#
# Runs offline, mutates nothing outside its temp dir. Wired into `task tofu:ci`.
#
# Exit codes:
#   0  every fence bit exactly where it should, and stayed quiet where it should
#   1  a fence regressed (or a scenario's setup broke)
#   2  environment error (a fence or the module is missing)
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
src="${repo_root}/tofu/modules/talos-cluster/main.tf"
shape_gate="${repo_root}/scripts/check-argocd-day0-apply-shape.sh"
det_gate="${repo_root}/scripts/check-render-determinism.sh"

for f in "$src" "$shape_gate" "$det_gate"; do
  [ -f "$f" ] || { echo "ERROR: $f missing" >&2; exit 2; }
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

rc=0

# ---------------------------------------------------------------- mutators --
# Each takes the copy's path, edits it in place, and returns non-zero only on an
# internal error; "did it change anything" is asserted by the caller.

# Re-add the flag whose removal is the point of #218.
mut_force_conflicts() {
  perl -0pi -e 's/(command\s*=\s*"kubectl apply --server-side)/$1 --force-conflicts/' "$1"
}

# Turn the server-side apply into a client-side one.
mut_client_side() {
  perl -0pi -e 's/(command\s*=\s*"kubectl apply) --server-side/$1/' "$1"
}

# Delete the precondition block belonging to the CRD FREEZE specifically —
# not merely the first precondition in the file, which lives on another
# resource entirely and is the mistake this scenario is calibrated against.
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

# Keep the precondition, but point its condition at something that is not the
# projection — the "guard in name only" regression. Hits the FIRST condition in
# the freeze, i.e. the by-name completeness guard; the exclusivity one survives,
# which is what makes this a discriminating scenario rather than a blunt one.
mut_hollow_freeze_condition() {
  perl -0pi -e 's/(resource "terraform_data" "argocd_crds_render".*?condition\s+= )[^\n]*/${1}var.deploy_argocd/s' "$1"
}

# Delete the plan-time exclusivity guard while leaving the by-name one intact.
# Buffer each precondition block and drop only the one mentioning
# argocd_crd_kinds — a regex cannot do this cleanly because the error_message
# strings carry `${jsonencode(...)}` interpolation braces.
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

# Break the #123 freeze on the CRD render.
mut_drop_ignore_changes() {
  perl -0pi -e 's/(resource "terraform_data" "argocd_crds_render".*?)^\s*ignore_changes\s*=\s*\[input\]\n/$1/ms' "$1"
}

# Remove the re-apply trigger: an intended chart bump would silently never apply.
mut_drop_triggers_replace() {
  perl -0pi -e 's/(resource "terraform_data" "argocd_crds_render".*?)^\s*triggers_replace\s*=\s*\[.*?\n\s*\]\n/$1/ms' "$1"
}

# The #218 bypass, shape 1: hand the live projection to a file sink, skipping the
# freeze. One line, passes every other check, reinstates the #121 drift.
mut_sink_content() {
  printf '\nresource "local_file" "bite_bypass" {\n  content  = local.argocd_crd_manifest\n  filename = "/tmp/bite"\n}\n' >> "$1"
}

# The #218 bypass, shape 2: same, via the re-apply trigger hash.
mut_sink_sha256() {
  printf '\nresource "null_resource" "bite_bypass" {\n  triggers = {\n    h = sha256(local.argocd_crd_manifest)\n  }\n}\n' >> "$1"
}

# The #218 bypass, shape 3 — INDIRECT: freeze the live projection in a second
# terraform_data that is not the sanctioned freeze, then read ITS output from a
# sink. No sink line mentions `local.`, so a one-hop scan does not see it. This
# is the fence's real boundary; without a scenario it stays unmeasured.
mut_sink_indirect_freeze() {
  printf '\nresource "terraform_data" "bite_bypass_freeze" {\n  input = local.argocd_crd_manifest\n}\n\nresource "local_file" "bite_bypass_indirect" {\n  content  = terraform_data.bite_bypass_freeze.output\n  filename = "/tmp/bite-indirect"\n}\n' >> "$1"
}

# Remove the dedicated field manager, so kubectl records the generic `kubectl`.
mut_drop_field_manager() {
  perl -0pi -e 's/ --field-manager=[^ "]+//' "$1"
}

# Point the field manager back at the generic default it exists to replace.
mut_generic_field_manager() {
  perl -0pi -e 's/--field-manager=[^ "]+/--field-manager=kubectl/' "$1"
}

# Delete the kind filter from the projection. The payload becomes the full
# twelve-kind chart render while the by-name precondition — a containment test —
# still passes. This is the #218 defect itself, and until A5 existed every
# blocking gate stayed green on it.
mut_drop_kind_filter() {
  perl -0pi -e 's/\n\s*doc if try\(yamldecode\(doc\)\.kind, ""\) == "CustomResourceDefinition"/\n    doc/' "$1"
}

# Put kubernetes_version back into the re-apply trigger set.
mut_readd_kubernetes_version_trigger() {
  perl -0pi -e 's/(resource "terraform_data" "argocd_crds_render".*?triggers_replace = \[\n)/${1}    var.kubernetes_version,\n/s' "$1"
}

# ---------------------------------------------------------------- scenarios --
# scenario <gate> <expected-exit> <expected-output-pattern> <mutator|-> <label>
scenario() {
  local gate="$1" want_exit="$2" pattern="$3" mutator="$4" label="$5"
  local copy="${work}/main.tf" out got=0

  cp "$src" "$copy"
  if [ "$mutator" != "-" ]; then
    "$mutator" "$copy"
    if cmp -s "$src" "$copy"; then
      echo "  SETUP BROKEN: ${mutator} changed nothing — the anchor it edits moved in main.tf"
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
  "apply-shape fence passes the real main.tf"
scenario "$det_gate" 0 "check-render-determinism: OK" - \
  "render-determinism fence passes the real main.tf"

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
# Patterns name the RESOURCE, not just the symptom. main.tf carries three
# `ignore_changes = [input]` blocks, so a mutation that hit the wrong freeze
# would still match a resource-agnostic pattern and report a false PASS — the
# same mis-anchoring class this file was written to catch.
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
