#!/bin/sh
# vault-ca-distribution-smoke.sh — assert that the label-based exclude
# path on pni-vault-ca-distribution correctly filters out
# privileged-profile and opt-out namespaces.
#
# kyverno-cli `test` cannot express a `skip` expectation when the
# policy match/exclude filters silently drop a resource (no result is
# emitted). This driver runs `kyverno apply --policy-report` against
# the same resources.yaml and asserts the report contains EXACTLY one
# rule application (tenant-consumer) and zero entries for the
# excluded namespaces.
#
# Verification invariant: pass=1, others=0. Any drift indicates the
# label-based exclude block broke.

set -eu

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
POLICY="${REPO_ROOT}/kubernetes/base/infrastructure/platform-network-interface/resources/kyverno-clusterpolicy-vault-ca-distribution.yaml"
RESOURCES="${REPO_ROOT}/kubernetes/base/infrastructure/platform-network-interface/resources/tests/vault-ca-distribution/resources.yaml"

if [ ! -f "$POLICY" ] || [ ! -f "$RESOURCES" ]; then
  echo "FATAL: required fixture missing" >&2
  exit 2
fi

command -v kyverno >/dev/null 2>&1 || {
  echo "FATAL: kyverno-cli not in PATH" >&2
  exit 2
}
command -v yq >/dev/null 2>&1 || {
  echo "FATAL: yq not in PATH" >&2
  exit 2
}

report=$(kyverno apply "$POLICY" --resource "$RESOURCES" --policy-report 2>/dev/null)

total=$(printf '%s' "$report" | yq '.results | length' 2>/dev/null || echo 0)
pass_count=$(printf '%s' "$report" | yq '[.results[] | select(.result == "pass")] | length' 2>/dev/null || echo 0)

if [ "$total" != "1" ]; then
  echo "FAIL: expected 1 rule application, got $total"
  printf '%s\n' "$report" >&2
  exit 1
fi
if [ "$pass_count" != "1" ]; then
  echo "FAIL: expected 1 pass, got $pass_count"
  printf '%s\n' "$report" >&2
  exit 1
fi

target=$(printf '%s' "$report" | yq -r '.results[0].resources[0].name' 2>/dev/null)
if [ "$target" != "tenant-consumer" ]; then
  echo "FAIL: expected the single result to be 'tenant-consumer', got '$target'"
  printf '%s\n' "$report" >&2
  exit 1
fi

echo "PASS: vault-ca-distribution label-based exclude correctly filters all opt-out cases"
