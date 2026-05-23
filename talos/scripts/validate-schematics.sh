#!/usr/bin/env bash
# validate-schematics.sh — Phase 1B cross-reference diagnostics
#
# Usage: validate-schematics.sh <cluster.yaml> [<base-dir>]
#
# Checks:
#   1. Each node's arch exists in cluster.yaml architectures
#   2. Each node's infrastructure-platform is compatible with its arch
#   3. Each node's hardware-platform is compatible with its arch
#   4. Each node's hardware-platform is compatible with its infrastructure-platform
#   5. Each node's hardware_capabilities entries exist in hardware-capabilities
#   6. Each hardware-capability's requires_features entries exist in Layer-C registry
#   7. Conflict detection: two capabilities patching the same JSON-pointer
#
# Exit 0 = all OK; Exit 1 = at least one FAIL diagnostic emitted.
# Requires: bash 3.2+, yq (mikefarah v4+)

set -euo pipefail

CLUSTER_YAML="${1:?Usage: $0 <cluster.yaml> [<base-dir>]}"
BASE_DIR="${2:-$(dirname "$(cd "$(dirname "$0")" && pwd)")}"
REGISTRY_FILE="$BASE_DIR/../docs/platform-hardware-features.yaml"

if [[ ! -f "$CLUSTER_YAML" ]]; then
    echo "ERROR: cluster.yaml not found: $CLUSTER_YAML" >&2
    exit 1
fi

if [[ ! -f "$REGISTRY_FILE" ]]; then
    echo "ERROR: Layer-C registry not found: $REGISTRY_FILE" >&2
    exit 1
fi

FAIL_COUNT=0
TMPDIR_LOCAL=$(mktemp -d)
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
fail() { echo "FAIL $*"; FAIL_COUNT=$(( FAIL_COUNT + 1 )); }
warn() { echo "WARN $*"; }
ok()   { echo "OK: $*"; }

# ---------------------------------------------------------------------------
# Load Layer-C feature ids from the registry
# ---------------------------------------------------------------------------
LAYER_C_IDS_FILE="$TMPDIR_LOCAL/layer_c_ids.txt"
yq -r '.hardware_features[].id' "$REGISTRY_FILE" > "$LAYER_C_IDS_FILE"

# ---------------------------------------------------------------------------
# Load strict_capability_merge flag (default: false)
# ---------------------------------------------------------------------------
STRICT_MERGE=$(yq -r '.strict_capability_merge // false' "$CLUSTER_YAML")

# ---------------------------------------------------------------------------
# Validate hardware-capabilities[*].requires_features (Layer-C cross-ref)
# ---------------------------------------------------------------------------
CAP_KEYS_FILE="$TMPDIR_LOCAL/cap_keys.txt"
yq -r '.["hardware-capabilities"] | keys | .[]' "$CLUSTER_YAML" 2>/dev/null > "$CAP_KEYS_FILE" || true

while IFS= read -r cap; do
    # Validate key charset before interpolating into yq expressions (injection guard).
    if ! [[ "$cap" =~ ^[A-Za-z0-9._-]+$ ]]; then
        fail "[hardware-capabilities]: key '$cap' contains illegal characters; expected ^[A-Za-z0-9._-]+\$"
        continue
    fi
    FEATURES_FILE="$TMPDIR_LOCAL/cap_features_$$.txt"
    yq -r "(.\"hardware-capabilities\".\"$cap\".requires_features // []) | .[]" "$CLUSTER_YAML" 2>/dev/null > "$FEATURES_FILE" || true
    while IFS= read -r feat; do
        if ! grep -qxF "$feat" "$LAYER_C_IDS_FILE"; then
            fail "[hardware-capabilities.$cap]: feature '$feat' in requires_features not present in Layer-C registry"
        fi
    done < "$FEATURES_FILE"
done < "$CAP_KEYS_FILE"

# ---------------------------------------------------------------------------
# Capability merge conflict detection
# Use a flat file: one "cap pointer" per line; sort+uniq -d finds conflicts
# ---------------------------------------------------------------------------
CAP_POINTER_FILE="$TMPDIR_LOCAL/cap_pointers.txt"
: > "$CAP_POINTER_FILE"

