#!/usr/bin/env bash
# check-capability-index-refs.sh — cross-reference validation for the
# Layer A Tool-Capability-Index against:
#   (a) the on-disk infrastructure component set,
#   (b) the Layer B PNI capability registry (the network-trust subset),
#   (c) the Layer C hardware-features registry (atomic hardware predicates).
#
# Per docs/adr-three-layer-capability-architecture.md §"Validation tooling"
# (extending the original two-artifact contract from the superseded
# Two-Layer ADR):
#   - composition[] entries exist as base infra directories or are marked
#     external (source.external truthy).
#   - replaced_by / split_into resolve to another Layer A capability id.
#   - pni_capability_id is null OR resolves to a Layer B entry.
#   - requires_hardware_features[] entries resolve to Layer C ids.
#   - orphan-infra-dir advisory: dirs under kubernetes/base/infrastructure/
#     not referenced by any Layer-A composition[] AND not in the Layer-C
#     producer-tooling allow-list emit a WARN line (informational; not a fail).
#
# Usage:
#   scripts/check-capability-index-refs.sh
#
# Exit codes:
#   0 — every cross-reference resolves.
#   1 — at least one unresolved reference.
#   2 — environment / file error.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INDEX_FILE="$REPO_ROOT/docs/platform-capability-index.yaml"
HW_FEATURES_FILE="$REPO_ROOT/docs/platform-hardware-features.yaml"
PNI_REGISTRY="$REPO_ROOT/kubernetes/base/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml"
INFRA_DIR="$REPO_ROOT/kubernetes/base/infrastructure"

# Expected non-Layer-A infrastructure directories — dirs under
# kubernetes/base/infrastructure/ that are load-bearing but legitimately
# don't appear in any Layer-A composition[]. Per
# adr-three-layer-capability-architecture.md §"NFD placement": NFD is
# Layer-C producer-tooling, NOT Layer-A composition. PNI is policy/
# admission machinery, not a tool capability. Both are expected to show
# clean (no orphan WARN); future tooling-only dirs should be added here.
# Keep this list small and audit periodically.
EXPECTED_NON_LAYER_A_DIRS="node-feature-discovery platform-network-interface"

case "${1:-}" in
  --help|-h)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

command -v yq >/dev/null 2>&1 || { echo "ERROR: yq not found in PATH" >&2; exit 2; }
[ -f "$INDEX_FILE" ] || { echo "ERROR: index not found: $INDEX_FILE" >&2; exit 2; }
[ -f "$HW_FEATURES_FILE" ] || { echo "ERROR: hardware-features registry not found: $HW_FEATURES_FILE" >&2; exit 2; }
[ -f "$PNI_REGISTRY" ] || { echo "ERROR: PNI registry not found: $PNI_REGISTRY" >&2; exit 2; }
[ -d "$INFRA_DIR" ] || { echo "ERROR: infra dir not found: $INFRA_DIR" >&2; exit 2; }

violations=0
violate() { echo "refs: $*" >&2; violations=$((violations + 1)); }

# Build sets:
#   layer_a_ids       — capability ids from the Layer A index
#   layer_b_ids       — capability ids from the Layer B PNI registry ConfigMap
#   layer_c_ids       — hardware-feature ids from the Layer C registry
#   infra_components  — directory basenames under kubernetes/base/infrastructure/
#   referenced_dirs   — infra dirs referenced by any Layer-A composition[]
infra_components_file="$(mktemp)"
layer_a_ids_file="$(mktemp)"
layer_b_ids_file="$(mktemp)"
layer_c_ids_file="$(mktemp)"
referenced_dirs_file="$(mktemp)"
trap 'rm -f "$infra_components_file" "$layer_a_ids_file" "$layer_b_ids_file" "$layer_c_ids_file" "$referenced_dirs_file"' EXIT

find "$INFRA_DIR" -mindepth 1 -maxdepth 1 -type d -print0 \
  | xargs -0 -n1 basename | sort -u > "$infra_components_file"

