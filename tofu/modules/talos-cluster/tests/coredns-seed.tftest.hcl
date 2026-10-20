# The CoreDNS seed replaces the Talos built-in under the built-in's object identities.
# Providers are mocked; the seed manifest and the patch lists are real.
mock_provider "talos" {
  # A rendered configuration the CoreDNS guard can read; the mock's random string is not one.
  mock_data "talos_machine_configuration" {
    defaults = {
      machine_configuration = "version: v1alpha1\ncluster:\n  network:\n    serviceSubnets:\n      - 10.96.0.0/12\n"
    }
  }
  mock_data "talos_image_factory_urls" {
    defaults = {
      urls = {
        disk_image            = ""
        disk_image_secureboot = ""
        initramfs             = ""
        installer_secureboot  = ""
        iso                   = ""
        iso_secureboot        = ""
        kernel                = ""
        kernel_command_line   = ""
        pxe                   = ""
        uki                   = ""
        installer             = "factory.talos.dev/metal-installer/test-schematic:v1.14.4"
      }
    }
  }
}
mock_provider "helm" {}
mock_provider "local" {}
mock_provider "null" {}

variables {
  cluster_name       = "coredns-seed-test"
  cluster_endpoint   = "https://192.0.2.1:6443"
  talos_version      = "v1.14.4"
  kubernetes_version = "v1.37.1"
  deploy_argocd      = false
  deploy_cilium      = false
  images             = { intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [] } }
  nodes = {
    cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
    worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
    worker-2 = { ip = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = [] }
  }
}

run "default_keeps_the_talos_builtin" {
  command = apply
  assert {
    condition     = !output.coredns_seeded && output.coredns_builtin_setting == null && output.coredns_seed_objects == [] && output.coredns_seed_digest == null
    error_message = "coredns_node_separation defaults to false: the module must write no CoreDNS setting and no seed; got seeded=${output.coredns_seeded}, setting=${jsonencode(output.coredns_builtin_setting)}"
  }
}

