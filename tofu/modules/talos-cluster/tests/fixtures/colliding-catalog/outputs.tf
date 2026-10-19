# Fixture outputs; the module outputs.tf is not symlinked because it needs providers,
# so every output an offline test asserts on is copied here.
output "node_kernel_args" {
  value = { for h, e in local.node_effective : h => e.kernel_args }
}

# The symlinked kubeconfig-refresh.tf instantiates its marker in every suite
# using this fixture.
output "kubeconfig_endpoint_marker_input" {
  value = terraform_data.kubeconfig_endpoint_marker.input
}

output "cilium_effective_values" {
  value = local.cilium_effective_values
}

output "cilium_self_management_app" {
  value = local.cilium_self_management_app
}

# cilium_effective_values is not a superset of this map; assert seed content here.
output "cilium_computed_values" {
  value = local.cilium_computed_values
}

output "cilium_operator_replicas_effective" {
  # An empty-map conditional coerces count to string; keep a stable object shape.
  value = {
    count = var.deploy_cilium ? (
      local.cilium_operator_replicas != null ? local.cilium_operator_replicas : try(local.cilium_floor_values.operator.replicas, null)
    ) : null
    source = var.deploy_cilium ? (
      var.cilium_operator_replicas != null ? "pin" :
      local.cilium_operator_replicas != null ? "node-count" : "floor"
    ) : "disabled"
  }
}

output "controlplane_ips" {
  value = local.controlplane_ips
}

output "worker_ips" {
  value = local.worker_ips
}

output "node_ips" {
  value = local.node_ips
}

output "first_controlplane_ip" {
  value = local.first_controlplane.ip
}

output "register_with_fqdn_patch" {
  value = local.register_with_fqdn_patch
}

output "cilium_self_management_values" {
  value = local.cilium_self_management_values_file
}

output "cilium_joint_keys" {
  value = local.cilium_joint_keys
}

output "cilium_values_override_digest" {
  value = local.cilium_values_override_digest
}
