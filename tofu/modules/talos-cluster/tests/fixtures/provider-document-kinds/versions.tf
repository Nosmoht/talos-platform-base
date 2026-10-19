# Must equal the talos constraint in the module versions.tf.
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.12.0, < 0.13.0-0"
    }
  }
}
