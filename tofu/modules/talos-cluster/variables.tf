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
    Talos Linux version for the **machine-config schema contract** —
    fixed at cluster bootstrap. Do NOT change this after the cluster
    exists; it drives data.talos_machine_configuration and the
    machine_secrets schema and changing it can cause schema drift on
    rolling reapplies.

    For OS upgrades, bump `talos_install_version` instead — that is the
    installer-image tag rendered into machine.install.image and the
    Image-Factory installer URL. The taskfile-driven `talosctl upgrade`
    reads it via tfplan JSON.
  EOT
  type        = string

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+([-+][0-9A-Za-z.-]+)?$", var.talos_version))
    error_message = "talos_version must be a v-prefixed semver (optional pre-release/build suffix), e.g. v1.13.0."
  }
}

variable "talos_install_version" {
  description = <<-EOT
    Talos installer-image tag — what's actually running on the nodes.
    Defaults to `talos_version` (= matches schema at bootstrap). Bump
    this for an OS upgrade; the Image-Factory installer URL and the
    per-node `machine.install.image` patch follow.

    The schema-pin `talos_version` stays fixed; the upgrade task
    (`task talos:upgrade:cluster` in the consumer repo) reads this value
    from tfplan JSON and runs `talosctl upgrade --image …:<version>`
    idempotently per node.
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
    Bare-metal nodes that make up the cluster. Each node must already be
    PXE-booted into Talos maintenance mode (reachable at `ip` on the Talos
    API port). The module applies the machine config, it does not provision
    the hardware or boot the nodes.

    Kubernetes node roles are ONLY `controlplane` or `worker`. Hardware
    specialisation (GPU, single-board-computer, storage) is NOT a role — it is
    expressed as a SET of `hardware_capabilities` (composed independently) plus
    the base `image` (architecture + CPU vendor + baseline extensions + overlay).

    The MAP KEY is the node's name — its Talos hostname, its Kubernetes node
    name, and the key of the per-node apply resource (and therefore its state
    address). It is deliberately NOT a field: one node, one definition place,
    uniqueness by construction instead of by an added-on check. Renaming a node
    IS an identity change (new state address, new Kubernetes node).

    `image` (required) must exist as a key in var.images.
    `hardware_capabilities` (optional, default []) is the set of capability ids
    (keys in var.hardware_capabilities) the node holds — a node can hold any set
    (storage + compute + GPU) without a hand-authored class.
    `config_patches` (optional) are machine-config patches applied to THIS node
    only — use it for genuinely per-node values such as a NIC-specific bridge
    config; the caller renders the concrete value into the YAML string. They
    apply AFTER the module-generated capability patch, so a raw patch can still
    override a generated machine.kernel.modules / sysctls / nodeLabels value.
  EOT
  type = map(object({
    ip                    = string
    role                  = string                     # "controlplane" | "worker"
    image                 = string                     # must exist as key in var.images
    hardware_capabilities = optional(list(string), []) # keys in var.hardware_capabilities
    config_patches        = optional(list(string), []) # per-node patches (e.g. NIC binding)
  }))

  validation {
    condition     = length([for h, n in var.nodes : h if n.role == "controlplane"]) >= 1
    error_message = "At least one controlplane node is required."
  }

  # Even controlplane counts add no etcd failure tolerance over the preceding odd count.
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

  # Node-map keys are state identities: require canonical names rather than normalizing them.
  validation {
    condition = alltrue([for h, n in var.nodes :
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$", h))
      && length(h) <= 253
      && alltrue([for label in split(".", h) : length(label) <= 63])
    ])
    error_message = "Node keys must be canonical Kubernetes node names: lowercase [a-z0-9-.], no leading/trailing '-' or '.', <= 63 chars per label, <= 253 total. Talos does NOT reject uppercase or '_' — it silently rewrites them, so two keys could collapse onto one Kubernetes node."
  }

  # Talos splits at the first dot; the first label must fit the Linux hostname limit.
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

  # Require canonical IP spelling so string uniqueness also means address uniqueness.
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
    Set machine.kubelet.registerWithFQDN, so the kubelet registers with the
    node's FQDN instead of its short hostname.

    Talos splits a dotted hostname at the first dot into hostname + domainname
    and, by default, registers only the SHORT hostname with Kubernetes — so a
    dotted node key is meaningless to Kubernetes unless this is true, which is
    why var.nodes rejects dotted keys while it is false. Leave it off for
    single-label node names.

    ALL-OR-NOTHING: this is an all-nodes machine-config patch, so a single dotted
    node key flips FQDN registration for every node in the cluster, including
    short-named ones — which changes their Kubernetes node name. Do not mix
    short and dotted node names unless that is what you want.
  EOT
  type        = bool
  default     = false
}

