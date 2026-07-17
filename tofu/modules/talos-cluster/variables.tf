# Inputs for the talos-cluster module.
#
# The module is backend- and caller-agnostic: a consumer's root module maps
# its cluster.yaml onto these variables and supplies the `provider "talos"`
# block plus the state backend. Cluster identity (endpoint, node IPs, NTP,
# install disk, registry mirrors) is caller-supplied via patches — the module
# ships none of its own. A direct `tofu apply` from a workstation and any
# higher-level orchestrator use the identical variable contract.

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
  type = list(object({
    hostname              = string
    ip                    = string
    role                  = string                     # "controlplane" | "worker"
    image                 = string                     # must exist as key in var.images
    hardware_capabilities = optional(list(string), []) # keys in var.hardware_capabilities
    config_patches        = optional(list(string), []) # per-node patches (e.g. NIC binding)
  }))

  validation {
    condition     = length([for n in var.nodes : n if n.role == "controlplane"]) >= 1
    error_message = "At least one controlplane node is required."
  }

  validation {
    condition     = alltrue([for n in var.nodes : contains(["controlplane", "worker"], n.role)])
    error_message = "Each node.role must be either \"controlplane\" or \"worker\"."
  }

  # Hostnames key the per-node apply resource; duplicates would silently collapse
  # a node out of the apply set. IPs target talosctl; duplicates make bootstrap
  # ambiguous. Catch both at plan time rather than as a silent mis-provision.
  validation {
    condition     = length(distinct([for n in var.nodes : n.hostname])) == length(var.nodes)
    error_message = "node.hostname values must be unique."
  }

  validation {
    condition     = length(distinct([for n in var.nodes : n.ip])) == length(var.nodes)
    error_message = "node.ip values must be unique."
  }
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

  # AC9 rules W/D/E/B on extra_kernel_args — lexical guardrails against a
  # documented footgun, not a security boundary (a consumer owns their repo).
  # Each validation is self-contained (references only var.images) and each
  # message names the offending image + element via an identical naming clause
  # (AC9's naming fence — grep-counted at exactly four occurrences below).
  # Empty-list safety: alltrue([]) is true, so the default [] passes every rule.

  # Rule W (whitespace) — a space smuggles a second arg past karg_conflicts,
  # which keys on "=" and never on whitespace. ASCII-scoped by design: RE2
  # [[:space:]] does not match U+00A0 and similar, which is not a cmdline-smuggle
  # vector (the kernel splits the cmdline on ASCII space/tab, so an NBSP stays
  # inside the token).
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

  # Rule D (removal spelling) — the karg removal/prefix syntax (§Non-Goals);
  # the conflict guard cannot see it.
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

  # Rule E (empty key) — rejects the bare empty string AND a leading '=' (both
  # key as "" via element(split("=", a), 0) and would otherwise defeat the
  # guard's =-keying; a leading '=' also bypasses rule B's key match).
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

  # Rule B (debugfs key) — the debugfs KEY at any value is rejected (AGENTS.md
  # §Hard Constraints forbids the `off` value that boot-loops Talos with
  # Cilium; this base's own gate greps only this repo's kubernetes/**/tofu/**
  # PR diff and can never see a consumer's cluster.yaml). Matches the key,
  # never the forbidden value literal, so this file stays clean of it.
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

# ---------------------------------------------------------------------------
# ArgoCD delivery (Layer-1 substrate, C4 layer model). ArgoCD is baked into the
# controlplane machine config as a Talos cluster.inlineManifest
# (data.helm_template, rendered locally), so it comes up with the bootstrap.
# ---------------------------------------------------------------------------

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
  EOT
  type        = string
  default     = "9.4.5"
}

variable "argocd_values_override" {
  description = <<-EOT
    Optional consumer Helm values, MERGED on top of the shipped
    helm/argocd-values.yaml (helm merges value files; later wins) — not a
    wholesale replacement. Empty = just the shipped values (slim, ksops). The
    steady state (cert-manager cert, RBAC, OIDC) arrives via ArgoCD
    self-management.
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

# ---------------------------------------------------------------------------
# Cluster network — pod / service CIDRs (install-time-fixed in Talos)
# ---------------------------------------------------------------------------
# These are first-class because a pod CIDR is irreversible at bootstrap AND it
# couples Talos (cluster.network.{podSubnets,serviceSubnets}) to Cilium
# (native-routing / masquerade / encryption strict-mode CIDR). Setting it in one
# place keeps both sides coherent; the defaults match Talos' own defaults, so a
# caller that does not care gets identical behaviour. Lists carry both families
# when dual_stack = true.

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

# ---------------------------------------------------------------------------
# Cilium delivery (Layer-1 substrate). Cilium is rendered locally with
# data.helm_template and baked into the controlplane cluster.inlineManifests as
# a bootstrap SEED, so it comes up as the CNI with the bootstrap — the same
# local-render → inlineManifest pattern as deploy_argocd. The module disables
# the Talos default CNI (cni.name = none) and kube-proxy when deploy_cilium is
# true, so Flannel never comes up.
#
# inlineManifests are create-only (Talos never edits a resource it created), so
# this is a SEED, not a reconciled deployment: cilium_chart_version is a SEED
# knob, not an upgrade knob (parity with argocd_chart_version). Install-time
# Cilium settings (routing mode, encryption, kube-proxy replacement, MTU) belong
# in the seed via the typed inputs below + cilium_values_override; runtime-mutable
# config (Hubble export, L2/BGP announcements) is Day-2 Cilium self-management.
# ---------------------------------------------------------------------------

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
  EOT
  type        = string
  default     = "1.19.4"
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
  EOT
  type        = string
  default     = ""
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
}

variable "cilium_kube_proxy_replacement" {
  description = "Run Cilium as the kube-proxy replacement (against Talos KubePrism). When true the module also sets Talos cluster.proxy.disabled. Install-time-fixed."
  type        = bool
  default     = true
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

  # Catch an obviously malformed key at plan time rather than as a post-boot CNI
  # failure. Cilium IPsec keys start with a numeric key id, e.g.
  # "3 rfc4106(gcm(aes)) <hex> 128". Permissive on purpose (multiple algos).
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
    gateway controller errors (harmless to the CNI). Cilium 1.19 needs Gateway API
    v1.4.1 standard channel (TLSRoute is experimental and degrades gracefully).
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
    dependency. Cilium 1.19 needs Gateway API v1.4.1 STANDARD channel:
    https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml
    (use the EXPERIMENTAL bundle for TLSRoute). Point only at a source you trust —
    no digest pin; extraManifests applies WHATEVER the URL returns at the most
    privileged moment of bootstrap. WARNING: a failed/blocked fetch is NOT graceful —
    Talos' ExtraManifestController crashloops with backoff and bootstrap does not
    complete cleanly (verified against Talos v1.10/v1.11 docs). Use an internal
    mirror for restricted-egress, or leave empty and apply via GitOps.
  EOT
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# cert-approver (postfinance/kubelet-csr-approver) — per-cluster config surface.
# The seed itself is UNCONDITIONAL (always delivered); these knobs tune the
# SAN-to-node binding. Defaults keep every cluster booting + approving
# out-of-the-box AND carry the always-on per-node DNS-SAN binding (the approver
# binds each DNS SAN to the requesting node's hostname regardless of the regex).
# See knowledge/decisions/0019-postfinance-kubelet-csr-approver.md.
# ---------------------------------------------------------------------------

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
    # The seed's audit outputs parse the rendered manifest by splitting on the
    # YAML document separator "---"; a regex containing it (or a newline) would
    # corrupt that parse. A compilable regex can still contain "---".
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
