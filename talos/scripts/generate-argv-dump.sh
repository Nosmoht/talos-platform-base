#!/usr/bin/env bash
# generate-argv-dump.sh — reproduce the legacy argv-dump files used in
# talos/scripts/test-bit-identity.sh bit-identity verification.
#
# CRIT-2 fix: this script makes the dump-generation reproducible from the
# branch alone. Previously the dump files were captured ad hoc from a live
# homelab-cluster checkout; this script codifies the procedure.
#
# Usage:
#   generate-argv-dump.sh <homelab-cluster-dir> <output-dir>
#
# Where:
#   <homelab-cluster-dir>  — checkout of talos-homelab-cluster repo (the
#                            consumer cluster repo containing talos/Makefile)
#   <output-dir>           — directory to write <node>.argv files into
#                            (defaults to .work/p2-talos-oci/argv-dump/)
#
# The script invokes `make -n -C <homelab>/talos gen-configs` (dry-run) for
# each node, captures the talosctl argv, and normalises it for comparison.
#
# Normalization rules (CRIT-2 §Methodology):
#   1. Secrets path: replace the mktemp-generated secrets path
#      (e.g. /var/folders/xx/.../<name>/secrets.yaml) with the literal
#      `.secrets.dec.yaml` that argv-print.sh emits. Both refer to the
#      same decrypted SOPS secrets file; the mktemp path is ephemeral.
#   2. Output path: replace the homelab-specific _out/<overlay>/... prefix
#      with the equivalent _out/<overlay>/... form used by argv-print.sh
#      (no normalisation needed; both use the same relative path).
#   3. NTP patch: the legacy argv includes an extra
#      --config-patch @_out/<overlay>/cluster.yaml step that injects NTP.
#      This step is documented in bit-identity-deltas.md §Delta and is the
#      only expected diff. Do NOT strip it before writing the dump — the
#      test-bit-identity.sh comparator expects it to be present so that the
#      delta shows up as a documented difference.
#   4. Comment lines (starting with #) and blank lines: stripped before
#      comparison by test-bit-identity.sh (grep -v '^#' | grep -v '^[[:space:]]*$').
#      Dump files may include comment headers for documentation purposes.
#
# Reproducibility note:
#   The homelab-cluster repo must be at the same commit as when the original
#   argv-dump was captured (tagged in .work/p2-talos-oci/phase-0-summary.md).
#   The schematic cache must be pre-seeded (factory.talos.dev not needed for
#   reproduction if .schematic-cache.yaml is committed in the consumer repo).
#
# SECURITY TRUST ASSUMPTION (R3 HIGH-B):
#   This script invokes `make -n -C "$HOMELAB_DIR/talos" gen-configs`.
#   `make -n` suppresses RECIPE execution, but GNU Make still evaluates
#   $(shell …), $(eval …), define/endef bodies, and include $(shell …) at
#   parse time on every invocation regardless of -n. A consumer Makefile
#   containing `FOO := $(shell <arbitrary command>)` therefore executes that
#   command when this script runs.
#
#   Implication: only run this script against a $HOMELAB_DIR you author or
#   audit yourself (your own consumer cluster repo). Do NOT run it against
#   third-party forks, untrusted PR checkouts, or any directory whose
#   Makefile content you have not reviewed. There is no sandboxing in this
#   script — it inherits the caller's full credentials, network access, and
#   $HOME.
#
#   This is a maintainer-side reproducibility helper, not a CI gate. It is
#   never run in the platform-base CI pipeline.

set -euo pipefail

# Emit the trust reminder at runtime so it's visible in shell history /
# CI logs even if a future caller skips the header docs.
echo "[security] generate-argv-dump.sh runs 'make -n' against \$HOMELAB_DIR." >&2
echo "[security] GNU Make parse-time \$(shell ...) executes regardless of -n." >&2
echo "[security] Only point this at a consumer repo you authored or audited." >&2

HOMELAB_DIR="${1:?Usage: $0 <homelab-cluster-dir> [output-dir]}"
OUTPUT_DIR="${2:-.work/p2-talos-oci/argv-dump}"

if [[ ! -d "$HOMELAB_DIR/talos" ]]; then
    echo "ERROR: $HOMELAB_DIR does not look like a consumer cluster repo (no talos/ subdir)" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

NODES_FILE="$TMPD/nodes.txt"

# Derive node list from dry-run Makefile output (POSIX grep, no -P).
make -n -C "$HOMELAB_DIR/talos" gen-configs 2>/dev/null \
    | grep 'talosctl gen config ' \
    | sed 's/.*talosctl gen config \([^ ]*\).*/\1/' \
    | sort -u > "$NODES_FILE" || true

if [[ ! -s "$NODES_FILE" ]]; then
    # Fallback: read node list from cluster.yaml if present
    CLUSTER_YAML="$HOMELAB_DIR/cluster.yaml"
    if [[ -f "$CLUSTER_YAML" ]]; then
        yq -r '.nodes[].name' "$CLUSTER_YAML" 2>/dev/null > "$NODES_FILE" || true
    fi
fi

if [[ ! -s "$NODES_FILE" ]]; then
    echo "ERROR: could not derive node list. Pass the homelab-cluster-dir and ensure cluster.yaml or a Makefile gen-configs target is present." >&2
    exit 1
fi

while IFS= read -r node; do
    DUMP_FILE="$OUTPUT_DIR/$node.argv"
    echo "Capturing argv for $node -> $DUMP_FILE"

    # Capture the dry-run recipe for this specific node target.
    # Legacy Makefile uses per-node phony targets named after the node.
    make -n -C "$HOMELAB_DIR/talos" "$node" 2>/dev/null \
        | grep -A 999 '^talosctl' \
        | head -1 \
        | tr ' ' '\n' \
        > "$TMPD/$node.raw" || true

    if [[ ! -s "$TMPD/$node.raw" ]]; then
        echo "WARN: no argv captured for $node (legacy Makefile may not have a per-node target)" >&2
        continue
    fi

    # Apply normalization rule #1: replace ephemeral secrets path with literal
    sed "s|--with-secrets [^ ]*|--with-secrets\n.secrets.dec.yaml|g" \
        "$TMPD/$node.raw" > "$DUMP_FILE"

    echo "OK: $DUMP_FILE"
done < "$NODES_FILE"

echo ""
echo "Done. Dump files written to $OUTPUT_DIR"
echo "Re-run test-bit-identity.sh against these to reproduce the CRIT-2 baseline."
