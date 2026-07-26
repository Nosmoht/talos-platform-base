#!/usr/bin/env bash
# CI regression guard for the node-projection wiring (issue #204).
#
# WHY THIS EXISTS: nodes.tf's projections (local.controlplane_ips / worker_ips /
# node_ips) are asserted offline via the provider-less `colliding-catalog`
# fixture, which re-exports those locals. But that fixture omits main.tf, so no
# test can see WHICH projection reaches WHICH Talos argument. Swapping
# `endpoints = local.controlplane_ips` for `local.node_ips` in
# data.talos_client_configuration would leave the entire offline suite green
# while putting worker IPs into the talosconfig endpoints — and the same class of
# swap in data.talos_cluster_health would health-check the wrong node set.
#
# Same gap and same remedy as scripts/check-kubeconfig-endpoint-regen.sh: a
# block-scoped, static (no provider/network) check asserting each boundary
# argument is bound to its intended projection.
#
# PORTABILITY: block extraction is awk-based rather than `grep -Pz`, so this runs
# identically on the GNU-grep CI image and on a BSD-grep developer machine. A
# check that errors out locally teaches maintainers to ignore it.
#
# Usage: scripts/check-node-projection-wiring.sh [main.tf]
# Exit: 0 all assertions hold; 1 at least one is wrong (message names which);
#       2 the named input file does not exist.
set -euo pipefail

MAIN="${1:-tofu/modules/talos-cluster/main.tf}"

if [ ! -f "$MAIN" ]; then
  echo "::error::check-node-projection-wiring: ${MAIN} not found" >&2
  exit 2
fi

# Print the body of the top-level block whose opening line starts with $1.
# Blocks in this file are brace-balanced and start at column 0, so tracking the
# opening line and stopping at the first column-0 "}" is sufficient and cannot
# run past the block into a same-named decoy elsewhere in the file.
block() {
  awk -v head="$1" '
    index($0, head) == 1 { inblock = 1 }
    inblock { print }
    inblock && $0 == "}" { exit }
  ' "$MAIN"
}

fail=0

assert_binding() {
  local head="$1" argument="$2" expected="$3" why="$4"
  # $expected is a literal local reference; escape it for grep -E rather than
  # asking every call site to carry backslashes into the error message.
  local pattern="${expected//./\\.}"
  if ! block "$head" | grep -Eq "^[[:space:]]*${argument}[[:space:]]*=[[:space:]]*${pattern}[[:space:]]*$"; then
    echo "::error::check-node-projection-wiring: ${MAIN} — ${head} no longer binds ${argument} = ${expected}. ${why}" >&2
    fail=1
  fi
}

# data.talos_client_configuration.this — endpoints are CONTROLPLANES, nodes is ALL.
assert_binding 'data "talos_client_configuration" "this"' 'endpoints' 'local.controlplane_ips' \
  'The talosconfig endpoints must be the controlplanes; any other projection puts workers (or nothing) in front of talosctl.'
assert_binding 'data "talos_client_configuration" "this"' 'nodes' 'local.node_ips' \
  'The talosconfig node list must cover every node.'

# data.talos_cluster_health.this — the apply-blocking gate must check the right sets.
assert_binding 'data "talos_cluster_health" "this"' 'control_plane_nodes' 'local.controlplane_ips' \
  'A wrong projection here makes the apply-blocking health gate check the wrong machines.'
assert_binding 'data "talos_cluster_health" "this"' 'worker_nodes' 'local.worker_ips' \
  'A wrong projection here makes the apply-blocking health gate check the wrong machines.'
assert_binding 'data "talos_cluster_health" "this"' 'endpoints' 'local.controlplane_ips' \
  'The health client must talk to controlplane endpoints.'

# The per-node apply must run over the IP-guarded view, not var.nodes directly —
# that is what keeps nodes.tf's duplicate-IP backstop in the dependency chain.
assert_binding 'resource "talos_machine_configuration_apply" "this"' 'for_each' 'local.nodes_checked' \
  'Iterating var.nodes directly drops the IP-collision guard out of the dependency chain, and OpenTofu never evaluates an unreferenced local.'

if [ "$fail" -eq 0 ]; then
  echo "check-node-projection-wiring: OK — the five Talos boundary arguments are bound to their intended node projections and the per-node apply runs over local.nodes_checked."
fi

exit "$fail"
