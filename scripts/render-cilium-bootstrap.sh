#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   CILIUM_CHART_VERSION=<version> [CILIUM_VALUES_OVERLAY=<path>] \
#     [CILIUM_OUTPUT_FILE=<path>] bash scripts/render-cilium-bootstrap.sh
#
# Optional environment variables:
#   CILIUM_VALUES_OVERLAY  Path to a Consumer-supplied Helm values file that is
#                          passed as a second -f argument after the base values.yaml.
#                          Helm uses right-most-wins map-merge semantics, so overlay
#                          keys take precedence over base keys.
#                          IMPORTANT — list-typed values (e.g. bpf.vlanBypass) are
#                          replaced wholesale by Helm, not merged. The overlay must
#                          repeat all substrate entries to extend a list.
#   CILIUM_OUTPUT_FILE     Path where the rendered cilium.yaml is written.
#                          Defaults to kubernetes/bootstrap/cilium/cilium.yaml.
#                          Parent directory must exist.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_DIR="${ROOT_DIR}/kubernetes/bootstrap/cilium"
OUTPUT_FILE="${CILIUM_OUTPUT_FILE:-${BOOTSTRAP_DIR}/cilium.yaml}"
VALUES_FILE="${BOOTSTRAP_DIR}/values.yaml"
EXTRAS_FILE="${BOOTSTRAP_DIR}/extras.yaml"
CHART_VERSION="${CILIUM_CHART_VERSION:?CILIUM_CHART_VERSION must be set}"

# Validate optional env vars before any network call (fail-fast).
OVERLAY="${CILIUM_VALUES_OVERLAY:-}"
# AC1: overlay must be a readable regular file — rejects nonexistent AND directory.
if [[ -n "${OVERLAY}" ]] && { [[ ! -f "${OVERLAY}" ]] || [[ ! -r "${OVERLAY}" ]]; }; then
  echo "cilium-render: CILIUM_VALUES_OVERLAY=\"${OVERLAY}\" is not a readable file" >&2
  exit 1
fi
# AC2: output target must not be an existing directory, and its parent must exist.
if [[ -d "${OUTPUT_FILE}" ]]; then
  echo "cilium-render: CILIUM_OUTPUT_FILE=\"${OUTPUT_FILE}\" is a directory, not a file" >&2
  exit 1
fi
out_dir="$(dirname "${OUTPUT_FILE}")"
if [[ ! -d "${out_dir}" ]]; then
  echo "cilium-render: CILIUM_OUTPUT_FILE parent directory \"${out_dir}\" does not exist" >&2
  exit 1
fi

tmp_render="$(mktemp)"
trap 'rm -f "${tmp_render}"' EXIT

# Ensure the cilium chart repo is available locally.
if ! helm repo list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -qx 'cilium'; then
  helm repo add cilium https://helm.cilium.io >/dev/null
fi
helm repo update cilium >/dev/null

# Build the -f argument list; append overlay after base for right-most-wins semantics.
values_args=(-f "${VALUES_FILE}")
if [[ -n "${OVERLAY}" ]]; then
  values_args+=(-f "${OVERLAY}")
fi

# Full render of the Cilium chart with the repo-managed values file.
helm template cilium cilium/cilium \
  --version "${CHART_VERSION}" \
  --namespace kube-system \
  "${values_args[@]}" > "${tmp_render}"

# Append hand-crafted extras (GatewayClass, Gateway API RBAC).
if [[ -f "${EXTRAS_FILE}" ]]; then
  printf '\n' >> "${tmp_render}"
  cat "${EXTRAS_FILE}" >> "${tmp_render}"
fi

# Normalize leading/trailing separators and force a single trailing newline.
perl -0pi -e 's/\A\n+//; s/\n---\n\z/\n/; s/\n*\z/\n/;' "${tmp_render}"

mv "${tmp_render}" "${OUTPUT_FILE}"

echo "Updated ${OUTPUT_FILE} using Cilium chart ${CHART_VERSION}"
