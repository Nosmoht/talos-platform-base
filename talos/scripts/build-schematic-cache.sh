#!/usr/bin/env bash
# build-schematic-cache.sh — Phase 1B hash-dedup schematic cache
#
# Usage: build-schematic-cache.sh <cluster.yaml> <cache-file>
#
# Algorithm:
#   1. For each node, derive extension set = union of:
#      - roles[node.role].default_extensions[]
#      - infrastructure-platforms[node.infrastructure-platform].extensions[]
#      - hardware-platforms[node.hardware-platform].extensions[]
#      - hardware-capabilities[cap].extensions[] for each cap in node.hardware_capabilities
#   2. Sort extension set lexicographically and deduplicate
#   3. Compute sha256(sorted extensions joined by newline) as set key
#   4. POST to factory.talos.dev only for new set keys (cache-hit skips POST)
#   5. Write <cache-file> in the bySet/byNode shape
#
# Network-safe: if cache-file is pre-seeded, known set keys never POST.
# Requires: bash 3.2+, yq (mikefarah v4+), openssl, curl (optional if all cached)
#
# SECURITY TRUST ASSUMPTION (HIGH-2):
#   This script POSTs extension lists to https://factory.talos.dev/schematics and
#   trusts the returned schematic_id as a 64-char SHA-256 hex string.
#   Trust basis: system CA bundle (curl default). No response-signature verification
#   is performed. A CA mis-issuance or MITM could return an attacker-controlled
#   schematic_id, which would produce a malicious installer image URL.
#
#   Mitigation in place: argv-print.sh validates schematic_id is [0-9a-f]{64};
#   PENDING or non-hex values abort gen-configs before any talosctl invocation.
#
#   Recommended hardening (Phase 3+): --cacert pinning or cosign-signed response
#   verification against the Sidero Labs signing key.

set -euo pipefail

CLUSTER_YAML="${1:?Usage: $0 <cluster.yaml> <cache-file>}"
CACHE_FILE="${2:?Usage: $0 <cluster.yaml> <cache-file>}"
FACTORY_URL="https://factory.talos.dev/schematics"

TMPDIR_LOCAL=$(mktemp -d)
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT

# ---------------------------------------------------------------------------
# Files for set_key -> extensions and set_key -> schematic_id mappings
# (flat-file approach; no associative arrays for bash 3.2 compat)
# ---------------------------------------------------------------------------
SET_KEYS_FILE="$TMPDIR_LOCAL/set_keys.txt"      # one set_key per line (unique)
EXTENSIONS_DIR="$TMPDIR_LOCAL/extensions"        # dir: one file per set_key
CACHED_IDS_FILE="$TMPDIR_LOCAL/cached_ids.txt"  # set_key<TAB>schematic_id
NODE_MAP_FILE="$TMPDIR_LOCAL/node_map.txt"       # node_name<TAB>set_key
mkdir -p "$EXTENSIONS_DIR"
: > "$SET_KEYS_FILE"
: > "$CACHED_IDS_FILE"
: > "$NODE_MAP_FILE"

# ---------------------------------------------------------------------------
# Load existing cache (if present)
# ---------------------------------------------------------------------------
if [[ -f "$CACHE_FILE" ]]; then
    # Extract bySet entries: set_key TAB schematic_id
    # R4 MED-A: symmetric guard with the write-site at line 153 below.
    # Without this, an attacker who corrupted the committed cache file
    # (PR-poisoning, on-disk tamper, or stale MITM artifact) would have
    # the malicious schematic_id read back into $CACHED_IDS_FILE on every
    # subsequent run. The legacy gen-configs production path does NOT
    # route through argv-print.sh, so the argv-print hex guard does not
    # protect this code path.
    while IFS=$'\t' read -r set_key sid; do
        [[ -z "$set_key" || -z "$sid" ]] && continue
        if [[ "$sid" == "PENDING" ]]; then
            # PENDING entries are intentional cache-miss markers; preserve.
            echo "$set_key	$sid" >> "$CACHED_IDS_FILE"
            continue
        fi
        if ! [[ "$sid" =~ ^[0-9a-f]{64}$ ]]; then
            echo "[WARN] cache file '$CACHE_FILE' contains non-hex schematic_id for set_key=${set_key:0:12}... (rejected; length=${#sid})" >&2
            echo "$set_key	PENDING" >> "$CACHED_IDS_FILE"
            continue
        fi
        echo "$set_key	$sid" >> "$CACHED_IDS_FILE"
    done < <(yq -r '.bySet | to_entries | .[] | [.key, .value.schematic_id] | join("\t")' "$CACHE_FILE" 2>/dev/null || true)
