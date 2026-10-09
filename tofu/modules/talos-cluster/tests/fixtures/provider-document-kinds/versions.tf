# The talos provider constraint is a VERBATIM copy of the module's own
# versions.tf constraint on purpose. The probe runs with the module's lock, so it
# asserts properties of the locked floor; moving the constraint there must move
# it here or the probe stops describing the module's provider.
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.12.0, < 0.13.0-0"
    }
  }
}
