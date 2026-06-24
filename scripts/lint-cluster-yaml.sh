#!/usr/bin/env bash
# lint-cluster-yaml.sh — schema validation for a consumer cluster.yaml against
# the JSON Schema (docs/schemas/cluster.schema.json).
#
# Per issue #136 Task 3 (ADR base:node-capability-composition §"Schema parity
# decisions" #1 deferred the enforcing schema to implementation). Mirrors
# lint-hardware-features.sh. The base ships no cluster.yaml (gitignored) — only
# cluster.yaml.example — so that is the default target; consumer repos point this
# at their committed cluster.yaml. Uses check-jsonschema (Python, draft 2020-12).
#
# The default target ends in .example (not .yaml), so check-jsonschema cannot
# infer the filetype — this script always passes --default-filetype yaml.
#
# Usage:
#   scripts/lint-cluster-yaml.sh                # lint cluster.yaml.example
#   scripts/lint-cluster-yaml.sh <file>         # lint an alternate cluster.yaml
#
# Exit codes:
#   0 — file passes schema validation.
#   1 — at least one schema violation.
#   2 — environment / argument error.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_FILE="${1:-$REPO_ROOT/cluster.yaml.example}"
SCHEMA_FILE="$REPO_ROOT/docs/schemas/cluster.schema.json"

case "${1:-}" in
  --help|-h)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

[ -f "$CLUSTER_FILE" ] || { echo "ERROR: cluster file not found: $CLUSTER_FILE" >&2; exit 2; }
[ -f "$SCHEMA_FILE" ] || { echo "ERROR: schema not found: $SCHEMA_FILE" >&2; exit 2; }

# Resolve check-jsonschema. Prefer a PATH binary (CI image installs it via pip);
# fall back to `uvx --from check-jsonschema check-jsonschema` for local dev where
# the Python binary isn't installed system-wide.
if command -v check-jsonschema >/dev/null 2>&1; then
  RUNNER=(check-jsonschema)
elif command -v uvx >/dev/null 2>&1; then
  RUNNER=(uvx --from check-jsonschema check-jsonschema)
else
  echo "ERROR: neither check-jsonschema nor uvx found on PATH" >&2
  exit 2
fi

"${RUNNER[@]}" --default-filetype yaml --schemafile "$SCHEMA_FILE" "$CLUSTER_FILE"

# Summary line (best-effort: skip if yq is unavailable — validation already passed).
if command -v yq >/dev/null 2>&1; then
  echo "OK: $CLUSTER_FILE passes schema ($(yq -r '.nodes | length' "$CLUSTER_FILE") nodes, $(yq -r '.images | length' "$CLUSTER_FILE") images)"
else
  echo "OK: $CLUSTER_FILE passes schema"
fi
