#!/usr/bin/env bash
# CI regression guard for the kubeconfig-endpoint-regen wiring (issue #186, PR #187).
#
# WHY THIS EXISTS: the PR #187 review (blocker #3) found that deleting the ENTIRE
# `lifecycle` block from main.tf's `talos_cluster_kubeconfig.this` left the full
# offline `tofu test` suite + `tofu validate` green — no committed check referenced
# `replace_triggered_by` or `kubeconfig_endpoint_marker` at all.
# `tests/kubeconfig-endpoint-marker.tftest.hcl` only binds the marker's tracked
# value against the provider-less `colliding-catalog` fixture, which omits
# main.tf, so it cannot see the `lifecycle` block regardless of whether the
# wiring is present.
#
# This is that guard: a resource-scoped, static (no provider/network) grep
# mirroring the AC #1 predicate form from .work/issue-186/plan.md, asserting
# BOTH halves of the load-bearing wiring:
#   1. tofu/modules/talos-cluster/main.tf's `talos_cluster_kubeconfig "this"`
#      block carries
#      `replace_triggered_by = [terraform_data.kubeconfig_endpoint_marker]`.
#   2. tofu/modules/talos-cluster/kubeconfig-refresh.tf declares
#      `terraform_data "kubeconfig_endpoint_marker"` with
#      `input = var.cluster_endpoint`.
#
# Resource-scoped (grep -Pzq over the whole file, pattern anchored on the
# `resource "..." "..."` opening line) rather than a bare substring match, so
# a same-named decoy resource elsewhere in the file cannot pass this check.
#
# Usage: scripts/check-kubeconfig-endpoint-regen.sh [main.tf] [kubeconfig-refresh.tf]
# Exit: 0 both assertions hold; 1 either is missing (message names which);
#       2 a named input file does not exist.
set -euo pipefail

MAIN="${1:-tofu/modules/talos-cluster/main.tf}"
MARKER_FILE="${2:-tofu/modules/talos-cluster/kubeconfig-refresh.tf}"

for f in "$MAIN" "$MARKER_FILE"; do
  if [ ! -f "$f" ]; then
    echo "::error::check-kubeconfig-endpoint-regen: ${f} not found" >&2
    exit 2
  fi
done

fail=0

if ! grep -Pzq 'resource "talos_cluster_kubeconfig" "this"[\s\S]*?replace_triggered_by\s*=\s*\[terraform_data\.kubeconfig_endpoint_marker\]' "$MAIN"; then
  echo "::error::check-kubeconfig-endpoint-regen: ${MAIN} — resource \"talos_cluster_kubeconfig\" \"this\" no longer carries lifecycle { replace_triggered_by = [terraform_data.kubeconfig_endpoint_marker] }. Without it, a changed var.cluster_endpoint no longer forces a kubeconfig re-fetch and issue #186 regresses silently — this is the exact gap the PR #187 review found (the offline test suite cannot see this block)." >&2
  fail=1
fi

if ! grep -Pzq 'resource "terraform_data" "kubeconfig_endpoint_marker"[\s\S]*?input\s*=\s*var\.cluster_endpoint' "$MARKER_FILE"; then
  echo "::error::check-kubeconfig-endpoint-regen: ${MARKER_FILE} — resource \"terraform_data\" \"kubeconfig_endpoint_marker\" no longer declares input = var.cluster_endpoint. The marker must track the advertised cluster endpoint, or the trigger above fires on the wrong signal (or never)." >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "check-kubeconfig-endpoint-regen: OK — talos_cluster_kubeconfig.this carries replace_triggered_by keyed on terraform_data.kubeconfig_endpoint_marker (input = var.cluster_endpoint)."
fi

exit "$fail"
