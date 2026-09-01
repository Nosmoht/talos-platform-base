# Example root for the talos-cluster module — mixed amd64 + arm64 topology.
#
# cluster.yaml here is a COVERAGE MATRIX, not a deployment: one node per distinct
# composition path, proving the module can express a heterogeneous,
# multi-architecture cluster without describing any particular one. It is a
# `tofu validate` fixture, NOT a runnable apply: the example uses RFC5737
# documentation IPs and no state backend.
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
