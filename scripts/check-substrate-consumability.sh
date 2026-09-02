#!/usr/bin/env bash
# check-substrate-consumability.sh — closes the #156 defect class and makes
# the ADR-0024 layout invariant mechanical:
#   (a) every component in .ci-renderable-components.txt must have its
#       consumable files (_rendered/manifests.yaml, the kustomization.yaml that
#       makes them a single consumable unit, plus namespace.yaml when the
#       component ships one) in .ci-oci-tarball-include.txt — a component that
#       renders green in CI but is absent from the allowlist exists in git yet
#       is unconsumable at every published tag, which is exactly the gap #156
#       documented for argocd;
#   (b) the retired kubernetes/base/ tree stays empty in the tracked tree
#       (git ls-files based, so gitignored local residue can neither fake a
#       violation nor a pass — ADR-0024 §Amendment to ADR-0004);
#   (c) every root-level .tf file in the talos-cluster module ships in the
#       artifact. A partial module can satisfy the allowlist membership diff
#       while failing for every vendoring consumer (#158).
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
  # The kustomization is what makes the rendered files a UNIT. Without it in the
  # artifact a vendored consumer gets loose manifests and must hand-reconstruct
  # the resource list and its ordering — the spec's "consumable as a single
  # kustomization" would then hold in-repo only, which is the #156 shape again
  # one level up. Unconditional, unlike namespace.yaml: a renderable component
  # without a kustomization.yaml is not a component.
  if [ ! -f "kubernetes/substrate/${comp}/kustomization.yaml" ]; then
    echo "FAIL: ${comp}: listed as renderable but ships no kustomization.yaml" >&2
    fail=1
  elif ! grep -qx "kubernetes/substrate/${comp}/kustomization.yaml" .ci-oci-tarball-include.txt; then
    echo "FAIL: ${comp}: kubernetes/substrate/${comp}/kustomization.yaml is not in .ci-oci-tarball-include.txt — a vendored consumer receives loose manifests instead of a buildable kustomization" >&2
    fail=1
  fi
  if [ -f "kubernetes/substrate/${comp}/namespace.yaml" ] \
     && ! grep -qx "kubernetes/substrate/${comp}/namespace.yaml" .ci-oci-tarball-include.txt; then
    echo "FAIL: ${comp}: ships namespace.yaml but it is not in .ci-oci-tarball-include.txt" >&2
    fail=1
  fi
  # Shipping the kustomization is not enough — it must be shipped WITH the files
  # it names. Hardcoding the three filenames we happen to use today would leave
  # the real requirement ("present alongside the resources it names") unchecked:
  # _rendered/crds.yaml is in the allowlist by luck, not by gate, and
  # render-component.sh deletes it whenever a chart ships no CRDs. So read the
  # actual resources: list. Local paths only — a remote base is fetched, not
  # packaged, and must not be demanded of the tarball.
  if [ -f "kubernetes/substrate/${comp}/kustomization.yaml" ] && command -v yq >/dev/null 2>&1; then
    while IFS= read -r res; do
      [ -n "${res}" ] || continue
      case "${res}" in
        http://*|https://*|git@*|github.com/*|git::*|ssh://*|*://*) continue ;;
      esac
      if ! grep -qx "kubernetes/substrate/${comp}/${res}" .ci-oci-tarball-include.txt; then
        echo "FAIL: ${comp}: kustomization.yaml names resource '${res}' but kubernetes/substrate/${comp}/${res} is not in .ci-oci-tarball-include.txt — the vendored kustomization would reference a file the artifact does not contain" >&2
        fail=1
      fi
    done <<EOF
$(yq e '.resources[] // ""' "kubernetes/substrate/${comp}/kustomization.yaml" 2>/dev/null)
EOF
  fi
done < .ci-renderable-components.txt

while IFS= read -r module_file; do
  relative="${module_file#tofu/modules/talos-cluster/}"
  case "${relative}" in
    */*) continue ;;
    *.tf) ;;
    *) continue ;;
  esac
  if ! grep -qx "${module_file}" .ci-oci-tarball-include.txt; then
    echo "FAIL: ${module_file} is part of the talos-cluster module but is absent from .ci-oci-tarball-include.txt — the vendored module is incomplete (#158)" >&2
    fail=1
  fi
done < <(git ls-files tofu/modules/talos-cluster/)

if [ "${fail}" -eq 0 ]; then
  echo "OK: the artifact carries every talos-cluster module file and every renderable substrate component; kubernetes/base/ stays retired."
fi
exit "${fail}"
