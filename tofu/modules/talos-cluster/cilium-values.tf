# Shared values for the bootstrap seed and emitted Application.
# Keep this file provider-free; offline fixtures also need nodes.tf.

locals {
  cilium_pod_v4 = [for c in var.pod_cidr : c if !strcontains(c, ":")]
  cilium_pod_v6 = [for c in var.pod_cidr : c if strcontains(c, ":")]
  cilium_native_v4 = var.cilium_native_routing_cidr != "" ? var.cilium_native_routing_cidr : (
    length(local.cilium_pod_v4) > 0 ? local.cilium_pod_v4[0] : var.pod_cidr[0]
  )

  # merge() is shallow: combine contributors to the same parent in one sub-map.
  cilium_prometheus_values = merge(
    { enabled = true },
    length(var.cilium_agent_metric_overrides) > 0 ? { metrics = var.cilium_agent_metric_overrides } : {},
  )

  # Use two operators on multiple nodes for rollout availability and a warm instance.
  # A single node retains the floor value because operator pods require hostname anti-affinity.
  cilium_operator_replicas = var.cilium_operator_replicas != null ? var.cilium_operator_replicas : (
    length(local.nodes_checked) >= 2 ? 2 : null
  )

  cilium_operator_values = merge(
    local.cilium_operator_replicas != null ? { replicas = local.cilium_operator_replicas } : {},
    var.cilium_operator_metrics ? { prometheus = { enabled = true } } : {},
  )

  # Omit the OpenMetrics key when disabled to avoid changing existing emitted Applications.
  cilium_hubble_metrics_values = merge(
    { enabled = var.cilium_hubble_metrics },
    var.cilium_hubble_open_metrics ? { enableOpenMetrics = true } : {},
  )

  # Reassert joint Talos/Cilium keys in the final valuesObject layer so missing git values
  # cannot disable kube-proxy replacement while Talos has kube-proxy disabled.
  cilium_joint_keys_endpoint = {
    k8sServiceHost = var.cilium_k8s_service_host
    k8sServicePort = var.cilium_k8s_service_port
  }

  cilium_joint_keys = merge(
    { kubeProxyReplacement = var.cilium_kube_proxy_replacement },
    var.cilium_kube_proxy_replacement ? local.cilium_joint_keys_endpoint : {},
  )

  cilium_computed_values = merge(
    {
      routingMode          = var.cilium_routing_mode
      kubeProxyReplacement = var.cilium_kube_proxy_replacement
    },
    var.cilium_kube_proxy_replacement ? local.cilium_joint_keys_endpoint : {},
    var.cilium_routing_mode == "native" ? { ipv4NativeRoutingCIDR = local.cilium_native_v4 } : {},
    (var.cilium_routing_mode == "native" && var.dual_stack && length(local.cilium_pod_v6) > 0) ? { ipv6NativeRoutingCIDR = local.cilium_pod_v6[0] } : {},
    var.dual_stack ? { ipv6 = { enabled = true } } : {},
    var.cilium_mtu > 0 ? { MTU = var.cilium_mtu } : {},
    # gRPC over the Gateway requires h2c appProtocol support.
    var.cilium_gateway_api ? { gatewayAPI = { enabled = true, enableAppProtocol = true } } : {},
    var.cilium_encryption.type == "wireguard" ? { encryption = { enabled = true, type = "wireguard" } } : {},
    var.cilium_encryption.type == "ipsec" ? { encryption = { enabled = true, type = "ipsec" } } : {},
    var.cilium_agent_metrics ? { prometheus = local.cilium_prometheus_values } : {},
    length(local.cilium_operator_values) > 0 ? { operator = local.cilium_operator_values } : {},
    # Metrics-only Hubble needs no observer TLS; disabling it also avoids template-time certificate generation.
    var.cilium_hubble_enabled ? {
      hubble = {
        enabled = true
        metrics = local.cilium_hubble_metrics_values
        tls     = { enabled = false }
      }
    } : {},
  )

  cilium_computed_values_yaml = yamlencode(local.cilium_computed_values)

  cilium_floor_values = yamldecode(file("${path.module}/helm/cilium-values.yaml"))

  # Explicitly merge operator siblings to match Helm semantics and preserve the floor replica count.
  # Any new shared parent needs its own sub-merge and a preservation assertion.
  cilium_effective_values = merge(
    local.cilium_floor_values,
    local.cilium_computed_values,
    {
      operator = merge(
        try(local.cilium_floor_values.operator, {}),
        try(local.cilium_computed_values.operator, {}),
      )
    },
  )

  cilium_self_management_multi_source = var.cilium_self_management_values_source != null

  # Declassify only the presence bit, never override contents.
  cilium_values_override_present = nonsensitive(var.cilium_values_override != "")

  # The digest detects changes but can confirm guessed contents; it is not a secrecy guarantee.
  cilium_values_override_digest = local.cilium_values_override_present ? nonsensitive(sha256(var.cilium_values_override)) : ""

  # Provide non-null attributes; boolean operators do not reliably short-circuit on the supported floor.
  cilium_values_source = coalesce(var.cilium_self_management_values_source, {
    repo_url      = ""
    revision      = ""
    values_path   = ""
    override_path = ""
  })

  # Consumers must compare this digest with the Application annotation; ArgoCD does not.
  cilium_self_management_values_digest = sha256(yamlencode(local.cilium_effective_values))

  cilium_self_management_values_file = var.cilium_self_management && local.cilium_self_management_multi_source ? join("", [
    "# GENERATED by talos-platform-base tofu/modules/talos-cluster — DO NOT EDIT.\n",
    "# Regenerate with: tofu output -raw cilium_self_management_values\n",
    "# Commit it at ${replace(local.cilium_values_source.values_path, "\n", " ")} in ${replace(local.cilium_values_source.repo_url, "\n", " ")}.\n",
    "# It is the FIRST valueFiles entry of the emitted Cilium Application; your own\n",
    "# override document is the second and wins over this file at any depth —\n",
    "# EXCEPT kubeProxyReplacement, k8sServiceHost and k8sServicePort, which the\n",
    "# Application re-asserts in helm.valuesObject as the last layer. Naming one of\n",
    "# those three in your override FILE does not take effect and is not reported:\n",
    "# the module rejects them in cilium_values_override, but it never reads the\n",
    "# file. Set them through cilium_k8s_service_host / cilium_k8s_service_port /\n",
    "# cilium_kube_proxy_replacement, which move the Talos side with them.\n",
    "# cilium chart: ${replace(var.cilium_chart_version, "\n", " ")}\n",
    "# values-digest: ${local.cilium_self_management_values_digest}\n",
    "#   (must equal the emitted Application's talos-platform-base.io/values-digest\n",
    "#   annotation — if it does not, this file is stale, re-run the output above.)\n",
    yamlencode(local.cilium_effective_values),
  ]) : ""

  # Keep module values before consumer overrides; missing files must remain a sync error.
  cilium_self_management_value_files = concat(
    local.cilium_self_management_multi_source ? ["$values/${local.cilium_values_source.values_path}"] : [],
    local.cilium_self_management_multi_source && local.cilium_values_override_present ? ["$values/${local.cilium_values_source.override_path}"] : [],
  )

  cilium_self_management_metadata = merge(
    {
      name      = "cilium"
      namespace = var.argocd_namespace
      labels = {
        "app.kubernetes.io/name"       = "cilium"
        "app.kubernetes.io/instance"   = "cilium"
        "app.kubernetes.io/version"    = var.cilium_chart_version
        "app.kubernetes.io/component"  = "cni"
        "app.kubernetes.io/part-of"    = "talos-platform-base"
        "app.kubernetes.io/managed-by" = "argocd"
      }
    },
    local.cilium_self_management_multi_source ? {
      annotations = {
        "talos-platform-base.io/values-digest" = local.cilium_self_management_values_digest
      }
    } : {},
  )

  cilium_self_management_spec = merge(
    {
      project = var.cilium_self_management_project
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.cilium_namespace
      }
    },
    !local.cilium_self_management_multi_source ? {
      source = {
        repoURL        = var.cilium_chart_repository
        chart          = "cilium"
        targetRevision = var.cilium_chart_version
        helm = {
          valuesObject = local.cilium_effective_values
        }
      }
    } : {},
    # source and sources are mutually exclusive. The first source only resolves $values paths.
    local.cilium_self_management_multi_source ? {
      sources = [
        {
          repoURL        = local.cilium_values_source.repo_url
          targetRevision = local.cilium_values_source.revision
          ref            = "values"
        },
        {
          repoURL        = var.cilium_chart_repository
          chart          = "cilium"
          targetRevision = var.cilium_chart_version
          helm = {
            valueFiles              = local.cilium_self_management_value_files
            ignoreMissingValueFiles = false
            valuesObject            = local.cilium_joint_keys
          }
        },
      ]
    } : {},
  )

  cilium_self_management_app = var.cilium_self_management ? yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = local.cilium_self_management_metadata
    spec       = local.cilium_self_management_spec
  }) : ""
}