variable "images" {
  description = <<-EOT
    Per node-IMAGE base-installer profile. Key = image id (matching node.image).
    The non-composable base axis a node sits on. Each image carries:

      - architecture: "amd64" | "arm64" — installer-image architecture. This is
        what unblocks ARM single-board computers (a Raspberry Pi worker uses an
        image with architecture = "arm64").
      - cpu_vendor: "intel" | "amd" | "arm" — resolves a provisioning profile's
        vendor variants (e.g. the iommu profile's intel_iommu vs amd_iommu).
        REQUIRED, no default: a defaulted vendor would silently bake the wrong
        IOMMU kernel arg on a mismatched CPU.
      - extensions: Image-Factory system extensions baked on EVERY node of this
        image regardless of capabilities — baseline content that is NOT a
        capability (CPU microcode, NIC/GPU firmware, base tooling, a default
        runtime sandbox). The node's effective extension set is this baseline
        UNION the selected provisioning profiles' extensions. Capability-specific
        extensions (drbd, nvidia) come from the base provisioning-profile catalog
        via a composite, NOT from here.
      - overlay: optional SBC/board overlay for ARM single-board computers (e.g.
        name = "rpi_generic", image = "siderolabs/sbc-raspberrypi"). Leave null
        for ordinary x86/metal nodes.
      - extra_kernel_args: optional per-image boot kernel command-line args,
        baked into the schematic's customization.extraKernelArgs (the
        Talos v1.10+ UKI-correct sink; machine.install.extraKernelArgs is
        ignored under systemd-boot). Unioned with the node's resolved
        provisioning-profile kernel args. One argument per element; a
        differing single-value key vs. a selected profile fails the plan
        (karg_conflicts) rather than landing both on the cmdline.

    The installer image is always the non-SecureBoot metal installer (NEVER the
    SecureBoot variant, per the base AGENTS.md Hard Constraint).
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

  # ASCII whitespace can smuggle a second kernel arg past key-based conflict checks.
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

  # Removal prefixes bypass the composition conflict model.
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

  # Reject the debugfs key at any value; consumer patches are outside this repository’s CI grep.
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
    Consumer-defined composite hardware-capabilities. Key = capability id
    (matching an entry in node.hardware_capabilities). Tool-agnostic, swappable:
    a node declares "storage-replicated", not "drbd". Each carries two SEPARATE
    lists plus a label (provisioning is DECOUPLED from detection):

      - requires_features: Layer-C atom ids for scheduling / labels (three-layer
        ADR convention). A PROVISIONED atom here (one a base catalog profile
        `provides`) MUST be satisfied by a listed provisioning_profile, and every
        listed profile's provided atom MUST appear here (symmetry, both ways).
      - provisioning_profiles: ids of base catalog profiles to apply. EXPLICIT —
        never inferred from requires_features. Unknown id → hard plan error.
      - emits_label: the node label set when a node holds this capability. MUST be
        in the platform.io/hardware-capability.* namespace; the reserved Layer-C
        platform.io/hardware-feature.* labels are emitted only from a profile's
        base-controlled `provides`, never from here. This closes forgery via the
        TYPED path only — a raw per-node `config_patches` string can still set
        machine.nodeLabels directly (the module does not parse patch content), so
        a forged reserved hardware-feature.* label there is the downstream-Kyverno
        boundary (reserved-layer-c-hardware-labels rule), the same residual as the
        raw-patch SecureBoot/podSubnets vectors. See the ADR for the threat model.
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
    Kubernetes API endpoint the cluster advertises, e.g.
    "https://api.example.com:6443" or a controlplane VIP. Caller-supplied
    because it is cluster identity (lives in the consumer repo / XCluster spec),
    not in this base module.
  EOT
  type        = string

  validation {
    condition     = can(regex("^https://", var.cluster_endpoint))
    error_message = "cluster_endpoint must be an https:// URL including the port."
  }
}

variable "config_patches" {
  description = <<-EOT
    Extra Talos machine-config patches (YAML strings) applied to ALL nodes,
    on top of the module defaults. Cluster-specific patches (registry mirrors,
    install disk, network) are supplied here by the caller — the module ships
    no cluster identity of its own.
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
  description = <<-EOT
    Whether the module ships ArgoCD as a Talos inlineManifest. Default true —
    ArgoCD is part of the Layer-1 base per the platform layer model (C4 Level-2).
    When true, sops_age_key MUST be set (ksops in the repoServer).
  EOT
  type        = bool
  default     = true
}

variable "sops_age_key" {
  description = <<-EOT
    age private key (contents of keys.txt) for the ArgoCD ksops repoServer, so
    ArgoCD can decrypt SOPS-encrypted manifests (ADR-0023 class B). Created as
    the sops-age-key Secret (inlineManifest) in the argocd namespace. Required
    when deploy_argocd = true.

    SECURITY: this is a cross-cutting master key (decrypts ALL SOPS secrets) and
    lands in plaintext stringData in the controlplane machine config + in the
    (encrypted) state. Whoever can read a controlplane node's machine config
    holds it. Incremental over the machine_secrets/PKI already in state, but a
    larger blast radius — a conscious acceptance. ROTATION: the inlineManifest
    Secret never reconciles, so rotating the key requires re-applying the
    machine config (tofu apply with the new key), not just updating the Secret.
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
    Version of the argo-cd Helm chart (argoproj.github.io/argo-helm). This is a
    SEED knob, not an upgrade knob: Talos applies inlineManifests once at
    bootstrap and never re-runs them, so bumping this after bootstrap only
    re-renders the machine config — it does NOT upgrade a running ArgoCD. Steady-
    state version is owned by ArgoCD self-management (the app reconciles itself
    from git). VERIFY the exact current chart version at push.

    As with `cilium_chart_version`, this default is the single source of truth
    and `nullable = false` lets a caller pass `null` to mean "take the base's
    pin" — see that variable for why the attribute is load-bearing.
  EOT
  type        = string
  default     = "10.10.1"
  nullable    = false
}

