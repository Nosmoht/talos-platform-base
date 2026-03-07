#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_FILE="${ROOT_DIR}/kubernetes/bootstrap/cilium/cilium.yaml"
CHART_VERSION="${CILIUM_CHART_VERSION:-1.19.0}"

tmp_render="$(mktemp)"
tmp_output="$(mktemp)"
trap 'rm -f "${tmp_render}" "${tmp_output}"' EXIT

# Ensure the cilium chart repo is available locally.
if ! helm repo list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -qx 'cilium'; then
  helm repo add cilium https://helm.cilium.io >/dev/null
fi
helm repo update cilium >/dev/null

# Render the chart section that includes Hubble TLS cronjob resources.
helm template cilium cilium/cilium \
  --version "${CHART_VERSION}" \
  --namespace kube-system \
  --set hubble.enabled=true \
  --set hubble.relay.enabled=true \
  --set hubble.ui.enabled=true \
  --set hubble.tls.auto.enabled=true \
  --set hubble.tls.auto.method=cronJob > "${tmp_render}"

# Keep existing bootstrap manifest mostly untouched, but remove static Hubble TLS secrets
# and replace any existing certgen docs with fresh cronjob-managed certgen resources.
awk -v RS='\n---\n' -v ORS='\n---\n' '
  {
    doc=$0
    if (doc ~ /kind: Secret/ && (doc ~ /name: hubble-relay-client-certs/ || doc ~ /name: hubble-server-certs/)) next
    if (doc ~ /name:[[:space:]]+"?hubble-generate-certs/) next
    print doc
  }
' "${OUTPUT_FILE}" > "${tmp_output}"

printf '\n' >> "${tmp_output}"
awk -v RS='\n---\n' -v ORS='\n---\n' '
  {
    doc=$0
    if (doc ~ /name:[[:space:]]+"?hubble-generate-certs/) print doc
  }
' "${tmp_render}" >> "${tmp_output}"

# Normalize leading/trailing separators and force a single trailing newline.
perl -0pi -e 's/\A\n+//; s/\n---\n\z/\n/; s/\n*\z/\n/;' "${tmp_output}"

mv "${tmp_output}" "${OUTPUT_FILE}"

echo "Updated ${OUTPUT_FILE} using Cilium chart ${CHART_VERSION}"
