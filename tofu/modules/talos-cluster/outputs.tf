output "kubeconfig" {
  description = "Admin kubeconfig for the bootstrapped cluster (raw YAML)."
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
  depends_on  = [data.talos_cluster_health.this]
}

output "talosconfig" {
  description = "talosctl client config (raw YAML) for day-2 node access."
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
  depends_on  = [data.talos_cluster_health.this]
}

output "cluster_health" {
  description = <<-EOT
    "healthy" once data.talos_cluster_health has passed. Reading it blocks
    until the cluster is online.
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
  description = "IPs of the controlplane nodes (talosconfig endpoints), ordered by node name — not by declaration order."
  value       = local.controlplane_ips
}

output "schematic_ids" {
  description = "Image Factory schematic IDs keyed by the module's content hash; identical nodes share one."
  value       = { for k, s in talos_image_factory_schematic.this : k => s.id }
}

output "installer_images" {
  description = "Resolved non-secureboot metal-installer image URL per node hostname."
  value       = { for hostname, key in local.node_install_key : hostname => data.talos_image_factory_urls.this[key].urls.installer }
}

output "node_schematic_hashes" {
  description = "Per-node content hash of the composed schematic, known at plan time."
  value       = local.node_hash
}

output "distinct_schematic_count" {
  description = "Number of distinct schematics after content-hash dedup, known at plan time."
  value       = length(local.schematics)
}

output "talos_install_version" {
  description = "Effective Talos installer version: talos_install_version, or talos_version if unset."
  value       = local.install_version
}

output "argocd_namespace_labels" {
  description = <<-EOT
    Labels seeded onto the module-delivered argocd namespace, or {} when
    deploy_argocd = false.
  EOT
  value       = var.deploy_argocd ? local.argocd_namespace_labels : {}
}

output "argocd_day0_apply_kinds" {
  description = <<-EOT
    Distinct kinds in the manifest the module kubectl-applies after the health
    gate, or [] when deploy_argocd = false. Expected: ["CustomResourceDefinition"];
    "<unparseable>" marks a document that does not decode.
  EOT
  value       = local.argocd_crd_kinds
}

output "argocd_day0_apply_crd_names" {
  description = <<-EOT
    Sorted metadata.names in the same applied manifest, or [] when
    deploy_argocd = false. Expected: the three ArgoCD CRDs.
  EOT
  value       = local.argocd_crd_names
}

output "kubelet_serving_cert_rotation" {
  description = <<-EOT
    Whether the kubelet serving-cert rotation patch is in each role's
    machine-config patch list, as { controlplane, worker } booleans.
  EOT
  value = {
    controlplane = contains(local.controlplane_base_patches, local.base_kubelet_rotation_patch)
    worker       = contains(local.worker_machine_config_patches, local.base_kubelet_rotation_patch)
  }
}

output "cert_approver_namespace_labels" {
  description = <<-EOT
    Labels seeded onto the module-delivered kubelet-csr-approver namespace.
  EOT
  value       = local.cert_approver_namespace_labels
}

output "cert_approver_seeded" {
  description = <<-EOT
    Whether the cert-approver inlineManifest seed is in the controlplane
    machine-config patch list.
  EOT
  value       = length(local.cert_approver_controlplane_patch) > 0 ? contains(local.controlplane_base_patches, local.cert_approver_controlplane_patch[0]) : false
}

output "kubelet_rotation_setting" {
  description = <<-EOT
    Decoded content of the kubelet serving-cert rotation patch
    (machine.kubelet.extraConfig.serverTLSBootstrap).
  EOT
  value       = yamldecode(local.base_kubelet_rotation_patch)
}

output "cert_approver_approve_resource_names" {
  description = <<-EOT
    resourceNames of every rule granting `approve` in the cert-approver seed,
    across all documents. A rule without resourceNames appears as "<UNSCOPED>".
    Expected: ["kubernetes.io/kubelet-serving"].
  EOT
  value = flatten([
    for doc in split("---", local.cert_approver_manifest) :
    [
      for rule in try(yamldecode(doc).rules, []) :
      length(try(rule.resourceNames, [])) > 0 ? rule.resourceNames : ["<UNSCOPED>"]
      if contains(try(rule.verbs, []), "approve")
    ]
    if try(yamldecode(doc).kind, "") != ""
  ])
}

