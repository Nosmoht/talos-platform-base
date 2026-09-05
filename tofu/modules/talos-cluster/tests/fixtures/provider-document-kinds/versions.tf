# The talos provider constraint is a VERBATIM copy of the module's own
# versions.tf pin on purpose: this fixture asserts a property of whatever
# provider that constraint resolves to, so moving it there must move it here or
# the probe stops describing the module's provider.
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.12.0-beta.0"
    }
  }
}
