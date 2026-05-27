# Provider + OpenTofu version constraints for the talos-cluster module.
#
# Deliberately NO `terraform { backend ... }` block here: the backend is the
# caller's concern (ADR-0006). Stage 0 uses a local+encrypted backend, Stage 1
# uses the DS720+ Garage S3 backend via a Crossplane tf.Workspace. The module
# must work with both without source-level changes.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.7.0, < 1.0.0"
    }
  }
}