while IFS= read -r cap; do
    # Charset guard (same as above — skip caps already rejected in requires_features loop)
    [[ "$cap" =~ ^[A-Za-z0-9._-]+$ ]] || continue
    # Only collect pointer-form patches (file-form patches have no pointer field)
    PATCH_POINTERS_FILE="$TMPDIR_LOCAL/patch_ptrs_$$.txt"
    yq -r "(.\"hardware-capabilities\".\"$cap\".patches // []) | .[] | select(has(\"pointer\")) | .pointer" "$CLUSTER_YAML" 2>/dev/null > "$PATCH_POINTERS_FILE" || true
    while IFS= read -r pointer; do
        printf '%s\t%s\n' "$pointer" "$cap" >> "$CAP_POINTER_FILE"
    done < "$PATCH_POINTERS_FILE"
done < "$CAP_KEYS_FILE"

if [[ -s "$CAP_POINTER_FILE" ]]; then
    # Find pointers that appear more than once
    CONFLICT_POINTERS_FILE="$TMPDIR_LOCAL/conflict_ptrs.txt"
    awk '{print $1}' "$CAP_POINTER_FILE" | sort | uniq -d > "$CONFLICT_POINTERS_FILE" || true
    while IFS= read -r pointer; do
        # Aggregate ALL caps that claim this pointer (HIGH-4 fix: no longer drops 3rd+)
        ALL_CAPS=$(grep "^${pointer}	" "$CAP_POINTER_FILE" | awk '{print $2}' | paste -sd,)
        msg="[conflict]: capabilities '$ALL_CAPS' patch the same pointer '$pointer'"
        if [[ "$STRICT_MERGE" == "true" ]]; then
            fail "$msg"
        else
            warn "$msg"
        fi
    done < "$CONFLICT_POINTERS_FILE"
fi

# ---------------------------------------------------------------------------
# Validate each node
# ---------------------------------------------------------------------------
NODE_COUNT=$(yq -r '.nodes | length' "$CLUSTER_YAML")
NODE_IDX=0
NODE_PASS=0

