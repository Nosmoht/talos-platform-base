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

    The installer image is always metal-installer (NEVER
    metal-installer-secureboot, per the base AGENTS.md Hard Constraint).
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
