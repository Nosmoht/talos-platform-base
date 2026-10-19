# Keep independent validation predicates in separate blocks so expect_failures tests bind each guard.

variable "cluster_name" {
  description = "Name of the Talos cluster (e.g. \"prod\"). Used in PKI CNs and config."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be a lowercase RFC-1123 label (a-z, 0-9, hyphen)."
  }
}

variable "talos_version" {
  description = <<-EOT
    Talos version of the machine-config schema. Fixed at bootstrap: do not
    change it afterwards. For an OS upgrade, change talos_install_version.
  EOT
  type        = string

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+([-+][0-9A-Za-z.-]+)?$", var.talos_version))
    error_message = "talos_version must be a v-prefixed semver (optional pre-release/build suffix), e.g. v1.13.0."
  }
}

variable "talos_install_version" {
  description = <<-EOT
    Talos installer-image tag the nodes run. Empty = talos_version. Change it
    for an OS upgrade; the installer URL and machine.install.image follow.
  EOT
  type        = string
  default     = ""

  validation {
    condition     = var.talos_install_version == "" || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+([-+][0-9A-Za-z.-]+)?$", var.talos_install_version))
    error_message = "talos_install_version must be empty (= falls back to talos_version) or a v-prefixed semver (optional pre-release/build suffix), e.g. v1.13.1."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version to install, e.g. \"v1.36.0\"."
  type        = string

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+([-+][0-9A-Za-z.-]+)?$", var.kubernetes_version))
    error_message = "kubernetes_version must be a v-prefixed semver (optional pre-release/build suffix), e.g. v1.36.0."
  }
}

variable "nodes" {
  description = <<-EOT
    Nodes keyed by node name (Talos hostname and Kubernetes node name). Renaming
    a key is an identity change. Nodes must already be in Talos maintenance mode at
    `ip`. role is controlplane or worker; image must be a key in var.images;
    hardware_capabilities are keys in var.hardware_capabilities. config_patches
    apply to that node only, after the capability patch, so they can override it.
  EOT
  type = map(object({
    ip                    = string
    role                  = string
    image                 = string
    hardware_capabilities = optional(list(string), [])
    config_patches        = optional(list(string), [])
  }))

  validation {
    condition     = length([for h, n in var.nodes : h if n.role == "controlplane"]) >= 1
    error_message = "At least one controlplane node is required."
  }

  validation {
    condition = (
      length([for h, n in var.nodes : h if n.role == "controlplane"]) == 0 ||
      length([for h, n in var.nodes : h if n.role == "controlplane"]) % 2 == 1
    )
    error_message = "The number of controlplane nodes must be ODD (etcd quorum): 1, 3, 5, … An even count tolerates no more failures than the odd count below it."
  }

  validation {
    condition     = alltrue([for h, n in var.nodes : contains(["controlplane", "worker"], n.role)])
    error_message = "Each node.role must be either \"controlplane\" or \"worker\"."
  }

  validation {
    condition = alltrue([for h, n in var.nodes :
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$", h))
      && length(h) <= 253
      && alltrue([for label in split(".", h) : length(label) <= 63])
    ])
    error_message = "Node keys must be canonical Kubernetes node names: lowercase [a-z0-9-.], no leading/trailing '-' or '.', <= 63 chars per label, <= 253 total. Talos does NOT reject uppercase or '_' — it silently rewrites them, so two keys could collapse onto one Kubernetes node."
  }

  validation {
    condition = (
      var.register_with_fqdn ||
      length(distinct([for h, n in var.nodes : split(".", h)[0]])) == length(var.nodes)
    )
    error_message = "The first label of every node key must be unique while register_with_fqdn is false: Talos splits the hostname at the first dot and uses the SHORT hostname as the Kubernetes node name, so two such keys would put two kubelets on one Node object."
  }

  validation {
    condition     = var.register_with_fqdn || alltrue([for h, n in var.nodes : !strcontains(h, ".")])
    error_message = "A dotted node key requires register_with_fqdn = true — otherwise Kubernetes only sees the first label and the domain part is silently dropped."
  }

  validation {
    condition     = length(distinct([for h, n in var.nodes : n.ip])) == length(var.nodes)
    error_message = "node.ip values must be unique."
  }

  validation {
    condition = alltrue([for h, n in var.nodes :
      (can(cidrhost("${n.ip}/32", 0)) && cidrhost("${n.ip}/32", 0) == n.ip) ||
      (can(cidrhost("${n.ip}/128", 0)) && cidrhost("${n.ip}/128", 0) == n.ip)
    ])
    error_message = "Each node.ip must be a single IP address in canonical form (no leading zeros, no IPv4-mapped IPv6, no CIDR suffix, no hostname). Non-canonical spellings of one address compare unequal, so they would defeat the ip-uniqueness check and put two nodes on one machine."
  }
}

