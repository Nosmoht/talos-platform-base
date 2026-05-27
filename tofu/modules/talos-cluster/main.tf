# talos-cluster: turns a set of PXE-booted Talos maintenance-mode nodes into a
# bootstrapped Kubernetes cluster. Hardware provisioning and the PXE boot are
# out of scope (see lifecycle/ipxe + the DHCP/next-server setup) — this module
# starts from "nodes reachable on the Talos API port" and ends at "kubeconfig".
#
# Flow:
#   machine_secrets (PKI)
#     -> machine_configuration (per machine_type, with k8s/talos version + patches)
#       -> configuration_apply (per node, with hostname patch)
#         -> bootstrap (first controlplane only)
#           -> kubeconfig + talosconfig outputs

locals {
  controlplanes = [for n in var.nodes : n if n.role == "controlplane"]

  # First controlplane is the bootstrap target and the node we pull
  # kubeconfig/talosconfig from. Deterministic: input order is preserved.
  first_controlplane = local.controlplanes[0]

  nodes_by_hostname = { for n in var.nodes : n.hostname => n }
}

# Cluster PKI + shared secrets. Generated once; stored in state (hence the
# encrypted backends per ADR-0006).
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

# Base machine configuration per role. Cluster-specific patches are layered on
# by the caller via var.config_patches (all) and the role-specific lists.
data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version
  config_patches     = concat(var.config_patches, var.controlplane_config_patches)
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version
  config_patches     = concat(var.config_patches, var.worker_config_patches)
}

# Apply the config to each node. The per-node hostname patch is the only
# node-specific config the module injects; everything else is role-uniform.
resource "talos_machine_configuration_apply" "this" {
  for_each = local.nodes_by_hostname

  client_configuration = talos_machine_secrets.this.client_configuration
  machine_configuration_input = (
    each.value.role == "controlplane"
    ? data.talos_machine_configuration.controlplane.machine_configuration
    : data.talos_machine_configuration.worker.machine_configuration
  )
  node = each.value.ip

  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname = each.value.hostname
        }
      }
    })
  ]
}

# Bootstrap etcd on the first controlplane only. Must run after the config is
# applied; bootstrapping more than one node would split-brain etcd.
resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.this]

  node                 = local.first_controlplane.ip
  endpoint             = local.first_controlplane.ip
  client_configuration = talos_machine_secrets.this.client_configuration
}

# Pull the admin kubeconfig once the cluster is bootstrapped. Resource (not
# data source) per the talos provider >= 0.7 deprecation — the data source is
# scheduled for removal.
resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  node                 = local.first_controlplane.ip
  endpoint             = local.first_controlplane.ip
  client_configuration = talos_machine_secrets.this.client_configuration
}

# talosconfig for day-2 talosctl access. Endpoints = controlplanes, nodes = all.
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for n in local.controlplanes : n.ip]
  nodes                = [for n in var.nodes : n.ip]
}
