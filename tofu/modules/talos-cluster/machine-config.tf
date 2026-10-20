locals {
  base_cluster_patch = local.native_config_documents ? yamlencode({
    apiVersion     = "v1alpha1"
    kind           = "KubeNetworkConfig"
    podSubnets     = var.pod_cidr
    serviceSubnets = var.service_cidr
    }) : yamlencode({
    cluster = {
      network = {
        podSubnets     = var.pod_cidr
        serviceSubnets = var.service_cidr
      }
      allowSchedulingOnControlPlanes = var.allow_scheduling_on_controlplanes
    }
  })

  # Serving-certificate rotation requires the unconditional cert-approver seed.
  base_kubelet_rotation_patch = local.native_config_documents ? yamlencode({
    apiVersion = "v1alpha1"
    kind       = "KubeletConfig"
    config     = { serverTLSBootstrap = true }
    }) : yamlencode({
    machine = { kubelet = { extraConfig = { serverTLSBootstrap = true } } }
  })
}

locals {
  # Talos machinery constants.GRPCMaxMessageSize.
  talos_grpc_max_message_bytes = 32 * 1024 * 1024

  # Reserve 1 MiB for the generated base document, per-node patches and gRPC framing.
  controlplane_payload_ceiling_bytes = local.talos_grpc_max_message_bytes - (1024 * 1024)

  controlplane_base_patches = concat(
    [local.base_cluster_patch],
    local.native_config_documents && var.allow_scheduling_on_controlplanes ? [yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeNodeConfig"
      taints     = { "node-role.kubernetes.io/control-plane" = { "$patch" = "delete" } }
    })] : [],
    [local.base_kubelet_rotation_patch],
    local.register_with_fqdn_patch,
    var.config_patches,
    var.controlplane_config_patches,
    local.base_cni_patch,
    local.gateway_api_patch,
    local.cert_approver_controlplane_patch,
    local.coredns_controlplane_patch,
  )
  controlplane_machine_config_patches = concat(
    local.controlplane_base_patches,
    local.argocd_controlplane_patch,
    local.cilium_controlplane_patch,
  )
  worker_machine_config_patches = concat(
    [local.base_cluster_patch],
    [local.base_kubelet_rotation_patch],
    local.register_with_fqdn_patch,
    var.config_patches,
    var.worker_config_patches,
    local.native_config_documents ? [] : local.base_cni_patch,
  )
}

data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version
  config_patches     = local.controlplane_machine_config_patches

  lifecycle {
    # Bound the combined seeds, not each seed separately; per-node overlays are outside this sum.
    precondition {
      condition     = sum([for p in local.controlplane_machine_config_patches : length(p)]) <= local.controlplane_payload_ceiling_bytes
      error_message = "controlplane config patches sum to ${sum([for p in local.controlplane_machine_config_patches : length(p)])} bytes, over the ${local.controlplane_payload_ceiling_bytes}-byte ceiling (Talos API gRPC limit ${local.talos_grpc_max_message_bytes} bytes, minus headroom for the generated base document and the pass-2 per-node overlays). Enabled inlineManifest seeds: cert-approver (always on), argocd=${var.deploy_argocd}, cilium=${var.deploy_cilium}, coredns=${var.coredns_node_separation}. Shrink a seed, move manifests to cluster.extraManifests, or disable a substrate component."
    }
  }
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version
  config_patches     = local.worker_machine_config_patches

}

locals {
  node_installer_images = {
    for h, n in local.nodes_checked : h => data.talos_image_factory_urls.this[local.node_install_key[h]].urls.installer
  }
  # Native installer patches must preserve provisioning; the provider cannot merge this block.
  role_install_provisioning = local.native_config_documents ? {
    for role, configuration in {
      controlplane = data.talos_machine_configuration.controlplane.machine_configuration
      worker       = data.talos_machine_configuration.worker.machine_configuration
      } : role => one([
        for document in split("\n---\n", configuration) : yamldecode(document).provisioning
        if try(yamldecode(document).kind, "") == "UnattendedInstallConfig"
    ])
  } : {}
  node_config_patches = {
    for h, n in local.nodes_checked : h => concat(
      [
        local.native_config_documents ? yamlencode({
          apiVersion   = "v1alpha1"
          kind         = "UnattendedInstallConfig"
          installer    = { image = local.node_installer_images[h] }
          provisioning = local.role_install_provisioning[n.role]
          }) : yamlencode({
          machine = {
            install = {
              # Use urls.installer; SecureBoot installers cause boot loops.
              image = local.node_installer_images[h]
            }
          }
        }),
        # Delete automatic hostname selection so the node-map key remains the node identity.
        yamlencode({
          apiVersion = "v1alpha1"
          kind       = "HostnameConfig"
          hostname   = h
          auto       = { "$patch" = "delete" }
        }),
      ],
      # Caller node patches may override generated capabilities.
      local.node_generated_patches[h],
      n.config_patches,
      # Reassert CNI invariants after node patches. Native workers carry no cluster CNI documents.
      local.native_config_documents && n.role == "worker" ? [] : local.base_cni_patch,
      n.role == "controlplane" ? local.coredns_builtin_disable_patch : [],
    )
  }
}

resource "talos_machine_configuration_apply" "this" {
  for_each = local.nodes_checked

  client_configuration = talos_machine_secrets.this.client_configuration
  machine_configuration_input = (
    each.value.role == "controlplane"
    ? data.talos_machine_configuration.controlplane.machine_configuration
    : data.talos_machine_configuration.worker.machine_configuration
  )
  node       = each.value.ip
  apply_mode = local.node_apply_mode[each.key]

  config_patches = local.node_config_patches[each.key]

  lifecycle {
    precondition {
      condition     = length(local.coredns_guard_violations) == 0
      error_message = "coredns_node_separation renders the CoreDNS Corefile for the DNS domain \"${local.coredns_cluster_domain}\", the kube-dns ClusterIP from service_cidr and the image coredns_image, and checks every rendered role configuration and per-node patch for a different value. Findings: ${join("; ", local.coredns_guard_violations)}. A JSON6902 patch on one of these fields, on cluster.inlineManifests or on a parent, a $patch directive on cluster, cluster.network or a KubeNetworkConfig, a per-node inline manifest named \"coredns\", a rendered configuration that states no serviceSubnets, and a document the check cannot read each count as a finding. Set service_cidr instead of patching serviceSubnets, set coredns_image instead of the Talos CoreDNS image, keep the default DNS domain, or set coredns_node_separation = false."
    }
  }
}
