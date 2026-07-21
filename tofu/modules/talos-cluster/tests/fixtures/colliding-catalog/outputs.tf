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
output "kubeconfig_endpoint_marker_input" {
  value = terraform_data.kubeconfig_endpoint_marker.input
}
