# Example root for the talos-cluster module — mixed amd64 + arm64 topology.
#
# This mirrors the shape of a representative mixed-architecture cluster (controlplane + kubevirt
# workers + a GPU worker + a Raspberry-Pi worker) to prove the module can
# express a heterogeneous, multi-architecture cluster. It is a `tofu validate`
# fixture, NOT a runnable apply: the example uses RFC5737 documentation IPs and
# no state backend.
#
# A real consumer root additionally supplies an ENCRYPTED state backend and the
# real cluster identity (endpoint, node IPs, NTP, install disk, registry
# mirrors) via patches.

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.7.0, < 1.0.0"
    }
  }
}

provider "talos" {}
