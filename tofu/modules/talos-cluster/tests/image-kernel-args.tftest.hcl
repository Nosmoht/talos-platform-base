# Offline: both fixtures symlink the real composition.tf and variables.tf and
# declare no providers.

variables {
  cluster_name       = "test"
  cluster_endpoint   = "https://192.0.2.1:6443"
  talos_version      = "v1.13.9"
  kubernetes_version = "v1.36.3"
}

# The profile order in this run yields the reverse of sorted order; keep it, or
# the sort() in the kernel-arg concat loses its only binding.
run "default_consumer_kernel_args_are_composed_order_exactly" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [] }
    }
    hardware_capabilities = {
      console = {
        requires_features     = []
        provisioning_profiles = ["console_a", "console_b"] # ORDER IS THE ORACLE
        emits_label           = "platform.io/hardware-capability.console"
      }
    }
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["console"] },
    }
  }
  assert {
    condition     = tolist(output.node_kernel_args["cp-1"]) == tolist(["console=tty0", "console=ttyS0,115200n8"])
    error_message = "default consumer (no extra_kernel_args) composed kernel_args must equal the sorted profile-only set exactly, order and multiplicity; got ${jsonencode(output.node_kernel_args["cp-1"])}"
  }
}

# Pinned hash: substr(sha256(yamlencode(schematic)), 0, 16) of w-1's schematic.
# A mismatch means every consumer re-images: stop and write an UPGRADING note,
# do not re-pin.
run "default_consumer_shipped_catalog_node_is_not_re_imaged" {
  command = plan
  module { source = "./tests/fixtures/real-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [] }
    }
    hardware_capabilities = {
      virt = {
        requires_features     = ["iommu-enabled"]
        provisioning_profiles = ["iommu"]
        emits_label           = "platform.io/hardware-capability.virt"
      }
    }
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = ["virt"] },
    }
  }
  assert {
    condition     = tolist(output.node_kernel_args["w-1"]) == tolist(["intel_iommu=on"])
    error_message = "existing consumer (no extra_kernel_args) on the shipped iommu profile must compose to exactly the profile's kernel_args, order and multiplicity; got ${jsonencode(output.node_kernel_args["w-1"])}"
  }
  assert {
    condition     = output.node_schematic_hashes["w-1"] == "760a1a00eabe770b"
    error_message = "existing consumer's schematic content hash for w-1 changed — this is the re-image event AC6 exists to prevent for a consumer setting no extra_kernel_args. If composition.tf:108-119's merge shape or the shipped iommu profile's content legitimately changed, this needs an UPGRADING.md entry, not a silent re-pin. got ${output.node_schematic_hashes["w-1"]}"
  }
}

# OpenTofu does not resolve run.<name> inside assert, so both runs compare
# against the same pinned baseline hash.
run "baseline_no_extra_kernel_args" {
  command = plan
  module { source = "./tests/fixtures/real-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [] }
    }
    hardware_capabilities = {
      virt = {
        requires_features     = ["iommu-enabled"]
        provisioning_profiles = ["iommu"]
        emits_label           = "platform.io/hardware-capability.virt"
      }
    }
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = ["virt"] },
    }
  }
  assert {
    condition     = output.node_schematic_hashes["w-1"] == "760a1a00eabe770b"
    error_message = "baseline (no extra_kernel_args) schematic hash for w-1 must equal the pinned pre-change literal; got ${output.node_schematic_hashes["w-1"]}"
  }
}

run "changed_extra_kernel_args_change_the_schematic_id" {
  command = plan
  module { source = "./tests/fixtures/real-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [], extra_kernel_args = ["hugepagesz=1G"] }
    }
    hardware_capabilities = {
      virt = {
        requires_features     = ["iommu-enabled"]
        provisioning_profiles = ["iommu"]
        emits_label           = "platform.io/hardware-capability.virt"
      }
    }
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = ["virt"] },
    }
  }
  assert {
    condition     = output.node_schematic_hashes["w-1"] != "760a1a00eabe770b"
    error_message = "a node whose image's extra_kernel_args changed must take the re-image path (differing schematic hash from the baseline), not silently no-op; got the SAME hash ${output.node_schematic_hashes["w-1"]}"
  }
}