variable "register_with_fqdn" {
  description = <<-EOT
    Set machine.kubelet.registerWithFQDN so kubelets register with the FQDN.
    Required for dotted node keys. Applies to all nodes, so it also changes the
    Kubernetes name of short-named nodes.
  EOT
  type        = bool
  default     = false
}

variable "images" {
  description = <<-EOT
    Installer-image profiles, keyed by the id node.image references.
      - architecture: "amd64" | "arm64".
      - cpu_vendor: "intel" | "amd" | "arm"; required, selects vendor-specific
        profile variants such as the IOMMU kernel arg.
      - extensions: Image Factory extensions baked on every node of this image, in
        addition to those of the node's provisioning profiles.
      - overlay: optional SBC overlay, e.g. name = "rpi_generic",
        image = "siderolabs/sbc-raspberrypi".
      - extra_kernel_args: boot kernel args, one per element, merged with the
        profiles' args; a conflicting single-value key fails the plan.
    Always installs the non-SecureBoot metal installer.
  EOT
  type = map(object({
    architecture      = optional(string, "amd64")
    cpu_vendor        = string
    extensions        = optional(list(string), [])
    extra_kernel_args = optional(list(string), [])
    overlay = optional(object({
      name    = string
      image   = string
      options = optional(map(string), null)
    }), null)
  }))

  validation {
    condition     = length(var.images) >= 1
    error_message = "At least one image must be defined (node.image references it)."
  }

  validation {
    condition     = alltrue([for img in var.images : contains(["amd64", "arm64"], img.architecture)])
    error_message = "Each image.architecture must be \"amd64\" or \"arm64\"."
  }

  validation {
    condition     = alltrue([for img in var.images : contains(["intel", "amd", "arm"], img.cpu_vendor)])
    error_message = "Each image.cpu_vendor must be \"intel\", \"amd\", or \"arm\"."
  }

  validation {
    condition = alltrue([
      for name, img in var.images : alltrue([
        for a in img.extra_kernel_args : !can(regex("[[:space:]]", a))
      ])
    ])
    error_message = "Each image.extra_kernel_args element must be a single kernel argument with no whitespace (a space smuggles a second arg past karg_conflicts, which splits on = and never on whitespace). Offending (image => elements): ${jsonencode({
      for name, img in var.images : name => [
        for a in img.extra_kernel_args : a if can(regex("[[:space:]]", a))
      ] if length([for a in img.extra_kernel_args : a if can(regex("[[:space:]]", a))]) > 0
    })}."
  }

  validation {
    condition = alltrue([
      for name, img in var.images : alltrue([
        for a in img.extra_kernel_args : !startswith(a, "-")
      ])
    ])
    error_message = "Each image.extra_kernel_args element must not begin with '-' (the karg removal spelling is a Non-Goal; the conflict guard cannot see it). Offending (image => elements): ${jsonencode({
      for name, img in var.images : name => [
        for a in img.extra_kernel_args : a if startswith(a, "-")
      ] if length([for a in img.extra_kernel_args : a if startswith(a, "-")]) > 0
    })}."
  }

  validation {
    condition = alltrue([
      for name, img in var.images : alltrue([
        for a in img.extra_kernel_args : element(split("=", a), 0) != ""
      ])
    ])
    error_message = "Each image.extra_kernel_args element must carry a non-empty key (the empty string reaches the Factory as extraKernelArgs: [\"\"], and a leading '=' defeats the guard's =-keying). Offending (image => elements): ${jsonencode({
      for name, img in var.images : name => [
        for a in img.extra_kernel_args : a if element(split("=", a), 0) == ""
      ] if length([for a in img.extra_kernel_args : a if element(split("=", a), 0) == ""]) > 0
    })}."
  }

  validation {
    condition = alltrue([
      for name, img in var.images : alltrue([
        for a in img.extra_kernel_args : element(split("=", a), 0) != "debugfs"
      ])
    ])
    error_message = "Each image.extra_kernel_args element must not use the debugfs key at any value (AGENTS.md §Hard Constraints forbids the value that boot-loops Talos with Cilium; this base's gate greps only its own kubernetes/**/tofu/** PR diff and can never see a consumer's cluster.yaml). Offending (image => elements): ${jsonencode({
      for name, img in var.images : name => [
        for a in img.extra_kernel_args : a if element(split("=", a), 0) == "debugfs"
      ] if length([for a in img.extra_kernel_args : a if element(split("=", a), 0) == "debugfs"]) > 0
    })}."
  }
}

