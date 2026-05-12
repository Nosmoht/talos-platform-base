#!/usr/bin/env bash
# capability-deprecation-scan.sh — surface deprecated capability ids used in a
# kustomize tree, optionally failing when any sunset date is in the past.
#
# Companion to lint-consume-labels.sh — narrower scope: report only on
# deprecation. Designed to be run unattended from CI on a schedule, so
# consumer teams see a warning before their alias's sunset passes.
#
# Usage:
#   scripts/capability-deprecation-scan.sh <kustomize-root> [--registry <path>] [--fail-on-sunset]
#
# Exit codes:
#   0  no deprecated capability ids found (or only within-grace usage when --fail-on-sunset is set)
#   1  --fail-on-sunset given and at least one sunset has passed
#   2  invocation error
#
# Dependencies: yq (mikefarah v4+), grep, date. Bash 3.2+ compatible.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_REGISTRY="$REPO_ROOT/kubernetes/base/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml"

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

kustomize_root=""
registry_path="$DEFAULT_REGISTRY"
fail_on_sunset=0

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --registry) registry_path="$2"; shift 2 ;;
    --fail-on-sunset) fail_on_sunset=1; shift ;;
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

# Enumerate deprecated entries into TSV: id<TAB>sunset<TAB>replaced_by<TAB>split_into_csv.
# Portable: tmpfile + grep instead of bash 4 associative arrays.
deprecated_tsv="$(mktemp)"
trap 'rm -f "$deprecated_tsv"' EXIT
echo "$caps_yaml" | yq -r '.capabilities[] | select(.deprecated == true) | [.id, (.sunset // ""), (.replaced_by // ""), (.split_into // [] | join(","))] | @tsv' > "$deprecated_tsv"

if [ ! -s "$deprecated_tsv" ]; then
  echo "no deprecated capabilities in registry — nothing to scan for"
  exit 0
fi

findings_total=0
findings_past_sunset=0

while IFS=$'\t' read -r id sunset replaced split; do
  [ -z "$id" ] && continue

  matches="$(grep -rEln "platform\.io/(consume|capability-consumer)\.${id}(\.|: )" "$kustomize_root" --include='*.yaml' --include='*.yml' 2>/dev/null || true)"
  [ -z "$matches" ] && continue

  status="within grace"
  if [ -n "$sunset" ] && [ "$today" \> "$sunset" ]; then
    status="SUNSET PASSED ($sunset)"
    findings_past_sunset=$((findings_past_sunset + 1))
  elif [ -n "$sunset" ]; then
    status="sunset $sunset"
  fi

  replacement=""
  [ -n "$replaced" ] && replacement="→ $replaced"
  [ -n "$split" ] && replacement="$replacement (split → $split)"

  echo ""
  echo "Deprecated capability '$id' — $status $replacement"
  echo "Files referencing it:"
  echo "$matches" | sed 's/^/  /'
  count="$(echo "$matches" | wc -l | tr -d ' ')"
  findings_total=$((findings_total + count))
done < "$deprecated_tsv"

echo ""
echo "Summary: $findings_total file(s) reference deprecated capabilities; $findings_past_sunset capability(ies) past sunset."

if [ "$fail_on_sunset" -eq 1 ] && [ "$findings_past_sunset" -gt 0 ]; then
  exit 1
fi
exit 0
