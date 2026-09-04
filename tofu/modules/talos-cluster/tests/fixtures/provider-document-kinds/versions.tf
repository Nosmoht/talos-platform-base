# The talos provider constraint is a VERBATIM copy of the module's own
# versions.tf range on purpose: this fixture asserts a property of whatever
# provider that range resolves to, so widening the range there must widen it
# here or the probe stops describing the module's provider.
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.7.0, < 1.0.0"
    }
  }
}