yq -r '.capabilities[].id' "$INDEX_FILE" | sort -u > "$layer_a_ids_file"

# PNI registry payload is inline YAML under .data."capabilities.yaml".
yq -r '.data."capabilities.yaml"' "$PNI_REGISTRY" \
  | yq -r '.capabilities[].id' - | sort -u > "$layer_b_ids_file"

# Layer C — flat list of hardware-feature ids.
yq -r '.hardware_features[].id' "$HW_FEATURES_FILE" | sort -u > "$layer_c_ids_file"

in_set() {
  grep -qxF "$1" "$2"
}

count="$(yq -r '.capabilities | length' "$INDEX_FILE")"
for i in $(seq 0 $((count - 1))); do
  id="$(yq -r ".capabilities[$i].id" "$INDEX_FILE")"
  prefix=".capabilities[$i] (id=$id)"

  # Per #62: when an entry is `kind: network-primitive`, it's a CIDR-based
  # CCNP / Gateway-API selector permission / cluster-singleton plumbing
  # with no tool composition — the rule itself IS the dataplane. Skip the
  # empty-composition check for these entries.
  entry_kind="$(yq -r ".capabilities[$i].kind // \"tool-capability\"" "$INDEX_FILE")"

  # composition[] entries on each implementation.
  impl_len="$(yq -r ".capabilities[$i].implementations // [] | length" "$INDEX_FILE")"
  for j in $(seq 0 $((impl_len - 1))); do
    impl_name="$(yq -r ".capabilities[$i].implementations[$j].name" "$INDEX_FILE")"
    is_external="$(yq -r ".capabilities[$i].implementations[$j].source.external // false" "$INDEX_FILE")"
    # Per-impl external_network_attachment flag (#62 hybrid for s3-object's
    # external-s3 impl): treat as external (no composition expected).
    is_ena="$(yq -r ".capabilities[$i].implementations[$j].external_network_attachment // false" "$INDEX_FILE")"

    # source.external can be a boolean true OR a non-empty string ("kubernetes"
    # for kube-apiserver, "talos" for the OS, …). Treat any non-false / non-null
    # value as external.
    if [ "$is_external" != "false" ] && [ "$is_external" != "null" ] && [ -n "$is_external" ]; then
      continue
    fi
    # External-network-attachment impls (#62) are also treated as external.
    if [ "$is_ena" = "true" ]; then
      continue
    fi

    comp_len="$(yq -r ".capabilities[$i].implementations[$j].composition // [] | length" "$INDEX_FILE")"
    # Empty composition is only a violation for non-external active impls in
    # tool-capability entries. Considered/candidate impls represent design
    # alternatives. Network-primitive entries (#62) legitimately have empty
    # composition — the network-policy rule itself IS the dataplane.
    impl_status="$(yq -r ".capabilities[$i].implementations[$j].status" "$INDEX_FILE")"
    if [ "$comp_len" -eq 0 ]; then
      if [ "$impl_status" = "active" ] && [ "$entry_kind" != "network-primitive" ]; then
        violate "$prefix .implementations[$j] ($impl_name): non-external active impl but composition is empty (kind=$entry_kind)"
      fi
      continue
    fi
    for k in $(seq 0 $((comp_len - 1))); do
      comp="$(yq -r ".capabilities[$i].implementations[$j].composition[$k]" "$INDEX_FILE")"
      if [ -z "$comp" ] || [ "$comp" = "null" ]; then
        violate "$prefix .implementations[$j] ($impl_name).composition[$k]: empty"
      elif ! in_set "$comp" "$infra_components_file"; then
        violate "$prefix .implementations[$j] ($impl_name).composition[$k]=$comp: no kubernetes/base/infrastructure/$comp/ directory"
      else
        echo "$comp" >> "$referenced_dirs_file"
      fi
    done
  done

  # replaced_by → Layer A id.
  replaced="$(yq -r ".capabilities[$i].replaced_by // \"\"" "$INDEX_FILE")"
  if [ -n "$replaced" ] && [ "$replaced" != "null" ]; then
    if ! in_set "$replaced" "$layer_a_ids_file"; then
      violate "$prefix .replaced_by=$replaced: not a Layer A capability id"
    fi
  fi

  # split_into[] → Layer A ids.
  split_len="$(yq -r ".capabilities[$i].split_into // [] | length" "$INDEX_FILE")"
  if [ "$split_len" -gt 0 ]; then
    for k in $(seq 0 $((split_len - 1))); do
      s="$(yq -r ".capabilities[$i].split_into[$k]" "$INDEX_FILE")"
      if ! in_set "$s" "$layer_a_ids_file"; then
        violate "$prefix .split_into[$k]=$s: not a Layer A capability id"
      fi
    done
  fi

  # pni_capability_id → Layer B id (null is fine).
  pni="$(yq -r ".capabilities[$i].pni_capability_id // \"null\"" "$INDEX_FILE")"
  if [ -n "$pni" ] && [ "$pni" != "null" ]; then
    if ! in_set "$pni" "$layer_b_ids_file"; then
      violate "$prefix .pni_capability_id=$pni: not a Layer B (PNI registry) capability id"
    fi
  fi

  # composed_of[] entries on the capability itself → Layer A ids.
  co_len="$(yq -r ".capabilities[$i].composed_of // [] | length" "$INDEX_FILE")"
  if [ "$co_len" -gt 0 ]; then
    for k in $(seq 0 $((co_len - 1))); do
      c="$(yq -r ".capabilities[$i].composed_of[$k]" "$INDEX_FILE")"
      if ! in_set "$c" "$layer_a_ids_file"; then
        violate "$prefix .composed_of[$k]=$c: not a Layer A capability id"
      fi
    done
  fi

  # requires_hardware_features[] → Layer C ids.
  rhf_len="$(yq -r ".capabilities[$i].requires_hardware_features // [] | length" "$INDEX_FILE")"
  if [ "$rhf_len" -gt 0 ]; then
    for k in $(seq 0 $((rhf_len - 1))); do
      fid="$(yq -r ".capabilities[$i].requires_hardware_features[$k]" "$INDEX_FILE")"
      if ! in_set "$fid" "$layer_c_ids_file"; then
        violate "$prefix .requires_hardware_features[$k]=$fid: not a Layer C (hardware-features) id"
      fi
    done
  fi