variable "hardware_capabilities" {
  description = <<-EOT
    Consumer-defined hardware capabilities, keyed by the id node
    hardware_capabilities references.
      - requires_features: Layer-C feature ids. Each provisioned feature must come
        from a listed provisioning profile, and each listed profile's feature must
        appear here.
      - provisioning_profiles: base catalog profile ids to apply; never inferred.
        An unknown id fails the plan.
      - emits_label: node label for the capability, in
        platform.io/hardware-capability.*. Reserved hardware-feature.* labels come
        only from profiles; a raw config_patches string is not checked.
  EOT
  type = map(object({
    requires_features     = optional(list(string), [])
    provisioning_profiles = optional(list(string), [])
    emits_label           = string
  }))
  default = {}

  validation {
    condition     = alltrue([for c in var.hardware_capabilities : startswith(c.emits_label, "platform.io/hardware-capability.")])
    error_message = "Each hardware_capabilities entry's emits_label must be in the platform.io/hardware-capability.* namespace (reserved hardware-feature.* labels come only from a profile's `provides`)."
  }
}

variable "cluster_endpoint" {
  description = <<-EOT
    Kubernetes API endpoint the cluster advertises, an https:// URL with port,
    e.g. "https://api.example.com:6443".
  EOT
  type        = string

  validation {
    condition     = can(regex("^https://", var.cluster_endpoint))
    error_message = "cluster_endpoint must be an https:// URL including the port."
  }
}

variable "config_patches" {
  description = <<-EOT
    Talos machine-config patches (YAML strings) applied to all nodes on top of
    the module defaults.
  EOT
  type        = list(string)
  default     = []
}

variable "controlplane_config_patches" {
  description = "Additional machine-config patches applied to controlplane nodes only."
  type        = list(string)
  default     = []
}

variable "worker_config_patches" {
  description = "Additional machine-config patches applied to worker nodes only."
  type        = list(string)
  default     = []
}

variable "deploy_argocd" {
  description = "Deliver ArgoCD as a Talos inlineManifest seed. Requires sops_age_key."
  type        = bool
  default     = true
}

variable "sops_age_key" {
  description = <<-EOT
    age private key (keys.txt contents) for the ArgoCD ksops repo-server, seeded
    as the sops-age-key Secret. Required when deploy_argocd = true. It decrypts every
    SOPS secret and lands in plaintext in the controlplane machine config and in
    state. The Secret is create-only: rotating the key needs a machine-config
    apply with the new key.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}

variable "argocd_namespace" {
  description = "Namespace for the ArgoCD bootstrap install."
  type        = string
  default     = "argocd"
}

variable "argocd_chart_version" {
  description = <<-EOT
    argo-cd Helm chart version. Feeds the bootstrap seed, which is frozen at the
    first apply, the Day-0 CRD apply and the seeded argocd namespace's version
    label, so changing it applies a new machine config to every controlplane. It
    does not upgrade a running Argo CD; the argocd component does. null selects
    this default.
  EOT
  type        = string
  default     = "10.10.5"
  nullable    = false
}

variable "argocd_values_override" {
  description = <<-EOT
    Helm values merged over helm/argocd-values.yaml for the bootstrap seed only.
    The steady-state argocd component does not read it and overwrites what it also
    declares on the first sync, so SSO and RBAC belong in the consumer's overlay.
  EOT
  type        = string
  default     = ""
}

variable "cluster_health_timeout" {
  description = <<-EOT
    Go duration `tofu apply` waits for the new cluster to become healthy
    (etcd quorum, nodes Ready, API server reachable).
  EOT
  type        = string
  default     = "10m"
}

variable "pod_cidr" {
  description = "Pod network CIDR(s). Drives Talos cluster.network.podSubnets AND Cilium IPAM/masquerade/native-routing. One entry for single-stack; v4+v6 when dual_stack = true."
  type        = list(string)
  default     = ["10.244.0.0/16"]

  validation {
    condition     = length(var.pod_cidr) >= 1
    error_message = "pod_cidr must contain at least one CIDR."
  }

  validation {
    condition     = alltrue([for c in var.pod_cidr : can(cidrhost(c, 0))])
    error_message = "Every pod_cidr entry must be a valid CIDR (e.g. \"10.244.0.0/16\" or \"fd00::/48\")."
  }
}

variable "service_cidr" {
  description = "Service network CIDR(s). Drives Talos cluster.network.serviceSubnets. One entry for single-stack; v4+v6 when dual_stack = true."
  type        = list(string)
  default     = ["10.96.0.0/12"]

  validation {
    condition     = length(var.service_cidr) >= 1
    error_message = "service_cidr must contain at least one CIDR."
  }

  validation {
    condition     = alltrue([for c in var.service_cidr : can(cidrhost(c, 0))])
    error_message = "Every service_cidr entry must be a valid CIDR (e.g. \"10.96.0.0/12\" or \"fd00:1234::/108\")."
  }
}

