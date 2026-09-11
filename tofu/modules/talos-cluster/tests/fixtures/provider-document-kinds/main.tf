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

locals {
  # The rendered configuration is a multi-document stream, and several of its
  # documents carry key material: the leading v1alpha1 one (cluster CA key, etcd
  # CA key, service-account key, bootstrap token) and the generated Kube*CAConfig
  # / KubeEtcdEncryptionConfig / KubeServiceAccountConfig documents. The probe
  # therefore never exposes the stream. `documents` is a kind-keyed map narrowed
  # to an ALLOWLIST: adding a kind to it is a decision that this document carries
  # no key material, taken once here rather than at each assertion site.
  rendered  = nonsensitive(data.talos_machine_configuration.probe.machine_configuration)
  separator = "\n---\n"
  chunks    = split(local.separator, local.rendered)
  v1alpha1  = local.chunks[0]

  assertable_kinds = [
    "UserVolumeConfig",
    "SecurityProfileConfig",
    "FilesystemTrimConfig",
    "KubeNodeConfig",
    "UnattendedInstallConfig",
    "HostnameConfig",
  ]

  # kind -> every document of that kind, joined. A kind the provider emits more
  # than once therefore reaches an assertion in full, so a negative assertion
  # cannot pass by reading only the first instance.
  documents = {
    for kind in local.assertable_kinds :
    kind => join(local.separator, [
      for chunk in local.chunks : chunk
      if contains(split("\n", chunk), "kind: ${kind}")
    ])
  }
}

output "document_kinds" {
  description = "Multi-document kinds present in the rendered machine configuration, in document order. The leading v1alpha1 document carries `version:` rather than `kind:` and is deliberately not listed. Kinds only — no document bodies, so this output is safe regardless of which documents carry key material."
  value = [
    for line in split("\n", join(local.separator, slice(local.chunks, 1, length(local.chunks)))) :
    trimspace(trimprefix(line, "kind:"))
    if startswith(line, "kind:")
  ]
}

output "documents" {
  description = "Bodies of the document kinds the probe is allowed to assert on, keyed by kind, each holding every instance of that kind. Kinds outside the allowlist in locals are absent by construction, because the rendered stream also carries the PKI documents."
  value       = local.documents
}

output "v1alpha1_install_disk" {
  description = "The value of `machine.install.disk` in the leading v1alpha1 document, and nothing else from it. The module writes an install block for every node, so a probe needs to see that the block still takes a patch — but the document around it holds the run's key material, so this extracts ONE scalar rather than a block: a widened match cannot spill a key into a failure message. Empty when the key is absent."
  value       = try(regex("(?m)^ {8}disk: (.*)$", local.v1alpha1)[0], "")
}