variable "argocd_values_override" {
  description = <<-EOT
    Optional consumer Helm values, MERGED on top of the shipped
    helm/argocd-values.yaml (helm merges value files; later wins) — not a
    wholesale replacement. Empty = just the shipped values (slim, ksops).

    SEED-ONLY. This configures the create-only bootstrap inlineManifest; the
    steady-state component (kubernetes/substrate/argocd) is what ArgoCD
    self-manages afterwards, and it does not read this variable. Anything set
    here that the steady-state render also declares is overwritten on the first
    sync — so SSO and RBAC do NOT belong here. Those are a consumer contract,
    patched onto the argocd-cm / argocd-rbac-cm ConfigMaps in the consumer's own
    kustomize overlay.
  EOT
  type        = string
  default     = ""
}

variable "cluster_health_timeout" {
  description = <<-EOT
    Max wait for the freshly bootstrapped cluster to be considered healthy
    (data.talos_cluster_health: etcd quorum, nodes Ready, apiserver reachable).
    `tofu apply` blocks until then — only afterwards is the cluster "online".
    Go duration string, e.g. "10m".
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
    Whether the module delivers Cilium as a Talos inlineManifest seed AND
    disables the Talos default CNI (cluster.network.cni.name = none) + kube-proxy.
    Default true — Cilium is part of the Layer-1 substrate (Talos + Cilium + ArgoCD).
    Set false to keep the Talos-default CNI (Flannel) or supply a different CNI
    via the caller's own config_patches/extraManifests.
  EOT
  type        = bool
  default     = true
}

variable "cilium_chart_version" {
  description = <<-EOT
    Version of the cilium Helm chart (helm.cilium.io). SEED knob, not an upgrade
    knob: Talos applies inlineManifests once at bootstrap and never re-runs them,
    so bumping this after bootstrap only re-renders the machine config — it does
    NOT upgrade a running Cilium. VERIFY the exact current chart version at push.

    This default is the SINGLE source of truth for the pinned chart version.
    `nullable = false` is what makes that true: a caller may pass `null` to mean
    "take the base's pin", and OpenTofu then substitutes this default. Without
    `nullable = false` a passed `null` stays null. That is the mechanism the
    example shim relies on, so a consumer who omits
    `substrate.cilium.chart_version` from `cluster.yaml` inherits every future
    bump instead of freezing whatever literal their shim was copied with.
  EOT
  type        = string
  default     = "1.20.0"
  nullable    = false
}

