#!/usr/bin/env bash
# Usage: scripts/check-kubeconfig-endpoint-regen.sh [main.tf]
set -euo pipefail

MAIN="${1:-tofu/modules/talos-cluster/main.tf}"

if [ ! -f "$MAIN" ]; then
  echo "::error::check-kubeconfig-endpoint-regen: ${MAIN} not found" >&2
  exit 2
fi

if ! grep -Eq 'resource "talos_cluster_kubeconfig" "this".*replace_triggered_by[[:space:]]*=[[:space:]]*\[terraform_data\.kubeconfig_endpoint_marker\]' <<<"$(tr '\n' ' ' <"$MAIN")"; then
  echo "::error::check-kubeconfig-endpoint-regen: ${MAIN} — resource \"talos_cluster_kubeconfig\" \"this\" no longer carries lifecycle { replace_triggered_by = [terraform_data.kubeconfig_endpoint_marker] }. Without it, a changed var.cluster_endpoint no longer forces a kubeconfig re-fetch and issue #186 regresses silently — this is the exact gap the PR #187 review found (the offline test suite cannot see this block)." >&2
  exit 1
fi

echo "check-kubeconfig-endpoint-regen: OK — talos_cluster_kubeconfig.this carries replace_triggered_by keyed on terraform_data.kubeconfig_endpoint_marker."
