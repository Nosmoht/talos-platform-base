#!/usr/bin/env bash
set -uo pipefail

FLOOR="tofu/modules/talos-cluster/helm/cilium-values.yaml"
REFERENCE="kubernetes/bootstrap/cilium/values.yaml"

die_env() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 2
}

[ -f "$FLOOR" ] || die_env "$FLOOR not found — run from the repo root"
[ -f "$REFERENCE" ] || die_env "$REFERENCE not found — run from the repo root"

fail=0

report() {
  printf '  FAIL — %s\n' "$1" >&2
  fail=1
}

assert_top_level_true() {
  local file="$1" label="$2"
  local hit
  hit=$(grep -nE '^rollOutCiliumPods:[[:space:]]*true[[:space:]]*$' "$file")

  if [ -n "$hit" ]; then
    printf '  ok   — %s %s sets rollOutCiliumPods: true at the top level (%s)\n' \
      "$label" "$file" "${hit%%:*}"
    return
  fi

  if grep -qiE '^[[:space:]]*rollout?ciliumpods?:' "$file"; then
    report "$label: $file carries a rollOutCiliumPods-like key that is not a top-level \`rollOutCiliumPods: true\`. Helm discards an unrecognised or mis-nested values key silently, so the agent DaemonSet renders with no checksum annotation and a Day-2 values change never reaches the running agents — with every offline test green."
  else
    report "$label: $file no longer sets rollOutCiliumPods: true. Without it a ConfigMap-only Cilium change syncs green while the agents keep the old configuration (issue #270), and the operator-facing documents that stopped prescribing \`kubectl -n kube-system rollout restart ds/cilium\` are wrong."
  fi
}

assert_top_level_true "$FLOOR" C1
assert_top_level_true "$REFERENCE" C2

if [ "$fail" -eq 0 ]; then
  printf 'check-cilium-rollout-pods-key: OK — the agent-roll key is set in the floor and the Day-2 reference.\n'
fi

exit "$fail"
