# Provider + OpenTofu version constraints for the talos-cluster module.
#
# Deliberately NO `terraform { backend ... }` block here: the backend is the
# caller's concern. The module is backend-agnostic so a consumer can wire any
# encrypted backend (local+encrypted, S3, …) without source-level changes.
# Because machine_secrets land in state, the chosen backend MUST be encrypted.

terraform {
  # >= 1.11.0: the auto_os_upgrade drain path uses an `ephemeral`
  # talos_cluster_kubeconfig + the write-only `kubeconfig_wo` argument on
  # talos_machine, both of which require Terraform/OpenTofu 1.11+. Consumers that
  # leave auto_os_upgrade = false still need 1.11 only because the constraint is
  # module-wide.
  required_version = ">= 1.11.0"

  required_providers {
    talos = {
      source = "siderolabs/talos"
      # The talos_machine resource (native in-place OS upgrade via the `image`
      # argument + drain_on_upgrade) lands in 0.12.x; 0.11.x has only the retired
      # talos_machine_configuration_apply (config-only, no upgrade).
      #
      # >>> GATE: 0.12.0 STABLE is not released yet — only v0.12.0-alpha.N exist
      # (latest alpha.4, 2026-06-12). This means `task ci` / `tofu validate` CANNOT
      # pass on this branch yet, BY DESIGN: the OpenTofu registry
      # (registry.opentofu.org) does not surface provider PRE-RELEASES at all, so
      # neither `>= 0.12.0` nor a `>= 0.12.0-alpha.N` pin resolves under tofu (the
      # alpha lives only on the Terraform registry). The tofu-validate check stays
      # red until a STABLE 0.12.x is published to the OpenTofu registry — that
      # release is itself the un-block. DO NOT merge / pin a consumer until then.
      # See #129.
      version = ">= 0.12.0, < 1.0.0"
    }
    # helm provider ONLY for data.helm_template (local rendering of ArgoCD into
    # a Talos inlineManifest — NO helm_release/apply, no kubeconfig-from-computed
    # anti-pattern). See var.deploy_argocd + main.tf. Upper bound pinned for the
    # same hygiene as the talos pin; floor at 2.12 (has data.helm_template).
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12, < 3.0.0"
    }
    # local + null ONLY for the ArgoCD-CRD kubectl-server-side apply (the CRDs are
    # too large for the inlineManifest). Both only instantiate when deploy_argocd.
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.2"
    }
  }
}
