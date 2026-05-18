#!/usr/bin/env bash
# lint-capability-index.sh — schema lint for docs/platform-capability-index.yaml
# (Layer A — Tool-Capability-Index).
#
# Per docs/adr-two-layer-capability-architecture.md §"Validation (CI required
# checks)". This script is a form-check only: required fields, kebab-case ids,
# enum validity, ISO-8601 dates. Cross-reference validation lives in the sibling
# check-capability-index-refs.sh.
#
# Usage:
#   scripts/lint-capability-index.sh              # lint default index file
#   scripts/lint-capability-index.sh <file>       # lint an alternate file
#
# Exit codes:
#   0 — every capability entry passes the lint rules.
#   1 — at least one violation found; all violations printed to stderr.
#   2 — environment / argument error.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INDEX_FILE="${1:-$REPO_ROOT/docs/platform-capability-index.yaml}"

case "${1:-}" in
  --help|-h)
    sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

command -v yq >/dev/null 2>&1 || { echo "ERROR: yq not found in PATH" >&2; exit 2; }
[ -f "$INDEX_FILE" ] || { echo "ERROR: index file not found: $INDEX_FILE" >&2; exit 2; }

violations=0
violate() { echo "lint: $*" >&2; violations=$((violations + 1)); }

# Top-level required fields.
for top in schema_version base_version default_owner capabilities; do
  if [ "$(yq -r "has(\"$top\")" "$INDEX_FILE")" != "true" ]; then
    violate "top-level field missing: .$top"
  fi
done

count="$(yq -r '.capabilities | length' "$INDEX_FILE")"
if [ -z "$count" ] || [ "$count" -lt 1 ]; then
  violate "no capabilities found"
  exit 1
fi

VALID_STABILITY="alpha beta ga deprecated"
VALID_TOPOLOGY="host-singleton host-only tenant-instance host-and-tenant"
VALID_SWAP_CLASS="drop-in label-move data-migration consumer-change rewrite-required"
VALID_IMPL_STATUS="active candidate considered deprecated"

is_in_set() {
  local needle="$1"; shift
  for v in "$@"; do
    [ "$needle" = "$v" ] && return 0
  done
  return 1
}

is_kebab() {
  printf '%s\n' "$1" | grep -Eq '^[a-z][a-z0-9]*(-[a-z0-9]+)*$'
}

is_iso8601_date() {
  printf '%s\n' "$1" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
}

# Track ids to detect duplicates.
seen_ids_file="$(mktemp)"
trap 'rm -f "$seen_ids_file"' EXIT

for i in $(seq 0 $((count - 1))); do
  id="$(yq -r ".capabilities[$i].id // \"\"" "$INDEX_FILE")"
  prefix=".capabilities[$i]"
  [ -n "$id" ] && prefix=".capabilities[$i] (id=$id)"

  # id present and kebab-case.
  if [ -z "$id" ]; then
    violate "$prefix: missing id"
  elif ! is_kebab "$id"; then
    violate "$prefix: id is not kebab-case"
  fi
  if [ -n "$id" ]; then
    if grep -qxF "$id" "$seen_ids_file"; then
      violate "$prefix: duplicate id"
    else
      echo "$id" >> "$seen_ids_file"
    fi
  fi

  # Required scalar fields.
  for f in name description stability contract; do
    val="$(yq -r ".capabilities[$i].$f // \"\"" "$INDEX_FILE")"
    if [ -z "$val" ] || [ "$val" = "null" ]; then
      violate "$prefix: missing .$f"
    fi
  done

  # Required nested: domain.layer, domain.category.
  for sub in layer category; do
    val="$(yq -r ".capabilities[$i].domain.$sub // \"\"" "$INDEX_FILE")"
    if [ -z "$val" ] || [ "$val" = "null" ]; then
      violate "$prefix: missing .domain.$sub"
    fi
  done

  # Required nested: independence_test fields.
  # has() instead of `// "missing"` — yq's // treats `false` as null.
  for it in alt_impls_exist contract_stable independent_lifecycle; do
    present="$(yq -r ".capabilities[$i].independence_test | has(\"$it\")" "$INDEX_FILE")"
    if [ "$present" != "true" ]; then
      violate "$prefix: missing .independence_test.$it"
      continue
    fi
    val="$(yq -r ".capabilities[$i].independence_test.$it" "$INDEX_FILE")"
    if [ "$val" != "true" ] && [ "$val" != "false" ]; then
      violate "$prefix: .independence_test.$it must be boolean (got: $val)"
    fi
  done

  # stability enum.
  stab="$(yq -r ".capabilities[$i].stability // \"\"" "$INDEX_FILE")"
  if [ -n "$stab" ] && ! is_in_set "$stab" $VALID_STABILITY; then
    violate "$prefix: .stability=$stab not in {$VALID_STABILITY}"
  fi

  # alpha requires explanatory notes. Per ADR §"alpha — notes field
  # mandatory explaining why an entry exists at this stage." Notes may
  # live either at top-level or inside independence_test.
  if [ "$stab" = "alpha" ]; then
    notes_top="$(yq -r ".capabilities[$i].notes // \"\"" "$INDEX_FILE")"
    notes_it="$(yq -r ".capabilities[$i].independence_test.notes // \"\"" "$INDEX_FILE")"
    if [ -z "$notes_top" ] && [ -z "$notes_it" ]; then
      violate "$prefix: stability=alpha requires .notes (top-level or .independence_test.notes)"
    fi
  fi

  # deprecated entries: replaced_by or split_into, plus sunset.{date,tag}.
  if [ "$stab" = "deprecated" ]; then
    replaced="$(yq -r ".capabilities[$i].replaced_by // \"\"" "$INDEX_FILE")"
    split_len="$(yq -r ".capabilities[$i].split_into // [] | length" "$INDEX_FILE")"
    if [ -z "$replaced" ] && [ "$split_len" -eq 0 ]; then
      violate "$prefix: stability=deprecated requires .replaced_by or .split_into"
    fi
    sunset_date="$(yq -r ".capabilities[$i].sunset.date // \"\"" "$INDEX_FILE")"
    sunset_tag="$(yq -r ".capabilities[$i].sunset.tag // \"\"" "$INDEX_FILE")"
    if [ -z "$sunset_date" ]; then
      violate "$prefix: stability=deprecated requires .sunset.date"
    elif ! is_iso8601_date "$sunset_date"; then
      violate "$prefix: .sunset.date=$sunset_date not ISO-8601 (YYYY-MM-DD)"
    fi
    if [ -z "$sunset_tag" ]; then
      violate "$prefix: stability=deprecated requires .sunset.tag"
    fi
  fi

  # deployment_topology optional but enum-restricted when present.
  topo="$(yq -r ".capabilities[$i].deployment_topology // \"\"" "$INDEX_FILE")"
  if [ -n "$topo" ] && [ "$topo" != "null" ] && ! is_in_set "$topo" $VALID_TOPOLOGY; then
    violate "$prefix: .deployment_topology=$topo not in {$VALID_TOPOLOGY}"
  fi

  # implementations: must be non-empty, each with name, status, swap_class.
  impl_len="$(yq -r ".capabilities[$i].implementations // [] | length" "$INDEX_FILE")"
  if [ "$impl_len" -lt 1 ]; then
    violate "$prefix: .implementations is empty"
  fi
  for j in $(seq 0 $((impl_len - 1))); do
    impl_name="$(yq -r ".capabilities[$i].implementations[$j].name // \"\"" "$INDEX_FILE")"
    impl_status="$(yq -r ".capabilities[$i].implementations[$j].status // \"\"" "$INDEX_FILE")"
    impl_swap="$(yq -r ".capabilities[$i].implementations[$j].swap_class // \"\"" "$INDEX_FILE")"
    iprefix="$prefix.implementations[$j]"
    [ -n "$impl_name" ] && iprefix="$prefix.implementations[$j] ($impl_name)"

    [ -z "$impl_name" ] && violate "$iprefix: missing .name"
    if [ -z "$impl_status" ]; then
      violate "$iprefix: missing .status"
    elif ! is_in_set "$impl_status" $VALID_IMPL_STATUS; then
      violate "$iprefix: .status=$impl_status not in {$VALID_IMPL_STATUS}"
    fi
    if [ -z "$impl_swap" ]; then
      violate "$iprefix: missing .swap_class"
    elif ! is_in_set "$impl_swap" $VALID_SWAP_CLASS; then
      violate "$iprefix: .swap_class=$impl_swap not in {$VALID_SWAP_CLASS}"
    fi
  done
done

if [ "$violations" -gt 0 ]; then
  echo "lint-capability-index: $violations violation(s) in $INDEX_FILE" >&2
  exit 1
fi

echo "OK: $(yq -r '.capabilities | length' "$INDEX_FILE") capabilities pass lint"
