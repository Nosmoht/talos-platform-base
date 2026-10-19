# ./tests/fixtures/colliding-catalog symlinks the real composition.tf and swaps in
# a synthetic profiles.tf; the conflict locals must stay in composition.tf. Fixture
# profiles carry provides = [] so each run trips exactly one guard; adding a
# `provides` changes which precondition fires.

variables {
  cluster_name       = "test"
  cluster_endpoint   = "https://192.0.2.1:6443"
  talos_version      = "v1.13.9"
  kubernetes_version = "v1.36.3"

  images = {
    intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [] }
  }
}

run "module_param_conflict_guard_fires" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    hardware_capabilities = {
      modparam = {
        requires_features     = []
        provisioning_profiles = ["modparam_a", "modparam_b"]
        emits_label           = "platform.io/hardware-capability.modparam"
      }
    }
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["modparam"] },
    }
  }
  expect_failures = [terraform_data.composition_guards]
}

run "sysctl_conflict_guard_fires" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    hardware_capabilities = {
      sysctl = {
        requires_features     = []
        provisioning_profiles = ["sysctl_a", "sysctl_b"]
        emits_label           = "platform.io/hardware-capability.sysctl"
      }
    }
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["sysctl"] },
    }
  }
  expect_failures = [terraform_data.composition_guards]
}

run "kernel_arg_conflict_guard_fires" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    hardware_capabilities = {
      karg = {
        requires_features     = []
        provisioning_profiles = ["karg_a", "karg_b"]
        emits_label           = "platform.io/hardware-capability.karg"
      }
    }
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["karg"] },
    }
  }
  expect_failures = [terraform_data.composition_guards]
}

run "console_multivalue_is_not_a_conflict" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    hardware_capabilities = {
      console = {
        requires_features     = []
        provisioning_profiles = ["console_a", "console_b"]
        emits_label           = "platform.io/hardware-capability.console"
      }
    }
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["console"] },
    }
  }
  assert {
    condition     = contains(output.node_kernel_args["cp-1"], "console=ttyS0,115200n8") && contains(output.node_kernel_args["cp-1"], "console=tty0")
    error_message = "both multi-value console= args must survive into the union; got ${jsonencode(output.node_kernel_args["cp-1"])}"
  }
}

run "image_karg_conflicting_with_a_profile_karg_fails_the_plan" {
  command = plan
  module { source = "./tests/fixtures/real-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [], extra_kernel_args = ["intel_iommu=on,sm_on"] }
    }
    hardware_capabilities = {
      virt = {
        requires_features     = ["iommu-enabled"]
        provisioning_profiles = ["iommu"]
        emits_label           = "platform.io/hardware-capability.virt"
      }
    }
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["virt"] },
    }
  }
  expect_failures = [terraform_data.composition_guards]
}

run "image_karg_restating_a_profile_karg_is_not_a_conflict" {
  command = plan
  module { source = "./tests/fixtures/real-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [], extra_kernel_args = ["intel_iommu=on"] }
    }
    hardware_capabilities = {
      virt = {
        requires_features     = ["iommu-enabled"]
        provisioning_profiles = ["iommu"]
        emits_label           = "platform.io/hardware-capability.virt"
      }
    }
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["virt"] },
    }
  }
  assert {
    condition     = join(",", output.node_kernel_args["cp-1"]) == "intel_iommu=on"
    error_message = "an image karg restating a profile karg verbatim must not duplicate on the cmdline (set equality, not list equality — a duplicate fails this); got ${join(",", output.node_kernel_args["cp-1"])}"
  }
}

run "consumer_only_key_is_not_guarded" {
  command = plan
  module { source = "./tests/fixtures/real-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [], extra_kernel_args = ["hugepagesz=2M", "hugepages=512", "hugepagesz=1G", "hugepages=8"] }
    }
    hardware_capabilities = {}
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition     = length(output.node_kernel_args["cp-1"]) == 4
    error_message = "a key no selected profile contributes must not be guarded, and all four consumer-only args must survive the union (none dropped/collapsed); got ${jsonencode(output.node_kernel_args["cp-1"])}"
  }
}

run "an_exempt_multivalue_key_coexists_across_sources" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [], extra_kernel_args = ["console=tty1"] }
    }
    hardware_capabilities = {
      console = {
        requires_features     = []
        provisioning_profiles = ["console_a", "console_b"]
        emits_label           = "platform.io/hardware-capability.console"
      }
    }
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["console"] },
    }
  }
  assert {
    condition     = tolist(output.node_kernel_args["cp-1"]) == tolist(["console=tty0", "console=tty1", "console=ttyS0,115200n8"])
    error_message = "an exempt multi-value key (console=) must coexist across a profile source and an image source, not conflict; got ${jsonencode(output.node_kernel_args["cp-1"])}"
  }
}
