# The caller owns the backend and must encrypt state containing cluster PKI.

terraform {
  # Cross-variable validation requires OpenTofu 1.9.
  required_version = ">= 1.9.0"

  required_providers {
    # Keep the constraint, examples, probe and lock synchronized; the lock stays at the floor.
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.12.0, < 0.13.0-0"
    }
    # Local chart rendering only; no Helm release or Kubernetes connection.
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12, < 3.0.0"
    }
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
