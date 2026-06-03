# Provider + OpenTofu version constraints for the talos-cluster module.
#
# Deliberately NO `terraform { backend ... }` block here: the backend is the
# caller's concern. The module is backend-agnostic so a consumer can wire any
# encrypted backend (local+encrypted, S3, …) without source-level changes.
# Because machine_secrets land in state, the chosen backend MUST be encrypted.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.7.0, < 1.0.0"
    }
    # helm-Provider NUR für data.helm_template (lokales Rendern von ArgoCD zu
    # einem Talos-inlineManifest — KEIN helm_release/apply, kein kubeconfig-
    # aus-computed-Anti-Pattern). Siehe var.deploy_argocd + main.tf.
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12"
    }
  }
}
