#!/usr/bin/env bash
# Check closed substrate schema keys against the consumer shim.
# Loose argocd keys and restructured non-substrate mappings are outside this check.
# Usage: scripts/check-shim-key-parity.sh [schema] [shim]
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

pairs="$(jq -r '
  .properties.substrate.properties
  | to_entries[]
  | . as $o
  | ($o.value.properties // {})
  | to_entries[]
  | . as $k
  | [ "\($o.key) \($k.key)" ]
    + [ ($k.value.properties // {} | keys[]) | "\($o.key) \($k.key).\(.)" ]
  | .[]
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
  key_re="${key//./\\.}"
  if ! grep -qE "local\.${obj}\.${key_re}([^a-zA-Z0-9_]|$)" "${SHIM}"; then
    echo "::error::check-shim-key-parity: ${SHIM} never reads local.${obj}.${key}, but schemas/cluster.schema.json declares substrate.${obj}.${key} — a consumer writing that key passes lint and plan while the value silently never reaches the module" >&2
    fail=1
  fi
done <<< "${pairs}"

if [ "${fail}" -eq 0 ]; then
  echo "check-shim-key-parity: OK — all ${checked} closed substrate schema keys are read by ${SHIM}."
fi

exit "${fail}"
