#!/usr/bin/env bash
# argv-print.sh — emit the exact talosctl gen config argv for one node.
#
# Usage: argv-print.sh <cluster.yaml> <node-name> [base-dir] [schematic-cache]
#
# Output: one argv element per line (matches legacy argv-dump format for
#         bit-identity diff in Phase 1C-3).
#
# Resolution chain (per Makefile.lib §Phase 1C-2 brief):
#   1. Read node attrs: role, arch, infrastructure-platform, hardware_capabilities
#   2. Resolve patch list from roles[role].patches (ordered; includes base patches)
#   3. Append per-node nodes/<name>.yaml (always last patch)
#   4. Resolve install-image from infrastructure-platforms[infra].install-image-template
#      + schematic-cache byNode[name].set_key → bySet[key].schematic_id
#   5. Emit full argv including --with-secrets, --output, --output-types, versions, --force
#
# Versions are read from versions.mk in BASE_DIR if present.
# Schematic cache defaults to <BASE_DIR>/.schematic-cache.yaml
#
# Dependencies: yq (mikefarah v4+), bash 3.2+

set -euo pipefail

CLUSTER_YAML="${1:?Usage: $0 <cluster.yaml> <node-name> [base-dir] [schematic-cache]}"
NODE_NAME="${2:?node-name required}"
BASE_DIR="${3:-$(dirname "$(cd "$(dirname "$0")" && pwd)")}"
SCHEMATIC_CACHE="${4:-$BASE_DIR/.schematic-cache.yaml}"
VERSIONS_MK="${BASE_DIR}/versions.mk"

TMPDIR_LOCAL=$(mktemp -d)
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT

# ---------------------------------------------------------------------------
# Load versions
# ---------------------------------------------------------------------------
TALOS_VERSION="v1.12.6"       # default fallback
KUBERNETES_VERSION="v1.35.0"  # default fallback
if [[ -f "$VERSIONS_MK" ]]; then
    _TV=$(grep '^TALOS_VERSION' "$VERSIONS_MK" | head -1 | sed 's/.*:= *//' | tr -d '[:space:]')
    _KV=$(grep '^KUBERNETES_VERSION' "$VERSIONS_MK" | head -1 | sed 's/.*:= *//' | tr -d '[:space:]')
    [[ -n "$_TV" ]] && TALOS_VERSION="$_TV"
    [[ -n "$_KV" ]] && KUBERNETES_VERSION="$_KV"
fi

# ---------------------------------------------------------------------------
# Find node in cluster.yaml
# ---------------------------------------------------------------------------
NODE_COUNT=$(yq -r '.nodes | length' "$CLUSTER_YAML")
NODE_IDX=-1
IDX=0
while [[ $IDX -lt $NODE_COUNT ]]; do
    NAME=$(yq -r ".nodes[$IDX].name" "$CLUSTER_YAML")
    if [[ "$NAME" == "$NODE_NAME" ]]; then
        NODE_IDX=$IDX
        break
    fi
    IDX=$(( IDX + 1 ))
done

if [[ $NODE_IDX -lt 0 ]]; then
    echo "ERROR: node '$NODE_NAME' not found in $CLUSTER_YAML" >&2
    exit 1
fi

NODE_ROLE=$(yq -r ".nodes[$NODE_IDX].role" "$CLUSTER_YAML")
NODE_INFRA=$(yq -r ".nodes[$NODE_IDX][\"infrastructure-platform\"]" "$CLUSTER_YAML")

# ---------------------------------------------------------------------------
# Cluster-level values
# ---------------------------------------------------------------------------
CLUSTER_NAME=$(yq -r '.cluster.name' "$CLUSTER_YAML")
ENDPOINT="https://$(yq -r '.cluster.api_vip' "$CLUSTER_YAML"):6443"
OVERLAY=$(yq -r '.cluster.overlay // .cluster.name' "$CLUSTER_YAML")