# Warn for inert inputs: opaque overrides may satisfy prerequisites.
# Keep independently testable predicates in separate check blocks.

check "cilium_agent_metric_overrides_effective" {
  assert {
    condition     = length(var.cilium_agent_metric_overrides) == 0 || (var.deploy_cilium && var.cilium_agent_metrics)
    error_message = "cilium_agent_metric_overrides is set but cannot take effect: it needs deploy_cilium = true (no seed and no emitted Application otherwise) AND cilium_agent_metrics = true (the chart emits the whole `prometheus` values block only when the agent scrape endpoint is on). The delta list is dropped from both engines as configured."
  }
}

check "cilium_operator_replicas_effective" {
  assert {
    condition     = var.cilium_operator_replicas == null || var.deploy_cilium
    error_message = "cilium_operator_replicas is set but cannot take effect: it needs deploy_cilium = true — with Cilium off the module renders no seed and emits no self-management Application, so there is no operator Deployment for the count to reach. NOTE, separately and NOT detectable from a plan: on an ALREADY-BOOTSTRAPPED cluster with cilium_self_management = false the pin reaches only the frozen seed render, never the running Deployment — it applies at the next fresh bootstrap or after a deliberate -replace of terraform_data.cilium_render (UPGRADING, the operator-replicas section §3)."
  }
}

