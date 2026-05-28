# talos-cluster: turns a set of PXE-booted Talos maintenance-mode nodes into a
# bootstrapped Kubernetes cluster, and reconciles Kubernetes version + system
# extensions on subsequent applies. Hardware provisioning and PXE boot are
# out of scope (see lifecycle/ipxe + the DHCP/next-server setup).
#
# Flow:
#   image-factory per class (extensions -> schematic -> installer URL)
#     -> machine_secrets (PKI)
#       -> machine_configuration (per machine_type, with k8s/talos version + patches)
#         -> configuration_apply (per node, with hostname + install.image patch)
#           -> bootstrap (first controlplane only)
#             -> kubeconfig + talosconfig
#               -> cluster_kubernetes_upgrade (Day-2, on kubernetes_version bump)

locals {
  controlplanes = [for n in var.nodes : n if n.role == "controlplane"]

  # First controlplane is the bootstrap target and the node we pull
  # kubeconfig/talosconfig from. Deterministic: input order is preserved.
  first_controlplane = local.controlplanes[0]

  nodes_by_hostname = { for n in var.nodes : n.hostname => n }

  # Node classes actually referenced by var.nodes. Used to verify each class
  # has a matching entry in var.extensions before installer URLs are looked up.
  used_classes = distinct([for n in var.nodes : n.class])
}

# Defensive cross-check: every class referenced by a node must be defined in
# var.extensions. Failing here gives a clearer error than a missing map key.
check "node_class_extensions_defined" {
  assert {
    condition = alltrue([
      for c in local.used_classes : contains(keys(var.extensions), c)
    ])
    error_message = format(
      "Every node.class must be a key in var.extensions. Used by nodes: %v. Defined in extensions: %v.",
      local.used_classes, keys(var.extensions),
    )
  }
}

# ---------------------------------------------------------------------------
# Image-Factory: per-class custom installer image
# ---------------------------------------------------------------------------
# Per class, resolve the extension package names against the Talos Image
# Factory (gets concrete versions for var.talos_version), commit them to a
# schematic, and derive the metal-installer URL. Empty extension lists yield
# the default Talos installer (no system extensions) for that class.
#
# Hard Constraint (base AGENTS.md): never use metal-installer-secureboot.
# secure_boot defaults to false in talos_image_factory_urls — we keep it that
# way.

data "talos_image_factory_extensions_versions" "per_class" {
  for_each = var.extensions

  talos_version = var.talos_version
  filters = {
    names = each.value
  }
}

resource "talos_image_factory_schematic" "per_class" {
  for_each = var.extensions

  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = [
          for ext in data.talos_image_factory_extensions_versions.per_class[each.key].extensions_info :
          ext.name
        ]
      }
    }
  })
}

data "talos_image_factory_urls" "per_class" {
  for_each = var.extensions

  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.per_class[each.key].id
  platform      = "metal"
  architecture  = "amd64" # TODO when ARM classes appear: per-class architecture map
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

# Apply the config to each node. Module-injected per-node patches:
#   - hostname (from node.hostname)
#   - install.image (the class-specific Image-Factory installer URL)
# Everything else is role-uniform from the data.talos_machine_configuration
# above plus the caller's config_patches.
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
        install = {
          image = data.talos_image_factory_urls.per_class[each.value.class].installer_image
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

# ---------------------------------------------------------------------------
# Day-2 reconciliation — what the module handles and what stays out-of-band
# ---------------------------------------------------------------------------
# - Talos OS upgrade (var.talos_version bump): the new version flows into
#   data.talos_machine_configuration AND into the per-class installer image
#   from the Image Factory. talos_machine_configuration_apply re-renders the
#   per-node config (including install.image) and applies it rolling — Talos
#   takes care of the actual upgrade.
# - Image-Factory extension changes (var.extensions edits): schematic_id
#   changes, installer_image URL changes, machine_configuration_apply re-rolls
#   nodes of the affected class.
# - System-extension version pinning: data.talos_image_factory_extensions_versions
#   is re-evaluated on every apply; new official versions become available
#   when var.talos_version changes (the factory pins extension versions to a
#   Talos release).
#
# OUT OF SCOPE for now: Kubernetes version upgrade. The siderolabs/talos
# Terraform provider does NOT ship a `talos_cluster_kubernetes_upgrade`
# resource (status: provider release used by this module). For Kubernetes
# upgrades, run `talosctl upgrade-k8s --to <version>` against the cluster —
# this is the one Day-2 op that escapes the tofu apply loop. Tracked for
# follow-up when the provider exposes the upgrade as a resource.
