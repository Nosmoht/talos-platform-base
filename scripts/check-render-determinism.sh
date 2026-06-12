#!/usr/bin/env bash
# Regression fence for #123 (talos-cluster render -> machineConfig decoupling).
#
# data.helm_template.{cilium,argocd,argocd_crds} are re-evaluated every plan and
# are NOT byte-stable (Sprig genCA at template time; helm-provider ordering).
# Consumed directly, every plan / Crossplane reconcile re-pushed a fresh
# machineConfig (#121). The fix freezes each render in state via a terraform_data
# carrying lifecycle { ignore_changes = [input] }.
#
# This guard fails if that decoupling is reverted: a render must be consumed ONLY
# through its frozen terraform_data.<r>_render, never the live
# data.helm_template.<r>[0].manifest (a contents=/content=/sha256() consumer
# re-introduces the drift). See docs/adr-opentofu-cluster-lifecycle.md.
#
# Hermetic: pure static analysis of main.tf, no providers/network. Wired into
# `task ci`. Usage: scripts/check-render-determinism.sh [path/to/main.tf]
set -euo pipefail

MAIN="${1:-tofu/modules/talos-cluster/main.tf}"

if [ ! -f "$MAIN" ]; then
  echo "::error::check-render-determinism: ${MAIN} not found" >&2
  exit 1
fi

fail=0

# Each helm render may be referenced exactly once — as the input= capture of its
# freeze. `\[0\]` anchors the count so `argocd` does not also match `argocd_crds`.
for r in cilium argocd argocd_crds; do
  total=$(grep -cE "data\.helm_template\.${r}\[0\]\.manifest" "$MAIN" || true)
  capture=$(grep -cE "^[[:space:]]*input[[:space:]]+= data\.helm_template\.${r}\[0\]\.manifest" "$MAIN" || true)
  if [ "$total" -ne 1 ] || [ "$capture" -ne 1 ]; then
    echo "::error::check-render-determinism: data.helm_template.${r} must be referenced exactly once, as the input= capture of terraform_data.${r}_render (found total=${total}, capture=${capture}). A direct consumer (contents=/content=/sha256()) re-introduces the #123 machineConfig re-push — route it through terraform_data.${r}_render[0].output." >&2
    fail=1
  fi
  if ! grep -qE "resource \"terraform_data\" \"${r}_render\"" "$MAIN"; then
    echo "::error::check-render-determinism: freeze resource terraform_data.${r}_render is missing in ${MAIN} (#123)." >&2
    fail=1
  fi
done

# Every *_render freeze must carry the ignore_changes that performs the freeze.
need=$(grep -cE 'resource "terraform_data" "[a-z_]+_render"' "$MAIN" || true)
have=$(grep -cE '^[[:space:]]*ignore_changes[[:space:]]*=[[:space:]]*\[input\]' "$MAIN" || true)
if [ "$have" -lt "$need" ]; then
  echo "::error::check-render-determinism: a terraform_data *_render freeze lacks lifecycle { ignore_changes = [input] } (need >= ${need}, have ${have}) (#123)." >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "check-render-determinism: OK — 3 helm renders frozen via terraform_data, no live consumption."
fi
exit "$fail"
