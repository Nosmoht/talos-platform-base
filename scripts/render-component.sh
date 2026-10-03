#!/usr/bin/env bash
# Render one component through Helm and Kustomize; split manifests and CRDs.
# Usage: scripts/render-component.sh <component>
# Verify the chart digest when present; write it to chart.lock.yaml when absent.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
CACHE="${ROOT}/.helm-cache"

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <component>" >&2
  exit 1
fi
COMP="$1"
COMP_DIR="${ROOT}/kubernetes/substrate/${COMP}"
LOCK="${COMP_DIR}/chart.lock.yaml"
STAGE1_DIR="${COMP_DIR}/.render-stage1"
RENDERED_DIR="${COMP_DIR}/_rendered"
OVERLAY_DIR="${COMP_DIR}/_rendered-overlay"

[ -d "${COMP_DIR}" ] || { echo "error: component dir not found: ${COMP_DIR}" >&2; exit 1; }
[ -f "${LOCK}" ]     || { echo "error: chart.lock.yaml missing: ${LOCK}" >&2; exit 1; }
[ -d "${OVERLAY_DIR}" ] || { echo "error: _rendered-overlay/ missing: ${OVERLAY_DIR}" >&2; exit 1; }

repo="$(yq -e '.chart.repo'    "${LOCK}")"
name="$(yq -e '.chart.name'    "${LOCK}")"
version="$(yq -e '.chart.version' "${LOCK}")"
expected_sha="$(yq '.chart.tgz_sha256 // ""' "${LOCK}")"
release_name="$(yq -e '.release.name' "${LOCK}")"
release_ns="$(yq -e '.release.namespace' "${LOCK}")"
include_crds="$(yq '.release.includeCRDs // true' "${LOCK}")"
values_rel="$(yq '.values // "values.yaml"' "${LOCK}")"
values_abs="${COMP_DIR}/${values_rel}"

[ -f "${values_abs}" ] || { echo "error: values file missing: ${values_abs}" >&2; exit 1; }

mkdir -p "${CACHE}" "${STAGE1_DIR}" "${RENDERED_DIR}"

echo "==> [${COMP}] Pulling chart ${name}@${version} from ${repo}"
case "${repo}" in
  oci://*)
    helm pull "${repo}/${name}" --version "${version}" --destination "${CACHE}" >/dev/null
    ;;
  *)
    helm pull "${name}" --repo "${repo}" --version "${version}" --destination "${CACHE}" >/dev/null
    ;;
esac

tgz="$(ls -t "${CACHE}/${name}"-*.tgz 2>/dev/null | head -n1)"
[ -n "${tgz}" ] && [ -f "${tgz}" ] || { echo "error: chart pull produced no tarball" >&2; exit 2; }

actual_sha="$(shasum -a 256 "${tgz}" | awk '{print $1}')"
if [ -n "${expected_sha}" ]; then
  if [ "${actual_sha}" != "${expected_sha}" ]; then
    echo "error: chart sha256 mismatch for ${tgz}" >&2
    echo "  expected: ${expected_sha}" >&2
    echo "  actual:   ${actual_sha}" >&2
    echo "  Either the upstream chart was republished under the same version (security event)" >&2
    echo "  or the lock needs updating: yq -i '.chart.tgz_sha256 = \"${actual_sha}\"' ${LOCK}" >&2
    exit 3
  fi
  echo "==> [${COMP}] sha256 verified: ${actual_sha}"
else
  echo "==> [${COMP}] sha256 not pinned; writing observed digest to chart.lock.yaml"
  yq -i ".chart.tgz_sha256 = \"${actual_sha}\"" "${LOCK}"
fi

echo "==> [${COMP}] Stage 1: helm template"
crds_flag=""
if [ "${include_crds}" = "true" ]; then
  crds_flag="--include-crds"
fi
stage1_out="${STAGE1_DIR}/${COMP}.yaml"
# shellcheck disable=SC2086 # crds_flag is intentionally unquoted (may be empty)
helm template "${release_name}" "${tgz}" \
  --namespace "${release_ns}" \
  ${crds_flag} \
  -f "${values_abs}" > "${stage1_out}" \
  || { echo "error: helm template failed" >&2; exit 4; }

# Allow consumer overlays to reference files outside the base.
echo "==> [${COMP}] Stage 2: kustomize build"
stage2_out="$(mktemp)"
trap 'rm -f "${stage2_out}"' EXIT
kustomize build --load-restrictor=LoadRestrictionsNone "${OVERLAY_DIR}" > "${stage2_out}" \
  || { echo "error: kustomize build failed" >&2; exit 5; }

echo "==> [${COMP}] Splitting CRDs from manifests"
yq 'select(.kind != "CustomResourceDefinition")' "${stage2_out}" > "${RENDERED_DIR}/manifests.yaml"
crds_tmp="$(mktemp)"
yq 'select(.kind == "CustomResourceDefinition")' "${stage2_out}" > "${crds_tmp}"
if [ -s "${crds_tmp}" ]; then
  mv "${crds_tmp}" "${RENDERED_DIR}/crds.yaml"
else
  rm -f "${crds_tmp}" "${RENDERED_DIR}/crds.yaml"
fi

for f in "${RENDERED_DIR}/manifests.yaml" "${RENDERED_DIR}/crds.yaml"; do
  [ -f "${f}" ] && perl -0pi -e 's/\n*\z/\n/' "${f}"
done

manifest_lines="$(wc -l < "${RENDERED_DIR}/manifests.yaml" | tr -d ' ')"
if [ -f "${RENDERED_DIR}/crds.yaml" ]; then
  crd_lines="$(wc -l < "${RENDERED_DIR}/crds.yaml" | tr -d ' ')"
  echo "==> [${COMP}] Done. manifests.yaml=${manifest_lines}L, crds.yaml=${crd_lines}L"
else
  echo "==> [${COMP}] Done. manifests.yaml=${manifest_lines}L, no CRDs"
fi
