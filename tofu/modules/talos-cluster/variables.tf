# Inputs for the talos-cluster module.
#
# The module is backend- and caller-agnostic: a consumer's root module maps
# its cluster.yaml onto these variables and supplies the `provider "talos"`
# block plus the state backend. Cluster identity (endpoint, node IPs, NTP,
# install disk, registry mirrors) is caller-supplied via patches — the module
# ships none of its own. A direct `tofu apply` from a workstation and any
# higher-level orchestrator use the identical variable contract.

variable "cluster_name" {
  description = "Name of the Talos cluster (e.g. \"dhq\"). Used in PKI CNs and config."
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
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+", var.talos_version))
    error_message = "talos_version must be a v-prefixed semver, e.g. v1.13.0."
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
    condition     = var.talos_install_version == "" || can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+", var.talos_install_version))
    error_message = "talos_install_version must be empty (= falls back to talos_version) or a v-prefixed semver, e.g. v1.13.1."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version to install, e.g. \"v1.36.0\"."
  type        = string

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+", var.kubernetes_version))
    error_message = "kubernetes_version must be a v-prefixed semver, e.g. v1.36.0."
  }
}

variable "nodes" {
  description = <<-EOT
    Bare-metal nodes that make up the cluster. Each node must already be
    PXE-booted into Talos maintenance mode (reachable at `ip` on the Talos
    API port). The module applies the machine config, it does not provision
    the hardware or boot the nodes.

    Kubernetes node roles are ONLY `controlplane` or `worker`. Hardware
    specialisation (GPU, single-board-computer, storage) is NOT a role — it
    is expressed via `class`, which selects an Image-Factory + patch profile
    from var.classes.

    `class` (optional, default "standard") must exist as a key in var.classes.
    `config_patches` (optional) are machine-config patches applied to THIS
    node only — use it for genuinely per-node values such as a NIC-specific
    bridge config; the caller renders the concrete value into the YAML string.
  EOT
  type = list(object({
    hostname       = string
    ip             = string
    role           = string                       # "controlplane" | "worker"
    class          = optional(string, "standard") # must exist as key in var.classes
    config_patches = optional(list(string), [])   # per-node patches (e.g. NIC binding)
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

variable "classes" {
  description = <<-EOT
    Per node-class Image-Factory + machine-config-patch profile. Key = class
    name (matching `node.class`). The "standard" class is mandatory; add more
    (e.g. "gpu", "pi") as the cluster needs. Each class carries:

      - architecture: "amd64" | "arm64" — installer-image architecture for
        nodes of this class. This is what unblocks ARM single-board computers
        (e.g. a Raspberry Pi worker uses architecture = "arm64").
      - extensions: Image-Factory system-extension package names (e.g.
        "siderolabs/drbd", "siderolabs/nvidia-container-toolkit-lts"). Empty
        list = default installer with no system extensions for that class.
      - overlay: optional SBC/board overlay for ARM single-board computers.
        When set, the schematic is built with the board overlay (e.g.
        name = "rpi_generic", image = "siderolabs/sbc-raspberrypi" for a
        Raspberry Pi). Leave null for ordinary x86/metal nodes.
      - config_patches: machine-config patches applied to EVERY node of this
        class, on top of the all-nodes (var.config_patches) and role patches.

    The installer image is always the non-SecureBoot metal installer (NEVER
    the SecureBoot variant, per the base AGENTS.md Hard Constraint).
  EOT
  type = map(object({
    architecture = optional(string, "amd64")
    extensions   = optional(list(string), [])
    overlay = optional(object({
      name    = string
      image   = string
      options = optional(map(string), null)
    }), null)
    config_patches = optional(list(string), [])
  }))
  default = {
    standard = { architecture = "amd64" }
  }

  validation {
    condition     = contains(keys(var.classes), "standard")
    error_message = "classes must define a 'standard' class — node.class defaults to it."
  }

  validation {
    condition     = alltrue([for c in var.classes : contains(["amd64", "arm64"], c.architecture)])
    error_message = "Each class.architecture must be \"amd64\" or \"arm64\"."
  }
}

variable "cluster_endpoint" {
  description = <<-EOT
    Kubernetes API endpoint the cluster advertises, e.g.
    "https://dhq.devoba.de:6443" or a controlplane VIP. Caller-supplied
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
}

variable "service_cidr" {
  description = "Service network CIDR(s). Drives Talos cluster.network.serviceSubnets. One entry for single-stack; v4+v6 when dual_stack = true."
  type        = list(string)
  default     = ["10.96.0.0/12"]

  validation {
    condition     = length(var.service_cidr) >= 1
    error_message = "service_cidr must contain at least one CIDR."
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
    Enable Cilium Gateway API support in the seed. Default true — the base Hard
    Constraint is "Gateway API only — no Ingress". When true the module renders
    the Cilium gateway controller AND seeds the Gateway API CRDs (from
    cilium_gateway_api_crds_url) via cluster.extraManifests, applied before the
    GatewayClass by Talos' CRD-first manifest sort. Cilium 1.19 requires Gateway
    API v1.4.1 standard channel (TLSRoute is experimental and degrades gracefully
    if its CRD is absent).
  EOT
  type        = bool
  default     = true
}

variable "cilium_gateway_api_crds_url" {
  description = <<-EOT
    URL of the Gateway API CRD manifest seeded via cluster.extraManifests when
    cilium_gateway_api is true. Default is the v1.4.1 STANDARD channel bundle
    (matches Cilium 1.19). Talos fetches it at bootstrap (no plan-time call), and
    retries until it applies. Override for: an air-gapped mirror; or the
    EXPERIMENTAL channel bundle if you need TLSRoute. NOTE: fetched by URL with no
    digest pin — point only at a source you trust. Empty = seed no CRDs (you must
    provide them another way).
  EOT
  type        = string
  default     = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.1/standard-install.yaml"
}
