#!/usr/bin/env bash
# lint-hardware-features.sh — schema validation for the Layer-C Hardware
# Features Registry (platform-hardware-features.yaml) against the
# JSON Schema (schemas/hardware-features.schema.json).
#
# Per knowledge/decisions/0003-three-layer-capability-architecture.md §Decision Drivers D6
# and issue #61 Phase 4 ACs. Validates the Layer-C registry that survives the
# substrate-only ablation. Uses check-jsonschema (Python, draft 2020-12 capable).
#
# Usage:
#   scripts/lint-hardware-features.sh                # lint default registry file
#   scripts/lint-hardware-features.sh <file>         # lint an alternate file
#
# Exit codes:
#   0 — registry passes schema validation.
#   1 — at least one schema violation.
#   2 — environment / argument error.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY_FILE="${1:-$REPO_ROOT/platform-hardware-features.yaml}"
SCHEMA_FILE="$REPO_ROOT/schemas/hardware-features.schema.json"

case "${1:-}" in
  --help|-h)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

[ -f "$REGISTRY_FILE" ] || { echo "ERROR: registry not found: $REGISTRY_FILE" >&2; exit 2; }
[ -f "$SCHEMA_FILE" ] || { echo "ERROR: schema not found: $SCHEMA_FILE" >&2; exit 2; }

# id uniqueness gate. JSON Schema 2020-12 cannot express per-property
# uniqueness inside an array (the former `uniqueItemProperties` keyword is
# an AJV-only extension that check-jsonschema silently ignores), so the
# registry's lookup-by-id contract is enforced here. yq is a hard
# dependency of this gate (pinned in .tool-versions).
command -v yq >/dev/null 2>&1 || { echo "ERROR: 'yq' required for the duplicate-id gate" >&2; exit 2; }
dup_ids="$(yq -r '.hardware_features[].id' "$REGISTRY_FILE" | LC_ALL=C sort | uniq -d)"
if [ -n "$dup_ids" ]; then
  echo "ERROR: duplicate hardware_features ids (lookup is by id — ids must be unique):" >&2
  echo "$dup_ids" | sed 's/^/  /' >&2
  exit 1
fi

# Resolve check-jsonschema. Prefer a PATH binary (CI image installs it
# via pip). Fall back to `uvx --from check-jsonschema check-jsonschema`
# for local dev where the Python binary isn't installed system-wide.
if command -v check-jsonschema >/dev/null 2>&1; then
  RUNNER=(check-jsonschema)
elif command -v uvx >/dev/null 2>&1; then
  RUNNER=(uvx --from check-jsonschema check-jsonschema)
else
  echo "ERROR: neither check-jsonschema nor uvx found on PATH" >&2
  exit 2
fi

"${RUNNER[@]}" --schemafile "$SCHEMA_FILE" "$REGISTRY_FILE"
echo "OK: $(yq -r '.hardware_features | length' "$REGISTRY_FILE") hardware features pass schema"