variable "dual_stack" {
  description = "Enable IPv4/IPv6 dual-stack. When true, pod_cidr/service_cidr should each carry a v4 and a v6 entry and Cilium ipv6 is enabled."
  type        = bool
  default     = false
}

variable "allow_scheduling_on_controlplanes" {
  description = "Remove the control-plane taint so workloads schedule on control-plane nodes (single-node / edge clusters). Sets Talos cluster.allowSchedulingOnControlPlanes."
  type        = bool
  default     = false
}

variable "deploy_cilium" {
  description = <<-EOT
    Deliver Cilium as a Talos inlineManifest seed and disable the Talos default
    CNI and kube-proxy. Set false to keep Flannel or bring another CNI through
    config_patches.
  EOT
  type        = bool
  default     = true
}

variable "cilium_chart_version" {
  description = <<-EOT
    Cilium Helm chart version. Feeds the bootstrap seed, which is frozen at the
    first apply, and the targetRevision of the self-management Application.
    Changing it does not upgrade a running Cilium without self-management.
    null selects this default.
  EOT
  type        = string
  default     = "1.20.3"
  nullable    = false
}

variable "cilium_chart_repository" {
  description = <<-EOT
    Helm repository for the cilium chart, e.g. a private mirror. The chart is
    pulled by tag without a digest and its render goes into the bootstrap seed, so
    point it only at a repository you trust.
  EOT
  type        = string
  default     = "https://helm.cilium.io"
}

variable "cilium_namespace" {
  description = "Namespace Cilium is rendered into (Talos convention: kube-system)."
  type        = string
  default     = "kube-system"
}

variable "cilium_values_override" {
  description = <<-EOT
    Helm values (a YAML mapping) merged last over helm/cilium-values.yaml and the
    module-computed values; Helm deep-merges, so lists replace and maps merge. It
    reaches the bootstrap seed and, with cilium_self_management_values_source, the
    Day-2 Application as a file the consumer commits at override_path.
    Marked sensitive, so plan hides its diff; cilium_values_override_digest shows
    changes. The content still reaches the machine config and state. Argo CD does
    not decrypt Helm valueFiles, so secrets in the committed override file are
    plaintext in git unless the consumer adds a decrypting plugin.
  EOT
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.cilium_values_override == "" || can(keys(yamldecode(var.cilium_values_override)))
    error_message = "cilium_values_override must be a YAML MAPPING (top-level `key: value` pairs) — a comment-only document decodes to null and a list-rooted one to a sequence, neither of which is a Helm values document."
  }

  validation {
    condition = var.cilium_values_override == "" || length(setintersection(
      try(keys(yamldecode(var.cilium_values_override)), []),
      ["kubeProxyReplacement", "k8sServiceHost", "k8sServicePort"],
    )) == 0
    error_message = "cilium_values_override must not name kubeProxyReplacement, k8sServiceHost or k8sServicePort: each has a Talos-side counterpart the module writes (cluster.proxy.disabled / the pre-CNI API-server endpoint), and setting one half alone leaves the cluster with no ClusterIP datapath and no cluster DNS. Use the typed inputs cilium_kube_proxy_replacement, cilium_k8s_service_host and cilium_k8s_service_port, which set both halves together."
  }
}

variable "cilium_routing_mode" {
  description = "Cilium datapath routing mode: \"tunnel\" (VXLAN/Geneve overlay) or \"native\" (routed fabric, e.g. BGP). Install-time-fixed."
  type        = string
  default     = "tunnel"

  validation {
    condition     = contains(["tunnel", "native"], var.cilium_routing_mode)
    error_message = "cilium_routing_mode must be \"tunnel\" or \"native\"."
  }
}

variable "cilium_native_routing_cidr" {
  description = "ipv4NativeRoutingCIDR for routing_mode = native. Empty = derive from the first IPv4 pod_cidr entry."
  type        = string
  default     = ""

  validation {
    condition     = var.cilium_native_routing_cidr == "" || can(cidrhost(var.cilium_native_routing_cidr, 0))
    error_message = "cilium_native_routing_cidr must be empty (derive from pod_cidr) or a well-formed CIDR such as \"10.244.0.0/16\"."
  }
}

variable "cilium_kube_proxy_replacement" {
  description = "Run Cilium as the kube-proxy replacement (against Talos KubePrism). When true the module also sets Talos cluster.proxy.disabled. Install-time-fixed."
  type        = bool
  default     = true
}

