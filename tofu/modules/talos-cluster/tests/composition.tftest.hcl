# Composition regression suite (ADR base:node-capability-composition).
#
# Proves the γ' composition + its hard-error invariants. command = plan (no
# apply). The valid run resolves the live Image Factory (network) for schematic
# dedup; the expect_failures runs lock in each guard (red-green: revert the guard
# and the matching run stops failing). NETWORK REQUIRED — run via `task tofu:test`,
# NOT part of the offline `task tofu:ci`.
#
# Not covered (no triggerable input via the real base catalog — the shipped
# profiles never collide): module-param / sysctl / kernel-arg conflict guards.
# Those are defensive for future catalog additions; a colliding synthetic catalog
# would be needed to exercise them.

provider "talos" {}
provider "helm" {}

variables {
  cluster_name       = "test"
  cluster_endpoint   = "https://192.0.2.1:6443"
  talos_version      = "v1.12.6"
  kubernetes_version = "v1.35.0"
  deploy_argocd      = false
  deploy_cilium      = false

  images = {
    intel = { architecture = "amd64", cpu_vendor = "intel", extensions = ["siderolabs/intel-ucode"] }
    arm   = { architecture = "arm64", cpu_vendor = "arm", extensions = [], overlay = { name = "rpi_generic", image = "siderolabs/sbc-raspberrypi" } }
  }
  hardware_capabilities = {
    storage-replicated = { requires_features = ["drbd-kernel-module"], provisioning_profiles = ["drbd"], emits_label = "platform.io/hardware-capability.storage-replicated" }
    virt-passthrough   = { requires_features = ["vt-x-or-amd-v", "kvm-kernel-module", "iommu-enabled"], provisioning_profiles = ["iommu"], emits_label = "platform.io/hardware-capability.virt-passthrough" }
  }
  nodes = [
    { hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["storage-replicated"] },
  ]
}

# Valid topology: dedup + determinism. w-1 and w-2 list the same two capabilities
# in REVERSED order -> identical effective provisioning -> one schematic.
run "valid_dedup_and_determinism" {
  command = plan
  variables {
    nodes = [
      { hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["storage-replicated"] },
      { hostname = "w-1", ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = ["storage-replicated", "virt-passthrough"] },
      { hostname = "w-2", ip = "192.0.2.22", role = "worker", image = "intel", hardware_capabilities = ["virt-passthrough", "storage-replicated"] },
      { hostname = "node-arm", ip = "192.0.2.41", role = "worker", image = "arm", hardware_capabilities = [] },
    ]
  }
  assert {
    condition     = output.distinct_schematic_count == 3
    error_message = "expected 3 distinct schematics (cp storage / w storage+virt [w-1==w-2 dedup] / arm), got ${output.distinct_schematic_count}"
  }
  assert {
    condition     = output.node_schematic_hashes["w-1"] == output.node_schematic_hashes["w-2"]
    error_message = "determinism: reversed-capability-order nodes w-1 and w-2 must hash identically"
  }
  assert {
    condition     = output.node_schematic_hashes["cp-1"] != output.node_schematic_hashes["w-1"]
    error_message = "storage-only and storage+virt nodes must NOT share a schematic (virt adds IOMMU kernel args)"
  }
}

# Symmetry FORWARD: a provisioned required-feature with no profile providing it.
run "symmetry_forward_violation" {
  command = plan
  variables {
    hardware_capabilities = {
      bad = { requires_features = ["drbd-kernel-module"], provisioning_profiles = [], emits_label = "platform.io/hardware-capability.bad" }
    }
    nodes = [{ hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["bad"] }]
  }
  expect_failures = [terraform_data.composition_guards]
}

# Symmetry INVERSE: a selected profile provides an atom the composite omits.
run "symmetry_inverse_violation" {
  command = plan
  variables {
    hardware_capabilities = {
      bad = { requires_features = [], provisioning_profiles = ["drbd"], emits_label = "platform.io/hardware-capability.bad" }
    }
    nodes = [{ hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["bad"] }]
  }
  expect_failures = [terraform_data.composition_guards]
}

