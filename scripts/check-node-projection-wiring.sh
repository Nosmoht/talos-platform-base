#!/usr/bin/env bash
# Usage: scripts/check-node-projection-wiring.sh [module-directory|file.tf]
set -euo pipefail

MAIN="${1:-tofu/modules/talos-cluster}"

if [ -d "$MAIN" ]; then
  source_file="$(mktemp)"
  trap 'rm -f "$source_file"' EXIT
  cat "$MAIN"/*.tf > "$source_file"
  MAIN="$source_file"
fi

if [ ! -f "$MAIN" ]; then
  echo "::error::check-node-projection-wiring: ${MAIN} not found" >&2
  exit 2
fi

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
  local pattern="${expected//./\\.}"
  if ! block "$head" | grep -Eq "^[[:space:]]*${argument}[[:space:]]*=[[:space:]]*${pattern}[[:space:]]*$"; then
    echo "::error::check-node-projection-wiring: ${MAIN} — ${head} no longer binds ${argument} = ${expected}. ${why}" >&2
    fail=1
  fi
}

assert_binding 'data "talos_client_configuration" "this"' 'endpoints' 'local.controlplane_ips' \
  'The talosconfig endpoints must be the controlplanes; any other projection puts workers (or nothing) in front of talosctl.'
assert_binding 'data "talos_client_configuration" "this"' 'nodes' 'local.node_ips' \
  'The talosconfig node list must cover every node.'

assert_binding 'data "talos_cluster_health" "this"' 'control_plane_nodes' 'local.controlplane_ips' \
  'A wrong projection here makes the apply-blocking health gate check the wrong machines.'
assert_binding 'data "talos_cluster_health" "this"' 'worker_nodes' 'local.worker_ips' \
  'A wrong projection here makes the apply-blocking health gate check the wrong machines.'
assert_binding 'data "talos_cluster_health" "this"' 'endpoints' 'local.controlplane_ips' \
  'The health client must talk to controlplane endpoints.'

assert_binding 'resource "talos_machine_configuration_apply" "this"' 'for_each' 'local.nodes_checked' \
  'Iterating var.nodes directly drops the IP-collision guard out of the dependency chain, and OpenTofu never evaluates an unreferenced local.'

if [ "$fail" -eq 0 ]; then
  echo "check-node-projection-wiring: OK — the five Talos boundary arguments are bound to their intended node projections and the per-node apply runs over local.nodes_checked."
fi

exit "$fail"
