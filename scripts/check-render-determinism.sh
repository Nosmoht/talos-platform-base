#!/usr/bin/env bash
# Require every live Helm render to flow through its state-backed freeze.
# Usage: scripts/check-render-determinism.sh [module-directory|file.tf]
# Checks triggers_replace presence, not completeness of its render-affecting inputs.
set -euo pipefail

MAIN="${1:-tofu/modules/talos-cluster}"

if [ -d "$MAIN" ]; then
  source_file="$(mktemp)"
  trap 'rm -f "$source_file"' EXIT
  cat "$MAIN"/*.tf > "$source_file"
  MAIN="$source_file"
fi

if [ ! -f "$MAIN" ]; then
  echo "::error::check-render-determinism: ${MAIN} not found" >&2
  exit 1
fi

block_of() {
  awk -v name="$1" '
    index($0, "resource \"terraform_data\" \"" name "\"") == 1 { inb = 1 }
    inb { print }
    inb && /^}/ { inb = 0 }
  ' "$MAIN"
}

# Top-level HCL blocks must start and end at column zero.
ref_inside_locals() {
  awk -v pat="$1" '
    /^[[:space:]]*#/              { next }
    /^locals[[:space:]]*\{/       { inloc = 1; next }
    /^[a-z][a-zA-Z_]*[[:space:]]/ { inloc = 0 }
    /^}/                          { inloc = 0; next }
    index($0, pat) > 0            { print (inloc ? "yes" : "no"); exit }
  ' "$MAIN"
}

locals_names() {
  awk '
    /^[[:space:]]*#/              { next }
    /^locals[[:space:]]*\{/       { inloc = 1; next }
    /^}/                          { inloc = 0; next }
    inloc && match($0, /^[[:space:]]+[a-z_][a-zA-Z0-9_]*[[:space:]]*=/) {
      s = $0; sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]*=.*$/, "", s); print s
    }
  ' "$MAIN"
}

lines_outside_locals() {
  awk '
    /^[[:space:]]*#/              { next }
    /^locals[[:space:]]*\{/       { inloc = 1; next }
    /^}/                          { if (inloc) { inloc = 0; next } }
    !inloc                        { print }
  ' "$MAIN"
}

fail=0

renders=$(grep -oE 'data "helm_template" "[a-z_]+"' "$MAIN" | sed -E 's/.*"([a-z_]+)"$/\1/' | sort -u)
if [ -z "$renders" ]; then
  echo "::error::check-render-determinism: no data \"helm_template\" found in ${MAIN} — fence assumptions broken (did the module move?)." >&2
  exit 1
fi

count=0
for r in $renders; do
  count=$((count + 1))

  # Allow one live read: directly into the freeze, or through a captured local projection.
  total=$(grep -cE "data\.helm_template\.${r}\[0\]\.manifest" "$MAIN" || true)
  capture=$(grep -cE "^[[:space:]]*input[[:space:]]+= data\.helm_template\.${r}\[0\]\.manifest" "$MAIN" || true)
  blk=$(block_of "${r}_render")
  projected=0
  if [ "$capture" -eq 0 ] && [ "$total" -eq 1 ] && [ -n "$blk" ] &&
    [ "$(ref_inside_locals "data.helm_template.${r}[0].manifest")" = "yes" ] &&
    printf '%s\n' "$blk" | grep -qE '^[[:space:]]*input[[:space:]]+= local\.'; then
    projected=1
  fi

  # A projected render must have no consumers that bypass the freeze.
  if [ "$projected" -eq 1 ]; then
    outside="$(lines_outside_locals)"
    while IFS= read -r lname; do
      [ -n "$lname" ] || continue
      if printf '%s\n' "$outside" |
        grep -E '(content[s]?[[:space:]]*=|command[[:space:]]*=|sha256\()' |
        grep -qE "local\.${lname}([^a-zA-Z0-9_]|\$)"; then
        echo "::error::check-render-determinism: local.${lname} — which may derive from the live data.helm_template.${r} render — reaches an apply-path sink (content/contents/command/sha256) outside the locals block. Every apply-path consumer must read terraform_data.${r}_render[0].output instead, or the non-byte-stable render is re-pushed on every plan (#121/#123)." >&2
        fail=1
      fi
    done <<EOF
$(locals_names)
EOF

    # Reject captures by another freeze: only the matching render resource is checked.
    while IFS= read -r cap; do
      [ -n "$cap" ] || continue
      [ "$cap" = "${r}_render" ] && continue
      echo "::error::check-render-determinism: resource terraform_data.${cap} captures a locals value derived from the live data.helm_template.${r} render via input =. That value may be captured only by terraform_data.${r}_render — a second freeze is an indirect apply-path sink: its .output reaches kubectl without ever passing the sanctioned freeze (#121/#123)." >&2
      fail=1
    done <<EOF
$(awk '
    /^resource "terraform_data" "/ { name = $0; sub(/^resource "terraform_data" "/, "", name); sub(/".*$/, "", name); inb = 1; next }
    inb && /^[[:space:]]*input[[:space:]]+= local\./ { print name }
    inb && /^}/ { inb = 0 }
  ' "$MAIN")
EOF
  fi

  if [ "$total" -ne 1 ] || { [ "$capture" -ne 1 ] && [ "$projected" -ne 1 ]; }; then
    echo "::error::check-render-determinism: data.helm_template.${r} must be referenced exactly once — either as the input= capture of terraform_data.${r}_render, or once inside a locals{} block whose value that freeze captures via input = local.* (found total=${total}, capture=${capture}, projected=${projected}). A direct consumer (contents=/content=/sha256()) or an unmatched reference shape re-introduces the #123 machineConfig re-push — route it through terraform_data.${r}_render[0].output." >&2
    fail=1
  fi

  if [ -z "$blk" ]; then
    echo "::error::check-render-determinism: freeze resource terraform_data.${r}_render is missing in ${MAIN} (#123)." >&2
    fail=1
    continue
  fi
  if ! printf '%s\n' "$blk" | grep -qE '^[[:space:]]*ignore_changes[[:space:]]*=[[:space:]]*\[input\]'; then
    echo "::error::check-render-determinism: terraform_data.${r}_render block lacks lifecycle { ignore_changes = [input] } — the freeze is broken and the render would re-capture every plan (#123)." >&2
    fail=1
  fi

  case "$r" in
    *crds*)
      if ! printf '%s\n' "$blk" | grep -qE '^[[:space:]]*triggers_replace[[:space:]]*='; then
        echo "::error::check-render-determinism: terraform_data.${r}_render (a Day-2 CRD kubectl-apply path) must carry triggers_replace so an intended chart/version bump re-applies; without it an intended bump silently never re-applies (#123)." >&2
        fail=1
      fi
      ;;
  esac
done

if [ "$fail" -eq 0 ]; then
  echo "check-render-determinism: OK — ${count} helm render(s) consumed only via frozen terraform_data (ignore_changes); CRD render(s) carry triggers_replace."
fi
exit "$fail"
