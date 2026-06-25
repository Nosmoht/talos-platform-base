# Fixture-only output (NOT symlinked from the real module's outputs.tf). Exposes
# each node's UNIONED effective kernel_args so the console= run can assert that
# multi-value keys are CARRIED INTO the union (Task 2 union-correctness), not only
# that no conflict was raised — composition.tf:223-227. node_effective lives in the
# symlinked composition.tf, so this binds to the real union logic.
output "node_kernel_args" {
  value = { for h, e in local.node_effective : h => e.kernel_args }
}