run "native_seed_disables_the_builtin_under_its_identities" {
  command = apply
  variables {
    coredns_node_separation = true
  }
  assert {
    condition     = output.coredns_seeded
    error_message = "The CoreDNS seed patches must be in the controlplane base patch list."
  }
  assert {
    condition     = output.coredns_builtin_setting == { document = "KubeCoreDNSConfig", enabled = false }
    error_message = "A native schema pin must disable the built-in with KubeCoreDNSConfig enabled: false; got ${jsonencode(output.coredns_builtin_setting)}"
  }
  # Any identity outside the built-in set would leave a built-in object for the upgrade-k8s prune.
  assert {
    condition = [for o in output.coredns_seed_objects : "${o.kind}/${try(o.metadata.namespace, "")}/${o.metadata.name}"] == [
      "ServiceAccount/kube-system/coredns",
      "ClusterRole//system:coredns",
      "ClusterRoleBinding//system:coredns",
      "ConfigMap/kube-system/coredns",
      "Deployment/kube-system/coredns",
      "Service/kube-system/kube-dns",
      "PodDisruptionBudget/kube-system/coredns-node-separation",
    ]
    error_message = "The seed must carry exactly the Talos built-in CoreDNS identities plus the PodDisruptionBudget; got ${jsonencode([for o in output.coredns_seed_objects : "${o.kind}/${try(o.metadata.namespace, "")}/${o.metadata.name}"])}"
  }
  assert {
    condition = one([for o in output.coredns_seed_objects : o.spec.template.spec.affinity.podAntiAffinity if o.kind == "Deployment"]) == {
      requiredDuringSchedulingIgnoredDuringExecution = [{
        labelSelector  = { matchLabels = { "k8s-app" = "kube-dns" } }
        matchLabelKeys = ["pod-template-hash"]
        topologyKey    = "kubernetes.io/hostname"
      }]
    }
    error_message = "The CoreDNS Deployment must carry exactly one required hostname anti-affinity term selecting k8s-app=kube-dns with matchLabelKeys [pod-template-hash], and no preferred term; got ${jsonencode([for o in output.coredns_seed_objects : o.spec.template.spec.affinity if o.kind == "Deployment"])}"
  }
  assert {
    condition = alltrue([for o in output.coredns_seed_objects : (
      o.spec.replicas == 2 &&
      o.spec.selector == { matchLabels = { "k8s-app" = "kube-dns" } } &&
      o.spec.template.metadata.labels["k8s-app"] == "kube-dns"
    ) if o.kind == "Deployment"])
    error_message = "The Deployment must default to 2 replicas and keep the built-in's immutable selector k8s-app=kube-dns on its pods."
  }
  assert {
    condition = one([for o in output.coredns_seed_objects : o.spec if o.kind == "PodDisruptionBudget"]) == {
      maxUnavailable             = 1
      selector                   = { matchLabels = { "k8s-app" = "kube-dns" } }
      unhealthyPodEvictionPolicy = "AlwaysAllow"
    }
    error_message = "The PodDisruptionBudget must allow one disruption of k8s-app=kube-dns with unhealthyPodEvictionPolicy AlwaysAllow; got ${jsonencode([for o in output.coredns_seed_objects : o.spec if o.kind == "PodDisruptionBudget"])}"
  }
  assert {
    condition = one([for o in output.coredns_seed_objects : {
      clusterIP      = o.spec.clusterIP
      clusterIPs     = o.spec.clusterIPs
      ipFamilies     = o.spec.ipFamilies
      ipFamilyPolicy = o.spec.ipFamilyPolicy
      selector       = o.spec.selector
      } if o.kind == "Service"]) == {
      clusterIP      = "10.96.0.10"
      clusterIPs     = ["10.96.0.10"]
      ipFamilies     = ["IPv4"]
      ipFamilyPolicy = "SingleStack"
      selector       = { "k8s-app" = "kube-dns" }
    }
    error_message = "The kube-dns Service must keep the built-in ClusterIP (tenth address of the default service CIDR) and selector; got ${jsonencode([for o in output.coredns_seed_objects : o.spec if o.kind == "Service"])}"
  }
  # Oracle: the upstream golden file, siderolabs/talos v1.14.4
  # `internal/app/machined/pkg/controllers/k8s/internal/k8stemplates/testdata/coredns-configmap-cluster-domain.yaml`.
  assert {
    condition     = one([for o in output.coredns_seed_objects : o.data.Corefile if o.kind == "ConfigMap"]) == ".:53 {\n    errors\n    health {\n        lameduck 5s\n    }\n    ready\n    log . {\n        class error\n    }\n    prometheus :9153\n\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n        pods insecure\n        fallthrough in-addr.arpa ip6.arpa\n        ttl 30\n    }\n    forward . /etc/resolv.conf {\n       max_concurrent 1000\n    }\n    cache 30 {\n       disable success cluster.local\n       disable denial cluster.local\n    }\n    loop\n    reload\n    loadbalance\n}\n"
    error_message = "The Corefile must equal the Talos built-in Corefile byte for byte; got ${jsonencode([for o in output.coredns_seed_objects : o.data if o.kind == "ConfigMap"])}"
  }
  # Oracle for the parity assertions below: siderolabs/talos v1.14.4
  # `internal/app/machined/pkg/controllers/k8s/internal/k8stemplates/coredns.go`
  # and its golden files `testdata/coredns-deployment.yaml`, `coredns-service-ipv4.yaml`
  # and `coredns-cluster-role.yaml`.
  assert {
    condition = jsonencode(one([for o in output.coredns_seed_objects : o.spec.ports if o.kind == "Service"])) == jsonencode([
      { name = "dns", port = 53, protocol = "UDP", targetPort = 53 },
      { name = "dns-tcp", port = 53, protocol = "TCP", targetPort = 53 },
      { name = "metrics", port = 9153, protocol = "TCP", targetPort = 9153 },
    ])
    error_message = "The kube-dns Service ports must equal the Talos built-in's."
  }
  assert {
    condition = jsonencode(one([for o in output.coredns_seed_objects : o.rules if o.kind == "ClusterRole"])) == jsonencode([
      { apiGroups = [""], resources = ["endpoints", "services", "pods", "namespaces"], verbs = ["list", "watch"] },
      { apiGroups = ["discovery.k8s.io"], resources = ["endpointslices"], verbs = ["list", "watch"] },
    ])
    error_message = "The system:coredns ClusterRole rules must equal the Talos built-in's."
  }
  assert {
    condition = jsonencode(one([for o in output.coredns_seed_objects : {
      strategy          = o.spec.strategy
      nodeSelector      = o.spec.template.spec.nodeSelector
      nodeAffinity      = o.spec.template.spec.affinity.nodeAffinity
      priorityClassName = o.spec.template.spec.priorityClassName
      tolerations       = o.spec.template.spec.tolerations
      dnsPolicy         = o.spec.template.spec.dnsPolicy
      volumes           = o.spec.template.spec.volumes
      serviceAccount    = o.spec.template.spec.serviceAccountName
      } if o.kind == "Deployment"])) == jsonencode({
      strategy     = { rollingUpdate = { maxUnavailable = 1 }, type = "RollingUpdate" }
      nodeSelector = { "kubernetes.io/os" = "linux" }
      nodeAffinity = { requiredDuringSchedulingIgnoredDuringExecution = { nodeSelectorTerms = [{ matchExpressions = [
        { key = "kubernetes.io/os", operator = "In", values = ["linux"] },
        { key = "kubernetes.io/arch", operator = "In", values = ["amd64", "arm64"] },
      ] }] } }
      priorityClassName = "system-cluster-critical"
      tolerations = [
        { effect = "NoSchedule", key = "node-role.kubernetes.io/control-plane", operator = "Exists" },
        { effect = "NoSchedule", key = "node.cloudprovider.kubernetes.io/uninitialized", operator = "Exists" },
      ]
      dnsPolicy      = "Default"
      volumes        = [{ configMap = { items = [{ key = "Corefile", path = "Corefile" }], name = "coredns" }, name = "config-volume" }]
      serviceAccount = "coredns"
    })
    error_message = "The Deployment's pod scheduling, priority, DNS policy and volumes must equal the Talos built-in's."
  }
  assert {
    condition = jsonencode(one([for o in output.coredns_seed_objects : {
      args            = o.spec.template.spec.containers[0].args
      env             = o.spec.template.spec.containers[0].env
      imagePullPolicy = o.spec.template.spec.containers[0].imagePullPolicy
      ports           = o.spec.template.spec.containers[0].ports
      livenessProbe   = o.spec.template.spec.containers[0].livenessProbe
      readinessProbe  = o.spec.template.spec.containers[0].readinessProbe
      resources       = o.spec.template.spec.containers[0].resources
      securityContext = o.spec.template.spec.containers[0].securityContext
      volumeMounts    = o.spec.template.spec.containers[0].volumeMounts
      } if o.kind == "Deployment"])) == jsonencode({
      args            = ["-conf", "/etc/coredns/Corefile"]
      env             = [{ name = "GOMEMLIMIT", value = "161MiB" }]
      imagePullPolicy = "IfNotPresent"
      ports = [
        { containerPort = 53, name = "dns", protocol = "UDP" },
        { containerPort = 53, name = "dns-tcp", protocol = "TCP" },
        { containerPort = 9153, name = "metrics", protocol = "TCP" },
      ]
      livenessProbe   = { failureThreshold = 5, httpGet = { path = "/health", port = 8080, scheme = "HTTP" }, initialDelaySeconds = 60, successThreshold = 1, timeoutSeconds = 5 }
      readinessProbe  = { httpGet = { path = "/ready", port = 8181, scheme = "HTTP" } }
      resources       = { limits = { memory = "170Mi" }, requests = { cpu = "100m", memory = "70Mi" } }
      securityContext = { allowPrivilegeEscalation = false, capabilities = { add = ["NET_BIND_SERVICE"], drop = ["ALL"] }, readOnlyRootFilesystem = true }
      volumeMounts    = [{ mountPath = "/etc/coredns", name = "config-volume", readOnly = true }]
    })
    error_message = "The CoreDNS container's args, environment, ports, probes, resources, securityContext and mounts must equal the Talos built-in's."
  }
  assert {
    condition = flatten([for o in output.coredns_seed_objects : setsubtract(
      ["app.kubernetes.io/name", "app.kubernetes.io/instance", "app.kubernetes.io/version", "app.kubernetes.io/component", "app.kubernetes.io/part-of", "app.kubernetes.io/managed-by"],
      keys(o.metadata.labels),
    )]) == []
    error_message = "AGENTS.md §Hard Constraints: every CoreDNS seed object must carry the six app.kubernetes.io/* recommended labels."
  }
  # The digest is what a node's rendered manifest shows; it must cover every object but itself.
  assert {
    condition = output.coredns_seed_digest == sha256(join("---\n", concat(
      [for o in output.coredns_seed_objects : yamlencode(o) if o.kind != "PodDisruptionBudget"],
      [for o in output.coredns_seed_objects : yamlencode(merge(o, { metadata = { for k, v in o.metadata : k => v if k != "annotations" } })) if o.kind == "PodDisruptionBudget"],
    )))
    error_message = "coredns_seed_digest must be the sha256 of the seed objects without the digest annotation."
  }
  assert {
    condition     = one([for o in output.coredns_seed_objects : o.metadata.annotations if o.kind == "PodDisruptionBudget"]) == { "talos-platform-base.io/seed-digest" = output.coredns_seed_digest }
    error_message = "The PodDisruptionBudget must carry coredns_seed_digest as its only annotation; got ${jsonencode([for o in output.coredns_seed_objects : try(o.metadata.annotations, null) if o.kind == "PodDisruptionBudget"])}"
  }
}

