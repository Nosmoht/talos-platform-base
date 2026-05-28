# Outputs consumed by the caller. Stage 1 (Crossplane tf.Workspace) writes
# kubeconfig + talosconfig into Kubernetes Secrets referenced by
# XCluster.status.{kubeconfigSecretRef,talosconfigSecretRef}; Stage 0 writes
# them to disk for talosctl/kubectl bootstrap.
#
# All credential outputs are marked sensitive — they must never land in plan
# output or logs.

output "kubeconfig" {
  description = "Admin kubeconfig for the bootstrapped cluster (raw YAML)."
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "talosconfig" {
  description = "talosctl client config (raw YAML) for day-2 node access."
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

output "client_configuration" {
  description = "Talos client configuration (ca + client cert/key) for chaining into other Talos resources."
  value       = talos_machine_secrets.this.client_configuration
  sensitive   = true
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint the cluster advertises (echoed from input for caller convenience)."
  value       = var.cluster_endpoint
}

output "controlplane_ips" {
  description = "IPs of the controlplane nodes (talosconfig endpoints)."
  value       = [for n in local.controlplanes : n.ip]
}

output "schematic_ids" {
  description = "Image-Factory schematic IDs per node class (for auditing / debugging which extensions ended up baked into the installer)."
  value       = { for k, s in talos_image_factory_schematic.per_class : k => s.id }
}

output "installer_images" {
  description = "Resolved metal-installer image URL per node class."
  value       = { for k, u in data.talos_image_factory_urls.per_class : k => u.installer_image }
}
