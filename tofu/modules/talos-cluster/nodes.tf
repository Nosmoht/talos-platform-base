# Provider-free node projections shared with offline fixtures.

locals {
  # Select documents from the immutable bootstrap schema pin, not the installed OS version.
  native_config_documents = try(
    tonumber(regex("^v([0-9]+)\\.([0-9]+)", var.talos_version)[0]) > 1 ||
    tonumber(regex("^v([0-9]+)\\.([0-9]+)", var.talos_version)[1]) >= 14,
    false,
  )

  # Duplicate IPs fail this map construction. Every provider-facing node view must use nodes_checked.
  node_name_by_ip = { for h, n in var.nodes : n.ip => h }

  nodes_checked = { for ip, h in local.node_name_by_ip : h => var.nodes[h] }

  controlplanes_by_hostname = { for h, n in local.nodes_checked : h => n if n.role == "controlplane" }
  workers_by_hostname       = { for h, n in local.nodes_checked : h => n if n.role == "worker" }

  # keys() sorts hostnames, keeping the bootstrap target stable across input ordering.
  first_controlplane = local.controlplanes_by_hostname[keys(local.controlplanes_by_hostname)[0]]

  # Provider arguments accept IP lists; derive them from the hostname-keyed identity model.
  controlplane_ips = [for h, n in local.controlplanes_by_hostname : n.ip]
  worker_ips       = [for h, n in local.workers_by_hostname : n.ip]
  node_ips         = [for h, n in local.nodes_checked : n.ip]

  # Only emit when enabled so the default does not override a caller patch.
  register_with_fqdn_patch = var.register_with_fqdn ? [local.native_config_documents ? yamlencode({
    apiVersion       = "v1alpha1"
    kind             = "KubeNodeConfig"
    registerWithFQDN = true
    }) : yamlencode({
    machine = { kubelet = { registerWithFQDN = true } }
  })] : []
}

locals {
  node_apply_mode = {
    for h, n in local.nodes_checked :
    h => n.role == "controlplane" ? var.controlplane_apply_mode : var.worker_apply_mode
  }
}
