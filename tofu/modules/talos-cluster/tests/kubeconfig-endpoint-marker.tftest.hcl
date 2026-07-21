# Kubeconfig-endpoint-marker regression suite (issue #186).
#
# `talos_cluster_kubeconfig.this` (main.tf) does not re-fetch when only the
# advertised cluster endpoint changes (its own `node`/`endpoint` arguments
# stay pinned to local.first_controlplane.ip — kubeconfig-refresh.tf), so a
# `terraform_data` marker keyed on var.cluster_endpoint drives a
# `lifecycle.replace_triggered_by` on the dependent resource instead. This
# test binds ONLY the marker's tracked value (the KEY), offline, via the
# provider-less ./tests/fixtures/colliding-catalog stand-in (which omits
# main.tf, so the lifecycle wiring itself is NOT exercised here — that is
# covered by the resource-scoped grep in
# scripts/check-kubeconfig-endpoint-regen.sh (wired into `task tofu:ci`) and
# by `tofu validate` reference resolution; the behavioral regeneration can
# be confirmed only by an out-of-repo consumer homelab `tofu apply` — not
# run as part of this repo's CI).
#
# Uses the same ./tests/fixtures/colliding-catalog stand-in (symlinked real
# variables.tf) as tests/input-validation.tftest.hcl — pure plan over
# terraform_data, no network, no provider. cluster_endpoint is deliberately
# DISTINCT from the node IP so a marker mis-keyed onto the wrong variable is
# observable (see plan.md §Step-by-step sequence step 5 for the red-green
# demonstration: re-keying kubeconfig-refresh.tf's `input` away from
# var.cluster_endpoint makes this assertion fail).

variables {
  cluster_name       = "test"
  cluster_endpoint   = "https://192.0.2.1:6443"
  talos_version      = "v1.12.6"
  kubernetes_version = "v1.35.0"

  images = {
    intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [] }
  }

  nodes = [
    { hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
  ]
}

run "kubeconfig_marker_tracks_cluster_endpoint" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }

  assert {
    condition     = output.kubeconfig_endpoint_marker_input == var.cluster_endpoint
    error_message = "issue #186: terraform_data.kubeconfig_endpoint_marker.input must equal var.cluster_endpoint (kubeconfig-refresh.tf) — got a value that does not track the advertised cluster endpoint."
  }
}
