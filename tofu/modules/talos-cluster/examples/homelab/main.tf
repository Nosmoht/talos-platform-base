# Example root for the talos-cluster module — declarative cluster.yaml SoT.
#
# This demonstrates the platform's Source-of-Truth model: the cluster is
# DECLARED in cluster.yaml; this root is a THIN yamldecode shim that maps that
# YAML onto the module's typed, validated variable interface. OpenTofu is the
# executor, not the SoT — the human-edited truth is cluster.yaml.
#
# It is a `tofu validate`/`plan` fixture, NOT a runnable apply: cluster.yaml uses
# RFC5737 documentation IPs and this root configures no state backend. Secrets
# (sops_age_key, cilium_ipsec_key) are NOT in cluster.yaml — they are supplied
# via tfvar/env (see variables.tf), here defaulted to validate-safe placeholders.

locals {
  cfg    = yamldecode(file("${path.module}/cluster.yaml"))
  cilium = try(local.cfg.substrate.cilium, {})
  argocd = try(local.cfg.substrate.argocd, {})

  # Talos machine-config patches are DECLARED as structured YAML maps in
  # cluster.yaml; the module's interface takes YAML strings. yamlencode bridges
  # the two (Talos accepts strategic-merge maps and RFC6902 lists; yamlencode
  # emits valid YAML for both).
  config_patches              = [for p in try(local.cfg.config_patches, []) : yamlencode(p)]
  controlplane_config_patches = [for p in try(local.cfg.controlplane_config_patches, []) : yamlencode(p)]
  worker_config_patches       = [for p in try(local.cfg.worker_config_patches, []) : yamlencode(p)]
}

module "homelab" {
  source = "../../"

  # --- Identity / versions ---
  cluster_name          = local.cfg.cluster.name
  cluster_endpoint      = local.cfg.cluster.endpoint
  talos_version         = local.cfg.talos.version
  talos_install_version = try(local.cfg.talos.install_version, "")
  kubernetes_version    = local.cfg.kubernetes.version

  # --- Cluster network (install-time-fixed) ---
  pod_cidr                          = try(local.cfg.cluster.pod_cidr, ["10.244.0.0/16"])
  service_cidr                      = try(local.cfg.cluster.service_cidr, ["10.96.0.0/12"])
  dual_stack                        = try(local.cfg.cluster.dual_stack, false)
  allow_scheduling_on_controlplanes = try(local.cfg.cluster.allow_scheduling_on_controlplanes, false)

  # --- Topology (node config_patches re-encoded to YAML strings) ---
  nodes = [for n in local.cfg.nodes : {
    hostname              = n.hostname
    ip                    = n.ip
    role                  = n.role
    image                 = n.image
    hardware_capabilities = try(n.hardware_capabilities, [])
    config_patches        = [for p in try(n.config_patches, []) : yamlencode(p)]
  }]

  images = { for name, img in local.cfg.images : name => {
    architecture = try(img.architecture, "amd64")
    cpu_vendor   = try(img.cpu_vendor, "intel")
    extensions   = try(img.extensions, [])
    overlay = try(img.overlay, null) == null ? null : {
      name    = img.overlay.name
      image   = img.overlay.image
      options = try(img.overlay.options, null)
    }
  } }

  hardware_capabilities = { for name, c in try(local.cfg.hardware_capabilities, {}) : name => {
    requires_features     = try(c.requires_features, [])
    provisioning_profiles = try(c.provisioning_profiles, [])
    emits_label           = c.emits_label
  } }

  # --- Cluster-wide + role patches ---
  config_patches              = local.config_patches
  controlplane_config_patches = local.controlplane_config_patches
  worker_config_patches       = local.worker_config_patches

  # --- Substrate: Cilium ---
  deploy_cilium                 = try(local.cilium.enabled, true)
  cilium_chart_version          = try(local.cilium.chart_version, "1.19.4")
  cilium_chart_repository       = try(local.cilium.chart_repository, "https://helm.cilium.io")
  cilium_routing_mode           = try(local.cilium.routing_mode, "tunnel")
  cilium_native_routing_cidr    = try(local.cilium.native_routing_cidr, "")
  cilium_kube_proxy_replacement = try(local.cilium.kube_proxy_replacement, true)
  cilium_mtu                    = try(local.cilium.mtu, 0)
  cilium_gateway_api            = try(local.cilium.gateway_api, true)
  cilium_gateway_api_crds_url   = try(local.cilium.gateway_api_crds_url, "")
  cilium_encryption             = try(local.cilium.encryption, { type = "none" })
  cilium_values_override        = try(local.cilium.values_override, "")
  cilium_ipsec_key              = var.cilium_ipsec_key # secret — tfvar/env, never cluster.yaml

  # --- Substrate: ArgoCD ---
  deploy_argocd          = try(local.argocd.enabled, true)
  argocd_chart_version   = try(local.argocd.chart_version, "9.4.5")
  argocd_namespace       = try(local.argocd.namespace, "argocd")
  argocd_values_override = try(local.argocd.values_override, "")
  sops_age_key           = var.sops_age_key # secret — tfvar/env, never cluster.yaml
}
