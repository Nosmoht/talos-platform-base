locals {
  # The seed reproduces the Talos built-in for these two inputs; the controlplane
  # postcondition in machine-config.tf rejects a caller patch that changes them.
  coredns_cluster_domain = "cluster.local"
  # Talos k8s.DNSServiceAddrs: the tenth address after each service subnet's base.
  coredns_service_ips  = [for c in var.service_cidr : cidrhost(c, 10)]
  coredns_service_ipv4 = try([for ip in local.coredns_service_ips : ip if !strcontains(ip, ":")][0], "")
  coredns_service_ipv6 = try([for ip in local.coredns_service_ips : ip if strcontains(ip, ":")][0], "")

  # A digest-only reference has no tag; a digest never fits the 63-character label limit.
  coredns_image_tag = try(regex(":([^:/]+)$", split("@", var.coredns_image)[0])[0], "unknown")
  # A label value must begin and end with an alphanumeric character; an image tag need not.
  coredns_version_label = trim(substr(local.coredns_image_tag, 0, 63), "._-")

  coredns_labels = {
    "app.kubernetes.io/name"       = "coredns"
    "app.kubernetes.io/instance"   = "coredns"
    "app.kubernetes.io/version"    = local.coredns_version_label != "" ? local.coredns_version_label : "unknown"
    "app.kubernetes.io/component"  = "cluster-dns"
    "app.kubernetes.io/part-of"    = "talos-platform-base"
    "app.kubernetes.io/managed-by" = "opentofu"
  }
  # kube-dns is the selector Talos' built-in Deployment and Service already use; both
  # are immutable or consumer-visible, so the seed keeps it.
  coredns_selector = { "k8s-app" = "kube-dns" }

  # Kinds, names and namespaces equal the Talos built-ins, so the upgrade-k8s SSA sync
  # updates them in place instead of pruning them and releasing the Service ClusterIP.
  coredns_objects = [
    {
      apiVersion = "v1"
      kind       = "ServiceAccount"
      metadata   = { name = "coredns", namespace = "kube-system", labels = local.coredns_labels }
    },
    {
      apiVersion = "rbac.authorization.k8s.io/v1"
      kind       = "ClusterRole"
      metadata = {
        name   = "system:coredns"
        labels = merge(local.coredns_labels, { "kubernetes.io/bootstrapping" = "rbac-defaults" })
      }
      rules = [
        { apiGroups = [""], resources = ["endpoints", "services", "pods", "namespaces"], verbs = ["list", "watch"] },
        { apiGroups = ["discovery.k8s.io"], resources = ["endpointslices"], verbs = ["list", "watch"] },
      ]
    },
    {
      apiVersion = "rbac.authorization.k8s.io/v1"
      kind       = "ClusterRoleBinding"
      metadata = {
        name        = "system:coredns"
        labels      = merge(local.coredns_labels, { "kubernetes.io/bootstrapping" = "rbac-defaults" })
        annotations = { "rbac.authorization.kubernetes.io/autoupdate" = "true" }
      }
      roleRef  = { apiGroup = "rbac.authorization.k8s.io", kind = "ClusterRole", name = "system:coredns" }
      subjects = [{ kind = "ServiceAccount", name = "coredns", namespace = "kube-system" }]
    },
    {
      apiVersion = "v1"
      kind       = "ConfigMap"
      metadata   = { name = "coredns", namespace = "kube-system", labels = local.coredns_labels }
      data = {
        # Byte-identical to the Talos built-in Corefile, so the cutover leaves it unchanged.
        Corefile = <<-EOT
          .:53 {
              errors
              health {
                  lameduck 5s
              }
              ready
              log . {
                  class error
              }
              prometheus :9153

              kubernetes ${local.coredns_cluster_domain} in-addr.arpa ip6.arpa {
                  pods insecure
                  fallthrough in-addr.arpa ip6.arpa
                  ttl 30
              }
              forward . /etc/resolv.conf {
                 max_concurrent 1000
              }
              cache 30 {
                 disable success ${local.coredns_cluster_domain}
                 disable denial ${local.coredns_cluster_domain}
              }
              loop
              reload
              loadbalance
          }
        EOT
      }
    },
    {
      apiVersion = "apps/v1"
      kind       = "Deployment"
      metadata = {
        name      = "coredns"
        namespace = "kube-system"
        labels    = merge(local.coredns_labels, local.coredns_selector, { "kubernetes.io/name" = "CoreDNS" })
      }
      spec = {
        replicas = var.coredns_replicas
        strategy = { type = "RollingUpdate", rollingUpdate = { maxUnavailable = 1 } }
        selector = { matchLabels = local.coredns_selector }
        template = {
          metadata = { labels = merge(local.coredns_labels, local.coredns_selector) }
          spec = {
            nodeSelector = { "kubernetes.io/os" = "linux" }
            affinity = {
              nodeAffinity = {
                requiredDuringSchedulingIgnoredDuringExecution = {
                  nodeSelectorTerms = [{
                    matchExpressions = [
                      { key = "kubernetes.io/os", operator = "In", values = ["linux"] },
                      { key = "kubernetes.io/arch", operator = "In", values = ["amd64", "arm64"] },
                    ]
                  }]
                }
              }
              podAntiAffinity = {
                # pod-template-hash stays out of labelSelector: the API server rejects a
                # matchLabelKeys key that the selector also names.
                requiredDuringSchedulingIgnoredDuringExecution = [{
                  labelSelector  = { matchLabels = local.coredns_selector }
                  matchLabelKeys = ["pod-template-hash"]
                  topologyKey    = "kubernetes.io/hostname"
                }]
              }
            }
            serviceAccountName = "coredns"
            priorityClassName  = "system-cluster-critical"
            tolerations = [
              { key = "node-role.kubernetes.io/control-plane", operator = "Exists", effect = "NoSchedule" },
              { key = "node.cloudprovider.kubernetes.io/uninitialized", operator = "Exists", effect = "NoSchedule" },
            ]
            containers = [{
              name            = "coredns"
              image           = var.coredns_image
              imagePullPolicy = "IfNotPresent"
              resources = {
                limits   = { memory = "170Mi" }
                requests = { cpu = "100m", memory = "70Mi" }
              }
              env          = [{ name = "GOMEMLIMIT", value = "161MiB" }]
              args         = ["-conf", "/etc/coredns/Corefile"]
              volumeMounts = [{ name = "config-volume", mountPath = "/etc/coredns", readOnly = true }]
              ports = [
                { name = "dns", protocol = "UDP", containerPort = 53 },
                { name = "dns-tcp", protocol = "TCP", containerPort = 53 },
                { name = "metrics", protocol = "TCP", containerPort = 9153 },
              ]
              livenessProbe = {
                httpGet             = { path = "/health", port = 8080, scheme = "HTTP" }
                initialDelaySeconds = 60
                timeoutSeconds      = 5
                successThreshold    = 1
                failureThreshold    = 5
              }
              readinessProbe = { httpGet = { path = "/ready", port = 8181, scheme = "HTTP" } }
              securityContext = {
                allowPrivilegeEscalation = false
                capabilities             = { add = ["NET_BIND_SERVICE"], drop = ["ALL"] }
                readOnlyRootFilesystem   = true
              }
            }]
            dnsPolicy = "Default"
            volumes = [{
              name      = "config-volume"
              configMap = { name = "coredns", items = [{ key = "Corefile", path = "Corefile" }] }
            }]
          }
        }
      }
    },
    {
      apiVersion = "v1"
      kind       = "Service"
      metadata = {
        name        = "kube-dns"
        namespace   = "kube-system"
        labels      = merge(local.coredns_labels, local.coredns_selector, { "kubernetes.io/cluster-service" = "true", "kubernetes.io/name" = "CoreDNS" })
        annotations = { "prometheus.io/scrape" = "true", "prometheus.io/port" = "9153" }
      }
      spec = {
        selector       = local.coredns_selector
        clusterIP      = local.coredns_service_ipv4 != "" ? local.coredns_service_ipv4 : local.coredns_service_ipv6
        clusterIPs     = compact([local.coredns_service_ipv4, local.coredns_service_ipv6])
        ipFamilies     = compact([local.coredns_service_ipv4 != "" ? "IPv4" : "", local.coredns_service_ipv6 != "" ? "IPv6" : ""])
        ipFamilyPolicy = local.coredns_service_ipv4 != "" && local.coredns_service_ipv6 != "" ? "RequireDualStack" : "SingleStack"
        ports = [
          { name = "dns", port = 53, protocol = "UDP", targetPort = 53 },
          { name = "dns-tcp", port = 53, protocol = "TCP", targetPort = 53 },
          { name = "metrics", port = 9153, protocol = "TCP", targetPort = 9153 },
        ]
      }
    },
  ]

  coredns_pdb = {
    apiVersion = "policy/v1"
    kind       = "PodDisruptionBudget"
    # Not "coredns": machined adopts an existing object of the same identity into its
    # inventory, so a consumer-owned PDB of that name would be overwritten and pruned.
    metadata = { name = "coredns-node-separation", namespace = "kube-system", labels = local.coredns_labels }
    spec = {
      maxUnavailable             = 1
      selector                   = { matchLabels = local.coredns_selector }
      unhealthyPodEvictionPolicy = "AlwaysAllow"
    }
  }

  # Covers every seed object; the budget carries it, so the 99-coredns manifest a node
  # renders shows which seed content that node runs.
  coredns_seed_digest = sha256(join("---\n", [for o in concat(local.coredns_objects, [local.coredns_pdb]) : yamlencode(o)]))

  coredns_manifest = join("---\n", [for o in concat(local.coredns_objects, [merge(local.coredns_pdb, {
    metadata = merge(local.coredns_pdb.metadata, { annotations = { "talos-platform-base.io/seed-digest" = local.coredns_seed_digest } })
  })]) : yamlencode(o)])

  coredns_builtin_disable_patch = var.coredns_node_separation ? [
    local.native_config_documents
    ? yamlencode({ apiVersion = "v1alpha1", kind = "KubeCoreDNSConfig", enabled = false })
    : yamlencode({ cluster = { coreDNS = { disabled = true } } })
  ] : []

  coredns_controlplane_patch = concat(local.coredns_builtin_disable_patch, var.coredns_node_separation ? [
    local.native_config_documents ? yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeInlineManifestConfig"
      name       = "coredns"
      manifest   = local.coredns_manifest
    }) : yamlencode({ cluster = { inlineManifests = [{ name = "coredns", contents = local.coredns_manifest }] } })
  ] : [])

  # One predicate for every place the seed's inputs can be overridden: both rendered
  # role configurations and each node's own patches, which merge only at apply.
  coredns_guarded_texts = var.coredns_node_separation ? merge(
    {
      controlplane = data.talos_machine_configuration.controlplane.machine_configuration
      worker       = data.talos_machine_configuration.worker.machine_configuration
    },
    { for h, n in local.nodes_checked : "node ${h}" => join("\n---\n", n.config_patches) },
  ) : {}

  # Splits on every YAML separator line, including one with trailing blanks or a comment
  # and CRLF line ends; drops pieces holding only blanks and comments, which do not decode.
  coredns_guarded_documents = {
    for source, text in local.coredns_guarded_texts : source => [
      for piece in split("\u001e", replace(replace(text, "\r\n", "\n"), "/(?m)^---[ \\t]*(#.*)?$/", "\u001e")) : piece
      if trimspace(replace(piece, "/(?m)^[ \\t]*#.*$/", "")) != ""
    ]
  }

  # JSON6902 patches address v1alpha1 paths only, and the predicate cannot evaluate
  # them, so it rejects any whose path or from names a guarded field or one of its parents.
  coredns_guarded_json_parents  = ["", "/cluster", "/cluster/network"]
  coredns_guarded_json_prefixes = ["/cluster/network/dnsDomain", "/cluster/network/serviceSubnets", "/cluster/coreDNS", "/cluster/inlineManifests"]

  coredns_service_cidr_sorted = jsonencode(sort(var.service_cidr))

  # Each finding names a field that differs from what the seed renders, a $patch that
  # deletes it or a parent, a node patch that replaces the seed, or a document the
  # predicate cannot read, which fails rather than passes. A rendered role configuration
  # must state serviceSubnets. The seed cannot follow node patches the way the disable
  # does: the legacy cluster.inlineManifests list appends, and Talos rejects a second
  # "coredns" entry.
  coredns_guard_findings = {
    for source, documents in local.coredns_guarded_documents : source => concat(flatten([
      for index, document in documents : [
        for finding in(!can(yamldecode(document)) ? ["it does not decode as YAML"] : flatten([
          for d in [yamldecode(document)] : d == null ? [] : can(concat(d, [])) ? [
            for op in d : "a JSON6902 operation on ${try(jsonencode(op.path), "no readable path")}${try(" from ${jsonencode(op.from)}", "")}"
            if try(
              contains(local.coredns_guarded_json_parents, op.path) ||
              anytrue([for prefix in local.coredns_guarded_json_prefixes : startswith(op.path, prefix)]),
              true,
              ) || try(
              contains(local.coredns_guarded_json_parents, op.from) ||
              anytrue([for prefix in local.coredns_guarded_json_prefixes : startswith(op.from, prefix)]),
              false,
            )
            ] : !can(keys(d)) ? ["it is neither a mapping nor a JSON6902 patch"] : contains(keys(d), "kind") ? (
            !can(tostring(d.kind)) ? ["its kind is not a string"] : d.kind == "KubeNetworkConfig" ? concat(
              contains(keys(d), "$patch") ? ["KubeNetworkConfig $patch"] : [],
              lookup(d, "dnsDomain", null) == null || try(tostring(d.dnsDomain) == local.coredns_cluster_domain, false) ? [] : ["KubeNetworkConfig dnsDomain"],
              lookup(d, "serviceSubnets", null) == null ? (startswith(source, "node ") ? [] : ["KubeNetworkConfig states no serviceSubnets"]) : try(jsonencode(sort(d.serviceSubnets)) == local.coredns_service_cidr_sorted, false) ? [] : ["KubeNetworkConfig serviceSubnets"],
              ) : d.kind == "KubeCoreDNSConfig" ? (
              lookup(d, "image", null) == null || try(contains(["", var.coredns_image], tostring(d.image)), false) ? [] : ["KubeCoreDNSConfig image"]
            ) : d.kind == "KubeInlineManifestConfig" && startswith(source, "node ") && try(tostring(d.name), "") == "coredns" ? ["KubeInlineManifestConfig coredns"] : []
            ) : concat(contains(keys(d), "$patch") ? ["v1alpha1 $patch"] : [], flatten([
              for c in [lookup(d, "cluster", null)] : c == null ? [] : !can(keys(c)) ? ["cluster is not a mapping"] : concat(
                contains(keys(c), "$patch") ? ["cluster $patch"] : [],
                flatten([
                  for n in [lookup(c, "network", null)] : n == null ? [] : !can(keys(n)) ? ["cluster.network is not a mapping"] : concat(
                    contains(keys(n), "$patch") ? ["cluster.network $patch"] : [],
                    lookup(n, "dnsDomain", null) == null || try(tostring(n.dnsDomain) == local.coredns_cluster_domain, false) ? [] : ["cluster.network.dnsDomain"],
                    lookup(n, "serviceSubnets", null) == null || try(jsonencode(sort(n.serviceSubnets)) == local.coredns_service_cidr_sorted, false) ? [] : ["cluster.network.serviceSubnets"],
                  )
                ]),
                flatten([
                  for k in [lookup(c, "coreDNS", null)] : k == null ? [] : !can(keys(k)) ? ["cluster.coreDNS is not a mapping"] : (
                    lookup(k, "image", null) == null || try(contains(["", var.coredns_image], tostring(k.image)), false) ? [] : ["cluster.coreDNS.image"]
                  )
                ]),
                flatten([
                  for m in [startswith(source, "node ") ? lookup(c, "inlineManifests", null) : null] : m == null ? [] : !can(concat(m, [])) ? ["cluster.inlineManifests is not a list"] : [
                    for e in m : !can(keys(e)) ? "cluster.inlineManifests entry is not a mapping" : contains(keys(e), "$patch") ? "cluster.inlineManifests $patch" : "cluster.inlineManifests coredns"
                    if !can(keys(e)) || try(contains(keys(e), "$patch"), false) || try(tostring(e.name) == "coredns", false)
                  ]
                ]),
              )
          ]))
        ])) : "document ${index + 1}: ${finding}"
      ]
      ]), startswith(source, "node ") || anytrue([
      for document in documents : try(yamldecode(document).kind == "KubeNetworkConfig" && yamldecode(document).serviceSubnets != null, false) || try(yamldecode(document).cluster.network.serviceSubnets != null, false)
    ]) ? [] : ["states no serviceSubnets"])
  }

  coredns_guard_violations = nonsensitive(sort(flatten([
    for source, findings in local.coredns_guard_findings : [for finding in findings : "${source} ${finding}"]
  ])))
}
