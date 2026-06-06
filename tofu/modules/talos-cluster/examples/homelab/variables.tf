# Substrate secrets for the talos-cluster module — supplied via tfvar/env, NEVER
# committed to cluster.yaml (the schema has no slot for either). Defaulted here to
# validate-safe placeholders so `tofu validate`/`plan` exercises the now-core
# delivery paths without a real key. A real consumer supplies the actual values
# via TF_VAR_* / a gitignored tfvars / SOPS; NEVER commit a real key.

variable "sops_age_key" {
  description = "age private key for the ArgoCD ksops repoServer (deploy_argocd). Supply via TF_VAR_sops_age_key / tfvars / SOPS."
  type        = string
  sensitive   = true
  # Non-empty placeholder: the module precondition only requires non-empty, and an
  # AGE-SECRET-KEY-shaped literal would trip the gitleaks secret scan.
  default = "dummy-placeholder-supply-real-key-via-tfvar-or-env"
}

variable "cilium_ipsec_key" {
  description = "Cilium IPsec pre-shared key (only when substrate.cilium.encryption.type = ipsec). Supply via TF_VAR_cilium_ipsec_key / tfvars / SOPS."
  type        = string
  sensitive   = true
  default     = "" # empty = no IPsec (the homelab example uses encryption: none)
}
