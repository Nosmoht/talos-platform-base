#!/usr/bin/env bash
# lint-hardware-features.sh — schema validation for the Layer-C Hardware
# Features Registry (docs/platform-hardware-features.yaml) against the
# JSON Schema (docs/schemas/hardware-features.schema.json).
#
# Per docs/adr-three-layer-capability-architecture.md §Decision Drivers D6
# and issue #61 Phase 4 ACs. Sibling to lint-capability-index.sh
# (Layer A). Uses check-jsonschema (Python, draft 2020-12 capable).
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
REGISTRY_FILE="${1:-$REPO_ROOT/docs/platform-hardware-features.yaml}"
SCHEMA_FILE="$REPO_ROOT/docs/schemas/hardware-features.schema.json"

case "${1:-}" in
  --help|-h)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

[ -f "$REGISTRY_FILE" ] || { echo "ERROR: registry not found: $REGISTRY_FILE" >&2; exit 2; }
[ -f "$SCHEMA_FILE" ] || { echo "ERROR: schema not found: $SCHEMA_FILE" >&2; exit 2; }

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
