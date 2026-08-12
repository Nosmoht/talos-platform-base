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
  description = "IPs of the controlplane nodes (talosconfig endpoints), ordered by node name — not by declaration order."
  value       = local.controlplane_ips
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
    Labels seeded onto the module-delivered kubelet-csr-approver
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
    the signer scope, drops resourceNames, OR adds a SECOND unscoped approve rule
    changes this list and fails the test. A rule granting `approve` with NO
    resourceNames (= all signers in RBAC) maps to the literal "<UNSCOPED>" so it
    can never flatten away invisibly. Scans EVERY doc (not only ClusterRole), so an
    approve grant smuggled into another kind is still caught. Secret-free.
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
    Per-object gaps in the six required app.kubernetes.io/* recommended labels
    (AGENTS.md Hard Constraint) across every object in the vendored cert-approver
    seed manifest. MUST be empty. The seed ships as a Talos inlineManifest, OUTSIDE
    the kustomize render / conftest label gate, so this output binds the
    all-resources label invariant to the seed at test time: dropping a label on a
    re-vendor makes this list non-empty and fails the composition test. Secret-free.
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
    The decoded ClusterRole rule set of the rendered cert-approver seed (the raw
    rule objects, for inspection). The ClusterRole is INVARIANT — always the three
    cluster-scoped rules (certificatesigningrequests read, .../approval update,
    signers approve scoped to kubernetes.io/kubelet-serving) regardless of replicas.
    The RBAC-CLOSURE binding at test time is cert_approver_clusterrole_signature
    (apiGroups+resources+verbs+resourceNames) plus cert_approver_clusterrolebinding_targets;
    this output is the un-normalized companion. The leader-election leases/events
    grant is NOT here — it is a namespaced Role (cert_approver_leaderelection_role_rules).
    Secret-free.
  EOT
  value = flatten([
    for doc in split("---", local.cert_approver_manifest) :
    try(yamldecode(doc).rules, [])
    if try(yamldecode(doc).kind, "") == "ClusterRole"
  ])
}

output "cert_approver_clusterrole_signature" {
  description = <<-EOT
    Full normalized signature of every cluster-scoped ClusterRole rule —
    apiGroups + resources + VERBS + resourceNames, each sorted, one string per
    rule, the list sorted. Binds the WHOLE cluster-wide RBAC surface (not just
    count + resources): a re-vendor adding a verb (e.g. `sign` on signers →
    cert issuance), widening apiGroups, or dropping the signer resourceNames
    changes a signature and fails the composition test. Secret-free.
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
    Every ClusterRoleBinding in the seed as {role = roleRef.name, subjects =
    ["<kind>/<namespace>/<name>", …]}. Binds the cluster-scoped binding surface:
    a re-vendor adding a SECOND ClusterRoleBinding (e.g. the approver SA →
    cluster-admin) or repointing roleRef changes this list and fails the test —
    the closure the rule-signature alone cannot see. Secret-free.
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
    The decoded namespaced Role rule set for leader-election (coordination.k8s.io/
    leases + events, in the approver's own namespace). EMPTY at the default
    replicas:1 (no Role rendered — least privilege) and populated only when
    replicas > 1. Binds the HA conditional AND the least-privilege default: the
    composition test asserts it is empty at replicas:1 and carries leases at
    replicas:2. Secret-free.
  EOT
  value = flatten([
    for doc in split("---", local.cert_approver_manifest) :
    try(yamldecode(doc).rules, [])
    if try(yamldecode(doc).kind, "") == "Role"
  ])
}

output "cert_approver_pod_security_context" {
  description = <<-EOT
    The decoded container securityContext of the rendered cert-approver Deployment
    — binds the restricted-PSA hardening (runAsNonRoot, drop ALL,
    readOnlyRootFilesystem, RuntimeDefault seccomp) at test time so a re-vendor
    that drops a field fails the composition test rather than only being caught by
    live PSA admission (which base CI never runs). Secret-free.
  EOT
  value = try([
    for doc in split("---", local.cert_approver_manifest) :
    yamldecode(doc).spec.template.spec.containers[0].securityContext
    if try(yamldecode(doc).kind, "") == "Deployment"
  ][0], {})
}

output "cert_approver_container_args" {
  description = <<-EOT
    The decoded container args of the rendered cert-approver Deployment. Binds the
    HA conditional: `-leader-election` appears ONLY when replicas > 1. Secret-free.
  EOT
  value = try([
    for doc in split("---", local.cert_approver_manifest) :
    yamldecode(doc).spec.template.spec.containers[0].args
    if try(yamldecode(doc).kind, "") == "Deployment"
  ][0], [])
}

output "cert_approver_replicas" {
  description = <<-EOT
    The decoded replica count of the rendered cert-approver Deployment — binds the
    consumer-settable replicas knob (default 1). Secret-free.
  EOT
  value = try([
    for doc in split("---", local.cert_approver_manifest) :
    yamldecode(doc).spec.replicas
    if try(yamldecode(doc).kind, "") == "Deployment"
  ][0], null)
}

output "cert_approver_env" {
  description = <<-EOT
    The decoded container environment of the rendered cert-approver Deployment as a
    name→value map (PROVIDER_REGEX, PROVIDER_IP_PREFIXES, BYPASS_DNS_RESOLUTION).
    Red-green binding for the per-cluster config injection: reverting the
    templatefile wiring flips these. Secret-free (config, not keys).
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

output "cilium_self_management_app" {
  description = <<-EOT
    The opt-in emitted Cilium ArgoCD Application manifest (YAML string) — the
    sole self-management deliverable a consumer commits into their own
    app-of-apps repo. "" when cilium_self_management = false (default). NEVER
    applied by the module (AGENTS.md §Hard Constraints — no kubectl apply of
    ArgoCD-managed resources); the consumer's own GitOps is the single writer.
    See knowledge/decisions/0022-cilium-observability-and-argocd-self-management.md.
  EOT
  value       = local.cilium_self_management_app

  precondition {
    # Empty-render guard: the floor is always merged into cilium_effective_values,
    # so valuesObject cannot legitimately be empty when the toggle is on. Belt-
    # and-suspenders against a future refactor dropping the floor merge (a
    # regression the offline test's floor-preservation asserts already fail on).
    condition     = !var.cilium_self_management || local.cilium_self_management_app != ""
    error_message = "cilium_self_management is true but the emitted Application rendered empty — refusing to emit a hollow Cilium Application. Check cilium-values.tf's cilium_self_management_app local."
  }
}

output "cilium_seed_observability_markers" {
  description = <<-EOT
    Booleans decoded from the FROZEN bootstrap seed render
    (terraform_data.cilium_render[0].output — NOT a second data.helm_template.cilium
    read), filtered by kind=="ConfigMap" && metadata.name=="cilium-config". Marker
    keys verified against the pinned chart (1.20.0) cilium-configmap.yaml template:
    `agent_metrics` <- presence of "prometheus-serve-addr" (gated by
    `{{- if .Values.prometheus.enabled }}`); `hubble` <- the "enable-hubble" value
    (unconditionally rendered, reflects hubble.enabled directly); `hubble_metrics`
    <- presence of "hubble-metrics-server" (gated by
    `{{- if or .Values.hubble.metrics.enabled .Values.hubble.metrics.dynamic.enabled }}`,
    itself nested under the outer `{{- if .Values.hubble.enabled }}` block).
    `operator_metrics` <- presence of "operator-prometheus-serve-addr" — CAVEAT
    (verified by rendering the pinned chart): the upstream chart's OWN default for
    `operator.prometheus.enabled` is `true` (values.yaml), and neither the floor
    nor this module's computed layer ever sets it false, so this key is present in
    the rendered ConfigMap REGARDLESS of var.cilium_operator_metrics — it does NOT
    discriminate the toggle at the render layer (a pre-existing chart-default fact,
    not introduced by this change). The offline `cilium_effective_values.operator.
    prometheus.enabled` assertion (tests/input-validation.tftest.hcl) is what
    genuinely red-green-binds the operator-metrics leg of AC #1; this field is
    audit-only for that leg. {} when deploy_cilium = false or the name-filtered
    ConfigMap list is empty (try()-wrapped, mirroring the cert_approver_env
    precedent). Secret-free (booleans + one raw string value only).
  EOT
  value = try(
    [
      for doc in split("---", try(terraform_data.cilium_render[0].output, "")) : {
        agent_metrics    = contains(keys(yamldecode(doc).data), "prometheus-serve-addr")
        operator_metrics = contains(keys(yamldecode(doc).data), "operator-prometheus-serve-addr")
        hubble           = try(yamldecode(doc).data["enable-hubble"], "false") == "true"
        hubble_metrics   = contains(keys(yamldecode(doc).data), "hubble-metrics-server")
      }
      if try(yamldecode(doc).kind, "") == "ConfigMap" && try(yamldecode(doc).metadata.name, "") == "cilium-config"
    ][0],
    {}
  )
}