fi

# ---------------------------------------------------------------------------
# Helper: look up cached schematic_id for a set_key
# ---------------------------------------------------------------------------
cached_id_for() {
    local set_key="$1"
    grep "^${set_key}	" "$CACHED_IDS_FILE" | awk -F'\t' '{print $2}' | head -1
}

# ---------------------------------------------------------------------------
# Process nodes
# ---------------------------------------------------------------------------
NODE_COUNT=$(yq -r '.nodes | length' "$CLUSTER_YAML")
NODE_IDX=0

while [[ $NODE_IDX -lt $NODE_COUNT ]]; do
    NODE_NAME=$(yq -r ".nodes[$NODE_IDX].name" "$CLUSTER_YAML")
    NODE_ROLE=$(yq -r ".nodes[$NODE_IDX].role" "$CLUSTER_YAML")
    NODE_INFRA=$(yq -r ".nodes[$NODE_IDX][\"infrastructure-platform\"]" "$CLUSTER_YAML")
    NODE_HW=$(yq -r ".nodes[$NODE_IDX][\"hardware-platform\"]" "$CLUSTER_YAML")

    EXT_LIST="$TMPDIR_LOCAL/node_exts_$NODE_IDX.txt"
    : > "$EXT_LIST"

    # Role extensions
    yq -r "(.roles.\"$NODE_ROLE\".default_extensions // []) | .[]" "$CLUSTER_YAML" 2>/dev/null >> "$EXT_LIST" || true

    # Infrastructure-platform extensions
    yq -r "(.\"infrastructure-platforms\".\"$NODE_INFRA\".extensions // []) | .[]" "$CLUSTER_YAML" 2>/dev/null >> "$EXT_LIST" || true

    # Hardware-platform extensions
    yq -r "(.\"hardware-platforms\".\"$NODE_HW\".extensions // []) | .[]" "$CLUSTER_YAML" 2>/dev/null >> "$EXT_LIST" || true

    # Hardware-capability extensions
    NODE_CAPS_FILE="$TMPDIR_LOCAL/node_caps_${NODE_IDX}.txt"
    yq -r ".nodes[$NODE_IDX].hardware_capabilities | .[]" "$CLUSTER_YAML" 2>/dev/null > "$NODE_CAPS_FILE" || true
    while IFS= read -r cap; do
        yq -r "(.\"hardware-capabilities\".\"$cap\".extensions // []) | .[]" "$CLUSTER_YAML" 2>/dev/null >> "$EXT_LIST" || true
    done < "$NODE_CAPS_FILE"

    # Sort + deduplicate, remove empty lines
    SORTED_EXTS_FILE="$TMPDIR_LOCAL/sorted_exts_$NODE_IDX.txt"
    sort -u "$EXT_LIST" | grep -v '^$' > "$SORTED_EXTS_FILE" || true

    # Compute set key
    SET_KEY=$(openssl dgst -sha256 < "$SORTED_EXTS_FILE" | awk '{print $NF}')

    # Register in node map
    echo "$NODE_NAME	$SET_KEY" >> "$NODE_MAP_FILE"

    # Register set key (if new)
    if ! grep -qxF "$SET_KEY" "$SET_KEYS_FILE"; then
        echo "$SET_KEY" >> "$SET_KEYS_FILE"
        cp "$SORTED_EXTS_FILE" "$EXTENSIONS_DIR/$SET_KEY"
    fi

    NODE_IDX=$(( NODE_IDX + 1 ))
