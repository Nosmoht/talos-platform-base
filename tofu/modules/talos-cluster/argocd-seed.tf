data "helm_template" "argocd" {
  count = var.deploy_argocd ? 1 : 0

  name         = "argocd"
  namespace    = var.argocd_namespace
  repository   = "https://argoproj.github.io/argo-helm"
  chart        = "argo-cd"
  version      = var.argocd_chart_version
  kube_version = var.kubernetes_version
  # CRDs exceed the inlineManifest size budget; argocd-crds.tf applies them separately.
  include_crds = false

  values = var.argocd_values_override != "" ? [
    file("${path.module}/helm/argocd-values.yaml"),
    var.argocd_values_override,
  ] : [file("${path.module}/helm/argocd-values.yaml")]

  lifecycle {
    precondition {
      condition     = startswith(var.sops_age_key, "AGE-SECRET-KEY-1")
      error_message = "deploy_argocd = true requires a real age private key in sops_age_key (it must start with \"AGE-SECRET-KEY-1\"; supply via TF_VAR_sops_age_key / tfvars / SOPS). The ArgoCD ksops repoServer needs it to decrypt SOPS manifests."
    }
    postcondition {
      condition     = self.manifest != ""
      error_message = "data.helm_template.argocd rendered an EMPTY manifest — refusing to freeze an empty ArgoCD seed. Check argocd_chart_version / repository / argocd_values_override."
    }
  }
}

# Freeze the create-only seed to prevent Helm render drift from re-pushing machine configs.
# No triggers_replace: deliberate re-seeding requires -replace.
resource "terraform_data" "argocd_render" {
  count = var.deploy_argocd ? 1 : 0
  input = data.helm_template.argocd[0].manifest
  lifecycle {
    ignore_changes = [input]
  }
}

locals {
  argocd_namespace_labels = {
    "app.kubernetes.io/name"                     = "argocd"
    "app.kubernetes.io/instance"                 = "argocd"
    "app.kubernetes.io/version"                  = var.argocd_chart_version
    "app.kubernetes.io/component"                = "bootstrap"
    "app.kubernetes.io/part-of"                  = "gitops"
    "app.kubernetes.io/managed-by"               = "opentofu"
    "pod-security.kubernetes.io/enforce"         = "baseline"
    "pod-security.kubernetes.io/enforce-version" = "latest"
    "pod-security.kubernetes.io/audit"           = "restricted"
    "pod-security.kubernetes.io/audit-version"   = "latest"
    "pod-security.kubernetes.io/warn"            = "restricted"
    "pod-security.kubernetes.io/warn-version"    = "latest"
  }

  argocd_controlplane_patch = local.native_config_documents ? flatten([
    for patch in local.argocd_legacy_controlplane_patch : [
      for manifest in yamldecode(patch).cluster.inlineManifests : yamlencode({
        apiVersion = "v1alpha1"
        kind       = "KubeInlineManifestConfig"
        name       = manifest.name
        manifest   = manifest.contents
      })
    ]
  ]) : local.argocd_legacy_controlplane_patch

  argocd_legacy_controlplane_patch = var.deploy_argocd ? [yamlencode({
    cluster = {
      inlineManifests = [
        {
          name = "argocd-namespace"
          contents = yamlencode({
            apiVersion = "v1"
            kind       = "Namespace"
            metadata = {
              name = var.argocd_namespace
              # Share the labels with the audit output so its assertions cover the seeded namespace.
              labels = local.argocd_namespace_labels
            }
          })
        },
        {
          name = "argocd-sops-age-key"
          contents = yamlencode({
            apiVersion = "v1"
            kind       = "Secret"
            type       = "Opaque"
            metadata   = { name = "sops-age-key", namespace = var.argocd_namespace }
            stringData = { "keys.txt" = var.sops_age_key }
          })
        },
        {
          name     = "argocd"
          contents = terraform_data.argocd_render[0].output
        },
      ]
    }
  })] : []
}
