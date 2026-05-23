#!/usr/bin/env bash
# test-bit-identity.sh — compare argv-print output against legacy argv-dump files.
#
# Usage: test-bit-identity.sh <cluster.yaml> <base-dir> <schematic-cache> <argv-dump-dir>
#
# Exits 0 when all nodes match; exits 1 with diff output for each failing node.
# Nodes without a legacy dump file are skipped (SKIP status).
#
# NORMALIZATION RULES (CRIT-2 §Methodology — reproducibility guarantee):
#   Comment lines (#...) and blank lines are stripped from the legacy dump before
#   diffing (see grep -v filters below). Two normalizations apply to dump files:
#
#   Rule 1 — Secrets path: the legacy talosctl invocation passes --with-secrets
#     followed by a mktemp-generated ephemeral path. Dump files store the literal
#     `.secrets.dec.yaml` form that argv-print.sh emits. Dumps are captured via
#     talos/scripts/generate-argv-dump.sh which applies this substitution.
#
#   Rule 2 — NTP patch present: the legacy argv includes
#     "--config-patch @_out/<overlay>/cluster.yaml" which injects NTP. This is
#     NOT stripped from dump files. It appears as the documented delta (see
#     .work/p2-talos-oci/bit-identity-deltas.md) and is expected to remain until
#     Phase 3 adds machine.time.servers to patches/common.yaml.
#
# To regenerate dump files from a consumer cluster repo:
#   bash talos/scripts/generate-argv-dump.sh <homelab-dir> <argv-dump-dir>

set -euo pipefail

CLUSTER_YAML="${1:?Usage: $0 <cluster.yaml> <base-dir> <schematic-cache> <argv-dump-dir>}"
BASE_DIR="${2:?base-dir required}"
SCHEMATIC_CACHE="${3:?schematic-cache required}"
ARGV_DUMP_DIR="${4:?argv-dump-dir required}"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

NODES=$(yq -r '.nodes[].name' "$CLUSTER_YAML")
FAIL=0
PASS=0
SKIP=0

for n in $NODES; do
    LEGACY="$ARGV_DUMP_DIR/$n.argv"
    if [[ ! -f "$LEGACY" ]]; then
        echo "SKIP $n: no legacy argv-dump at $LEGACY"
        SKIP=$(( SKIP + 1 ))
        continue
    fi

    bash "$BASE_DIR/scripts/argv-print.sh" \
        "$CLUSTER_YAML" "$n" "$BASE_DIR" "$SCHEMATIC_CACHE" \
        2>/dev/null > "$TMPD/new.$n"

    grep -v '^#' "$LEGACY" | grep -v '^[[:space:]]*$' > "$TMPD/leg.$n"

    if diff -u "$TMPD/leg.$n" "$TMPD/new.$n" > "$TMPD/diff.$n" 2>&1; then
        echo "PASS $n"
        PASS=$(( PASS + 1 ))
    else
        echo "FAIL $n:"
        cat "$TMPD/diff.$n"
        echo "---"
        FAIL=$(( FAIL + 1 ))
    fi
done

echo ""
echo "Results: $PASS PASS, $FAIL FAIL, $SKIP SKIP (of $( echo "$NODES" | wc -w | tr -d ' ') nodes)"

if [[ $FAIL -gt 0 ]]; then
    echo "Bit-identity FAILED: $FAIL node(s) differ"
    exit 1
fi
echo "Bit-identity PASS: all tested nodes match"
