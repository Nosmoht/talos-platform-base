#!/usr/bin/env bash
# check-capability-index-refs.sh — cross-reference validation for the
# Layer A Tool-Capability-Index against (a) the on-disk infrastructure
# component set and (b) the Layer B PNI capability registry.
#
# Per docs/adr-two-layer-capability-architecture.md §"Validation":
#   - composition[] entries exist as base infra directories or are marked
#     external (source.external truthy).
#   - replaced_by / split_into resolve to another Layer A capability id.
#   - pni_capability_id is null OR resolves to a Layer B entry.
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
PNI_REGISTRY="$REPO_ROOT/kubernetes/base/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml"
INFRA_DIR="$REPO_ROOT/kubernetes/base/infrastructure"

case "${1:-}" in
  --help|-h)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

command -v yq >/dev/null 2>&1 || { echo "ERROR: yq not found in PATH" >&2; exit 2; }
[ -f "$INDEX_FILE" ] || { echo "ERROR: index not found: $INDEX_FILE" >&2; exit 2; }
[ -f "$PNI_REGISTRY" ] || { echo "ERROR: PNI registry not found: $PNI_REGISTRY" >&2; exit 2; }
[ -d "$INFRA_DIR" ] || { echo "ERROR: infra dir not found: $INFRA_DIR" >&2; exit 2; }

violations=0
violate() { echo "refs: $*" >&2; violations=$((violations + 1)); }

# Build sets:
#   layer_a_ids       — capability ids from the index
#   layer_b_ids       — capability ids from the PNI registry ConfigMap
#   infra_components  — directory basenames under kubernetes/base/infrastructure/
infra_components_file="$(mktemp)"
layer_a_ids_file="$(mktemp)"
layer_b_ids_file="$(mktemp)"
trap 'rm -f "$infra_components_file" "$layer_a_ids_file" "$layer_b_ids_file"' EXIT

find "$INFRA_DIR" -mindepth 1 -maxdepth 1 -type d -print0 \
  | xargs -0 -n1 basename | sort -u > "$infra_components_file"

yq -r '.capabilities[].id' "$INDEX_FILE" | sort -u > "$layer_a_ids_file"

# PNI registry payload is inline YAML under .data."capabilities.yaml".
yq -r '.data."capabilities.yaml"' "$PNI_REGISTRY" \
  | yq -r '.capabilities[].id' - | sort -u > "$layer_b_ids_file"

in_set() {
  grep -qxF "$1" "$2"
}

count="$(yq -r '.capabilities | length' "$INDEX_FILE")"
for i in $(seq 0 $((count - 1))); do
  id="$(yq -r ".capabilities[$i].id" "$INDEX_FILE")"
  prefix=".capabilities[$i] (id=$id)"

  # composition[] entries on each implementation.
  impl_len="$(yq -r ".capabilities[$i].implementations // [] | length" "$INDEX_FILE")"
  for j in $(seq 0 $((impl_len - 1))); do
    impl_name="$(yq -r ".capabilities[$i].implementations[$j].name" "$INDEX_FILE")"
    is_external="$(yq -r ".capabilities[$i].implementations[$j].source.external // false" "$INDEX_FILE")"

    # source.external can be a boolean true OR a non-empty string ("kubernetes"
    # for kube-apiserver, "talos" for the OS, …). Treat any non-false / non-null
    # value as external.
    if [ "$is_external" != "false" ] && [ "$is_external" != "null" ] && [ -n "$is_external" ]; then
      continue
    fi

    comp_len="$(yq -r ".capabilities[$i].implementations[$j].composition // [] | length" "$INDEX_FILE")"
    # Empty composition is only a violation for non-external active impls.
    # Considered / candidate impls represent design alternatives — they need
    # not point at a deployed component.
    impl_status="$(yq -r ".capabilities[$i].implementations[$j].status" "$INDEX_FILE")"
    if [ "$comp_len" -eq 0 ]; then
      if [ "$impl_status" = "active" ]; then
        violate "$prefix .implementations[$j] ($impl_name): non-external active impl but composition is empty"
      fi
      continue
    fi
    for k in $(seq 0 $((comp_len - 1))); do
      comp="$(yq -r ".capabilities[$i].implementations[$j].composition[$k]" "$INDEX_FILE")"
      if [ -z "$comp" ] || [ "$comp" = "null" ]; then
        violate "$prefix .implementations[$j] ($impl_name).composition[$k]: empty"
      elif ! in_set "$comp" "$infra_components_file"; then
        violate "$prefix .implementations[$j] ($impl_name).composition[$k]=$comp: no kubernetes/base/infrastructure/$comp/ directory"
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
done

if [ "$violations" -gt 0 ]; then
  echo "check-capability-index-refs: $violations violation(s)" >&2
  exit 1
fi

echo "OK: cross-references resolve ($(wc -l < "$layer_a_ids_file" | tr -d ' ') Layer A ids, $(wc -l < "$layer_b_ids_file" | tr -d ' ') Layer B ids, $(wc -l < "$infra_components_file" | tr -d ' ') infra components)"
