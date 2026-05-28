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
ENDPOINT="https://$(yq -r '.cluster.vip' "$CLUSTER_YAML"):6443"
OVERLAY=$(yq -r '.cluster.overlay // .cluster.name' "$CLUSTER_YAML")
NTP_SERVER=$(yq -r '.cluster.ntp_server // ""' "$CLUSTER_YAML" 2>/dev/null || true)

# ---------------------------------------------------------------------------
# CRIT-4 (closed in v0.5.2): render NTP patch from cluster.ntp_server.
# Legacy gen-configs injected NTP via a rendered _out/<overlay>/cluster.yaml
# patch; the new path renders an equivalent ephemeral patch into tmpdir and
# emits it as the FIRST role-patch (so every subsequent role-patch and the
# per-node nodes/<n>.yaml can override it). machine.time.servers is the
# Talos field the patch sets.
#
# R2 HIGH (team-red): the value goes into a heredoc — validate it as a
# strict hostname/IPv4/IPv6 charset and reject any newline / shell-meta to
# prevent YAML injection into machine.* keys (e.g. attacker-controlled
# extraKernelArgs landing through the NTP slot bypassing the AGENTS.md
# Hard-Constraints check). Pattern admits letters, digits, dot, hyphen,
# colon (IPv6) — nothing else.
# ---------------------------------------------------------------------------
NTP_PATCH_FILE=""
if [[ -n "$NTP_SERVER" && "$NTP_SERVER" != "null" ]]; then
    if ! [[ "$NTP_SERVER" =~ ^[A-Za-z0-9.:_-]{1,253}$ ]]; then
        echo "ERROR: cluster.ntp_server value violates charset ^[A-Za-z0-9.:_-]{1,253}\$ — refused (potential YAML injection). Use a single RFC 1123 hostname, IPv4, or IPv6 literal." >&2
        exit 1
    fi
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
# Read canonical kebab-case field first; fall back to deprecated underscore
# alias (kept for v0.5.4 grace window per schema $defs.node-spec).
yq -r ".nodes[$NODE_IDX].\"hardware-capabilities\" // .nodes[$NODE_IDX].hardware_capabilities // [] | .[]" "$CLUSTER_YAML" 2>/dev/null > "$NODE_CAPS_FILE" || true

CAP_BINDINGS_FILE="$TMPDIR_LOCAL/cap_bindings.txt"
while IFS= read -r cap; do
    [[ -z "$cap" ]] && continue
    # Charset guard — mirrors validate-schematics.sh runtime check.
    [[ "$cap" =~ ^[A-Za-z0-9._-]+$ ]] || continue
    # R2 MED: explicit truncate per iteration (prior `>` redirect truncates
    # on success but can leak prior-iteration content if yq spawn fails).
    : > "$CAP_BINDINGS_FILE"
    # Read the cap's placeholder_bindings map. Use --output-format=props for a
    # NAME=VALUE flat shape (stable bash-parameter-expansion parsing without
    # a jq dependency or yq path accessors that could collide with file-name
    # patterns).
    # yq -o=props passes YAML comments through as '# ...' lines; strip them
    # before bash parsing (KEY = VALUE lines start with [A-Z]).
    yq -o=props -r ".\"hardware-capabilities\".\"$cap\".placeholder_bindings // {}" "$CLUSTER_YAML" 2>/dev/null \
        | grep -E '^[A-Z]' > "$CAP_BINDINGS_FILE" || true
    while IFS= read -r binding; do
        [[ -z "$binding" ]] && continue
        # props output shape: "KEY = VALUE" (yq adds spaces around =)
        placeholder="${binding%% =*}"
        field_path="${binding#*= }"
        [[ -z "$placeholder" || -z "$field_path" ]] && continue
        # R2 HIGH (team-red): field_path is consumer-authored cluster.yaml
        # content and gets interpolated into a yq expression below — strict
        # charset blocks yq-expression injection (comma/pipe/coalesce
        # operators, square-brackets, parentheses).
        # R3 HIGH (team-red): also scope the path to the machine.* subtree
        # so a malicious binding RHS cannot traverse into cluster.* or
        # other root-level keys that the per-node yaml may carry by
        # accident (e.g. via a templating copy-paste) — preventing
        # value-exfiltration into the substituted patch and the talosctl
        # argv (visible in CI logs / argv-dump).
        if ! [[ "$field_path" =~ ^machine[.][A-Za-z_][A-Za-z0-9_.-]*$ ]]; then
            echo "ERROR: placeholder_bindings.$placeholder value '$field_path' violates field-path charset ^machine[.][A-Za-z_][A-Za-z0-9_.-]*\$ — refused (potential yq-expression injection or out-of-scope traversal). Field paths must address fields under nodes/<n>.yaml's 'machine.*' subtree." >&2
            exit 1
        fi
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