variable "cilium_k8s_service_host" {
  description = <<-EOT
    Cilium k8sServiceHost, the API-server endpoint Cilium uses before the CNI is
    up. Default "localhost" (Talos KubePrism). Emitted only when
    cilium_kube_proxy_replacement = true. A bare host; IPv6 unbracketed and
    canonical. Install-time-fixed on the seed; reaches a running cluster only
    through cilium_self_management. An endpoint that needs the CNI deadlocks
    bootstrap.
  EOT
  type        = string
  default     = "localhost"
  nullable    = false

  # Use try() because boolean operators may evaluate a failing cidrhost() call.
  validation {
    condition = can(regex("^[a-zA-Z0-9._-]+$", var.cilium_k8s_service_host)) || (
      try(cidrhost("${var.cilium_k8s_service_host}/128", 0), "") == var.cilium_k8s_service_host
    )
    error_message = "cilium_k8s_service_host must be a bare host — a DNS name, an IPv4 literal, or an UNBRACKETED IPv6 literal in canonical form such as \"2001:db8::1\" — with no whitespace, no scheme, no brackets and no \":port\" (use cilium_k8s_service_port). An IPv6 value is parsed, not pattern-matched, so a non-canonical spelling (\"2001:0db8::1\") or an IPv4-embedded one (\"::ffff:192.0.2.1\") is rejected — write the form it normalizes to. Brackets are rejected on purpose: the chart passes this value to KUBERNETES_SERVICE_HOST, and client-go joins host and port with net.JoinHostPort, which brackets a colon-bearing host again — \"[2001:db8::1]\" would reach the API server as \"[[2001:db8::1]]:6443\"."
  }
}

variable "cilium_k8s_service_port" {
  description = <<-EOT
    Cilium k8sServicePort, paired with cilium_k8s_service_host, as a string.
    Default "7445" (Talos KubePrism).
  EOT
  type        = string
  default     = "7445"
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]{1,5}$", var.cilium_k8s_service_port))
    error_message = "cilium_k8s_service_port must be a decimal TCP port as a string — digits only, no whitespace, no scheme, no host (e.g. \"7445\")."
  }

  # The format validation reports non-numeric values; do not raise during this range check.
  validation {
    condition     = try(tonumber(var.cilium_k8s_service_port), 0) > 0 && try(tonumber(var.cilium_k8s_service_port), 0) < 65536
    error_message = "cilium_k8s_service_port must be in the TCP port range 1-65535 (e.g. \"7445\", the Talos KubePrism port)."
  }
}

variable "cilium_mtu" {
  description = "Cilium datapath MTU. 0 = chart auto-detect. Set for jumbo-frame fabrics."
  type        = number
  default     = 0
}

variable "cilium_encryption" {
  description = <<-EOT
    Transparent pod-traffic encryption: type "none" (default), "wireguard", or
    "ipsec" (needs cilium_ipsec_key). Install-time-fixed.
  EOT
  type = object({
    type = optional(string, "none")
  })
  default = { type = "none" }

  validation {
    condition     = contains(["none", "wireguard", "ipsec"], var.cilium_encryption.type)
    error_message = "cilium_encryption.type must be \"none\", \"wireguard\", or \"ipsec\"."
  }
}

variable "cilium_ipsec_key" {
  description = <<-EOT
    IPsec key for the cilium-ipsec-keys Secret, e.g.
    "3 rfc4106(gcm(aes)) <hex> 128". Required for cilium_encryption.type = "ipsec".
    Lands in the controlplane machine config and state.
  EOT
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.cilium_ipsec_key == "" || can(regex("^[0-9]+ ", var.cilium_ipsec_key))
    error_message = "cilium_ipsec_key must be empty or a Cilium IPsec key starting with a numeric key id (e.g. \"3 rfc4106(gcm(aes)) <hex> 128\")."
  }
}

variable "cilium_gateway_api" {
  description = <<-EOT
    Enable the Cilium Gateway API controller in the seed. Install-time-fixed.
    The Gateway API CRDs (v1.6.1 or newer, standard channel) are not seeded unless
    cilium_gateway_api_crds_url is set; until they exist the controller logs
    errors, the CNI is unaffected.
  EOT
  type        = bool
  default     = true
}

variable "cilium_gateway_api_crds_url" {
  description = <<-EOT
    Optional URL of a Gateway API CRD bundle Talos applies at bootstrap through
    cluster.extraManifests, e.g.
    https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml.
    Use the experimental bundle only if v1alpha2 TLSRoute objects already exist.
    Not digest-pinned, and a failed fetch stalls bootstrap; leave empty to apply
    the CRDs through GitOps instead.
  EOT
  type        = string
  default     = ""
}