check "cilium_hubble_open_metrics_effective" {
  # The chart emits OpenMetrics only when the metrics list is non-empty.
  assert {
    condition     = !var.cilium_hubble_open_metrics || (var.deploy_cilium && var.cilium_hubble_enabled && length(var.cilium_hubble_metrics) > 0)
    error_message = "cilium_hubble_open_metrics is true but cannot take effect: it needs deploy_cilium = true, cilium_hubble_enabled = true, AND a non-empty cilium_hubble_metrics — the chart gates the OpenMetrics key on the metrics list being non-empty, so it changes the exposition format of an endpoint that exports nothing. Disregard the Hubble half of this if you enable Hubble through cilium_values_override; the module cannot introspect that string."
  }
}

check "cilium_k8s_service_endpoint_effective" {
  assert {
    condition = (
      var.cilium_k8s_service_host == "localhost" && var.cilium_k8s_service_port == "7445"
      ) || (
      var.deploy_cilium && var.cilium_kube_proxy_replacement
    )
    error_message = "cilium_k8s_service_host / cilium_k8s_service_port are set away from the KubePrism default but cannot take effect: they need deploy_cilium = true AND cilium_kube_proxy_replacement = true. The module emits k8sServiceHost/k8sServicePort only alongside kubeProxyReplacement, because each has a Talos-side half (cluster.proxy.disabled) that moves with it — with the replacement off, Cilium reaches the API server through the in-cluster Service that kube-proxy provides, and the endpoint you set reaches nothing."
  }
}

check "cilium_self_management_values_source_is_inert" {
  assert {
    condition     = var.cilium_self_management_values_source == null || var.cilium_self_management
    error_message = "cilium_self_management_values_source is set but cannot take effect: it needs cilium_self_management = true. With self-management off the module emits no Application and no values file, so the values source reaches nothing."
  }
}

check "cilium_self_management_values_source_on_permissive_project" {
  assert {
    condition     = var.cilium_self_management_values_source == null || !var.cilium_self_management || var.cilium_self_management_project != "default"
    error_message = "cilium_self_management_values_source is set while cilium_self_management_project is \"default\": that AppProject allows every source repo (sourceRepos: ['*']), so nothing but PR review stops a repo_url edit from feeding attacker-chosen Helm values to the privileged cilium DaemonSet. Scope the Application to a dedicated AppProject whose sourceRepos lists exactly cilium_chart_repository and this values repo (README, the Cilium Self-Management section)."
  }
}

check "cilium_values_override_emptied_while_day2_wired" {
  assert {
    condition     = !(var.cilium_self_management && trimspace(try(var.cilium_self_management_values_source.override_path, "")) != "" && !local.cilium_values_override_present)
    error_message = "cilium_values_override is empty while cilium_self_management_values_source is still set: the emitted Application drops its override valueFiles entry, so the next ArgoCD sync reconciles Cilium WITHOUT the Day-2 values the override carried. If that is the intent, this is expected — otherwise restore the override, or unset cilium_self_management_values_source to return to the single-source shape deliberately. See UPGRADING, the Cilium self-management rollback section."
  }
}
