locals {
  # Apply this after caller patches so Cilium cannot coexist with Flannel or kube-proxy.
  base_cni_patch = var.deploy_cilium ? (local.native_config_documents ? concat(
    [yamlencode({ apiVersion = "v1alpha1", kind = "KubeFlannelCNIConfig", "$patch" = "delete" })],
    var.cilium_kube_proxy_replacement ? [yamlencode({ apiVersion = "v1alpha1", kind = "KubeProxyConfig", enabled = false })] : [],
    ) : [yamlencode({
      cluster = merge(
        { network = { cni = { name = "none" } } },
        var.cilium_kube_proxy_replacement ? { proxy = { disabled = true } } : {},
      )
  })]) : []

  gateway_api_patch = (var.deploy_cilium && var.cilium_gateway_api && var.cilium_gateway_api_crds_url != "") ? [local.native_config_documents ? yamlencode({
    apiVersion = "v1alpha1"
    kind       = "KubeExternalManifestConfig"
    name       = "gateway-api-crds"
    url        = var.cilium_gateway_api_crds_url
    }) : yamlencode({
    cluster = { extraManifests = [var.cilium_gateway_api_crds_url] }
  })] : []

  # Seed the IPsec Secret before the Cilium workloads that consume it.
  cilium_controlplane_patch = local.native_config_documents ? flatten([
    for patch in local.cilium_legacy_controlplane_patch : [
      for manifest in yamldecode(patch).cluster.inlineManifests : yamlencode({
        apiVersion = "v1alpha1"
        kind       = "KubeInlineManifestConfig"
        name       = manifest.name
        manifest   = manifest.contents
      })
    ]
  ]) : local.cilium_legacy_controlplane_patch

  cilium_legacy_controlplane_patch = var.deploy_cilium ? [yamlencode({
    cluster = {
      inlineManifests = concat(
        var.cilium_encryption.type == "ipsec" ? [{
          name = "cilium-ipsec-keys"
          contents = yamlencode({
            apiVersion = "v1"
            kind       = "Secret"
            type       = "Opaque"
            metadata   = { name = "cilium-ipsec-keys", namespace = var.cilium_namespace }
            stringData = { keys = var.cilium_ipsec_key }
          })
        }] : [],
        [{
          name     = "cilium"
          contents = terraform_data.cilium_render[0].output
        }],
      )
    }
  })] : []
}

data "helm_template" "cilium" {
  count = var.deploy_cilium ? 1 : 0

  name         = "cilium"
  namespace    = var.cilium_namespace
  repository   = var.cilium_chart_repository
  chart        = "cilium"
  version      = var.cilium_chart_version
  kube_version = var.kubernetes_version
  # Cilium CRDs are required for the operator to start.
  include_crds = true

  values = compact([
    file("${path.module}/helm/cilium-values.yaml"),
    local.cilium_computed_values_yaml,
    var.cilium_values_override,
  ])

  lifecycle {
    precondition {
      condition     = var.cilium_encryption.type != "ipsec" || var.cilium_ipsec_key != ""
      error_message = "cilium_encryption.type = \"ipsec\" requires cilium_ipsec_key (the cilium-ipsec-keys Secret material)."
    }
    precondition {
      condition     = var.cilium_routing_mode != "native" || var.cilium_native_routing_cidr != "" || length(local.cilium_pod_v4) > 0
      error_message = "cilium_routing_mode = \"native\" needs an IPv4 CIDR: set cilium_native_routing_cidr or include an IPv4 entry in pod_cidr."
    }
    postcondition {
      condition     = self.manifest != ""
      error_message = "data.helm_template.cilium rendered an EMPTY manifest — refusing to freeze an empty Cilium seed (would bootstrap a CNI-less cluster). Check cilium_chart_version / cilium_chart_repository / values."
    }
  }
}

# Freeze this create-only seed; Helm render drift must not re-push machine configs.
# Deliberate re-seeding requires -replace.
resource "terraform_data" "cilium_render" {
  count = var.deploy_cilium ? 1 : 0
  input = data.helm_template.cilium[0].manifest
  lifecycle {
    ignore_changes = [input]
  }
}