variable "cilium_agent_metrics" {
  description = "Enable Cilium agent Prometheus metrics (prometheus.enabled)."
  type        = bool
  default     = false
}

variable "cilium_operator_metrics" {
  description = "Enable Cilium operator Prometheus metrics (operator.prometheus.enabled)."
  type        = bool
  default     = false
}

variable "cilium_operator_replicas" {
  description = <<-EOT
    Cilium operator replicas. null = 2 at two or more nodes and the floor's 1 on a
    single node. A number pins the count on both delivery paths and must not exceed
    the node count. Seed knob: reaches a running cluster only through
    cilium_self_management.
  EOT
  type        = number
  default     = null

  validation {
    # Only the conditional reliably skips floor(null) on the supported OpenTofu floor.
    condition = var.cilium_operator_replicas == null ? true : (
      var.cilium_operator_replicas >= 1 &&
      floor(var.cilium_operator_replicas) == var.cilium_operator_replicas
    )
    error_message = "cilium_operator_replicas must be null (derive from the node count) or an integer >= 1."
  }

  validation {
    condition     = var.cilium_operator_replicas == null || var.cilium_operator_replicas <= length(var.nodes)
    error_message = "cilium_operator_replicas must not exceed the number of declared nodes: the chart's operator podAntiAffinity is requiredDuringScheduling on kubernetes.io/hostname, so at most one operator pod places per node and every surplus replica stays Pending indefinitely. Rejected rather than warned because the value is baked into a create-only inlineManifest — the bootstrap that carries it cannot be walked back by a later apply."
  }
}

variable "cilium_hubble_enabled" {
  description = <<-EOT
    Enable Hubble for metrics (hubble.enabled), with observer TLS off and no
    Relay or UI. On a self-managed cluster, enabling it rolls the agents.
  EOT
  type        = bool
  default     = false
}

variable "cilium_hubble_metrics" {
  description = <<-EOT
    Hubble metrics to export (hubble.metrics.enabled), in Hubble's context syntax,
    e.g. ["dns:query;ignoreAAAA", "drop"]. Empty with Hubble on exports nothing.
  EOT
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for m in var.cilium_hubble_metrics : !strcontains(m, "\n") && !strcontains(m, "\r") && !strcontains(m, "---")
    ])
    error_message = "each cilium_hubble_metrics entry must be a single line and must not contain \"---\": the chart renders these raw and unquoted into the cilium-config ConfigMap that is baked into the controlplane machine config, so a newline injects arbitrary ConfigMap keys and a document separator corrupts the rendered manifest."
  }
}

variable "cilium_agent_metric_overrides" {
  description = <<-EOT
    Changes to the agent's default metric set (prometheus.metrics): "+name" adds,
    "-name" removes. Needs cilium_agent_metrics = true. Reaches a running cluster
    only through cilium_self_management.
  EOT
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for m in var.cilium_agent_metric_overrides : can(regex("^[+-][a-zA-Z_][a-zA-Z0-9_]*$", m))
    ])
    error_message = "each cilium_agent_metric_overrides entry must be \"+metric_name\" or \"-metric_name\" (letters, digits and underscores only): the chart renders these raw and unquoted into the cilium-config ConfigMap that is baked into the controlplane machine config, so an entry containing a newline, a space or \"---\" corrupts that document."
  }
}

variable "cilium_hubble_open_metrics" {
  description = <<-EOT
    Export Hubble metrics in OpenMetrics format (hubble.metrics.enableOpenMetrics).
    Needs cilium_hubble_enabled = true and a non-empty cilium_hubble_metrics.
    Reaches a running cluster only through cilium_self_management, and rolls the
    agents there unless the override sets rollOutCiliumPods: false.
  EOT
  type        = bool
  default     = false
  nullable    = false
}

variable "cilium_self_management" {
  description = <<-EOT
    Emit a Cilium ArgoCD Application in output cilium_self_management_app for the
    consumer's GitOps to apply; the module never applies it. It is the only path
    for a Cilium change to reach a running cluster. Single-source by default;
    multi-source, reading values files from git, when
    cilium_self_management_values_source is set. Requires deploy_argocd and
    deploy_cilium.
  EOT
  type        = bool
  default     = false

  validation {
    condition     = !var.cilium_self_management || (var.deploy_argocd && var.deploy_cilium)
    error_message = "cilium_self_management requires deploy_argocd = true AND deploy_cilium = true (self-management hands the Day-2 config off from the module-delivered Cilium seed to the consumer's ArgoCD)."
  }

  validation {
    condition     = !(var.cilium_self_management && var.cilium_values_override != "" && var.cilium_self_management_values_source == null)
    error_message = "cilium_self_management with a non-empty cilium_values_override requires cilium_self_management_values_source: without it the emitted Application is single-source and its valuesObject carries no override term, so a datapath-critical override (BGP control-plane / L2 announcements / bpf tuning) would be silently dropped when ArgoCD adopts Cilium. Set cilium_self_management_values_source to the git repo, revision and two file paths the Application should read its values layers from."
  }
}

