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
NTP_SERVER=$(yq -r '.cluster.ntp_server // ""' "$CLUSTER_YAML" 2>/dev/null || true)

# ---------------------------------------------------------------------------
# CRIT-4 (closed in v0.5.2): render NTP patch from cluster.ntp_server.
# Legacy gen-configs injected NTP via a rendered _out/<overlay>/cluster.yaml
# patch; the new path renders an equivalent ephemeral patch into tmpdir and
# emits it in the per-node argv. machine.time.servers is the Talos field
# the patch sets.
# ---------------------------------------------------------------------------
NTP_PATCH_FILE=""
if [[ -n "$NTP_SERVER" && "$NTP_SERVER" != "null" ]]; then
    NTP_PATCH_FILE="$TMPDIR_LOCAL/ntp.yaml"
    cat > "$NTP_PATCH_FILE" <<EOF
machine:
  time:
    servers:
      - $NTP_SERVER
EOF
fi

# ---------------------------------------------------------------------------
# Patch list: roles[role].patches (ordered list; this IS the full patch list)
# ---------------------------------------------------------------------------
ROLE_PATCHES_FILE="$TMPDIR_LOCAL/role_patches.txt"
yq -r ".roles[\"$NODE_ROLE\"].patches // [] | .[]" "$CLUSTER_YAML" 2>/dev/null > "$ROLE_PATCHES_FILE" || true

# ---------------------------------------------------------------------------
# CRIT-1 (closed in v0.5.2): build per-node placeholder bindings from the
# node's hardware_capabilities entries. For each cap, read its
# placeholder_bindings map (PLACEHOLDER -> yq path into nodes/<NODE>.yaml)
# and resolve the field into a flat NAME<TAB>VALUE bindings file.
# resolve-placeholders.sh consumes this file and renders any patch that
# contains ${PLACEHOLDER} tokens. validate-schematics already enforces
# binding-missing at the diagnostic layer; this is the runtime resolution.
# ---------------------------------------------------------------------------
BINDINGS_FILE="$TMPDIR_LOCAL/bindings.txt"
: > "$BINDINGS_FILE"
NODE_YAML_PATH="$(dirname "$CLUSTER_YAML")/nodes/$NODE_NAME.yaml"

# Collect per-node caps
NODE_CAPS_FILE="$TMPDIR_LOCAL/node_caps.txt"
yq -r ".nodes[$NODE_IDX].hardware_capabilities // [] | .[]" "$CLUSTER_YAML" 2>/dev/null > "$NODE_CAPS_FILE" || true

while IFS= read -r cap; do
    [[ -z "$cap" ]] && continue
    # Charset guard — mirrors validate-schematics.sh runtime check.
    [[ "$cap" =~ ^[A-Za-z0-9._-]+$ ]] || continue
    # Read the cap's placeholder_bindings map. Use --output-format=props for a
    # NAME=VALUE flat shape (avoids the .key/.value yq accessor which can
    # collide with shell-token detection in some harnesses).
    CAP_BINDINGS_FILE="$TMPDIR_LOCAL/cap_bindings.txt"
    yq -o=props -r ".\"hardware-capabilities\".\"$cap\".placeholder_bindings // {}" "$CLUSTER_YAML" 2>/dev/null > "$CAP_BINDINGS_FILE" || true
    while IFS= read -r binding; do
        [[ -z "$binding" ]] && continue
        # props output shape: "KEY = VALUE" (yq adds spaces around =)
        placeholder="${binding%% =*}"
        field_path="${binding#*= }"
        [[ -z "$placeholder" || -z "$field_path" ]] && continue
        # Resolve the field from nodes/<NODE>.yaml using the field path AS WRITTEN
        # (absolute from the nodes/<n>.yaml root — e.g., `machine.network.bridge.nic`).
        # No implicit `machine.` prefix added: the cluster.yaml author is in charge
        # of the path; this avoids hidden-magic ambiguity.
        if [[ -f "$NODE_YAML_PATH" ]]; then
            field_val=$(yq -r ".${field_path} // \"\"" "$NODE_YAML_PATH" 2>/dev/null || true)
            if [[ -n "$field_val" && "$field_val" != "null" ]]; then
                printf '%s\t%s\n' "$placeholder" "$field_val" >> "$BINDINGS_FILE"
            fi
        fi
    done < "$CAP_BINDINGS_FILE"
done < "$NODE_CAPS_FILE"

# ---------------------------------------------------------------------------
# Helper: emit one --config-patch flag. If the patch contains ${PLACEHOLDER}
# tokens, render via resolve-placeholders.sh into tmpdir and emit the rendered
# path; otherwise emit @<source-path> verbatim (bit-identical with legacy).
# ---------------------------------------------------------------------------
emit_patch() {
    local patch="$1"
    local resolved_dir base rendered abs_patch
    # Patch paths in cluster.yaml are relative to the base talos dir.
    if [[ "$patch" == /* ]]; then
        abs_patch="$patch"
    else
        abs_patch="$BASE_DIR/$patch"
    fi
    if [[ -f "$abs_patch" ]] && grep -qE '\$\{[A-Z][A-Z0-9_]*\}' "$abs_patch"; then
        resolved_dir="$TMPDIR_LOCAL/patches"
        mkdir -p "$resolved_dir"
        base=$(basename "$patch")
        rendered="$resolved_dir/$base"
        bash "$BASE_DIR/scripts/resolve-placeholders.sh" "$abs_patch" "$BINDINGS_FILE" > "$rendered"
        echo "--config-patch"
        echo "@$rendered"
    else
        echo "--config-patch"
        echo "@$patch"
    fi
}

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

# Emit role patches, inserting the rendered NTP patch right after the first
# `common.yaml` (matches the legacy ordering: common → rendered-cluster.yaml
# (carrying NTP) → drbd → role-patch). If no common.yaml is in the list, NTP
# is emitted first. If cluster.ntp_server is unset, no NTP patch is emitted.
NTP_INSERTED=0
while IFS= read -r patch; do
    emit_patch "$patch"
    if [[ "$NTP_INSERTED" == "0" && -n "$NTP_PATCH_FILE" && "$(basename "$patch")" == "common.yaml" ]]; then
        echo "--config-patch"
        echo "@$NTP_PATCH_FILE"
        NTP_INSERTED=1
    fi
done < "$ROLE_PATCHES_FILE"
# Fallback: if NTP set but no common.yaml in role_patches, emit it before
# nodes/<n>.yaml so it still applies.
if [[ "$NTP_INSERTED" == "0" && -n "$NTP_PATCH_FILE" ]]; then
    echo "--config-patch"
    echo "@$NTP_PATCH_FILE"
fi

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
