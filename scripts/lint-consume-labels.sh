#!/usr/bin/env bash
# lint-consume-labels.sh — validate platform.io/consume.* and capability-consumer.*
# label usage in consumer kustomizations against the vendored PNI registry.
#
# Intended to be invoked from consumer cluster repos after
# `oras pull` has populated `vendor/base/`. Can also run from this base
# repo against its own kustomize tree.
#
# Usage:
#   scripts/lint-consume-labels.sh <kustomize-root> [--registry <path>]
#
# Exit codes:
#   0  all consume.* labels reference a non-deprecated registry id
#   1  one or more labels reference unknown or already-sunset ids
#   2  invocation error
#
# Dependencies: yq (mikefarah, v4+), grep, find. Bash 3.2+ compatible.

set -euo pipefail

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_REGISTRY="$REPO_ROOT/kubernetes/base/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml"

kustomize_root=""
registry_path="$DEFAULT_REGISTRY"

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --registry) registry_path="$2"; shift 2 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *)
      if [ -z "$kustomize_root" ]; then
        kustomize_root="$1"
      else
        echo "unexpected positional argument: $1" >&2; exit 2
      fi
      shift
      ;;
  esac
done

if [ -z "$kustomize_root" ]; then
  echo "ERROR: missing <kustomize-root> argument" >&2
  usage >&2
  exit 2
fi

[ -d "$kustomize_root" ] || { echo "ERROR: not a directory: $kustomize_root" >&2; exit 2; }
[ -f "$registry_path" ] || { echo "ERROR: registry not found: $registry_path" >&2; exit 2; }
command -v yq >/dev/null 2>&1 || { echo "ERROR: yq not found in PATH" >&2; exit 2; }

today="$(date -u +%Y-%m-%d)"
caps_yaml="$(yq -r '.data."capabilities.yaml"' "$registry_path")"

# Materialize registry lookup as a TSV temp file: id<TAB>instanced<TAB>deprecated<TAB>sunset.
# Bash 3.2 has no associative arrays; grep against this file is portable.
registry_tsv="$(mktemp)"
trap 'rm -f "$registry_tsv"' EXIT
echo "$caps_yaml" | yq -r '.capabilities[] | [.id, (.instanced // false), (.deprecated // false), (.sunset // "")] | @tsv' > "$registry_tsv"

# Helper: returns first matching line of registry_tsv where field 1 == $1.
lookup_id() {
  awk -F'\t' -v id="$1" '$1 == id { print; exit 0 }' "$registry_tsv"
}

findings_unknown=0
findings_sunset_passed=0
findings_deprecated_use=0
findings_instanced_no_suffix=0

# Scan kustomize tree for consume.* / capability-consumer.* labels.
while IFS= read -r match; do
  file="${match%%:*}"
  rest="${match#*:}"
  key="$(echo "$rest" | grep -oE 'platform\.io/(consume|capability-consumer)\.[a-z0-9.-]+' | head -1)"
  [ -z "$key" ] && continue

  # Strip prefix.
  suffix="${key#platform.io/consume.}"
  suffix="${suffix#platform.io/capability-consumer.}"
  # Find the longest prefix of suffix that is a known capability id by
  # trying suffix, suffix-without-last-dot-segment, etc.
  cap_id=""
  remainder="$suffix"
  while [ -n "$remainder" ]; do
    if [ -n "$(lookup_id "$remainder")" ]; then
      cap_id="$remainder"
      break
    fi
    next="${remainder%.*}"
    [ "$next" = "$remainder" ] && break
    remainder="$next"
  done

  if [ -z "$cap_id" ]; then
    echo "UNKNOWN $file: capability id in label '$key' is not in the registry"
    findings_unknown=$((findings_unknown + 1))
    continue
  fi

  reg_line="$(lookup_id "$cap_id")"
  reg_instanced="$(echo "$reg_line" | awk -F'\t' '{print $2}')"
  reg_deprecated="$(echo "$reg_line" | awk -F'\t' '{print $3}')"
  reg_sunset="$(echo "$reg_line" | awk -F'\t' '{print $4}')"

  instance_suffix="${suffix#"$cap_id"}"
  instance_suffix="${instance_suffix#.}"

  if [ "$reg_instanced" = "true" ] && [ -z "$instance_suffix" ]; then
    echo "MISSING-INSTANCE $file: capability '$cap_id' is instanced but no <instance> suffix in '$key'"
    findings_instanced_no_suffix=$((findings_instanced_no_suffix + 1))
  fi

  if [ "$reg_deprecated" = "true" ]; then
    if [ -n "$reg_sunset" ] && [ "$today" \> "$reg_sunset" ]; then
      echo "SUNSET-PASSED $file: capability '$cap_id' sunset $reg_sunset is in the past"
      findings_sunset_passed=$((findings_sunset_passed + 1))
    else
      echo "DEPRECATED $file: capability '$cap_id' is deprecated (sunset $reg_sunset); update before sunset"
      findings_deprecated_use=$((findings_deprecated_use + 1))
    fi
  fi
done < <(grep -rEn 'platform\.io/(consume|capability-consumer)\.' "$kustomize_root" --include='*.yaml' --include='*.yml' 2>/dev/null || true)

echo ""
echo "Summary:"
echo "  unknown ids:                $findings_unknown"
echo "  sunset already passed:      $findings_sunset_passed"
echo "  deprecated (within grace):  $findings_deprecated_use"
echo "  instanced w/o suffix:       $findings_instanced_no_suffix"

if [ $findings_unknown -gt 0 ] || [ $findings_sunset_passed -gt 0 ] || [ $findings_instanced_no_suffix -gt 0 ]; then
  exit 1
fi
exit 0