variable "cilium_self_management_project" {
  description = <<-EOT
    AppProject of the emitted Cilium Application. Use a project that allows
    kube-system on https://kubernetes.default.svc and Cilium's cluster-scoped
    resources; an under-scoped project leaves the Application degraded.
  EOT
  type        = string
  default     = "default"
}

variable "cilium_self_management_values_source" {
  description = <<-EOT
    Git source of the emitted Application's values files; setting it switches the
    Application to multi-source. The module dereferences none of these.
      - repo_url: git repo registered in ArgoCD; a scoped project lists it in
        sourceRepos together with cilium_chart_repository.
      - revision: targetRevision for that repo.
      - values_path: repo-relative path where the consumer commits the
        cilium_self_management_values output.
      - override_path: repo-relative path of the consumer's cilium_values_override
        document; required when the override is set, distinct from values_path.
    Nothing compares the committed files at sync time; compare the values-digest
    annotation with the values file.
  EOT
  type = object({
    repo_url      = string
    revision      = string
    values_path   = string
    override_path = optional(string, "")
  })
  default = null

  # Use try() for nullable attributes; boolean operators may evaluate both sides.
  validation {
    condition = var.cilium_self_management_values_source == null || alltrue([
      for f in ["repo_url", "revision", "values_path"] :
      trimspace(try(var.cilium_self_management_values_source[f], "")) != ""
    ])
    error_message = "cilium_self_management_values_source needs a non-empty repo_url, revision and values_path — they become spec.sources[0].repoURL, its targetRevision, and the first $values/… valueFiles entry of the emitted Application."
  }

  validation {
    condition = var.cilium_self_management_values_source == null || alltrue([
      for p in compact([
        try(var.cilium_self_management_values_source.values_path, ""),
        try(var.cilium_self_management_values_source.override_path, ""),
        ]) : can(regex("^[A-Za-z0-9._/-]+$", p)) && alltrue([
        for seg in split("/", p) : seg != "" && seg != "."
      ])
    ])
    error_message = "cilium_self_management_values_source paths must be normalized repo-relative paths: only letters, digits, dot, underscore, dash and \"/\", and no empty or \".\" segment. Whitespace or a newline injects a top-level values key into the emitted Helm values document's header, and a non-normalized spelling (\"./cilium/values.yaml\") would let two paths naming ONE file pass the distinctness guard below."
  }

  validation {
    condition     = var.cilium_self_management_values_source == null || can(regex("^[^[:space:]]+$", try(var.cilium_self_management_values_source.repo_url, "")))
    error_message = "cilium_self_management_values_source.repo_url must carry no whitespace — it is interpolated into an emitted Helm values document's header, where a newline injects a top-level values key. It must also carry no userinfo (no \"https://user:token@host\"): ArgoCD repository credentials belong in the repository registration, and this URL is written into a file the consumer commits to git."
  }

  validation {
    condition = var.cilium_self_management_values_source == null || can(regex(
      "^(https://[^@[:space:]]+|ssh://([A-Za-z0-9._-]+@)?[^@:[:space:]]+(:[0-9]+)?/[^@[:space:]]*|[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:[^@[:space:]]+)$",
      try(var.cilium_self_management_values_source.repo_url, ""),
    ))
    error_message = "cilium_self_management_values_source.repo_url must be a git remote ArgoCD can resolve — \"https://host/org/repo.git\", \"ssh://git@host[:port]/org/repo.git\" or \"git@host:org/repo.git\" — and must carry no embedded PASSWORD (no \"https://user:token@host\", no \"ssh://user:pass@host\"): ArgoCD repository credentials belong in the repository registration, not in a manifest committed to git. An SSH USERNAME is fine, and is the documented form."
  }

  validation {
    condition = var.cilium_self_management_values_source == null || (
      trimspace(try(var.cilium_self_management_values_source.override_path, "")) == "" ||
      trimspace(try(var.cilium_self_management_values_source.override_path, "")) != trimspace(try(var.cilium_self_management_values_source.values_path, ""))
    )
    error_message = "cilium_self_management_values_source.values_path and .override_path must be different files — they are two ordered layers of one Helm merge, and one path for both means the module-set layer overwrites your override document (the values-digest check stays green on that state, because the digest covers the module-set layer only)."
  }

  validation {
    condition = var.cilium_self_management_values_source == null || alltrue([
      for p in compact([
        try(var.cilium_self_management_values_source.values_path, ""),
        try(var.cilium_self_management_values_source.override_path, ""),
      ]) : !startswith(p, "/") && !contains(split("/", p), "..")
    ])
    error_message = "cilium_self_management_values_source paths must be repo-root-relative with no leading \"/\" and no \"..\" segment — they are interpolated into $values/<path> and resolved against the ref source's checkout root."
  }

  validation {
    condition = var.cilium_self_management_values_source == null || var.cilium_values_override == "" || (
      trimspace(try(var.cilium_self_management_values_source.override_path, "")) != ""
    )
    error_message = "cilium_self_management_values_source.override_path is required while cilium_values_override is non-empty: it is the second valueFiles entry, the one that carries the override into the emitted Application. Without it the Application renders from the module-set layer alone and the override is silently dropped."
  }
}