while [[ $NODE_IDX -lt $NODE_COUNT ]]; do
    NODE_NAME=$(yq -r ".nodes[$NODE_IDX].name" "$CLUSTER_YAML")
    NODE_ARCH=$(yq -r ".nodes[$NODE_IDX].arch" "$CLUSTER_YAML")
    NODE_INFRA=$(yq -r ".nodes[$NODE_IDX][\"infrastructure-platform\"]" "$CLUSTER_YAML")
    NODE_HW=$(yq -r ".nodes[$NODE_IDX][\"hardware-platform\"]" "$CLUSTER_YAML")

    NODE_FAIL=0

    # Check 1: arch exists in architectures
    ARCH_EXISTS=$(yq -r ".architectures | has(\"$NODE_ARCH\")" "$CLUSTER_YAML" 2>/dev/null || echo "false")
    if [[ "$ARCH_EXISTS" != "true" ]]; then
        fail "[n.$NODE_NAME]: arch '$NODE_ARCH' not in cluster.yaml architectures"
        NODE_FAIL=1
    else
        # Check 2: infrastructure-platform compatible with arch
        INFRA_COMPAT=$(yq -r ".architectures.\"$NODE_ARCH\".\"compatible-infrastructure-platforms\" // [] | map(select(. == \"$NODE_INFRA\")) | length" "$CLUSTER_YAML" 2>/dev/null || echo "0")
        if [[ "$INFRA_COMPAT" == "0" ]]; then
            fail "[n.$NODE_NAME]: infrastructure-platform '$NODE_INFRA' not compatible with arch '$NODE_ARCH'"
            NODE_FAIL=1
        fi

        # Check 3: hardware-platform compatible with arch (only when arch defines the constraint)
        HAS_HW_COMPAT=$(yq -r ".architectures.\"$NODE_ARCH\" | has(\"compatible-hardware-platforms\")" "$CLUSTER_YAML" 2>/dev/null || echo "false")
        if [[ "$HAS_HW_COMPAT" == "true" ]]; then
            HW_ARCH_COMPAT=$(yq -r ".architectures.\"$NODE_ARCH\".\"compatible-hardware-platforms\" | map(select(. == \"$NODE_HW\")) | length" "$CLUSTER_YAML" 2>/dev/null || echo "0")
            if [[ "$HW_ARCH_COMPAT" == "0" ]]; then
                fail "[n.$NODE_NAME]: hardware-platform '$NODE_HW' not compatible with arch '$NODE_ARCH'"
                NODE_FAIL=1
            fi
        fi
    fi

    # Check 4: hardware-platform compatible with infrastructure-platform (only when infra defines the constraint)
    INFRA_HAS_HW=$(yq -r ".\"infrastructure-platforms\".\"$NODE_INFRA\" | has(\"compatible-hardware-platforms\")" "$CLUSTER_YAML" 2>/dev/null || echo "false")
    if [[ "$INFRA_HAS_HW" == "true" ]]; then
        INFRA_HW_COMPAT=$(yq -r ".\"infrastructure-platforms\".\"$NODE_INFRA\".\"compatible-hardware-platforms\" | map(select(. == \"$NODE_HW\")) | length" "$CLUSTER_YAML" 2>/dev/null || echo "0")
        if [[ "$INFRA_HW_COMPAT" == "0" ]]; then
            fail "[n.$NODE_NAME]: hardware-platform '$NODE_HW' not in compatible-infrastructure-platforms of '$NODE_INFRA'"
            NODE_FAIL=1
        fi
    fi

    # Check 5: hardware_capabilities entries exist in hardware-capabilities
    NODE_CAPS_FILE="$TMPDIR_LOCAL/node_caps_${NODE_IDX}.txt"
    yq -r ".nodes[$NODE_IDX].hardware_capabilities | .[]" "$CLUSTER_YAML" 2>/dev/null > "$NODE_CAPS_FILE" || true
    while IFS= read -r cap; do
        # Charset guard before interpolating into yq expressions
        if ! [[ "$cap" =~ ^[A-Za-z0-9._-]+$ ]]; then
            fail "[n.$NODE_NAME]: hardware_capabilities entry '$cap' contains illegal characters; expected ^[A-Za-z0-9._-]+\$"
            NODE_FAIL=1
            continue
        fi
        CAP_EXISTS=$(yq -r ".\"hardware-capabilities\" | has(\"$cap\")" "$CLUSTER_YAML" 2>/dev/null || echo "false")
        if [[ "$CAP_EXISTS" != "true" ]]; then
            fail "[n.$NODE_NAME]: capability '$cap' in hardware_capabilities not defined in cluster.yaml hardware-capabilities"
            NODE_FAIL=1
        else
            # Check 6: binding-missing — capability declares placeholder_bindings
            # that must be present in nodes/<name>.yaml for this node.
            # placeholder_bindings is a map: PLACEHOLDER_NAME -> nodes/<name>.yaml field path
            BINDINGS_FILE="$TMPDIR_LOCAL/bindings_${NODE_IDX}_$$.txt"
            yq -r ".\"hardware-capabilities\".\"$cap\".placeholder_bindings // {} | to_entries | .[] | .key + \"=\" + .value" "$CLUSTER_YAML" 2>/dev/null > "$BINDINGS_FILE" || true
            while IFS= read -r binding; do
                PLACEHOLDER="${binding%%=*}"
                FIELD_PATH="${binding#*=}"
                # Look for nodes/<name>.yaml relative to the cluster.yaml location
                CLUSTER_DIR="$(dirname "$CLUSTER_YAML")"
                NODE_YAML="$CLUSTER_DIR/nodes/$NODE_NAME.yaml"
                if [[ ! -f "$NODE_YAML" ]]; then
                    fail "[n.$NODE_NAME]: binding-missing — capability '$cap' references placeholder '\${$PLACEHOLDER}' but nodes/$NODE_NAME.yaml not found (expected at path '$FIELD_PATH')"
                    NODE_FAIL=1
                else
                    # Convert dot-path to yq expression (e.g. network.bridge.nic -> .network.bridge.nic)
                    # Note: field paths are flat dot-separated keys; keys with literal dots are not supported.
                    YQ_PATH=".$FIELD_PATH"
                    FIELD_VAL=$(yq -r "$YQ_PATH // \"\"" "$NODE_YAML" 2>/dev/null || true)
                    if [[ -z "$FIELD_VAL" || "$FIELD_VAL" == "null" ]]; then
                        fail "[n.$NODE_NAME]: binding-missing — capability '$cap' references placeholder '\${$PLACEHOLDER}' but nodes/$NODE_NAME.yaml is missing the binding (expected at path '$FIELD_PATH')"
                        NODE_FAIL=1
                    fi
                fi
            done < "$BINDINGS_FILE"
        fi
    done < "$NODE_CAPS_FILE"

    if [[ $NODE_FAIL -eq 0 ]]; then
        NODE_PASS=$(( NODE_PASS + 1 ))
    fi

    NODE_IDX=$(( NODE_IDX + 1 ))
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
if [[ $FAIL_COUNT -eq 0 ]]; then
    ok "$NODE_PASS nodes pass validation"
    exit 0
else
    exit 1
fi