run "the_disable_follows_every_caller_patch" {
  command = apply
  variables {
    coredns_node_separation     = true
    config_patches              = ["apiVersion: v1alpha1\nkind: KubeCoreDNSConfig\nenabled: true\n"]
    controlplane_config_patches = ["apiVersion: v1alpha1\nkind: KubeCoreDNSConfig\nenabled: true\n"]
    nodes = {
      cp = {
        ip             = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = []
        config_patches = ["apiVersion: v1alpha1\nkind: KubeCoreDNSConfig\nenabled: true\n"]
      }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = { ip = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = [] }
    }
  }
  # Talos merges patches in list order, so the last KubeCoreDNSConfig document wins.
  assert {
    condition = [
      for p in data.talos_machine_configuration.controlplane.config_patches : yamldecode(p).enabled
      if try(yamldecode(p).kind, "") == "KubeCoreDNSConfig"
    ] == [true, true, false]
    error_message = "The generation pass must place the built-in disable after both caller patches."
  }
  assert {
    condition = [
      for p in talos_machine_configuration_apply.this["cp"].config_patches : yamldecode(p).enabled
      if try(yamldecode(p).kind, "") == "KubeCoreDNSConfig"
    ] == [true, false]
    error_message = "The apply pass must reassert the built-in disable after the node's own patches."
  }
  assert {
    condition = alltrue([
      for p in talos_machine_configuration_apply.this["worker-1"].config_patches : try(yamldecode(p).kind, "") != "KubeCoreDNSConfig"
    ])
    error_message = "Workers carry no CoreDNS document."
  }
}

