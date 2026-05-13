#!/usr/bin/env bash
# verify-tools.sh — confirm installed binaries match .tool-versions pins.
#
# Reads .tool-versions (asdf/mise format) at the repo root. For each
# tool, runs the canonical version-print command, normalises the output,
# and compares against the pinned value.
#
# Exit codes:
#   0 — all tools present at pinned versions
#   1 — at least one tool missing or version mismatch
#
# Used by `make verify-tools` and CI drift-check step.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
TOOLS_FILE="${ROOT}/.tool-versions"

if [ ! -f "${TOOLS_FILE}" ]; then
  echo "error: ${TOOLS_FILE} not found" >&2
  exit 1
fi

# Map asdf-style tool name → (binary, version-extractor).
# Extractors strip leading 'v' and trailing build metadata to compare
# against the pinned token.
extract_version() {
  local tool="$1"
  case "${tool}" in
    helm)        helm version --short 2>/dev/null | sed -E 's/^v//; s/\+.*$//' ;;
    kustomize)   kustomize version 2>/dev/null | sed -E 's/^v//; s/\{.*//' | head -n1 | tr -d '[:space:]' ;;
    oras)        oras version 2>/dev/null | awk '/^Version:/ {print $2}' | sed -E 's/^v//; s/\+.*$//' ;;
    cosign)      cosign version 2>/dev/null | awk '/^GitVersion:/ {print $2}' | sed -E 's/^v//' ;;
    conftest)    conftest --version 2>/dev/null | awk '/^Version:/ {print $2}' | sed -E 's/^v//' ;;
    kyverno-cli) kyverno version 2>/dev/null | awk '/^Version:/ {print $2}' | sed -E 's/^v//' ;;
    kubeconform) kubeconform -v 2>/dev/null | sed -E 's/^v//' ;;
    *) echo "" ;;
  esac
}

binary_for() {
  local tool="$1"
  case "${tool}" in
    kyverno-cli) echo "kyverno" ;;
    *) echo "${tool}" ;;
  esac
}

fail=0
while IFS= read -r line; do
  # Skip comments and blank lines.
  case "${line}" in ''|\#*) continue ;; esac
  tool="$(echo "${line}" | awk '{print $1}')"
  pinned="$(echo "${line}" | awk '{print $2}')"
  bin="$(binary_for "${tool}")"

  if ! command -v "${bin}" >/dev/null 2>&1; then
    printf 'MISSING:  %-12s  (pinned: %s)\n' "${tool}" "${pinned}"
    fail=1
    continue
  fi

  installed="$(extract_version "${tool}")"
  if [ -z "${installed}" ]; then
    printf 'UNKNOWN:  %-12s  (pinned: %s, could not extract installed version)\n' "${tool}" "${pinned}"
    fail=1
    continue
  fi

  if [ "${installed}" = "${pinned}" ]; then
    printf 'OK:       %-12s  %s\n' "${tool}" "${installed}"
  else
    printf 'MISMATCH: %-12s  installed=%s pinned=%s\n' "${tool}" "${installed}" "${pinned}"
    fail=1
  fi
done < "${TOOLS_FILE}"

if [ "${fail}" -eq 0 ]; then
  echo ""
  echo "All tools match .tool-versions pins."
  exit 0
fi
echo ""
echo "One or more tools missing or version-drifted. Install via asdf/mise or fix manually." >&2
exit 1
