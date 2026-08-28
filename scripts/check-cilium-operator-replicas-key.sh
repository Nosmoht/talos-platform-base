#!/usr/bin/env bash
# Regression fence for the Cilium operator replica count's Helm KEY SPELLING.
#
# Helm merges values without `--strict`: a values key the chart does not
# recognise is discarded with no error and no warning. So renaming
# `operator.replicas` to `operator.replica`, nesting it one level wrong, or
# losing the floor key leaves the module's own map exactly as intended — and
# every offline assertion in tests/input-validation.tftest.hcl green — while the
# rendered Deployment silently carries a different number into a create-only
# controlplane inlineManifest.
#
# Why a static fence and not a tofu test: the only assertions that read the
# RENDERED Deployment live in tests/composition.tftest.hcl, which resolves the
# live Talos Image Factory. Its CI job is ADVISORY by design (an upstream outage
# must not block every tofu/** merge), and `task tofu:ci` deliberately excludes
# it. This fence is offline and rides tofu:ci, which the required tofu-validate
# job runs, so the key spelling has a BLOCKING gate. Same rationale and shape as
# check-argocd-day0-apply-shape.sh, check-kubeconfig-endpoint-regen.sh and
# check-node-projection-wiring.sh.
#
# Scope, honestly: this binds the spelling on BOTH sides of the module's own
# contract. It cannot detect a chart that renames the key upstream — nothing
# offline can, since that fact lives in the chart. The composition runs remain
# the only check of the rendered VALUE; a chart-side rename surfaces there, or
# at the next cilium_chart_version bump's reconciliation.
#
# Asserts:
#   C1  cilium-values.tf's local.cilium_operator_values writes the literal key
#       `replicas` (a rename or a nesting change fails).
#   C2  helm/cilium-values.yaml still carries operator.replicas. It is the floor
#       contributor that (i) keeps the explicit `operator` sub-merge falsifiable
#       (mutant M2) and (ii) makes the composition suite's >= 2-node assertion
#       DISCRIMINATE: with the floor gone, a dropped computed key renders the
#       chart's own default of 2 and that assertion passes on the very mutation
#       it exists to catch.
#   C3  the computed contributor is reached through local.cilium_operator_values,
#       i.e. `operator` appears exactly once as a term of the computed merge — a
#       second `operator` term would replace the first wholesale (the level-B
#       collision the file's two-engine-drift invariant records).
#
# Measured in both directions before shipping: each assertion was made to fail on
# its own mutant (key renamed to `replica`; floor key deleted; a second `operator`
# term appended to the computed merge) and to pass on the conforming tree.
#
# Exit: 0 all assertions hold, 1 an assertion failed, 2 environment error.
set -uo pipefail

VALUES_TF="tofu/modules/talos-cluster/cilium-values.tf"
FLOOR="tofu/modules/talos-cluster/helm/cilium-values.yaml"

die_env() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 2
}

[ -f "$VALUES_TF" ] || die_env "$VALUES_TF not found — run from the repo root"
[ -f "$FLOOR" ] || die_env "$FLOOR not found — run from the repo root"

fail=0

report() {
  printf '  FAIL — %s\n' "$1" >&2
  fail=1
}

# C1 — the computed contributor writes the literal chart key.
# Scoped to the cilium_operator_values block so an unrelated `replicas` elsewhere
# in the file cannot satisfy it.
operator_values_block=$(awk '
  /^  cilium_operator_values = merge\(/ { inside = 1 }
  inside { print }
  inside && /^  \)/ { exit }
' "$VALUES_TF")

if [ -z "$operator_values_block" ]; then
  die_env "could not locate the local.cilium_operator_values merge block in $VALUES_TF — parser broken, not a clean sheet"
fi

if printf '%s\n' "$operator_values_block" | grep -qE '\{ *replicas *='; then
  printf '  ok   — C1 local.cilium_operator_values writes the chart key replicas\n'
else
  report "C1: local.cilium_operator_values no longer writes a literal \`replicas\` key. Helm discards an unrecognised values key silently, so the rendered cilium-operator Deployment would keep the chart default with every offline test still green."
fi

# C2 — the floor still carries operator.replicas.
floor_operator_replicas=$(awk '
  /^operator:/ { inside = 1; next }
  inside && /^[^ ]/ { exit }
  inside && /^  replicas:/ { print; exit }
' "$FLOOR")

if [ -n "$floor_operator_replicas" ]; then
  printf '  ok   — C2 %s still carries operator.replicas (%s)\n' "$FLOOR" "$(printf '%s' "$floor_operator_replicas" | tr -d ' ')"
else
  report "C2: $FLOOR no longer sets operator.replicas. That key is load-bearing beyond its value: it is the sole floor contributor under \`operator\` (mutant M2's binding), and it is what makes the composition suite's >= 2-node render assertion discriminate — without it, a dropped computed key renders the chart's own default of 2 and that assertion passes on the mutation it exists to catch."
fi

# C3 — `operator` appears exactly once as a term of the computed merge.
computed_block=$(awk '
  /^  cilium_computed_values = merge\(/ { inside = 1 }
  inside { print }
  inside && /^  \)$/ { exit }
' "$VALUES_TF")

if [ -z "$computed_block" ]; then
  die_env "could not locate the local.cilium_computed_values merge block in $VALUES_TF — parser broken, not a clean sheet"
fi

operator_terms=$(printf '%s\n' "$computed_block" | grep -cE '^\s*[^#]*\{ *operator *=')

if [ "$operator_terms" -eq 1 ]; then
  printf '  ok   — C3 operator is exactly one term of the computed merge\n'
else
  report "C3: found $operator_terms \`operator\` terms in local.cilium_computed_values (expected exactly 1). merge() is SHALLOW — a second term replaces the first wholesale, so one contributor's keys vanish with no error. Fold every contributor through local.cilium_operator_values instead."
fi

if [ "$fail" -eq 0 ]; then
  printf 'check-cilium-operator-replicas-key: OK — the operator replica key is bound on both sides of the module contract.\n'
fi

exit "$fail"
