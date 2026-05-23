#!/usr/bin/env bash
# check-role-patches-field.sh — CI gate for the Direction-A invariants
# of issue #69. Exits 0 if all checks pass, non-zero otherwise.
# See talos/AGENTS.md §"Role-spec patches field" and
# talos/RELEASE-NOTES-v0.5.3.md for context.
set -euo pipefail

cd "$(dirname "$0")/../.."
ROOT="$(pwd)"

err() { echo "FAIL: $1" >&2; exit 1; }

# (1) Schema: $defs.role-spec has 'patches', NOT 'default_patches',
#     and additionalProperties=false
yq -e '."$defs"."role-spec".properties | has("patches")' \
  "${ROOT}/talos/schemas/cluster.schema.json" >/dev/null \
  || err "schema: \$defs.role-spec.properties.patches missing (see talos/AGENTS.md §\"Role-spec patches field\")"
yq -e '."$defs"."role-spec".properties | has("default_patches") | not' \
  "${ROOT}/talos/schemas/cluster.schema.json" >/dev/null \
  || err "schema: \$defs.role-spec.properties.default_patches still declared (see talos/RELEASE-NOTES-v0.5.3.md)"
yq -e '."$defs"."role-spec".additionalProperties == false' \
  "${ROOT}/talos/schemas/cluster.schema.json" >/dev/null \
  || err "schema: \$defs.role-spec.additionalProperties is not false"

# (2) cluster.yaml.example: no default_patches anywhere; every role has
#     non-empty patches
yq -e '.roles | to_entries | map(.value | has("default_patches")) | any | not' \
  "${ROOT}/talos/test/cluster.yaml.example" >/dev/null \
  || err "cluster.yaml.example: a role still declares default_patches"
for r in controlplane worker gpu-worker; do
  yq -e ".roles.${r}.patches | length > 0" \
    "${ROOT}/talos/test/cluster.yaml.example" >/dev/null \
    || err "cluster.yaml.example: role '${r}' has no non-empty patches array"
done

# (3) Source sweep: no deprecated field name under talos/scripts/ or talos/test/
#     EXCLUDING talos/test/regressions/ (mutation fixtures contain the
#     string by design — see §6/§7 in the plan) and this script itself
#     (which contains the pattern in comments and checks).
DEPRECATED_FIELD="default""_patches"
THIS_SCRIPT="$(basename "$0")"
if grep -lrE \
     --exclude-dir=regressions \
     --exclude="${THIS_SCRIPT}" \
     "${DEPRECATED_FIELD}" \
     "${ROOT}/talos/scripts/" "${ROOT}/talos/test/" >/dev/null 2>&1; then
  echo "FAIL: '${DEPRECATED_FIELD}' still appears under talos/scripts/ or talos/test/ (excluding mutation regressions and this script):" >&2
  grep -lrE --exclude-dir=regressions --exclude="${THIS_SCRIPT}" "${DEPRECATED_FIELD}" \
    "${ROOT}/talos/scripts/" "${ROOT}/talos/test/" >&2
  exit 1
fi

# (4) AGENTS.md carries a 'Role-spec patches field' section AND its body
#     mentions the canonical name 'patches'
grep -cE '^## .*[Rr]ole-spec patches' "${ROOT}/talos/AGENTS.md" >/dev/null \
  || err "talos/AGENTS.md: '## Role-spec patches field' section missing"
awk '/^## .*[Rr]ole-spec patches/{flag=1;next} flag && /^## /{exit} flag' \
  "${ROOT}/talos/AGENTS.md" | grep -qE '\bpatches\b' \
  || err "talos/AGENTS.md: 'Role-spec patches field' section body does not mention canonical name 'patches'"

echo "OK: role-patches canonical invariants hold"