# Per-CAPABILITY symmetry (ADR §step-3 "both directions"): two individually
# malformed capabilities that COMPENSATE in the per-node union — a forward
# violator (requires a provisioned atom, no profile) + an inverse violator
# (a profile providing that atom, not in requires) — on ONE node must STILL be
# rejected. Under the prior per-node-union check this pair PASSED (Codex review
# finding). Red-green: revert composition.tf to the per-node-union symmetry and
# this run stops failing.
run "symmetry_per_capability_not_masked_by_union" {
  command = plan
  variables {
    hardware_capabilities = {
      label_only     = { requires_features = ["drbd-kernel-module"], provisioning_profiles = [], emits_label = "platform.io/hardware-capability.label-only" }
      provision_only = { requires_features = [], provisioning_profiles = ["drbd"], emits_label = "platform.io/hardware-capability.provision-only" }
    }
    nodes = [{ hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["label_only", "provision_only"] }]
  }
  expect_failures = [terraform_data.composition_guards]
}

# Variant mismatch: an arm node selecting the iommu profile (variants intel|amd).
run "variant_mismatch" {
  command = plan
  variables {
    hardware_capabilities = {
      vp = { requires_features = ["iommu-enabled"], provisioning_profiles = ["iommu"], emits_label = "platform.io/hardware-capability.vp" }
    }
    nodes = [
      { hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      { hostname = "arm-1", ip = "192.0.2.41", role = "worker", image = "arm", hardware_capabilities = ["vp"] },
    ]
  }
  expect_failures = [terraform_data.composition_guards]
}

# Undefined image reference.
run "undefined_image" {
  command = plan
  variables {
    nodes = [{ hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "ghost", hardware_capabilities = [] }]
  }
  expect_failures = [terraform_data.composition_guards]
}

# Undefined capability reference.
run "undefined_capability" {
  command = plan
  variables {
    nodes = [{ hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["ghost"] }]
  }
  expect_failures = [terraform_data.composition_guards]
}

# H1: emits_label must be in the platform.io/hardware-capability.* namespace
# (reserved hardware-feature.* forbidden) — a variable validation, fails pre-plan.
run "emits_label_reserved_namespace_rejected" {
  command = plan
  variables {
    hardware_capabilities = {
      forge = { requires_features = [], provisioning_profiles = [], emits_label = "platform.io/hardware-feature.iommu-enabled" }
    }
    nodes = [{ hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }]
  }
  expect_failures = [var.hardware_capabilities]
}

# argocd-namespace seed carries the PSA floor + the six recommended labels.
# Spec: AGENTS.md §Hard Constraints ("Kubernetes recommended labels on all
# resources") + the PSA floor (enforce: baseline) preserved from the retired
# kubernetes/bootstrap/argocd/namespace.yaml — the module is now the sole creator
# of the namespace, so the create-only inlineManifest seed must carry these
# itself. Red-green: drop labels from local.argocd_namespace_labels (main.tf) and
# both asserts fail. deploy_argocd = true renders the argo-cd chart (NETWORK) and
# needs a prefix-valid age key — already part of the network-gated `task tofu:test`.
run "argocd_namespace_seed_carries_psa_floor_and_recommended_labels" {
  command = plan
  variables {
    deploy_argocd = true
    sops_age_key  = "AGE-SECRET-KEY-1TESTONLYPLACEHOLDERNOTAREALKEY00000000000000000000000000000"
    nodes = [
      { hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    ]
  }
  assert {
    condition     = lookup(output.argocd_namespace_labels, "pod-security.kubernetes.io/enforce", "<absent>") == "baseline"
    error_message = "AGENTS.md §Hard Constraints + namespace.yaml PSA floor: the module-seeded argocd namespace must enforce PSA baseline; got '${lookup(output.argocd_namespace_labels, "pod-security.kubernetes.io/enforce", "<absent>")}'"
  }
  assert {
    condition = length(setsubtract(
      ["app.kubernetes.io/name", "app.kubernetes.io/instance", "app.kubernetes.io/version", "app.kubernetes.io/component", "app.kubernetes.io/part-of", "app.kubernetes.io/managed-by"],
      keys(output.argocd_namespace_labels)
    )) == 0
    error_message = "AGENTS.md §Hard Constraints: all six app.kubernetes.io/* recommended labels must be seeded on the argocd namespace; missing: ${jsonencode(setsubtract(["app.kubernetes.io/name", "app.kubernetes.io/instance", "app.kubernetes.io/version", "app.kubernetes.io/component", "app.kubernetes.io/part-of", "app.kubernetes.io/managed-by"], keys(output.argocd_namespace_labels)))}"
  }
}
