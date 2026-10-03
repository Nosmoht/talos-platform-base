#!/usr/bin/env bash
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
