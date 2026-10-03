locals {
  # Keep the bootstrap schema pin fixed; use the install pin for OS upgrades.
  install_version = var.talos_install_version != "" ? var.talos_install_version : var.talos_version

  # Substring guard only: renamed or digest-pinned SecureBoot images remain a consumer responsibility.
  all_caller_patches = concat(
    var.config_patches,
    var.controlplane_config_patches,
    var.worker_config_patches,
    flatten([for n in var.nodes : n.config_patches]),
  )
  secureboot_patches = [for p in local.all_caller_patches : p if can(regex("-secureboot", p))]
}

# Import the existing cluster PKI before adopting a running cluster. Never generate replacement secrets.
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version

  lifecycle {
    precondition {
      condition     = length(local.secureboot_patches) == 0
      error_message = "A config_patch selects a SecureBoot installer image (a *-secureboot reference). The base Hard Constraint forbids SecureBoot (boot loops) — use the non-secureboot installer."
    }
    precondition {
      condition = var.dual_stack ? (
        anytrue([for c in var.pod_cidr : !strcontains(c, ":")]) &&
        anytrue([for c in var.pod_cidr : strcontains(c, ":")]) &&
        anytrue([for c in var.service_cidr : !strcontains(c, ":")]) &&
        anytrue([for c in var.service_cidr : strcontains(c, ":")])
        ) : (
        !anytrue([for c in var.pod_cidr : strcontains(c, ":")]) &&
        !anytrue([for c in var.service_cidr : strcontains(c, ":")])
      )
      error_message = "pod_cidr/service_cidr IP families must match dual_stack: dual_stack = true requires each to carry both an IPv4 and an IPv6 CIDR; dual_stack = false requires each to be IPv4-only (a \":\"-bearing IPv6 entry needs dual_stack = true; v6-only single-stack is unsupported). Got dual_stack=${var.dual_stack}, pod_cidr=${jsonencode(var.pod_cidr)}, service_cidr=${jsonencode(var.service_cidr)}."
    }
  }
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.this]

  node                 = local.first_controlplane.ip
  endpoint             = local.first_controlplane.ip
  client_configuration = talos_machine_secrets.this.client_configuration
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  node                 = local.first_controlplane.ip
  endpoint             = local.first_controlplane.ip
  client_configuration = talos_machine_secrets.this.client_configuration

  # Re-fetch on advertised endpoint changes; the Talos API dial target remains this controlplane.
  lifecycle {
    replace_triggered_by = [terraform_data.kubeconfig_endpoint_marker]
  }
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.controlplane_ips
  nodes                = local.node_ips
}

# Do not expose a usable cluster until all nodes, etcd and the API are healthy.
data "talos_cluster_health" "this" {
  depends_on = [
    talos_machine_configuration_apply.this,
    talos_machine_bootstrap.this,
    talos_cluster_kubeconfig.this,
  ]

  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = local.controlplane_ips
  worker_nodes         = local.worker_ips
  endpoints            = local.controlplane_ips

  timeouts = {
    read = var.cluster_health_timeout
  }
}