variable "cert_approver_provider_regex" {
  description = <<-EOT
    PROVIDER_REGEX of kubelet-csr-approver: a regex every serving-cert DNS SAN
    must also match. Each SAN is bound to the requesting node's hostname anyway.
    Seed knob: changes the machine config, not a running approver.
  EOT
  type        = string
  default     = ".*"

  validation {
    condition     = trimspace(var.cert_approver_provider_regex) != ""
    error_message = "cert_approver_provider_regex must not be empty or whitespace-only — an empty PROVIDER_REGEX makes postfinance/kubelet-csr-approver v1.2.14 exit fatally at startup so the approver never runs, and a whitespace-only regex compiles but matches no DNS SAN, denying every serving-cert CSR. Use \".*\" for no extra pattern constraint."
  }
  validation {
    condition     = can(regexall(var.cert_approver_provider_regex, ""))
    error_message = "cert_approver_provider_regex must be a valid RE2 regex (it is compiled by the Go approver)."
  }
  validation {
    condition     = !strcontains(var.cert_approver_provider_regex, "---") && !strcontains(var.cert_approver_provider_regex, "\n")
    error_message = "cert_approver_provider_regex must not contain a YAML document separator (---) or a newline."
  }
}

variable "cert_approver_provider_ip_prefixes" {
  description = <<-EOT
    PROVIDER_IP_PREFIXES of kubelet-csr-approver: CIDRs every serving-cert IP SAN
    must fall within. Seed knob, like cert_approver_provider_regex.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]

  validation {
    condition     = length(var.cert_approver_provider_ip_prefixes) > 0
    error_message = "cert_approver_provider_ip_prefixes must not be empty — an empty set denies every CSR that carries an IP SAN. Use [\"0.0.0.0/0\", \"::/0\"] for all IPs."
  }
  validation {
    condition     = alltrue([for c in var.cert_approver_provider_ip_prefixes : can(cidrhost(c, 0))])
    error_message = "Every cert_approver_provider_ip_prefixes entry must be a valid CIDR (e.g. \"192.0.2.0/24\" or \"::/0\")."
  }
}

variable "cert_approver_replicas" {
  description = <<-EOT
    cert-approver replicas. More than 1 enables leader election and its leases
    RBAC. Seed knob: on a running cluster, `kubectl scale` adds replicas but not
    leader election.
  EOT
  type        = number
  default     = 1

  validation {
    condition     = var.cert_approver_replicas >= 1 && floor(var.cert_approver_replicas) == var.cert_approver_replicas
    error_message = "cert_approver_replicas must be an integer >= 1."
  }
}

variable "controlplane_apply_mode" {
  description = <<-EOT
    apply_mode of the controlplane machine-config apply: auto | reboot |
    no_reboot | staged. Only "auto" works on Day 0. "staged" defers the change to
    the next boot, which the operator triggers one node at a time. "reboot"
    reboots every controlplane at once and loses etcd quorum. "no_reboot" fails an
    apply that needs a reboot.
  EOT
  type        = string
  default     = "auto"
  nullable    = false

  validation {
    condition     = contains(["auto", "reboot", "no_reboot", "staged"], var.controlplane_apply_mode)
    error_message = "controlplane_apply_mode must be one of: auto, reboot, no_reboot, staged."
  }
}

variable "worker_apply_mode" {
  description = <<-EOT
    apply_mode of the worker machine-config applies, with the values and Day-0
    constraint of controlplane_apply_mode. After a "staged" window, switch back to
    "auto" only once every worker has rebooted: the switch alone re-applies the
    still-staged configs and reboots those nodes.
  EOT
  type        = string
  default     = "auto"
  nullable    = false

  validation {
    condition     = contains(["auto", "reboot", "no_reboot", "staged"], var.worker_apply_mode)
    error_message = "worker_apply_mode must be one of: auto, reboot, no_reboot, staged."
  }
}