done

# Orphan-infra-dir detection (advisory). A directory under
# kubernetes/base/infrastructure/ is "orphan" if no Layer-A composition[]
# references it AND it is not a known Layer-C producer-tooling
# component (NFD). Emit a WARN line per orphan; do NOT fail.
# Per Phase 4 AC: advisory in v1.
sort -u -o "$referenced_dirs_file" "$referenced_dirs_file" 2>/dev/null || true
while IFS= read -r dir; do
  in_set "$dir" "$referenced_dirs_file" && continue
  is_expected=false
  for c_dir in $EXPECTED_NON_LAYER_A_DIRS; do
    [ "$dir" = "$c_dir" ] && { is_expected=true; break; }
  done
  $is_expected && continue
  echo "WARN: orphan-infra-dir kubernetes/base/infrastructure/$dir/" >&2
done < "$infra_components_file"

if [ "$violations" -gt 0 ]; then
  echo "check-capability-index-refs: $violations violation(s)" >&2
  exit 1
fi

echo "OK: cross-references resolve ($(wc -l < "$layer_a_ids_file" | tr -d ' ') Layer A ids, $(wc -l < "$layer_b_ids_file" | tr -d ' ') Layer B ids, $(wc -l < "$layer_c_ids_file" | tr -d ' ') Layer C ids, $(wc -l < "$infra_components_file" | tr -d ' ') infra components)"