variable "cilium_chart_repository" {
  description = <<-EOT
    Helm repository for the cilium chart. Override for a private mirror /
    air-gapped registry. NOTE: the chart is pulled by tag with no digest/cosign
    pin, and its render is baked into the controlplane inlineManifest seed — point
    this only at a repository you trust (a poisoned repo injects arbitrary
    bootstrap manifests). Integrity pinning is a tracked follow-on.
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
    Optional consumer Helm values, MERGED on top of the shipped
    helm/cilium-values.yaml AND the module-computed install-time values (helm
    DEEP-merges value layers per key, later wins: list values replace, map values
    merge — you can set/extend but cannot null-out a nested map key set by the
    floor). Carries the long tail the typed inputs do not name (Hubble, L2/BGP
    announcements, bpf tuning, VLAN bypass, secretsNamespaceLabels for the PNI
    contract). Empty = the minimal agnostic floor + the typed inputs only.

    Reaches BOTH delivery paths (adr-0028 §(a)/§(b)): the bootstrap seed as the
    last of three Helm values layers, and — with
    cilium_self_management_values_source set — the emitted Day-2 Application as
    the last `valueFiles` entry, a file the CONSUMER commits. The module never
    re-emits the string, so the emitted manifest stays secret-free.

    SECURITY: marked sensitive because Cilium values legitimately carry secret
    material (IPsec keys, Hubble/clustermesh TLS, BGP peer passwords). The mark
    covers the VARIABLE, and what it buys is bounded — state it rather than
    over-read it:

      - `tofu plan` no longer shows this input's diff, so a datapath-relevant
        change to it is invisible in plan output. `output
        cilium_values_override_digest` is the replacement change detector.
      - The CONTENT still reaches the rendered cilium-config ConfigMap, the
        controlplane machine config and therefore STATE — encrypt the backend,
        exactly as for cilium_ipsec_key and sops_age_key. adr-0007 §5 scopes its
        mitigation to operator discipline behind the gitleaks gate, not to a
        structural guarantee, and that is unchanged here.
      - The Day-2 path does NOT answer the confidentiality question, and the
        earlier "put it behind your own SOPS gate" framing was wrong. Argo CD
        reads the file at override_path as a plain Helm values document and
        applies no decryption to a Helm `valueFiles` source (documented behavior;
        argoproj/argo-cd#3024 is the standing request), so a SOPS-encrypted file
        is not a values document and does not render. Making it work needs a
        config-management plugin — helm-secrets in a custom repo-server image, or
        an equivalent — which this base neither ships nor configures. Until the
        consumer has built that, key material at override_path is PLAINTEXT in
        git. If the override carries IPsec keys or TLS material, either build
        that path first or keep the values out of git entirely (a Secret the
        chart references, delivered by the consumer's own sealed/SOPS pipeline).
  EOT
  type        = string
  default     = ""
  sensitive   = true

  validation {
    condition     = var.cilium_values_override == "" || can(keys(yamldecode(var.cilium_values_override)))
    error_message = "cilium_values_override must be a YAML MAPPING (top-level `key: value` pairs) — a comment-only document decodes to null and a list-rooted one to a sequence, neither of which is a Helm values document."
  }

  # These keys must agree with Talos configuration; change them through the paired typed inputs.
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
  description = "ipv4NativeRoutingCIDR for routing_mode = native. Empty = derive from the first pod_cidr entry."
  type        = string
  default     = ""

  # The chart renders this CIDR unquoted; reject malformed strings before freezing the seed.
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
    Cilium's `k8sServiceHost` — the endpoint Cilium reaches the API server
    through BEFORE the CNI is up. Default "localhost", i.e. Talos KubePrism on
    the node. Set it to a cluster VIP or load-balancer address on a cluster where
    KubePrism is not the intended path. Only emitted when
    cilium_kube_proxy_replacement = true (with kube-proxy present Cilium reaches
    the API server through the ClusterIP kube-proxy provides).

    An IPv6 endpoint goes in UNBRACKETED ("2001:db8::1") — client-go joins this
    value with the port through net.JoinHostPort, which brackets it itself.

    Install-time-fixed on the seed; reaches an already-bootstrapped cluster only
    through cilium_self_management. An endpoint that does not exist until the CNI
    is up deadlocks a fresh bootstrap — the reason this is a typed input rather
    than an override key (adr-0028 §(d)).
  EOT
  type        = string
  default     = "localhost"
  nullable    = false

  # client-go adds IPv6 brackets itself; accept only bare canonical literals.
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
    Cilium's `k8sServicePort`, paired with cilium_k8s_service_host. Default
    "7445", the Talos KubePrism port. A STRING because that is the shape the
    module has always emitted into the chart and into cilium-config; the chart
    accepts either.
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
    Transparent encryption for pod traffic. type one of:
      - "none"      — no encryption (default)
      - "wireguard" — keyless (per-node keys generated automatically)
      - "ipsec"     — requires a pre-shared key in var.cilium_ipsec_key, which the
                      module seeds as the cilium-ipsec-keys Secret (inlineManifest).
    Install-time-fixed (changing it later requires re-bootstrapping the CNI).
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
    IPsec pre-shared key material (the contents of the cilium-ipsec-keys Secret's
    `keys` entry, e.g. "3 rfc4106(gcm(aes)) <hex> 128"). Required when
    cilium_encryption.type = "ipsec"; lands in the controlplane machine config +
    (encrypted) state as a Secret inlineManifest. NEVER commit a real key —
    supply via tfvar/env/SOPS. wireguard needs no key.
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
    Enable the Cilium Gateway API controller in the seed (install-time-fixed).
    Default true — the base Hard Constraint is "Gateway API only — no Ingress".
    This renders gatewayAPI.enabled; the Cilium operator creates the GatewayClass
    at runtime once the Gateway API CRDs exist. The CRDs themselves are NOT seeded
    by default — apply them via GitOps / the apps catalog (Day-1), or opt into
    bootstrap seeding via cilium_gateway_api_crds_url. Until the CRDs land the
    gateway controller errors (harmless to the CNI). Cilium 1.20 needs Gateway API
    v1.6.1 AT A MINIMUM; the standard channel now carries TLSRoute at v1, so the
    standard bundle alone satisfies the Gateway-API-only Hard Constraint.
  EOT
  type        = bool
  default     = true
}

variable "cilium_gateway_api_crds_url" {
  description = <<-EOT
    OPT-IN bootstrap seeding of the Gateway API CRDs. Default EMPTY — the base does
    NOT fetch CRDs at bootstrap by default: the CRDs are a Day-1 GitOps / apps-catalog
    concern (apply them via ArgoCD after the cluster is up), which is the
    substrate/apps boundary and the air-gap-safe path. Cilium's gateway controller
    (enabled by cilium_gateway_api) tolerates absent CRDs — it errors until they
    land, but the CNI is unaffected and the cluster bootstraps normally.

    Set this to a CRD manifest URL ONLY if you want Talos to seed it at bootstrap via
    cluster.extraManifests — appropriate for a CONNECTED cluster that accepts the
    dependency. Cilium 1.20 needs Gateway API v1.6.1 at a MINIMUM; STANDARD channel:
    https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml
    TLSRoute is in the standard channel as of v1.6.1 (served at v1), so standard is
    the right bundle for a fresh cluster. Use the EXPERIMENTAL bundle ONLY if you
    carry pre-existing v1alpha2 TLSRoute objects: standard v1.6.1 declares v1alpha2
    but does not SERVE it, so those objects become unreadable.
    Point only at a source you trust —
    no digest pin; extraManifests applies WHATEVER the URL returns at the most
    privileged moment of bootstrap. WARNING: a failed/blocked fetch is NOT graceful —
    Talos' ExtraManifestController crashloops with backoff and bootstrap does not
    complete cleanly (verified against Talos v1.10/v1.11 docs). Use an internal
    mirror for restricted-egress, or leave empty and apply via GitOps.
  EOT
  type        = string
  default     = ""
}

variable "cilium_agent_metrics" {
  description = <<-EOT
    Enable Cilium agent Prometheus metrics (prometheus.enabled). Default false.
    Documented first-class alternative to hand-rolling cilium_values_override
    for the "I want Cilium metrics" case (issue #188).
  EOT
  type        = bool
  default     = false
}

variable "cilium_operator_metrics" {
  description = <<-EOT
    Enable Cilium operator Prometheus metrics (operator.prometheus.enabled).
    Default false. See cilium_agent_metrics.
  EOT
  type        = bool
  default     = false
}

variable "cilium_operator_replicas" {
  description = <<-EOT
    Cilium operator Deployment replica count (operator.replicas). Default null =
    derive it from the node count: 2 at two or more nodes (the chart's own
    default), and NOTHING at exactly one node, where the shipped floor's 1 stays
    effective because the chart's operator podAntiAffinity is
    requiredDuringScheduling on kubernetes.io/hostname and a second replica would
    stay Pending forever.

    Set a number to pin the count instead. It wins on BOTH delivery paths, and
    deterministically, which is the reason this input exists: the override can
    now reach both paths too (adr-0028 §(b)), but the module cannot introspect
    an opaque YAML string, so nothing there validates the count against the node
    set or reports which mechanism produced it.

    Pinning MORE replicas than there are declared nodes is REJECTED at plan time.
    The operator's podAntiAffinity is requiredDuringScheduling on
    kubernetes.io/hostname, so at most one pod places per node and the surplus is
    Pending forever — and because the value is baked into a create-only
    inlineManifest, the bootstrap that carries it cannot be corrected by a later
    apply. `var.nodes` IS the cluster this module builds, so this is one of the
    few non-convergent inputs the module can decide with certainty from its own
    declared state, in the same class as the odd-controlplane rule. It also
    bounds the value, which nothing else does.

    SEED knob on the default path (create-only inlineManifests): a changed value
    reaches an already-bootstrapped cluster only through cilium_self_management
    or a deliberate `-replace` of the render.
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
    Enable Hubble (hubble.enabled) for flow/metrics observability. Default false
    — the frozen bootstrap seed floor (helm/cilium-values.yaml) ships
    hubble.enabled: false for a deterministic render (see that file's header).
    When true, the observability layer ALSO forces hubble.tls.enabled = false:
    metrics-only scope (no Relay/UI — issue Non-goal), so the observer gRPC
    API's server TLS is unnecessary. The Hubble METRICS scrape endpoint
    (hubble-metrics Service, :9965) is gated by hubble.enabled + a non-empty
    hubble.metrics.enabled and is architecturally INDEPENDENT of
    hubble.tls.enabled (its own hubble.metrics.tls.enabled knob since Cilium
    1.16) — see ADR-0022 §(g). Enabling this on an already-running cluster
    (via the emitted self-management Application, cilium_self_management)
    changes the DaemonSet pod template (new ports + scrape annotations) -> a
    rolling restart; graceful-restart-gate on BGP-speaking clusters (UPGRADING.md).
  EOT
  type        = bool
  default     = false
}

variable "cilium_hubble_metrics" {
  description = <<-EOT
    Hubble metrics to export (hubble.metrics.enabled), e.g. ["dns","drop","tcp"].
    Default [] — with cilium_hubble_enabled=true and this left empty, the Hubble
    server is up but no metrics are exported (a documented half-on state — see
    README). Scrape wiring (ServiceMonitors/PodMonitors) stays consumer-side
    (issue Non-goal).

    Entries carry Hubble's own context syntax (e.g. "dns:query;ignoreAAAA",
    "flow:sourceContext=pod;destinationContext=pod"), so the guard below is an
    EXCLUSION rule, not an allowlist like cilium_agent_metric_overrides.
  EOT
  type        = list(string)
  default     = []
  nullable    = false

  # The chart renders entries unquoted; newlines inject keys and separators corrupt seed audits.
  validation {
    condition = alltrue([
      for m in var.cilium_hubble_metrics : !strcontains(m, "\n") && !strcontains(m, "\r") && !strcontains(m, "---")
    ])
    error_message = "each cilium_hubble_metrics entry must be a single line and must not contain \"---\": the chart renders these raw and unquoted into the cilium-config ConfigMap that is baked into the controlplane machine config, so a newline injects arbitrary ConfigMap keys and a document separator corrupts the rendered manifest."
  }
}

variable "cilium_agent_metric_overrides" {
  description = <<-EOT
    Cilium agent metric DELTA list (prometheus.metrics): "+name" ADDS a metric to
    the agent's default metric set, "-name" REMOVES one, e.g.
    ["+cilium_bpf_map_pressure", "-cilium_node_connectivity_status"]. It is NOT a
    wholesale replacement of that set, and — despite the similar name — it is
    unrelated to cilium_values_override, the free-form Helm-values escape hatch.
    Default [] (chart defaults). Effective only with cilium_agent_metrics = true:
    the chart renders the whole `prometheus` values block under
    `{{- if .Values.prometheus.enabled }}`.

    Layered into BOTH engines — the frozen bootstrap seed AND the emitted
    self-management Application. WHEN that reaches a running cluster is a
    separate question, and the answer is not "on the next apply": the seed
    render is frozen at first capture (terraform_data.cilium_render carries
    ignore_changes, and inlineManifests are create-only), so on an
    already-bootstrapped cluster this value arrives ONLY through the emitted
    Application (cilium_self_management = true), or at the next fresh bootstrap
    or deliberate -replace of the render. With self-management off on an
    existing cluster, setting this changes the plan and nothing else.
  EOT
  type        = list(string)
  default     = []
  nullable    = false

  # Keep the raw-rendered metric names free of YAML syntax and document separators.
  validation {
    condition = alltrue([
      for m in var.cilium_agent_metric_overrides : can(regex("^[+-][a-zA-Z_][a-zA-Z0-9_]*$", m))
    ])
    error_message = "each cilium_agent_metric_overrides entry must be \"+metric_name\" or \"-metric_name\" (letters, digits and underscores only): the chart renders these raw and unquoted into the cilium-config ConfigMap that is baked into the controlplane machine config, so an entry containing a newline, a space or \"---\" corrupts that document."
  }
}

variable "cilium_hubble_open_metrics" {
  description = <<-EOT
    Export the Hubble metrics endpoint in OpenMetrics format
    (hubble.metrics.enableOpenMetrics). Default false. Effective only with
    cilium_hubble_enabled = true — the chart renders the whole `hubble` values
    block under that gate.

    Layered into BOTH engines — the frozen bootstrap seed AND the emitted
    self-management Application — but see cilium_agent_metric_overrides for when
    that actually reaches a running cluster: the seed is frozen after first
    capture, so on an existing cluster this arrives only via the emitted
    Application, a fresh bootstrap, or a deliberate -replace.

    Also inert with an EMPTY cilium_hubble_metrics: the chart gates the
    OpenMetrics key on the metrics list being non-empty, so it would change the
    exposition format of an endpoint that exports nothing. A plan-time check
    warns about both conditions.

    ROLLS THE AGENTS, on the paths where the chart re-renders. This changes only
    the cilium-config ConfigMap (enable-hubble-open-metrics), but the floor sets
    rollOutCiliumPods: true (issue #270), so the chart stamps a ConfigMap
    checksum into the agent pod template and the change lands on the next sync.
    A manual `kubectl -n kube-system rollout restart ds/cilium` is STILL needed
    in ONE case: a consumer who set rollOutCiliumPods: false in their override,
    where the ConfigMap changes and the pod template deliberately does not. On
    the frozen seed and on the multi-source arm before its values file is
    regenerated, the live ConfigMap has not changed at all — a restart there
    reloads the same configuration, so deliver the change first (see the
    seed-freeze note above). UPGRADING.md separates the two.
  EOT
  type        = bool
  default     = false
  nullable    = false
}

variable "cilium_self_management" {
  description = <<-EOT
    Opt-in: emit a Cilium ArgoCD Application manifest (module OUTPUT only,
    cilium_self_management_app — never applied by the module) for the
    consumer's own GitOps to own and reconcile, as the Day-2 delivery path for
    a Cilium config change (including the observability inputs above) on an
    already-bootstrapped cluster — the frozen bootstrap inlineManifest seed is
    create-only and does not reconcile.

    Two emitted shapes, selected by cilium_self_management_values_source
    (adr-0028 §(b)):

      - unset (default) — a SINGLE-source Application whose
        `spec.source.helm.valuesObject` is the module-set layer (floor +
        computed-incl-observability) only. Byte-identical to what this module
        emitted before the values-source input existed.
      - set — a MULTI-SOURCE Application: the module-set layer and
        cilium_values_override are two ordered `valueFiles` entries read from the
        consumer's git repo, so HELM performs the merge at arbitrary depth
        (HCL has no generic recursive merge, and $values/… resolves only through
        spec.sources[].ref). `valuesObject` then carries the adr-0028 §(d) joint
        keys alone, re-asserted last so a missing or stale values file cannot
        strand the cluster without a kube-proxy replacement.

    Default false. Requires deploy_argocd = true AND deploy_cilium = true (first
    validation below).
  EOT
  type        = bool
  default     = false

  validation {
    condition     = !var.cilium_self_management || (var.deploy_argocd && var.deploy_cilium)
    error_message = "cilium_self_management requires deploy_argocd = true AND deploy_cilium = true (self-management hands the Day-2 config off from the module-delivered Cilium seed to the consumer's ArgoCD)."
  }

  # Overrides require the multi-source path; the single-source valuesObject cannot carry them.
  validation {
    condition     = !(var.cilium_self_management && var.cilium_values_override != "" && var.cilium_self_management_values_source == null)
    error_message = "cilium_self_management with a non-empty cilium_values_override requires cilium_self_management_values_source: without it the emitted Application is single-source and its valuesObject carries no override term, so a datapath-critical override (BGP control-plane / L2 announcements / bpf tuning) would be silently dropped when ArgoCD adopts Cilium. Set cilium_self_management_values_source to the git repo, revision and two file paths the Application should read its values layers from."
  }
}

variable "cilium_self_management_project" {
  description = <<-EOT
    ArgoCD AppProject the emitted Cilium Application targets. Default "default"
    (the always-present permissive project — the base defines exactly one
    AppProject, root-bootstrap, kubernetes/bootstrap/argocd/root-project.yaml.tmpl;
    no "cilium" project exists). STRONGLY RECOMMENDED to scope this to a
    consumer-created project that grants destination namespace kube-system +
    https://kubernetes.default.svc and the cluster-scoped resources Cilium
    needs (its CRDs, ClusterRoles, ClusterRoleBindings) in
    clusterResourceWhitelist — an under-scoped project makes the adopted
    Application inert/degraded. See README + ADR-0022.
  EOT
  type        = string
  default     = "default"
}

variable "cilium_self_management_values_source" {
  description = <<-EOT
    The git source the emitted Day-2 Application reads its Helm values layers
    from. Setting it switches cilium_self_management's emitted manifest from the
    single-source shape to a MULTI-SOURCE one; leaving it null keeps today's
    shape byte-identical. Required whenever cilium_values_override is non-empty
    alongside cilium_self_management (see that guard).

    Why a git source at all: composing two values layers so the consumer's wins
    means letting HELM merge them, and ArgoCD only orders `valueFiles` entries
    that resolve against a source — `$values/…` resolves ONLY through a sibling
    `spec.sources[]` entry carrying `ref`. A single-source chart Application
    cannot address a consumer-committed file at all.

    Attributes — all caller-supplied, the module dereferences none of them:
      repo_url      git repo ArgoCD reads the values from. Normally the consumer's
                    own app-of-apps repo (their cluster.yaml `repo.url`). It must
                    be registered in ArgoCD, and a scoped
                    cilium_self_management_project must list it in sourceRepos
                    ALONGSIDE cilium_chart_repository.
      revision      targetRevision for that source. The shipped shim inherits
                    cluster.target_revision, which is normally a branch — the
                    same branch the consumer's own root Application tracks, so
                    the values half of this Application moves the way every
                    other manifest in that repo does, and `git revert` is the
                    rollback. Understand the trade-off before changing it: a
                    branch means the values half follows the branch tip while
                    the chart half stays pinned to cilium_chart_version, so
                    "which values did this Application have last Tuesday" is
                    answerable only from git history. A tag or a SHA makes the
                    pair explicit at the cost of a second thing to bump.
      values_path   repo-root-relative path the consumer commits the
                    `cilium_self_management_values` output to.
      override_path repo-root-relative path the consumer commits their
                    cilium_values_override document to. Required when the
                    override is non-empty. The module never writes this file —
                    which keeps the override out of the emitted manifest, but does
                    NOT make it confidential: ArgoCD reads it as a plain Helm
                    values document and decrypts nothing (see the SECURITY note on
                    cilium_values_override). Must differ from values_path.

    The two artifacts are committed independently and nothing at sync time
    compares them: the emitted Application carries a
    `talos-platform-base.io/values-digest` annotation over the module-set layer
    so a consumer-side gate (or a reviewer) can catch a stale values_path file.
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

  # These values reach generated YAML comment headers through interpolation; reject line breaks.
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

  # Restrict URL forms and reject embedded credentials. AppProject sourceRepos owns authorization.
  validation {
    condition = var.cilium_self_management_values_source == null || can(regex(
      "^(https://[^@[:space:]]+|ssh://([A-Za-z0-9._-]+@)?[^@:[:space:]]+(:[0-9]+)?/[^@[:space:]]*|[A-Za-z0-9._-]+@[A-Za-z0-9.-]+:[^@[:space:]]+)$",
      try(var.cilium_self_management_values_source.repo_url, ""),
    ))
    error_message = "cilium_self_management_values_source.repo_url must be a git remote ArgoCD can resolve — \"https://host/org/repo.git\", \"ssh://git@host[:port]/org/repo.git\" or \"git@host:org/repo.git\" — and must carry no embedded PASSWORD (no \"https://user:token@host\", no \"ssh://user:pass@host\"): ArgoCD repository credentials belong in the repository registration, not in a manifest committed to git. An SSH USERNAME is fine, and is the documented form."
  }

  # Using one path for both layers would overwrite the consumer override with module values.
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
    postfinance/kubelet-csr-approver PROVIDER_REGEX — a cluster-wide regex every
    kubelet-serving CSR's SAN DNS name must additionally match. Default ".*"
    (no extra constraint): the approver still binds each DNS SAN to the requesting
    node via HasPrefix(sanDNSName, hostname) regardless, so ".*" is not "no
    binding". Tighten to your node-naming pattern (e.g. "^node-.*$") for a
    cluster-wide pattern gate on top. SEED knob (create-only inlineManifest):
    changing it re-renders the machine config but does NOT update a running
    approver — see UPGRADING.md.
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
    # Document separators and newlines would corrupt the seed audit parser.
    condition     = !strcontains(var.cert_approver_provider_regex, "---") && !strcontains(var.cert_approver_provider_regex, "\n")
    error_message = "cert_approver_provider_regex must not contain a YAML document separator (---) or a newline."
  }
}

variable "cert_approver_provider_ip_prefixes" {
  description = <<-EOT
    postfinance/kubelet-csr-approver PROVIDER_IP_PREFIXES — the CIDR set every
    kubelet-serving CSR's SAN IP address must fall within. Default
    ["0.0.0.0/0", "::/0"] (all IPs — the safe out-of-the-box floor). NOTE: an
    EMPTY list would DENY every CSR carrying an IP SAN (the approver checks each
    IP SAN for set membership unconditionally), so the default is all-IPs, not
    empty. Tighten to your node subnets to bind IP SANs to the cluster's
    addresses. SEED knob (create-only) — see cert_approver_provider_regex.
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
    cert-approver Deployment replica count. Default 1 (minimal footprint; a
    single-node/edge cluster must not be forced to 2). Raise it (e.g. 2) to opt
    into HA — replicas > 1 AUTO-enables leader-election and the
    coordination.k8s.io/leases RBAC, so the default replicas:1 keeps least
    privilege (no leases grant). SEED knob (create-only): on a running cluster,
    basic redundancy is a `kubectl scale`; enabling leader-election Day-2 needs a
    manual apply / re-seed. postfinance denies terminally, so a down approver
    stalls new serving-cert issuance — HA matters more than under the old approver.
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
    apply_mode for the controlplane machine-config apply. Accepted: auto |
    reboot | no_reboot | staged — the set the provider has carried since 0.7.0.
    The provider's fifth value "staged_if_needing_reboot" is deliberately NOT
    accepted here: the pinned provider offers it, but gates it on its own bundled
    Talos SDK and warns it always resolves to "auto" on Talos 1.14+ — the version
    line the pin exists to reach — so admitting it would buy a spelling, not a
    behaviour. See knowledge/decisions/0026-machine-config-apply-mode.md.
    Default "auto" — the provider's own default, and the ONLY value that works
    on Day-0:
    the first apply to a maintenance-mode node IS the install, so a staging mode
    writes the config without installing and talos_machine_bootstrap then runs
    against a node that never left maintenance mode.
    Set "staged" for a Day-2 window on nodes that must not reboot from the apply:
    the config is written to be picked up at the next boot, and the reboot becomes
    an out-of-band, health-gated operator step (one node at a time). Between
    staging and that reboot, tofu state and the node's effective config diverge
    with no drift signal — the window is the operator's to close.
    "reboot" forces a reboot of every controlplane on the apply even when the
    change needs none — a simultaneous reboot of the whole role, i.e. etcd
    quorum loss. "no_reboot" fails the apply when the change needs a reboot.
  EOT
  type        = string
  default     = "auto"
  # An explicit null from a consumer shim selects the default.
  nullable = false

  validation {
    condition     = contains(["auto", "reboot", "no_reboot", "staged"], var.controlplane_apply_mode)
    error_message = "controlplane_apply_mode must be one of: auto, reboot, no_reboot, staged."
  }
}

variable "worker_apply_mode" {
  description = <<-EOT
    apply_mode for the worker machine-config applies — same accepted set, same
    Day-0 constraint and same out-of-band reboot obligation as
    controlplane_apply_mode.
    Separate input because the two roles roll under different gates: controlplanes
    under etcd quorum, workers under whatever the workload requires (storage
    replication, quorum-based stores). A worker set applied with the default
    reboots unsequenced, so a stateful worker set is set to "staged" for the
    window and rebooted one node at a time. Revert to "auto" only AFTER every
    node of the role has been rebooted: an apply_mode change alone reaches the
    provider's Update path, so flipping back while configs are still staged
    re-applies them in "auto" mode and reboots exactly the nodes not yet gated.
  EOT
  type        = string
  default     = "auto"
  # An explicit null from a consumer shim selects the default.
  nullable = false

  validation {
    condition     = contains(["auto", "reboot", "no_reboot", "staged"], var.worker_apply_mode)
    error_message = "worker_apply_mode must be one of: auto, reboot, no_reboot, staged."
  }
}