done

# ---------------------------------------------------------------------------
# Fetch schematic IDs for uncached sets
# ---------------------------------------------------------------------------
while IFS= read -r set_key; do
    [[ -z "$set_key" ]] && continue

    EXISTING=$(cached_id_for "$set_key")
    if [[ -n "$EXISTING" ]]; then
        echo "[cache hit] set_key=${set_key:0:12}... -> $EXISTING"
        continue
    fi

    EXT_FILE="$EXTENSIONS_DIR/$set_key"

    # Build JSON payload for factory.talos.dev
    EXT_JSON=$(jq -Rsn '[inputs]' "$EXT_FILE" | \
        jq '{customization: {systemExtensions: {officialExtensions: .}}}')

    echo "[POST] factory.talos.dev for set_key=${set_key:0:12}..."
    RESPONSE=$(curl -sf -X POST -H 'Content-Type: application/json' \
        -d "$EXT_JSON" "$FACTORY_URL" 2>/dev/null || true)

    if [[ -n "$RESPONSE" ]]; then
        SID=$(echo "$RESPONSE" | jq -r '.id // empty' 2>/dev/null || true)
        # R3 MED-1: validate SID is 64-char lowercase hex at write site.
        # Without this guard, a MITM-controlled factory response can persist
        # attacker-shaped content in the cache file; argv-print's hex guard
        # only fires when argv-print runs (not on the legacy gen-configs
        # production path documented in RELEASE-NOTES-v0.5.1.md).
        if [[ -n "$SID" && "$SID" =~ ^[0-9a-f]{64}$ ]]; then
            echo "$set_key	$SID" >> "$CACHED_IDS_FILE"
            echo "[cached] set_key=${set_key:0:12}... -> $SID"
        elif [[ -n "$SID" ]]; then
            # Do not echo $RESPONSE — body is attacker-controlled; could carry
            # terminal escapes that execute when the log is later cat'd.
            echo "[WARN] factory returned non-hex schematic_id for set_key=${set_key:0:12} (rejected; length=${#SID})" >&2
            echo "$set_key	PENDING" >> "$CACHED_IDS_FILE"
        else
            echo "[WARN] factory returned unexpected response for set_key=${set_key:0:12} (jq parse failed)" >&2
            echo "$set_key	PENDING" >> "$CACHED_IDS_FILE"
        fi
    else
        echo "[WARN] factory POST failed for set_key=${set_key:0:12} (offline or HTTP error)" >&2
        echo "$set_key	PENDING" >> "$CACHED_IDS_FILE"
    fi
done < "$SET_KEYS_FILE"

# ---------------------------------------------------------------------------
# Write cache YAML
# ---------------------------------------------------------------------------
{
    echo "bySet:"
    while IFS= read -r set_key; do
        [[ -z "$set_key" ]] && continue
        SID=$(cached_id_for "$set_key")
        [[ -z "$SID" ]] && SID="PENDING"
        EXT_FILE="$EXTENSIONS_DIR/$set_key"
        echo "  $set_key:"
        echo "    extensions:"
        while IFS= read -r ext; do
            [[ -z "$ext" ]] && continue
            echo "      - $ext"
        done < "$EXT_FILE"
        echo "    schematic_id: $SID"
    done < "$SET_KEYS_FILE"

    echo "byNode:"
    while IFS=$'\t' read -r node_name set_key; do
        [[ -z "$node_name" ]] && continue
        echo "  $node_name:"
        echo "    set_key: $set_key"
    done < "$NODE_MAP_FILE"
} > "$CACHE_FILE"

SET_COUNT=$(wc -l < "$SET_KEYS_FILE" | tr -d ' ')
NODE_COUNT_OUT=$(wc -l < "$NODE_MAP_FILE" | tr -d ' ')
echo "[done] cache written to $CACHE_FILE"
echo "  bySet entries: $SET_COUNT"
echo "  byNode entries: $NODE_COUNT_OUT"