run "seed_follows_the_replica_and_image_inputs" {
  command = apply
  variables {
    coredns_node_separation = true
    coredns_replicas        = 3
    coredns_image           = "registry.example.com:5000/mirror/coredns:v1.14.8@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = { ip = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-3 = { ip = "192.0.2.14", role = "worker", image = "intel", hardware_capabilities = [] }
    }
  }
  assert {
    condition = one([for o in output.coredns_seed_objects : [o.spec.replicas, o.spec.template.spec.containers[0].image] if o.kind == "Deployment"]) == [
      3, "registry.example.com:5000/mirror/coredns:v1.14.8@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    ]
    error_message = "The Deployment must carry coredns_replicas and coredns_image."
  }
  assert {
    condition     = jsonencode(distinct([for o in output.coredns_seed_objects : o.metadata.labels["app.kubernetes.io/version"]])) == jsonencode(["v1.14.8"])
    error_message = "The version label must be the tag, not the digest or the registry port; got ${jsonencode(distinct([for o in output.coredns_seed_objects : o.metadata.labels["app.kubernetes.io/version"]]))}"
  }
}

run "a_digest_only_image_gets_a_valid_version_label" {
  command = apply
  variables {
    coredns_node_separation = true
    coredns_image           = "registry.k8s.io/coredns/coredns@sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  }
  assert {
    condition     = jsonencode(distinct([for o in output.coredns_seed_objects : o.metadata.labels["app.kubernetes.io/version"]])) == jsonencode(["unknown"])
    error_message = "A digest-only image must not put the 64-character digest into a label value; got ${jsonencode(distinct([for o in output.coredns_seed_objects : o.metadata.labels["app.kubernetes.io/version"]]))}"
  }
}

run "a_null_image_takes_the_base_pin" {
  command = apply
  variables {
    coredns_node_separation = true
    coredns_image           = null
  }
  assert {
    condition     = one([for o in output.coredns_seed_objects : o.spec.template.spec.containers[0].image if o.kind == "Deployment"]) == "registry.k8s.io/coredns/coredns:v1.14.7"
    error_message = "coredns_image = null must select the module default, as the example passes it when cluster.yaml omits the image."
  }
}

run "legacy_seed_disables_the_builtin" {
  command = apply
  variables {
    talos_version           = "v1.13.10"
    kubernetes_version      = "v1.36.4"
    coredns_node_separation = true
  }
  assert {
    condition     = output.coredns_seeded && output.coredns_builtin_setting == { document = "cluster.coreDNS", enabled = false }
    error_message = "A pre-1.14 schema pin must disable the built-in with cluster.coreDNS.disabled: true; got ${jsonencode(output.coredns_builtin_setting)}"
  }
  # The cluster.inlineManifests form must carry the same objects as the native form.
  assert {
    condition = [for o in output.coredns_seed_objects : "${o.kind}/${try(o.metadata.namespace, "")}/${o.metadata.name}"] == [
      "ServiceAccount/kube-system/coredns",
      "ClusterRole//system:coredns",
      "ClusterRoleBinding//system:coredns",
      "ConfigMap/kube-system/coredns",
      "Deployment/kube-system/coredns",
      "Service/kube-system/kube-dns",
      "PodDisruptionBudget/kube-system/coredns-node-separation",
    ]
    error_message = "The legacy seed must carry exactly the Talos built-in CoreDNS identities plus the PodDisruptionBudget; got ${jsonencode([for o in output.coredns_seed_objects : "${o.kind}/${try(o.metadata.namespace, "")}/${o.metadata.name}"])}"
  }
  assert {
    condition = one([for o in output.coredns_seed_objects : o.spec.template.spec.affinity.podAntiAffinity if o.kind == "Deployment"]) == {
      requiredDuringSchedulingIgnoredDuringExecution = [{
        labelSelector  = { matchLabels = { "k8s-app" = "kube-dns" } }
        matchLabelKeys = ["pod-template-hash"]
        topologyKey    = "kubernetes.io/hostname"
      }]
    }
    error_message = "The legacy seed's Deployment must carry the required hostname anti-affinity term; got ${jsonencode([for o in output.coredns_seed_objects : o.spec.template.spec.affinity if o.kind == "Deployment"])}"
  }
}

run "dual_stack_service_keeps_both_builtin_cluster_ips" {
  command = apply
  variables {
    coredns_node_separation = true
    dual_stack              = true
    pod_cidr                = ["10.244.0.0/16", "2001:db8:10::/56"]
    service_cidr            = ["10.96.0.0/12", "2001:db8:20::/108"]
  }
  override_data {
    target = data.talos_machine_configuration.controlplane
    values = {
      machine_configuration = "version: v1alpha1\n---\napiVersion: v1alpha1\nkind: KubeNetworkConfig\nserviceSubnets:\n  - 10.96.0.0/12\n  - 2001:db8:20::/108\n"
    }
  }
  override_data {
    target = data.talos_machine_configuration.worker
    values = {
      machine_configuration = "version: v1alpha1\n---\napiVersion: v1alpha1\nkind: KubeNetworkConfig\nserviceSubnets:\n  - 10.96.0.0/12\n  - 2001:db8:20::/108\n"
    }
  }
  assert {
    condition = one([for o in output.coredns_seed_objects : [o.spec.clusterIP, o.spec.clusterIPs, o.spec.ipFamilies, o.spec.ipFamilyPolicy] if o.kind == "Service"]) == [
      "10.96.0.10", ["10.96.0.10", "2001:db8:20::a"], ["IPv4", "IPv6"], "RequireDualStack",
    ]
    error_message = "A dual-stack Service must carry the tenth address of each service CIDR, IPv4 first; got ${jsonencode([for o in output.coredns_seed_objects : o.spec if o.kind == "Service"])}"
  }
}

run "ipv6_first_dual_stack_keeps_ipv4_first" {
  command = apply
  variables {
    coredns_node_separation = true
    dual_stack              = true
    pod_cidr                = ["2001:db8:10::/56", "10.244.0.0/16"]
    service_cidr            = ["2001:db8:20::/108", "10.96.0.0/12"]
  }
  # Talos sets clusterIP to the IPv4 address when one exists and lists IPv4 first.
  override_data {
    target = data.talos_machine_configuration.controlplane
    values = {
      machine_configuration = "version: v1alpha1\n---\napiVersion: v1alpha1\nkind: KubeNetworkConfig\nserviceSubnets:\n  - 2001:db8:20::/108\n  - 10.96.0.0/12\n"
    }
  }
  override_data {
    target = data.talos_machine_configuration.worker
    values = {
      machine_configuration = "version: v1alpha1\n---\napiVersion: v1alpha1\nkind: KubeNetworkConfig\nserviceSubnets:\n  - 2001:db8:20::/108\n  - 10.96.0.0/12\n"
    }
  }
  assert {
    condition = one([for o in output.coredns_seed_objects : [o.spec.clusterIP, o.spec.clusterIPs, o.spec.ipFamilies] if o.kind == "Service"]) == [
      "10.96.0.10", ["10.96.0.10", "2001:db8:20::a"], ["IPv4", "IPv6"],
    ]
    error_message = "An IPv6-first service_cidr must still yield the IPv4 ClusterIP first."
  }
}

run "replicas_must_stay_below_the_node_count" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
    }
  }
  expect_failures = [var.coredns_replicas]
}

