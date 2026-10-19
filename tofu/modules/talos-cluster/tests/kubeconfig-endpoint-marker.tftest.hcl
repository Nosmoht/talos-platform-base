# The fixture omits main.tf, so this binds only the marker's input; the
# replace_triggered_by wiring is checked by scripts/check-kubeconfig-endpoint-regen.sh.
# cluster_endpoint differs from the node IP so a marker keyed on the wrong input fails.

variables {
  cluster_name       = "test"
  cluster_endpoint   = "https://192.0.2.1:6443"
  talos_version      = "v1.13.9"
  kubernetes_version = "v1.36.3"

  images = {
    intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [] }
  }

  nodes = {
    cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
  }
}

run "kubeconfig_marker_tracks_cluster_endpoint" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }

  assert {
    condition     = output.kubeconfig_endpoint_marker_input == var.cluster_endpoint
    error_message = "issue #186: terraform_data.kubeconfig_endpoint_marker.input must equal var.cluster_endpoint (kubeconfig-refresh.tf) — got a value that does not track the advertised cluster endpoint."
  }
}