# R2 MED: detect duplicate placeholder names across capabilities (silent
# first-write semantics in sed render is non-deterministic on cap-iteration
# order; fail-closed instead with a named diagnostic).
if [[ -s "$BINDINGS_FILE" ]]; then
    DUP_NAMES=$(awk -F'\t' '{print $1}' "$BINDINGS_FILE" | sort | uniq -d || true)
    if [[ -n "$DUP_NAMES" ]]; then
        echo "ERROR: duplicate placeholder names across capabilities (each placeholder must be declared by exactly one capability):" >&2
        echo "$DUP_NAMES" | sed 's/^/  /' >&2
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# Helper: emit one --config-patch flag. If the patch contains ${PLACEHOLDER}
# tokens, render via resolve-placeholders.sh into tmpdir and emit the rendered
# path; otherwise emit @<source-path> verbatim (bit-identical with legacy).
# ---------------------------------------------------------------------------
emit_patch() {
    local patch="$1"
    local resolved_dir base rendered abs_patch emit_path
    # Patch resolution: CWD-first overlay, BASE_DIR fallback.
    #   1. absolute path → use as-is
    #   2. CWD-relative path exists → consumer-local overlay wins (consumer-talos/patches/<x>)
    #   3. $BASE_DIR/<patch> exists → base-shipped patch
    #   4. otherwise → fail loud
    # The emitted talosctl @<path> stays in the same form so talosctl finds
    # the file relative to its CWD (caller-controlled, e.g. consumer-talos/).
    if [[ "$patch" == /* ]]; then
        abs_patch="$patch"
        emit_path="$patch"
    elif [[ -f "$patch" ]]; then
        abs_patch="$patch"
        emit_path="$patch"
    elif [[ -f "$BASE_DIR/$patch" ]]; then
        abs_patch="$BASE_DIR/$patch"
        emit_path="$BASE_DIR/$patch"
    else
        echo "ERROR: patch file not found in CWD nor under \$BASE_DIR ($BASE_DIR): $patch" >&2
        exit 1
    fi
    if grep -qE '\$\{[A-Z][A-Z0-9_]*\}' "$abs_patch"; then
        resolved_dir="$TMPDIR_LOCAL/patches"
        mkdir -p "$resolved_dir"
        base=$(basename "$patch")
        rendered="$resolved_dir/$base"
        bash "$BASE_DIR/scripts/resolve-placeholders.sh" "$abs_patch" "$BINDINGS_FILE" > "$rendered"
        echo "--config-patch"
        echo "@$rendered"
    else
        echo "--config-patch"
        echo "@$emit_path"
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
# SECRETS_FILE env var overrides the default for ephemeral SOPS decryption
# in Makefile.lib gen-configs (mktemp+trap). Default preserves legacy
# bit-identity tests (`.work/p2-talos-oci/argv-dump/` golden expects
# the literal '.secrets.dec.yaml').
echo "${SECRETS_FILE:-.secrets.dec.yaml}"

# R2 HIGH (reviewer): simplify NTP precedence. NTP is a platform baseline
# the consumer may override at any layer (role-patch or per-node patch).
# Always emit NTP as the FIRST patch (before any role-patch); every
# subsequent --config-patch then has the chance to override
# machine.time.servers. This drops the prior "after first common.yaml"
# heuristic + fallback, which produced different precedences for roles
# with vs without common.yaml and contradicted the production-safe claim.
# Documented in talos/RELEASE-NOTES-v0.5.2.md §CRIT-4.
if [[ -n "$NTP_PATCH_FILE" ]]; then
    echo "--config-patch"
    echo "@$NTP_PATCH_FILE"
fi

# Emit role patches in declared order; each may override the NTP baseline.
while IFS= read -r patch; do
    emit_patch "$patch"
done < "$ROLE_PATCHES_FILE"

# Auto-compose file-form cap.patches[]:
# For each hardware-capability on this node, emit its patches[].file entries
# (in cap-list order). Inline {pointer, value} entries remain declarative-only
# (see talos/schemas/cluster.schema.json $defs.hardware-capability-spec.patches).
# Cap-patches are emitted AFTER role-patches so capability-specific overrides
# take precedence (later --config-patch wins in talosctl merge semantics).
# Duplicate-file detection across role+cap and inter-cap is intentionally not
# implemented here; validate-schematics surfaces it as a diagnostic.
while IFS= read -r cap; do
    [[ -z "$cap" ]] && continue
    [[ "$cap" =~ ^[A-Za-z0-9._-]+$ ]] || continue
    while IFS= read -r patch_file; do
        [[ -z "$patch_file" || "$patch_file" == "null" ]] && continue
        emit_patch "$patch_file"
    done < <(yq -r ".\"hardware-capabilities\".\"$cap\".patches // [] | .[] | select(has(\"file\")) | .file" "$CLUSTER_YAML" 2>/dev/null)
done < "$NODE_CAPS_FILE"

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