run "replicas_below_two_are_rejected" {
  command = plan
  variables {
    coredns_replicas = 1
  }
  expect_failures = [var.coredns_replicas]
}

run "image_with_whitespace_is_rejected" {
  command = plan
  variables {
    coredns_image = "registry.k8s.io/coredns/coredns:v1.14.7\nkind: Secret"
  }
  expect_failures = [var.coredns_image]
}

run "caller_dns_domain_patch_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
  }
  override_data {
    target = data.talos_machine_configuration.controlplane
    values = {
      machine_configuration = "version: v1alpha1\n---\napiVersion: v1alpha1\nkind: KubeNetworkConfig\ndnsDomain: example.internal\nserviceSubnets:\n  - 10.96.0.0/12\n"
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["controlplane document 2: KubeNetworkConfig dnsDomain"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "caller_service_subnet_patch_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
  }
  override_data {
    target = data.talos_machine_configuration.controlplane
    values = {
      machine_configuration = "version: v1alpha1\ncluster:\n  network:\n    dnsDomain: cluster.local\n    serviceSubnets:\n      - 198.51.100.0/24\n"
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["controlplane document 1: cluster.network.serviceSubnets"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "default_network_passes_the_seed_guard" {
  command = apply
  variables {
    coredns_node_separation = true
  }
  override_data {
    target = data.talos_machine_configuration.controlplane
    values = {
      machine_configuration = "version: v1alpha1\n---\napiVersion: v1alpha1\nkind: KubeNetworkConfig\ndnsDomain: cluster.local\nserviceSubnets:\n  - 10.96.0.0/12\n"
    }
  }
  assert {
    condition     = output.coredns_seeded
    error_message = "The default DNS domain and service CIDR must pass the CoreDNS seed guard."
  }
}

run "caller_native_service_subnet_patch_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
  }
  override_data {
    target = data.talos_machine_configuration.controlplane
    values = {
      machine_configuration = "version: v1alpha1\n---\napiVersion: v1alpha1\nkind: KubeNetworkConfig\ndnsDomain: cluster.local\nserviceSubnets:\n  - 198.51.100.0/24\n"
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["controlplane document 2: KubeNetworkConfig serviceSubnets"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "caller_legacy_dns_domain_patch_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
  }
  override_data {
    target = data.talos_machine_configuration.controlplane
    values = {
      machine_configuration = "version: v1alpha1\ncluster:\n  network:\n    dnsDomain: example.internal\n    serviceSubnets:\n      - 10.96.0.0/12\n"
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["controlplane document 1: cluster.network.dnsDomain"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "caller_coredns_image_patch_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
  }
  override_data {
    target = data.talos_machine_configuration.controlplane
    values = {
      machine_configuration = "version: v1alpha1\ncluster:\n  network:\n    serviceSubnets:\n      - 10.96.0.0/12\n---\napiVersion: v1alpha1\nkind: KubeCoreDNSConfig\nenabled: false\nimage: mirror.example.com/coredns/coredns:v1.14.7\n"
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["controlplane document 2: KubeCoreDNSConfig image"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "worker_dns_domain_patch_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
  }
  override_data {
    target = data.talos_machine_configuration.worker
    values = {
      machine_configuration = "version: v1alpha1\n---\napiVersion: v1alpha1\nkind: KubeNetworkConfig\ndnsDomain: example.internal\nserviceSubnets:\n  - 10.96.0.0/12\n"
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["worker document 2: KubeNetworkConfig dnsDomain"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "seed_off_ignores_a_custom_network" {
  command = plan
  override_data {
    target = data.talos_machine_configuration.controlplane
    values = {
      machine_configuration = "version: v1alpha1\n---\napiVersion: v1alpha1\nkind: KubeNetworkConfig\ndnsDomain: example.internal\nserviceSubnets:\n  - 198.51.100.0/24\n"
    }
  }
  override_data {
    target = data.talos_machine_configuration.worker
    values = {
      machine_configuration = "version: v1alpha1\n---\napiVersion: v1alpha1\nkind: KubeNetworkConfig\ndnsDomain: example.internal\n"
    }
  }
  assert {
    condition     = !output.coredns_seeded
    error_message = "With the seed off, a custom DNS domain or service subnet must still plan."
  }
}

run "per_node_native_dns_domain_patch_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp = {
        ip             = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = []
        config_patches = ["apiVersion: v1alpha1\nkind: KubeNetworkConfig\ndnsDomain: example.internal\n"]
      }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = { ip = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = [] }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node cp document 1: KubeNetworkConfig dnsDomain"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "per_node_json6902_patch_on_a_guarded_path_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["- op: replace\n  path: /cluster/network/dnsDomain\n  value: example.internal\n"]
      }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-2 document 1: a JSON6902 operation on \"/cluster/network/dnsDomain\""])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "per_node_json6902_patch_elsewhere_passes" {
  command = apply
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["- op: add\n  path: /machine/kubelet/extraArgs\n  value:\n    v: \"2\"\n"]
      }
    }
  }
  assert {
    condition     = output.coredns_seeded
    error_message = "A JSON6902 patch outside the guarded paths must not fail the CoreDNS seed guard."
  }
}

run "per_node_legacy_coredns_image_patch_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["machine:\n  kubelet: {}\n---\ncluster:\n  coreDNS:\n    image: mirror.example.com/coredns/coredns:v1.14.7\n"]
      }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-2 document 2: cluster.coreDNS.image"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "per_node_json6902_patch_on_root_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["- op: replace\n  path: ''\n  value: {}\n"]
      }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-2 document 1: a JSON6902 operation on \"\""])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "per_node_json6902_patch_on_cluster_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["- op: replace\n  path: /cluster\n  value: {}\n"]
      }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-2 document 1: a JSON6902 operation on \"/cluster\""])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "per_node_json6902_patch_on_network_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["- op: replace\n  path: /cluster/network\n  value: {}\n"]
      }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-2 document 1: a JSON6902 operation on \"/cluster/network\""])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "per_node_json6902_patch_on_service_subnets_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["- op: replace\n  path: /cluster/network/serviceSubnets\n  value: {}\n"]
      }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-2 document 1: a JSON6902 operation on \"/cluster/network/serviceSubnets\""])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "per_node_json6902_patch_on_coredns_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["- op: replace\n  path: /cluster/coreDNS\n  value: {}\n"]
      }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-2 document 1: a JSON6902 operation on \"/cluster/coreDNS\""])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "per_node_json6902_operation_without_a_path_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["- op: replace\n  value: {}\n"]
      }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-2 document 1: a JSON6902 operation on no readable path"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

