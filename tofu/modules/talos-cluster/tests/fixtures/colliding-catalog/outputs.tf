# Fixture-only output (NOT symlinked from the real module's outputs.tf). Exposes
# each node's UNIONED effective kernel_args so the console= run can assert that
# multi-value keys are CARRIED INTO the union (Task 2 union-correctness), not only
# that no conflict was raised — composition.tf:223-227. node_effective lives in the
# symlinked composition.tf, so this binds to the real union logic.
output "node_kernel_args" {
  value = { for h, e in local.node_effective : h => e.kernel_args }
}

# This fixture ALSO hosts the kubeconfig-endpoint-marker assertion (issue
# #186) — the symlinked kubeconfig-refresh.tf's terraform_data resource needs
# no fixture-side wiring, just this output to expose its tracked input.
#
# Fixture coupling: the kubeconfig-refresh.tf symlink instantiates the real
# terraform_data.kubeconfig_endpoint_marker resource unconditionally, so
# EVERY suite reusing this fixture (currently also
# tests/input-validation.tftest.hcl) carries it too — a future edit to the
# marker (renaming it, changing its tracked input) can break those other
# suites even though they assert nothing about the marker themselves.
output "kubeconfig_endpoint_marker_input" {
  value = terraform_data.kubeconfig_endpoint_marker.input
}

# Fixture-only outputs (NOT symlinked from the real module's outputs.tf) exposing
# the two locals tests/input-validation.tftest.hcl asserts on for the Cilium
# observability + self-management surface (issue #188) — cilium-values.tf is pure
# var.*-derived locals (no data/terraform_data), so it is provider-less-fixture-safe.
output "cilium_effective_values" {
  value = local.cilium_effective_values
}

output "cilium_self_management_app" {
  value = local.cilium_self_management_app
}

# The SEED-side map. Exposed because cilium_effective_values is NOT a superset of
# it: cilium_effective_values ends in explicit sub-merge terms, and a trailing
# `{ operator = merge(...) }` term REPLACES its parent wholesale, so a key present
# in the computed layer can be absent from the effective one. Any assertion about
# what the frozen seed carries — that is cilium_computed_values_yaml, fed straight
# to data.helm_template.cilium in the real main.tf — has to be made on this map,
# not inferred from the emitted Application's.
output "cilium_computed_values" {
  value = local.cilium_computed_values
}

# Fixture-only outputs exposing the node-identity projections from the symlinked
# nodes.tf (provider-less, pure var.nodes-derived), so the ordering contract can
# be asserted OFFLINE. The real module feeds these same locals straight into
# data.talos_cluster_health / data.talos_client_configuration, so asserting them
# here binds the real boundary arguments, not a fixture copy of them.
output "controlplane_ips" {
  value = local.controlplane_ips
}

output "worker_ips" {
  value = local.worker_ips
}

output "node_ips" {
  value = local.node_ips
}

# The bootstrap target. talos_machine_bootstrap lives in the real main.tf (which
# this provider-less fixture does not symlink), so exposing the local is how the
# selection rule gets an offline binding at all — without it, a refactor to
# "first key overall" (which can pick a WORKER) turns no test red.
output "first_controlplane_ip" {
  value = local.first_controlplane.ip
}

# The only behaviour var.register_with_fqdn has. Exposed so both arms are
# assertable offline: [] when off, the registerWithFQDN patch when on.
output "register_with_fqdn_patch" {
  value = local.register_with_fqdn_patch
}
