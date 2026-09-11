# Provider + OpenTofu version constraints for the talos-cluster module.
#
# Deliberately NO `terraform { backend ... }` block here: the backend is the
# caller's concern. The module is backend-agnostic so a consumer can wire any
# encrypted backend (local+encrypted, S3, …) without source-level changes.
# Because machine_secrets land in state, the chosen backend MUST be encrypted.

terraform {
  # >= 1.9.0: cilium_self_management's two cross-variable `validation` blocks
  # (deploy-prereq guard + the override-drop hard-reject guard, variables.tf)
  # reference OTHER variables in their `condition` — an OpenTofu >= 1.9 feature,
  # parsed at module load regardless of the toggle's value. A consumer on
  # 1.7.x/1.8.x gets a hard parse break the instant they consume a tag carrying
  # this bump — a permanent, consumer-visible compatibility floor for one
  # opt-in, default-off feature. See
  # knowledge/decisions/0022-cilium-observability-and-argocd-self-management.md.
  required_version = ">= 1.9.0"

  required_providers {
    # EXACT, and a prerelease: 0.12.0-beta.0 is the only release bundling the
    # Talos 1.14 machinery, and a RANGE never selects a prerelease — the former
    # `>= 0.7.0, < 1.0.0` resolves to 0.11.0 and leaves every 1.14 document kind
    # undecodable. A consumer root declaring a range still resolves (measured:
    # the exact pin wins the intersection); only a root pinning a DIFFERENT exact
    # version fails init. Mirrored verbatim in examples/complete/versions.tf,
    # tests/fixtures/provider-document-kinds/versions.tf, the README's example
    # root and test/pki-reconcile-microtest.sh — parity is asserted by
    # scripts/check-provider-document-kinds.sh. See
    # knowledge/decisions/0027-talos-provider-prerelease-pin.md.
    talos = {
      source  = "siderolabs/talos"
      version = "0.12.0-beta.0"
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
