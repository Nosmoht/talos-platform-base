# Substrate secrets for the talos-cluster module — supplied via tfvar/env, NEVER
# committed to cluster.yaml (the schema has no slot for either). Defaulted here to
# validate-safe placeholders so `tofu validate`/`plan` exercises the now-core
# delivery paths without a real key. A real consumer supplies the actual values
# via TF_VAR_* / a gitignored tfvars / SOPS; NEVER commit a real key.

variable "sops_age_key" {
  description = "age private key for the ArgoCD ksops repoServer (deploy_argocd). Supply via TF_VAR_sops_age_key / tfvars / SOPS."
  type        = string
  sensitive   = true
  # No default — deliberately. `tofu plan` on this example (deploy_argocd = true)
  # requires a real age key via TF_VAR_sops_age_key (or tfvars/SOPS); the module's
  # startswith("AGE-SECRET-KEY-1") precondition then passes. A default placeholder
  # would let a copied example root silently `apply` a non-functional ksops key —
  # the exact foot-gun the precondition exists to catch. `tofu validate` (CI) does
  # not evaluate the precondition, so it stays green without a key.
}

variable "cilium_ipsec_key" {
  description = "Cilium IPsec pre-shared key (only when substrate.cilium.encryption.type = ipsec). Supply via TF_VAR_cilium_ipsec_key / tfvars / SOPS."
  type        = string
  sensitive   = true
  default     = "" # empty = no IPsec (the complete example uses encryption: none)
}
