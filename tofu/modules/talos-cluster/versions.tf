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
  }
}
