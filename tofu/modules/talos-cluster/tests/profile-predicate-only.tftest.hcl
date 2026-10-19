# ./tests/fixtures/real-catalog symlinks the shipped composition.tf, variables.tf
# and profiles.tf; moving local.node_effective or local.provisioning_profiles out
# of those files makes these runs assert nothing.

variables {
  cluster_name       = "test"
  cluster_endpoint   = "https://192.0.2.1:6443"
  talos_version      = "v1.13.9"
  kubernetes_version = "v1.36.3"

  images = {
    intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [] }
    amd   = { architecture = "amd64", cpu_vendor = "amd", extensions = [] }
  }

  hardware_capabilities = {
    virt = {
      requires_features     = ["iommu-enabled"]
      provisioning_profiles = ["iommu"]
      emits_label           = "platform.io/hardware-capability.virt"
    }
  }
}

# Set equality: any arg beyond the predicate arg violates the requirement.
run "catalog_iommu_variants_carry_exactly_their_predicate_arg" {
  command = plan
  module { source = "./tests/fixtures/real-catalog" }

  variables {
    nodes = {
      cp-1 = { ip = "192.0.2.10", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.11", role = "worker", image = "intel", hardware_capabilities = ["virt"] },
    }
  }

  assert {
    condition     = join(",", output.catalog_profile_kernel_args["iommu.intel"]) == "intel_iommu=on"
    error_message = "iommu.intel kernel_args must equal exactly [\"intel_iommu=on\"] — the arg the iommu-enabled atom's presence_predicate names (platform-hardware-features.yaml). Got: ${jsonencode(output.catalog_profile_kernel_args["iommu.intel"])}. Adding host tuning here spends a kernel-arg key the consumer cannot get back (ADR-0016)."
  }

  assert {
    condition     = join(",", output.catalog_profile_kernel_args["iommu.amd"]) == "amd_iommu=on"
    error_message = "iommu.amd kernel_args must equal exactly [\"amd_iommu=on\"]. Got: ${jsonencode(output.catalog_profile_kernel_args["iommu.amd"])}."
  }

  # Kargs resolve through variants; a top-level list would bypass vendor resolution.
  assert {
    condition     = length(output.catalog_profile_kernel_args["iommu"]) == 0
    error_message = "the iommu profile's top-level kernel_args must be empty — vendor variants carry the args. Got: ${jsonencode(output.catalog_profile_kernel_args["iommu"])}."
  }
}

run "catalog_profiles_without_predicate_args_carry_none" {
  command = plan
  module { source = "./tests/fixtures/real-catalog" }

  variables {
    nodes = {
      cp-1 = { ip = "192.0.2.10", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.11", role = "worker", image = "intel", hardware_capabilities = ["virt"] },
    }
  }

  assert {
    condition     = length(output.catalog_profile_provides["nvidia-lts"]) == 0 && length(output.catalog_profile_kernel_args["nvidia-lts"]) == 0
    error_message = "nvidia-lts provides no atom, so no presence_predicate names a kernel arg for it — its kernel_args must be empty. Got provides=${jsonencode(output.catalog_profile_provides["nvidia-lts"])} kernel_args=${jsonencode(output.catalog_profile_kernel_args["nvidia-lts"])}."
  }

  assert {
    condition     = length(output.catalog_profile_kernel_args["drbd"]) == 0
    error_message = "the drbd-kernel-module predicate names no kernel arg, so the drbd profile must carry none. Got: ${jsonencode(output.catalog_profile_kernel_args["drbd"])}."
  }
}

# Binds the composed node kargs, not only the authored catalog.
run "composed_node_kernel_args_carry_no_host_tuning" {
  command = plan
  module { source = "./tests/fixtures/real-catalog" }

  variables {
    nodes = {
      cp-1    = { ip = "192.0.2.10", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-intel = { ip = "192.0.2.11", role = "worker", image = "intel", hardware_capabilities = ["virt"] },
      w-amd   = { ip = "192.0.2.12", role = "worker", image = "amd", hardware_capabilities = ["virt"] },
    }
  }

  assert {
    condition     = join(",", output.node_kernel_args["w-intel"]) == "intel_iommu=on"
    error_message = "an intel node holding the iommu capability must compose exactly [\"intel_iommu=on\"]. Got: ${jsonencode(output.node_kernel_args["w-intel"])}."
  }

  assert {
    condition     = join(",", output.node_kernel_args["w-amd"]) == "amd_iommu=on"
    error_message = "an amd node holding the iommu capability must compose exactly [\"amd_iommu=on\"]. Got: ${jsonencode(output.node_kernel_args["w-amd"])}."
  }
}
