#!/usr/bin/env bash
# test-content-mode.sh — assert argv-print.sh EMIT=content shares the argv
# composition and emits a valid Terraform-consumable artifact.
#
# Behavioural invariants (NOT a byte snapshot — survives patch-content edits):
#   1. content .config_patches is a non-empty list(string)  (== terraform list(string))
#   2. composition parity: content patch count == argv @-patch count for the
#      same node (no patch lost or added between the two frontends)
#   3. per-node placeholder resolution: a node carrying a placeholder capability
#      (kubevirt-networking) emits the resolved patch content, not the token
#
# Uses the heterogeneous test/cluster.yaml.example fixture. worker-test is the
# node with a nodes/<name>.yaml (required for parity + placeholder resolution).
#
# Usage: test-content-mode.sh [base-dir]
set -euo pipefail

BASE_DIR="${1:-$(dirname "$(cd "$(dirname "$0")" && pwd)")}"
ARGV="$BASE_DIR/scripts/argv-print.sh"
CY="$BASE_DIR/test/cluster.yaml.example"
NODE="worker-test"

argv_n=$(EMIT=argv bash "$ARGV" "$CY" "$NODE" "$BASE_DIR" "" 2>/dev/null | grep -c '^@' || true)
cjson=$(EMIT=content bash "$ARGV" "$CY" "$NODE" "$BASE_DIR" "" 2>/dev/null)

# 1. valid non-empty list(string)
if ! printf '%s' "$cjson" | jq -e '.config_patches | (type=="array") and (length>0) and all(type=="string")' >/dev/null 2>&1; then
    echo "FAIL: content .config_patches is not a non-empty list(string)" >&2
    exit 1
fi

# 2. composition parity with argv mode
content_n=$(printf '%s' "$cjson" | jq '.config_patches | length')
if [[ "$argv_n" != "$content_n" ]]; then
    echo "FAIL: argv @-patches ($argv_n) != content config_patches ($content_n) — frontends diverged" >&2
    exit 1
fi

# 3. per-node placeholder resolution (kubevirt VLAN patch, ${NIC_NAME} -> eth0)
if ! printf '%s' "$cjson" | jq -e '.config_patches | any(test("VLANConfig"))' >/dev/null 2>&1; then
    echo "FAIL: kubevirt VLANConfig patch missing from content for $NODE" >&2
    exit 1
fi
if ! printf '%s' "$cjson" | jq -e '.config_patches | any(test("parent: eth0"))' >/dev/null 2>&1; then
    echo "FAIL: placeholder \${NIC_NAME} not resolved to eth0 in content output" >&2
    exit 1
fi

echo "OK: content mode shares argv composition ($content_n patches), valid list(string), placeholder resolved"
