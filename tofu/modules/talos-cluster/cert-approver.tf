locals {
  cert_approver_leader_election = var.cert_approver_replicas > 1

  # JSON-encode strings before template interpolation so regexes and prefixes remain YAML scalars.
  cert_approver_manifest = templatefile("${path.module}/manifests/kubelet-csr-approver.yaml", {
    provider_regex       = jsonencode(var.cert_approver_provider_regex)
    provider_ip_prefixes = jsonencode(join(",", var.cert_approver_provider_ip_prefixes))
    replicas             = var.cert_approver_replicas
    leader_election      = local.cert_approver_leader_election
  })

  cert_approver_namespace_labels = {
    "app.kubernetes.io/name"                     = "kubelet-csr-approver"
    "app.kubernetes.io/instance"                 = "kubelet-csr-approver"
    "app.kubernetes.io/version"                  = "v1.2.14"
    "app.kubernetes.io/component"                = "cert-approver"
    "app.kubernetes.io/part-of"                  = "talos-platform-base"
    "app.kubernetes.io/managed-by"               = "opentofu"
    "pod-security.kubernetes.io/enforce"         = "restricted"
    "pod-security.kubernetes.io/enforce-version" = "latest"
    "pod-security.kubernetes.io/audit"           = "restricted"
    "pod-security.kubernetes.io/audit-version"   = "latest"
    "pod-security.kubernetes.io/warn"            = "restricted"
    "pod-security.kubernetes.io/warn-version"    = "latest"
  }

  cert_approver_controlplane_patch = local.native_config_documents ? flatten([
    for patch in local.cert_approver_legacy_controlplane_patch : [
      for manifest in yamldecode(patch).cluster.inlineManifests : yamlencode({
        apiVersion = "v1alpha1"
        kind       = "KubeInlineManifestConfig"
        name       = manifest.name
        manifest   = manifest.contents
      })
    ]
  ]) : local.cert_approver_legacy_controlplane_patch

  cert_approver_legacy_controlplane_patch = [yamlencode({
    cluster = {
      inlineManifests = [
        {
          name = "kubelet-csr-approver-namespace"
          contents = yamlencode({
            apiVersion = "v1"
            kind       = "Namespace"
            metadata = {
              name   = "kubelet-csr-approver"
              labels = local.cert_approver_namespace_labels
            }
          })
        },
        {
          name     = "kubelet-csr-approver"
          contents = local.cert_approver_manifest
        },
      ]
    }
  })]
}