# A document the guard cannot read fails it instead of passing.
run "undecodable_per_node_patch_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["cluster:\n  network: [unclosed\n"]
      }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-2 document 1: it does not decode as YAML"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "scalar_per_node_patch_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["just-a-string\n"]
      }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-2 document 1: it is neither a mapping nor a JSON6902 patch"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "non_mapping_network_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["cluster:\n  network: oops\n"]
      }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-2 document 1: cluster.network is not a mapping"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "non_string_kind_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["kind: [KubeNetworkConfig]\ndnsDomain: example.internal\n"]
      }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-2 document 1: its kind is not a string"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "non_mapping_cluster_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["cluster: oops\n"]
      }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-2 document 1: cluster is not a mapping"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "non_mapping_coredns_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["cluster:\n  coreDNS: oops\n"]
      }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-2 document 1: cluster.coreDNS is not a mapping"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "commented_separator_and_crlf_documents_pass" {
  command = apply
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["machine:\r\n  kubelet: {}\r\n---  # second document\r\nmachine:\r\n  nodeLabels: {}\r\n"]
      }
    }
  }
  assert {
    condition     = output.coredns_seeded
    error_message = "YAML documents split by a commented separator with CRLF line ends must decode and pass the CoreDNS seed guard."
  }
}


run "separator_with_a_comment_still_splits" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["machine:\n  kubelet: {}\n---  # network override\ncluster:\n  network:\n    dnsDomain: example.internal\n"]
      }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-2 document 2: cluster.network.dnsDomain"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "crlf_separator_still_splits" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["machine:\r\n  kubelet: {}\r\n---\r\napiVersion: v1alpha1\r\nkind: KubeNetworkConfig\r\ndnsDomain: example.internal\r\n"]
      }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-2 document 2: KubeNetworkConfig dnsDomain"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "blank_and_comment_only_documents_pass" {
  command = apply
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["---\nmachine:\n  kubelet: {}\n---\n# no settings in this document\n---\n"]
      }
    }
  }
  assert {
    condition     = output.coredns_seeded
    error_message = "Empty and comment-only YAML documents carry no setting and must not fail the CoreDNS seed guard."
  }
}

