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

output "kubelet_serving_cert_rotation" {
  description = <<-EOT
    Whether the base kubelet serving-cert rotation patch
    (machine.kubelet.extraConfig.serverTLSBootstrap) is wired into each role's
    machine-config patch list. BOTH must be true — the serving cert is per
    kubelet, so rotation is all-nodes. Binding point for the composition test
    (red-green: drop [local.base_kubelet_rotation_patch] from a role's concat in
    main.tf and that role flips to false). Secret-free: booleans only — the role
    patch lists themselves embed the sops/ipsec seed Secrets and are NOT exposed.
  EOT
  value = {
    controlplane = contains(local.controlplane_base_patches, local.base_kubelet_rotation_patch)
    worker       = contains(local.worker_machine_config_patches, local.base_kubelet_rotation_patch)
  }
}

output "cert_approver_namespace_labels" {
  description = <<-EOT
    Labels seeded onto the module-delivered kubelet-serving-cert-approver
    namespace (PSA-restricted floor + the six recommended labels). Audit surface
    + the binding point for the composition test's PSA-restricted assertion.
    Non-sensitive (labels carry no secret).
  EOT
  value       = local.cert_approver_namespace_labels
}

output "cert_approver_seeded" {
  description = <<-EOT
    Whether the cert-approver inlineManifest seed is wired into the controlplane
    machine-config patch list. Always true (unconditional substrate boot-glue);
    red-green binding for the seed wiring. Secret-free (boolean).
  EOT
  value       = length(local.cert_approver_controlplane_patch) > 0 ? contains(local.controlplane_base_patches, local.cert_approver_controlplane_patch[0]) : false
}

output "kubelet_rotation_setting" {
  description = <<-EOT
    Decoded content of the base kubelet rotation patch — proves the mechanism is
    the non-deprecated KubeletConfiguration field machine.kubelet.extraConfig.
    serverTLSBootstrap (NOT the deprecated --rotate-server-certificates extraArgs
    flag; repo directive: no deprecated options). Audit surface + the composition
    test's mechanism-binding point. Secret-free.
  EOT
  value       = yamldecode(local.base_kubelet_rotation_patch)
}

output "cert_approver_approve_resource_names" {
  description = <<-EOT
    The resourceNames the vendored cert-approver ClusterRole's `approve` verb is
    scoped to — MUST be exactly ["kubernetes.io/kubelet-serving"] (NOT ["*"], not
    empty/absent). Parses the multi-doc vendored manifest and collects, across all
    ClusterRole docs, the resourceNames of every rule whose verbs include "approve".
    Binds the composition test to the RBAC SCOPE (H7) — a re-vendor that broadens
    the signer scope or drops resourceNames changes this list and fails the test
    (unlike a presence-only substring check, which the signer string survives in
    the ClusterRole name / namespace / comments). Secret-free.
  EOT
  value = flatten([
    for doc in split("---", file("${path.module}/manifests/cert-approver.yaml")) :
    [
      for rule in try(yamldecode(doc).rules, []) :
      try(rule.resourceNames, [])
      if contains(try(rule.verbs, []), "approve")
    ]
    if try(yamldecode(doc).kind, "") == "ClusterRole"
  ])
}

output "cert_approver_seed_missing_labels" {
  description = <<-EOT
    Per-object gaps in the six required app.kubernetes.io/* recommended labels
    (AGENTS.md Hard Constraint) across every object in the vendored cert-approver
    seed manifest. MUST be empty. The seed ships as a Talos inlineManifest, OUTSIDE
    the kustomize render / conftest label gate, so this output binds the
    all-resources label invariant to the seed at test time: dropping a label on a
    re-vendor makes this list non-empty and fails the composition test. Secret-free.
  EOT
  value = flatten([
    for doc in split("---", file("${path.module}/manifests/cert-approver.yaml")) :
    setsubtract(
      ["app.kubernetes.io/name", "app.kubernetes.io/instance", "app.kubernetes.io/version", "app.kubernetes.io/component", "app.kubernetes.io/part-of", "app.kubernetes.io/managed-by"],
      keys(try(yamldecode(doc).metadata.labels, {}))
    )
    if try(yamldecode(doc).kind, "") != ""
  ])
}

output "controlplane_base_is_prefix_of_final" {
  description = <<-EOT
    True iff the assembled controlplane patch list (what
    data.talos_machine_configuration.controlplane actually receives) BEGINS with
    controlplane_base_patches — i.e. the sensitive argocd/cilium seeds are only
    APPENDED after the base, never reordered before it or replacing it. The
    rotation + cert-approver wiring outputs check the non-sensitive base sub-list
    (a contains() over the full list would taint on the sops/ipsec seed Secrets and
    a non-sensitive root output would be rejected); this output binds the LAST
    assembly step so a future edit that drops or reorders the base prefix fails the
    test. Secret-free (boolean — the sensitive tail is excluded by the slice).
  EOT
  value = slice(
    local.controlplane_machine_config_patches, 0, length(local.controlplane_base_patches)
  ) == local.controlplane_base_patches
}
