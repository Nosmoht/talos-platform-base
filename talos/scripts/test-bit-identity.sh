#!/usr/bin/env bash
# test-bit-identity.sh — compare argv-print output against legacy argv-dump files.
#
# Usage: test-bit-identity.sh <cluster.yaml> <base-dir> <schematic-cache> <argv-dump-dir>
#
# Exits 0 when all nodes match; exits 1 with diff output for each failing node.
# Nodes without a legacy dump file are skipped (SKIP status).

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
