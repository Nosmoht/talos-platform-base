#!/usr/bin/env bash
# check-substrate-consumability.sh — closes the #156 defect class and makes
# the ADR-0024 layout invariant mechanical:
#   (a) every component in .ci-renderable-components.txt must have its
#       consumable files (_rendered/manifests.yaml, plus namespace.yaml when
#       the component ships one) in .ci-oci-tarball-include.txt — a component
#       that renders green in CI but is absent from the allowlist exists in
#       git yet is unconsumable at every published tag, which is exactly the
#       gap #156 documented for argocd;
#   (b) the retired kubernetes/base/ tree stays empty in the tracked tree
#       (git ls-files based, so gitignored local residue can neither fake a
#       violation nor a pass — ADR-0024 §Amendment to ADR-0004).
# Invoked by `task supply-chain:oci-allowlist` and the gitops-validate.yml
# oci-allowlist-check job (same script, same verdict — local green means what
# CI green means).
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "${ROOT}"

for f in .ci-renderable-components.txt .ci-oci-tarball-include.txt; do
  [ -f "$f" ] || { echo "FAIL: $f missing" >&2; exit 2; }
done

fail=0

if [ "$(git ls-files kubernetes/base/ | wc -l | tr -d ' ')" != "0" ]; then
  echo "FAIL: tracked files reappeared under kubernetes/base/ (tree retired by ADR-0024):" >&2
  git ls-files kubernetes/base/ >&2
  fail=1
fi

while IFS= read -r comp; do
  [ -n "${comp}" ] || continue
  if ! grep -qx "kubernetes/substrate/${comp}/_rendered/manifests.yaml" .ci-oci-tarball-include.txt; then
    echo "FAIL: ${comp}: kubernetes/substrate/${comp}/_rendered/manifests.yaml is not in .ci-oci-tarball-include.txt — renderable but unconsumable (the #156 defect class)" >&2
    fail=1
  fi
  if [ -f "kubernetes/substrate/${comp}/namespace.yaml" ] \
     && ! grep -qx "kubernetes/substrate/${comp}/namespace.yaml" .ci-oci-tarball-include.txt; then
    echo "FAIL: ${comp}: ships namespace.yaml but it is not in .ci-oci-tarball-include.txt" >&2
    fail=1
  fi
done < .ci-renderable-components.txt

if [ "${fail}" -eq 0 ]; then
  echo "OK: every renderable substrate component is consumable from the artifact; kubernetes/base/ stays retired."
fi
exit "${fail}"