output "cert_approver_seed_missing_labels" {
  description = <<-EOT
    app.kubernetes.io/* recommended labels missing from objects in the
    cert-approver seed. Expected: empty; the seed bypasses the kustomize label gate.
  EOT
  value = flatten([
    for doc in split("---", local.cert_approver_manifest) :
    setsubtract(
      ["app.kubernetes.io/name", "app.kubernetes.io/instance", "app.kubernetes.io/version", "app.kubernetes.io/component", "app.kubernetes.io/part-of", "app.kubernetes.io/managed-by"],
      keys(try(yamldecode(doc).metadata.labels, {}))
    )
    if try(yamldecode(doc).kind, "") != ""
  ])
}

output "cert_approver_rbac_rules" {
  description = <<-EOT
    Raw ClusterRole rules of the cert-approver seed. The leader-election
    grant is a namespaced Role, see cert_approver_leaderelection_role_rules.
  EOT
  value = flatten([
    for doc in split("---", local.cert_approver_manifest) :
    try(yamldecode(doc).rules, [])
    if try(yamldecode(doc).kind, "") == "ClusterRole"
  ])
}

output "cert_approver_clusterrole_signature" {
  description = <<-EOT
    Sorted "g=|r=|v=|n=" signature (apiGroups, resources, verbs,
    resourceNames) of every ClusterRole rule in the cert-approver seed.
  EOT
  value = sort(flatten([
    for doc in split("---", local.cert_approver_manifest) :
    [
      for r in try(yamldecode(doc).rules, []) :
      format("g=%s|r=%s|v=%s|n=%s",
        join(",", sort(try(r.apiGroups, []))),
        join(",", sort(try(r.resources, []))),
        join(",", sort(try(r.verbs, []))),
        join(",", sort(try(r.resourceNames, [])))
      )
    ]
    if try(yamldecode(doc).kind, "") == "ClusterRole"
  ]))
}

output "cert_approver_clusterrolebinding_targets" {
  description = <<-EOT
    Every ClusterRoleBinding in the cert-approver seed as
    { role, subjects = ["<kind>/<namespace>/<name>", ...] }.
  EOT
  value = [
    for doc in split("---", local.cert_approver_manifest) :
    {
      role     = try(yamldecode(doc).roleRef.name, "")
      subjects = [for s in try(yamldecode(doc).subjects, []) : "${try(s.kind, "")}/${try(s.namespace, "")}/${try(s.name, "")}"]
    }
    if try(yamldecode(doc).kind, "") == "ClusterRoleBinding"
  ]
}

output "cert_approver_leaderelection_role_rules" {
  description = <<-EOT
    Rules of the cert-approver leader-election Role. Empty at replicas = 1,
    where no Role is rendered.
  EOT
  value = flatten([
    for doc in split("---", local.cert_approver_manifest) :
    try(yamldecode(doc).rules, [])
    if try(yamldecode(doc).kind, "") == "Role"
  ])
}

output "cert_approver_pod_security_context" {
  description = <<-EOT
    Container securityContext of the cert-approver Deployment, or {}.
  EOT
  value = try([
    for doc in split("---", local.cert_approver_manifest) :
    yamldecode(doc).spec.template.spec.containers[0].securityContext
    if try(yamldecode(doc).kind, "") == "Deployment"
  ][0], {})
}

output "cert_approver_container_args" {
  description = <<-EOT
    Container args of the cert-approver Deployment. `-leader-election`
    appears only when replicas > 1.
  EOT
  value = try([
    for doc in split("---", local.cert_approver_manifest) :
    yamldecode(doc).spec.template.spec.containers[0].args
    if try(yamldecode(doc).kind, "") == "Deployment"
  ][0], [])
}

output "cert_approver_replicas" {
  description = <<-EOT
    Replica count of the cert-approver Deployment.
  EOT
  value = try([
    for doc in split("---", local.cert_approver_manifest) :
    yamldecode(doc).spec.replicas
    if try(yamldecode(doc).kind, "") == "Deployment"
  ][0], null)
}

output "cert_approver_affinity" {
  description = <<-EOT
    Pod-template affinity of the cert-approver Deployment, or {} when none
    renders. Set only when replicas > 1.
  EOT
  value = try([
    for doc in split("---", local.cert_approver_manifest) :
    yamldecode(doc).spec.template.spec.affinity
    if try(yamldecode(doc).kind, "") == "Deployment"
  ][0], {})
}

output "cert_approver_pod_disruption_budgets" {
  description = <<-EOT
    Every PodDisruptionBudget in the cert-approver seed as
    { api_version, name, namespace, spec }. Empty at replicas = 1.
  EOT
  value = [
    for doc in split("---", local.cert_approver_manifest) :
    {
      api_version = try(yamldecode(doc).apiVersion, "")
      name        = try(yamldecode(doc).metadata.name, "")
      namespace   = try(yamldecode(doc).metadata.namespace, "")
      spec        = try(yamldecode(doc).spec, {})
    }
    if try(yamldecode(doc).kind, "") == "PodDisruptionBudget"
  ]
}

output "cert_approver_env" {
  description = <<-EOT
    Container environment of the cert-approver Deployment as a name => value
    map, or {}.
  EOT
  value = try({
    for e in [
      for doc in split("---", local.cert_approver_manifest) :
      yamldecode(doc).spec.template.spec.containers[0].env
      if try(yamldecode(doc).kind, "") == "Deployment"
    ][0] : e.name => e.value
  }, {})
}

output "controlplane_base_is_prefix_of_final" {
  description = <<-EOT
    True when the final controlplane patch list begins with
    controlplane_base_patches, so the seeds are only appended after the base.
  EOT
  # Declassify only the comparison result, never patch or seed contents.
  value = nonsensitive(slice(
    local.controlplane_machine_config_patches, 0, length(local.controlplane_base_patches)
  ) == local.controlplane_base_patches)
}

output "cilium_self_management_app" {
  description = <<-EOT
    The Cilium ArgoCD Application manifest (YAML) for the consumer to commit,
    or "" when cilium_self_management = false. Never applied by the module.
    With cilium_self_management_values_source set it is multi-source and its
    first valueFiles entry is the cilium_self_management_values output: commit
    that file first or together with this manifest. Its
    talos-platform-base.io/values-digest annotation must equal the digest in
    that file's header.
  EOT
  value       = local.cilium_self_management_app

  precondition {
    condition     = !var.cilium_self_management || local.cilium_self_management_app != ""
    error_message = "cilium_self_management is true but the emitted Application rendered empty — refusing to emit a hollow Cilium Application. Check cilium-values.tf's cilium_self_management_app local."
  }

  precondition {
    # && does not short-circuit here; keep the conditional and try().
    condition = var.cilium_self_management && local.cilium_self_management_multi_source ? (
      startswith(try(local.cilium_self_management_value_files[0], ""), "$values/") &&
      length(try(local.cilium_self_management_value_files[0], "")) > length("$values/")
    ) : true
    error_message = "cilium_self_management_values_source is set but the emitted Application's first valueFiles entry is not a non-empty $values/<path> reference — refusing to emit an Application that would render the chart without the module-set values layer. Check cilium-values.tf's cilium_self_management_value_files local."
  }
}

output "cilium_self_management_values" {
  description = <<-EOT
    The module-set Cilium values (floor and computed) as YAML, to commit at
    cilium_self_management_values_source.values_path; "" on the single-source
    arm. Its header carries the values digest the Application's annotation must
    match. cilium_values_override is not part of it.
  EOT
  value       = local.cilium_self_management_values_file

  precondition {
    condition     = (local.cilium_self_management_values_file != "") == (var.cilium_self_management && local.cilium_self_management_multi_source)
    error_message = "cilium_self_management_values must be non-empty exactly when cilium_self_management is true AND cilium_self_management_values_source is set. Check cilium-values.tf's cilium_self_management_values_file local."
  }
}

output "cilium_values_override_digest" {
  description = <<-EOT
    SHA-256 of cilium_values_override, or "" when it is empty. Shows in the
    plan when the sensitive override changes.
  EOT
  value       = local.cilium_values_override_digest
}

locals {
  # Stays out of cilium-values.tf, which provider-free test fixtures share.
  # Split on "\n---\n": a bare "---" inside a value would break the split.
  cilium_seed_observability_markers = try(
    [
      for doc in split("\n---\n", try(terraform_data.cilium_render[0].output, "")) : {
        agent_metrics          = contains(keys(yamldecode(doc).data), "prometheus-serve-addr")
        agent_metric_overrides = contains(keys(yamldecode(doc).data), "metrics")
        operator_metrics       = contains(keys(yamldecode(doc).data), "operator-prometheus-serve-addr")
        hubble                 = try(yamldecode(doc).data["enable-hubble"], "false") == "true"
        hubble_metrics         = contains(keys(yamldecode(doc).data), "hubble-metrics-server")
        hubble_open_metrics    = try(yamldecode(doc).data["enable-hubble-open-metrics"], "false") == "true"
      }
      if try(yamldecode(doc).kind, "") == "ConfigMap" && try(yamldecode(doc).metadata.name, "") == "cilium-config"
    ][0],
    {}
  )
}

output "cilium_seed_observability_markers" {
  description = <<-EOT
    Booleans decoded from the cilium-config ConfigMap of the frozen bootstrap
    seed: what was baked in at bootstrap, not what runs now. operator_metrics is
    true regardless of cilium_operator_metrics, because the chart enables
    operator metrics by default. {} when deploy_cilium = false.
  EOT
  # Declassify only boolean markers. Fall back to the raw value if the provider did not mark it sensitive.
  value = try(
    nonsensitive(local.cilium_seed_observability_markers),
    local.cilium_seed_observability_markers,
    {},
  )
}

output "cilium_operator_replicas_effective" {
  description = <<-EOT
    Cilium operator replica count this plan resolves and its source:
    `pin`, `node-count`, `floor`, or `disabled` (count null). On a bootstrapped
    cluster without self-management this is not what runs: the seed is frozen.
  EOT
  # An empty-map conditional coerces count to string; keep a stable object shape.
  value = {
    count = var.deploy_cilium ? (
      local.cilium_operator_replicas != null ? local.cilium_operator_replicas : try(local.cilium_floor_values.operator.replicas, null)
    ) : null
    source = var.deploy_cilium ? (
      var.cilium_operator_replicas != null ? "pin" :
      local.cilium_operator_replicas != null ? "node-count" : "floor"
    ) : "disabled"
  }
}

output "node_apply_mode" {
  description = <<-EOT
    apply_mode each node was last written with, keyed by node name. A role
    at "staged" keeps the previous config until a reboot while the plan stays
    clean.
  EOT
  value       = local.node_apply_mode
}

output "coredns_seeded" {
  description = <<-EOT
    Whether the CoreDNS seed — the built-in disable plus its inlineManifest — is
    in the controlplane machine-config patch list.
  EOT
  value = length(local.coredns_controlplane_patch) > 0 && alltrue([
    for patch in local.coredns_controlplane_patch : contains(local.controlplane_base_patches, patch)
  ])
}

output "coredns_builtin_setting" {
  description = <<-EOT
    The Talos CoreDNS setting the module writes, as { document, enabled }:
    document is "KubeCoreDNSConfig" on a native schema pin and "cluster.coreDNS"
    on an earlier one. null when the module writes none and the Talos built-in
    stays on.
  EOT
  value = try(one(concat(
    [for patch in local.coredns_controlplane_patch : { document = "KubeCoreDNSConfig", enabled = yamldecode(patch).enabled } if try(yamldecode(patch).kind, "") == "KubeCoreDNSConfig"],
    [for patch in local.coredns_controlplane_patch : { document = "cluster.coreDNS", enabled = !yamldecode(patch).cluster.coreDNS.disabled } if can(yamldecode(patch).cluster.coreDNS)],
  )), null)
}

output "coredns_seed_objects" {
  description = <<-EOT
    Objects decoded from the CoreDNS seed manifest inside the controlplane patch,
    in apply order. Empty when coredns_node_separation is false.
  EOT
  value = flatten([
    for patch in local.coredns_controlplane_patch : [
      for doc in split("\n---\n", try(yamldecode(patch).manifest, yamldecode(patch).cluster.inlineManifests[0].contents, "")) : yamldecode(doc)
      if doc != ""
    ]
  ])
}

output "coredns_seed_digest" {
  description = <<-EOT
    sha256 of the CoreDNS seed objects, which the seed's PodDisruptionBudget carries
    as the annotation talos-platform-base.io/seed-digest: a control plane runs this
    seed when its rendered 99-coredns manifest shows the value. null when
    coredns_node_separation is false.
  EOT
  value       = var.coredns_node_separation ? local.coredns_seed_digest : null
}