# Talos picks the first address of each family, so the subnet order does not move the ClusterIP.
run "reordered_dual_stack_service_subnets_pass" {
  command = apply
  variables {
    coredns_node_separation = true
    dual_stack              = true
    pod_cidr                = ["10.244.0.0/16", "2001:db8:10::/56"]
    service_cidr            = ["10.96.0.0/12", "2001:db8:20::/108"]
  }
  override_data {
    target = data.talos_machine_configuration.controlplane
    values = {
      machine_configuration = "version: v1alpha1\n---\napiVersion: v1alpha1\nkind: KubeNetworkConfig\ndnsDomain: cluster.local\nserviceSubnets:\n  - 2001:db8:20::/108\n  - 10.96.0.0/12\n"
    }
  }
  override_data {
    target = data.talos_machine_configuration.worker
    values = {
      machine_configuration = "version: v1alpha1\n---\napiVersion: v1alpha1\nkind: KubeNetworkConfig\nserviceSubnets:\n  - 2001:db8:20::/108\n  - 10.96.0.0/12\n"
    }
  }
  assert {
    condition     = output.coredns_seeded
    error_message = "The service_cidr subnets in another order must pass the CoreDNS seed guard."
  }
}

run "bare_crlf_separator_documents_pass" {
  command = apply
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["machine:\r\n  kubelet: {}\r\n---\r\nmachine:\r\n  nodeLabels: {}\r\n"]
      }
    }
  }
  assert {
    condition     = output.coredns_seeded
    error_message = "YAML documents split by a bare --- separator with CRLF line ends must decode and pass the CoreDNS seed guard."
  }
}

