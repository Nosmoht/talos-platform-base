# Provider document-kind probe.
#
# The module's four config_patches inputs are opaque YAML, which reads as "any
# Talos machine-config field is reachable without a module change". That is only
# true for document kinds the PINNED provider's machinery registry knows: the
# provider decodes every patch locally before rendering, and an unknown kind is
# a hard error, not a passthrough. So the reachable surface is bounded by the
# provider version, not by the Talos version a consumer pins — a coupling
# nothing else in this repo observes (knowledge/decisions/0026 records the same
# unbound-mirror problem for apply_mode).
#
# Local-only, hence offline: talos_machine_secrets generates its PKI in memory
# and talos_machine_configuration renders from that, so the probe needs neither
# a cluster nor the Image Factory and can sit in tofu:test:offline.
#
# RFC5737 documentation addresses throughout — the PKI is generated per run and
# discarded with the test state.

variable "talos_version" {
  description = "Machine-config schema pin the probe generates against."
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version the probe generates against."
  type        = string
}

variable "config_patches" {
  description = "Patches handed to the provider verbatim, exactly as the module hands over its own four lists."
  type        = list(string)
  default     = []
}

resource "talos_machine_secrets" "probe" {
  talos_version = var.talos_version
}

data "talos_machine_configuration" "probe" {
  cluster_name       = "document-kind-probe"
  cluster_endpoint   = "https://192.0.2.1:6443"
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.probe.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  config_patches     = var.config_patches
}

output "document_kinds" {
  description = "Multi-document kinds present in the rendered machine configuration, in document order. The leading v1alpha1 document carries `version:` rather than `kind:` and is deliberately not listed."
  value = [
    for line in split("\n", nonsensitive(data.talos_machine_configuration.probe.machine_configuration)) :
    trimspace(trimprefix(line, "kind:"))
    if startswith(line, "kind:")
  ]
}
