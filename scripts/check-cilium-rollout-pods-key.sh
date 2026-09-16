#!/usr/bin/env bash
# Regression fence for the Cilium agent-roll key's Helm KEY SPELLING (issue #270).
#
# Helm merges values without `--strict`: a values key the chart does not
# recognise is discarded with no error and no warning. So writing
# `rolloutCiliumPods`, nesting the key one level down, or losing it entirely
# leaves every offline assertion green — while the rendered agent DaemonSet
# carries no cilium.io/cilium-configmap-checksum annotation and a Day-2 values
# change syncs green without ever reaching the running agents. That is exactly
# the defect #270 closes, re-introduced silently.
#
# Why a static fence and not a tofu test: the only assertions that read the
# RENDERED DaemonSet live in tests/composition.tftest.hcl, which resolves the
# live Talos Image Factory. Its CI job is ADVISORY by design, and
# `task tofu:ci` deliberately excludes it. This fence is offline and rides
# tofu:ci. Same rationale and shape as check-cilium-operator-replicas-key.sh.
#
# Scope, honestly: this binds the spelling on the module's own side only. It
# cannot detect a chart that renames the key upstream — nothing offline can,
# since that fact lives in the chart. The composition runs
# cilium_seed_render_rolls_agents_on_configmap_change and
# cilium_seed_render_roll_is_overridable remain the only check of the RENDERED
# annotation; a chart-side rename surfaces there, or at the next
# cilium_chart_version bump. Note also that the tofu-validate job carrying this
# fence is not in branch protection's required contexts, so a red fence reds the
# PR without blocking the merge.
#
# Asserts:
#   C1  helm/cilium-values.yaml carries rollOutCiliumPods at the TOP level with
#       value true. Top-level matters: the chart reads .Values.rollOutCiliumPods,
#       and a nested copy is discarded silently.
#   C2  kubernetes/bootstrap/cilium/values.yaml carries it too. That file is the
#       Day-2 reference a consumer is told to copy; a consumer following the
#       documented copy path must not silently keep the defect.
#
# Exit: 0 all assertions hold, 1 an assertion failed, 2 environment error.
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

# A top-level key starts at column 0. Anchoring the pattern there is what makes
# a nested copy fail rather than satisfy the assertion.
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