run "per_node_inline_manifest_named_like_the_seed_fails" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp = {
        ip             = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = []
        config_patches = ["apiVersion: v1alpha1\nkind: KubeInlineManifestConfig\nname: coredns\nmanifest: \"\"\n"]
      }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = { ip = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = [] }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node cp document 1: KubeInlineManifestConfig coredns"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "per_node_inline_manifest_with_another_name_passes" {
  command = apply
  variables {
    coredns_node_separation = true
    nodes = {
      cp = {
        ip             = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = []
        config_patches = ["apiVersion: v1alpha1\nkind: KubeInlineManifestConfig\nname: extra\nmanifest: \"\"\n"]
      }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = { ip = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = [] }
    }
  }
  assert {
    condition     = output.coredns_seeded
    error_message = "A per-node inline manifest with another name must not fail the CoreDNS seed guard."
  }
}

run "per_node_legacy_inline_manifest_named_like_the_seed_fails" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp = {
        ip             = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = []
        config_patches = ["cluster:\n  inlineManifests:\n    - name: coredns\n      contents: \"\"\n"]
      }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = { ip = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = [] }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node cp document 1: cluster.inlineManifests coredns"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "per_node_legacy_inline_manifest_delete_fails" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp = {
        ip             = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = []
        config_patches = ["cluster:\n  inlineManifests:\n    - $patch: delete\n      contents: x\n"]
      }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = { ip = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = [] }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node cp document 1: cluster.inlineManifests $patch"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "per_node_legacy_inline_manifests_delete_fails" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp = {
        ip             = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = []
        config_patches = ["cluster:\n  inlineManifests:\n    $patch: delete\n"]
      }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = { ip = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = [] }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node cp document 1: cluster.inlineManifests is not a list"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "per_node_json6902_patch_on_inline_manifests_fails" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp = {
        ip             = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = []
        config_patches = ["- op: remove\n  path: /cluster/inlineManifests/0\n"]
      }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = { ip = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = [] }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node cp document 1: a JSON6902 operation on \"/cluster/inlineManifests/0\""])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "per_node_network_delete_fails" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = {
        ip             = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["cluster:\n  network:\n    $patch: delete\n"]
      }
      worker-2 = { ip = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = [] }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-1 document 1: cluster.network $patch"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "per_node_cluster_delete_fails" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = {
        ip             = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["cluster:\n  $patch: delete\n"]
      }
      worker-2 = { ip = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = [] }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-1 document 1: cluster $patch"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "per_node_v1alpha1_document_delete_fails" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = {
        ip             = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["version: v1alpha1\n$patch: delete\n"]
      }
      worker-2 = { ip = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = [] }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-1 document 1: v1alpha1 $patch"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "per_node_native_network_document_delete_fails" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = {
        ip             = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["apiVersion: v1alpha1\nkind: KubeNetworkConfig\n$patch: delete\n"]
      }
      worker-2 = { ip = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = [] }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-1 document 1: KubeNetworkConfig $patch"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "per_node_network_patch_without_subnets_passes" {
  command = apply
  variables {
    coredns_node_separation = true
    nodes = {
      cp = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = {
        ip             = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["apiVersion: v1alpha1\nkind: KubeNetworkConfig\ndnsDomain: cluster.local\n"]
      }
      worker-2 = { ip = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = [] }
    }
  }
  assert {
    condition     = output.coredns_seeded
    error_message = "A per-node KubeNetworkConfig that keeps the DNS domain and states no serviceSubnets leaves the rendered subnets in place and must pass."
  }
}

run "render_without_service_subnets_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
  }
  override_data {
    target = data.talos_machine_configuration.controlplane
    values = {
      machine_configuration = "version: v1alpha1\n"
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["controlplane states no serviceSubnets"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "render_with_a_subnetless_network_document_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
  }
  override_data {
    target = data.talos_machine_configuration.worker
    values = {
      machine_configuration = "version: v1alpha1\ncluster:\n  network:\n    serviceSubnets:\n      - 10.96.0.0/12\n---\napiVersion: v1alpha1\nkind: KubeNetworkConfig\ndnsDomain: cluster.local\n"
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["worker document 2: KubeNetworkConfig states no serviceSubnets"])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}

run "per_node_json6902_move_from_a_guarded_path_fails_the_seed" {
  command = plan
  variables {
    coredns_node_separation = true
    nodes = {
      cp       = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
      worker-1 = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
      worker-2 = {
        ip             = "192.0.2.13", role = "worker", image = "intel", hardware_capabilities = []
        config_patches = ["- op: move\n  from: /cluster/network/serviceSubnets\n  path: /machine/kubelet/extraConfig/subnets\n"]
      }
    }
  }
  expect_failures = [talos_machine_configuration_apply.this]
  assert {
    condition     = jsonencode(local.coredns_guard_violations) == jsonencode(["node worker-2 document 1: a JSON6902 operation on \"/machine/kubelet/extraConfig/subnets\" from \"/cluster/network/serviceSubnets\""])
    error_message = "The guard must report exactly this finding; got ${jsonencode(local.coredns_guard_violations)}"
  }
}
