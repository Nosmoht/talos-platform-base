# Outputs consumed by the caller. A direct `tofu apply` writes kubeconfig +
# talosconfig to disk for talosctl/kubectl bootstrap; a higher-level
# orchestrator may instead write them into secret storage. The contract is the
# same either way.
#
# All credential outputs are marked sensitive — they must never land in plan
# output or logs.

output "kubeconfig" {
  description = "Admin kubeconfig for the bootstrapped cluster (raw YAML)."
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
  # Only emit once the cluster is healthy — a consumer that writes this output
  # into secret storage should not receive a kubeconfig for a cluster that is
  # not yet reachable.
  depends_on = [data.talos_cluster_health.this]
}

output "talosconfig" {
  description = "talosctl client config (raw YAML) for day-2 node access."
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
  depends_on  = [data.talos_cluster_health.this]
}

output "cluster_health" {
  description = <<-EOT
    "healthy" once data.talos_cluster_health has passed (etcd quorum, nodes
    Ready, apiserver reachable). Because the output references the health data
    source, any consumer that reads it blocks until the cluster is online — the
    module's explicit "wait until reachable" contract.
  EOT
  value       = "healthy (${data.talos_cluster_health.this.id})"
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
  description = "Image-Factory schematic IDs per DISTINCT content-hash (auditing which extensions / kernel-args ended up baked). Identical nodes share a hash; the key is the module's dedup hash, not a class name."
  value       = { for k, s in talos_image_factory_schematic.this : k => s.id }
}

output "installer_images" {
  description = "Resolved (non-secureboot) metal-installer image URL per node HOSTNAME. Echoed for tfplan-JSON consumption by the consumer's `talos:upgrade:cluster` task (keyed by hostname now that `class` is gone)."
  value       = { for hostname, key in local.node_install_key : hostname => data.talos_image_factory_urls.this[key].urls.installer }
}

output "node_schematic_hashes" {
  description = "Per-node content-hash of the composed schematic (audit / dedup debugging). Known at plan time; identical effective provisioning -> identical hash."
  value       = local.node_hash
}

output "distinct_schematic_count" {
  description = "Number of distinct schematics after content-hash dedup (<= node count). Known at plan time."
  value       = length(local.schematics)
}

output "talos_install_version" {
  description = "Effective Talos OS installer version (= var.talos_install_version, or var.talos_version if unset). The upgrade task reads this from tfplan JSON for `talosctl upgrade --image …:<version>`."
  value       = local.install_version
}

output "argocd_namespace_labels" {
  description = <<-EOT
    Labels seeded onto the module-delivered argocd namespace (PSA floor +
    recommended labels), or {} when deploy_argocd = false. Audit surface (which
    PSA level / labels the create-only seed bakes) and the binding point for the
    composition test's PSA assertion. Non-sensitive (labels carry no secret).
  EOT
  value       = var.deploy_argocd ? local.argocd_namespace_labels : {}
}
