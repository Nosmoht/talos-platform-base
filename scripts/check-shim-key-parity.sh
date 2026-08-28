#!/usr/bin/env bash
# check-shim-key-parity.sh — bind the closed substrate schema to the shipped
# consumer shim.
#
# WHY THIS EXISTS: the worked example's root module reads cluster.yaml through
# `try(local.<section>.<key>, <default>)`. try() is total — a MISTYPED key is
# not an error, it silently yields the default, so the value the consumer wrote
# never reaches the module. Nothing else in the repo catches that: the schema
# lint validates cluster.yaml (which is correct), `tofu validate` and `tofu
# plan` both succeed (the shim is valid HCL), and the module's own test suite
# never loads the shim. The failure is a cluster running the default while its
# declared SoT says otherwise.
#
# The same class bites in the other direction on every schema widening: adding
# a key to a closed substrate object is only useful once the shim maps it, and
# openspec/specs/cluster-yaml-sot.md requires the two to land together. This is
# that requirement made mechanical.
#
# SCOPE: the CLOSED substrate objects only (those declaring `properties` in the
# schema). `substrate.argocd` is deliberately loosely typed and declares none,
# so it is skipped — there is no closed key set there to bind. Sections outside
# `substrate` are out of scope by design: their shim mappings restructure the
# data (nodes/images go through for-expressions, patches through yamlencode),
# so key-name presence is not the right oracle for them.
#
# Usage: scripts/check-shim-key-parity.sh [schema] [shim]
# Exit: 0 every closed substrate key is mapped; 1 at least one is not (the
#       message names which); 2 an input file or jq is missing.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "${ROOT}"

SCHEMA="${1:-schemas/cluster.schema.json}"
SHIM="${2:-tofu/modules/talos-cluster/examples/complete/main.tf}"

command -v jq >/dev/null 2>&1 || {
  echo "::error::check-shim-key-parity: jq not on PATH" >&2
  exit 2
}
for f in "${SCHEMA}" "${SHIM}"; do
  [ -f "$f" ] || { echo "::error::check-shim-key-parity: ${f} not found" >&2; exit 2; }
done

# Emit "<object> <key>" for every property of every CLOSED substrate object.
# An object without `properties` contributes nothing (see SCOPE above).
pairs="$(jq -r '
  .properties.substrate.properties
  | to_entries[]
  | . as $o
  | ($o.value.properties // {})
  | keys[]
  | "\($o.key) \(.)"
' "${SCHEMA}")"

[ -n "${pairs}" ] || {
  echo "::error::check-shim-key-parity: no closed substrate object found in ${SCHEMA} — the schema shape this gate reads has changed, so the gate is checking nothing" >&2
  exit 2
}

fail=0
checked=0

while read -r obj key; do
  [ -n "${obj}" ] || continue
  checked=$((checked + 1))
  # The shim aliases each substrate object to a local of the same name
  # (local.cilium, local.cert_approver), then reads keys off it.
  if ! grep -qE "local\.${obj}\.${key}([^a-zA-Z0-9_]|$)" "${SHIM}"; then
    echo "::error::check-shim-key-parity: ${SHIM} never reads local.${obj}.${key}, but schemas/cluster.schema.json declares substrate.${obj}.${key} — a consumer writing that key passes lint and plan while the value silently never reaches the module" >&2
    fail=1
  fi
done <<< "${pairs}"

if [ "${fail}" -eq 0 ]; then
  echo "check-shim-key-parity: OK — all ${checked} closed substrate schema keys are read by ${SHIM}."
fi

exit "${fail}"
