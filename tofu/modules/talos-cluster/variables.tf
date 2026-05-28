# Inputs for the talos-cluster module.
#
# The shape mirrors the XCluster CRD schema in talos-platform-apps
# (sub-layers/lifecycle/components/compositions): a Crossplane tf.Workspace
# maps XCluster.spec fields onto these variables, and the Stage-0 root module
# passes the same values from cluster.yaml. One module, two callers, identical
# variable contract.

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
    API port) — see the lifecycle/ipxe component. The module applies the
    machine config, it does not provision the hardware or boot the nodes.

    `class` (optional, default "standard") selects the Image-Factory
    schematic from var.extensions — used to install Talos with the right
    set of system extensions (e.g. drbd, qemu-guest-agent, nvidia drivers).
  EOT
  type = list(object({
    hostname = string
    ip       = string
    role     = string                       # "controlplane" | "worker"
    class    = optional(string, "standard") # must exist as key in var.extensions
  }))

  validation {
    condition     = length([for n in var.nodes : n if n.role == "controlplane"]) >= 1
    error_message = "At least one controlplane node is required."
  }

  validation {
    condition     = alltrue([for n in var.nodes : contains(["controlplane", "worker"], n.role)])
    error_message = "Each node.role must be either \"controlplane\" or \"worker\"."
  }
}

variable "extensions" {
  description = <<-EOT
    Image-Factory system extensions per node class. Key = class name
    (matching `node.class`), value = list of extension package names like
    "siderolabs/qemu-guest-agent" or "siderolabs/drbd". The module resolves
    each list against the Talos Image Factory at var.talos_version, derives
    a schematic ID, and uses the resulting installer image
    (metal-installer — NEVER metal-installer-secureboot per the base
    AGENTS.md Hard Constraint) for nodes of that class.

    Empty list → default Talos installer (no extensions) for that class.
    Class "standard" is mandatory; "gpu" / "pi" are conventional but optional.
  EOT
  type        = map(list(string))
  default     = { standard = [], gpu = [], pi = [] }

  validation {
    condition     = contains(keys(var.extensions), "standard")
    error_message = "extensions must define a 'standard' class (even if empty) — node.class defaults to it."
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
