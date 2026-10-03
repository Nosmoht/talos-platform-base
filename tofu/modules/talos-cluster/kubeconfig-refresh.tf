# Force kubeconfig retrieval when the advertised endpoint changes; the provider dials a node IP.
resource "terraform_data" "kubeconfig_endpoint_marker" {
  input = var.cluster_endpoint
}
