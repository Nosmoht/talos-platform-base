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