# ---------------------------------------------------------------------------
# Patch list: roles[role].patches (ordered list; this IS the full patch list)
# ---------------------------------------------------------------------------
ROLE_PATCHES_FILE="$TMPDIR_LOCAL/role_patches.txt"
yq -r ".roles[\"$NODE_ROLE\"].patches // [] | .[]" "$CLUSTER_YAML" 2>/dev/null > "$ROLE_PATCHES_FILE" || true

# ---------------------------------------------------------------------------
# Install-image URI
# ---------------------------------------------------------------------------
INSTALL_IMAGE=""
if [[ -f "$SCHEMATIC_CACHE" ]]; then
    # Get set_key for this node from byNode
    SET_KEY=$(yq -r ".byNode[\"$NODE_NAME\"].set_key // \"\"" "$SCHEMATIC_CACHE" 2>/dev/null || true)
    if [[ -n "$SET_KEY" && "$SET_KEY" != "null" ]]; then
        SCHEMATIC_ID=$(yq -r ".bySet[\"$SET_KEY\"].schematic_id // \"\"" "$SCHEMATIC_CACHE" 2>/dev/null || true)
        if [[ -n "$SCHEMATIC_ID" && "$SCHEMATIC_ID" != "null" ]]; then
            # Guard: reject PENDING or any non-sha256-hex value (HIGH-1 PENDING cache poisoning fix).
            # A valid schematic_id is a 64-character lowercase hex string.
            if [[ "$SCHEMATIC_ID" == "PENDING" ]] || ! [[ "$SCHEMATIC_ID" =~ ^[0-9a-f]{64}$ ]]; then
                echo "ERROR: schematic_id for node '$NODE_NAME' is '$SCHEMATIC_ID' — not a valid SHA-256 hex string. Re-run 'make schematics' to refresh the cache." >&2
                exit 1
            fi
            # Get install-image-template from infrastructure-platform
            TEMPLATE=$(yq -r ".\"infrastructure-platforms\".\"$NODE_INFRA\".\"install-image-template\" // \"\"" "$CLUSTER_YAML" 2>/dev/null || true)
            if [[ -n "$TEMPLATE" && "$TEMPLATE" != "null" ]]; then
                INSTALL_IMAGE=$(echo "$TEMPLATE" | sed "s/\${SCHEMATIC_ID}/$SCHEMATIC_ID/g; s/\${TALOS_VERSION}/$TALOS_VERSION/g")
            fi
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Determine output-types (role → talosctl type)
# ---------------------------------------------------------------------------
case "$NODE_ROLE" in
    controlplane) OUTPUT_TYPE="controlplane" ;;
    worker|gpu-worker) OUTPUT_TYPE="worker" ;;
    *) OUTPUT_TYPE="worker" ;;
esac

# ---------------------------------------------------------------------------
# Emit argv (one element per line — matches argv-dump format)
# ---------------------------------------------------------------------------
echo "talosctl"
echo "gen"
echo "config"
echo "$CLUSTER_NAME"
echo "$ENDPOINT"
echo "--with-secrets"
echo ".secrets.dec.yaml"

while IFS= read -r patch; do
    echo "--config-patch"
    echo "@$patch"
done < "$ROLE_PATCHES_FILE"

echo "--config-patch"
echo "@nodes/$NODE_NAME.yaml"

if [[ -n "$INSTALL_IMAGE" ]]; then
    echo "--config-patch"
    printf '{"machine":{"install":{"image":"%s"}}}\n' "$INSTALL_IMAGE"
fi

echo "--output"
echo "_out/$OVERLAY/$OUTPUT_TYPE/$NODE_NAME.yaml"
echo "--output-types"
echo "$OUTPUT_TYPE"
echo "--talos-version"
echo "$TALOS_VERSION"
echo "--kubernetes-version"
echo "$KUBERNETES_VERSION"
echo "--force"
