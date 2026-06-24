# Conflict-guard regression suite (issue #136, Tasks 1 + 2).
#
# The module-param / sysctl / kernel-arg conflict guards in composition.tf are
# defensive: the shipped base catalog (profiles.tf) holds no colliding profiles,
# and the catalog is a module-local constant (not a var), so no `variables {}`
# input can make them fire — they had no red-green binding (composition.tftest.hcl
# header documented this gap).
#
# Each run below points at ./tests/fixtures/colliding-catalog via `run { module }`.
# That fixture SYMLINKS the real composition.tf + variables.tf and substitutes a
# synthetic profiles.tf engineered to collide, so the guards under test are the
# REAL code: revert a guard in composition.tf and the matching run stops failing
# ("Missing expected failure"). Pure plan over terraform_data — NO network, NO
# provider — so this file is offline (unlike composition.tftest.hcl).
#
# expect_failures references the resource (terraform_data.composition_guards); a
# precondition failure on it is the checkable object. Each run's capability sets
# requires_features = [] and each fixture profile provides = [], so the symmetry
# and variant guards never fire — every run isolates exactly one conflict guard.

variables {
  cluster_name       = "test"
  cluster_endpoint   = "https://192.0.2.1:6443"
  talos_version      = "v1.12.6"
  kubernetes_version = "v1.35.0"

  images = {
    intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [] }
  }
}

# Guard 1 — module_conflicts: two profiles contribute kernel module "zfs" with
# differing parameters on one node. Red-green: revert the module_conflicts
# precondition (composition.tf) and this run stops failing.
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
    nodes = [
      { hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["modparam"] },
    ]
  }
  expect_failures = [terraform_data.composition_guards]
}

# Guard 2 — sysctl_conflicts: two profiles set vm.swappiness to differing values.
# Red-green: revert the sysctl_conflicts precondition and this run stops failing.
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
    nodes = [
      { hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["sysctl"] },
    ]
  }
  expect_failures = [terraform_data.composition_guards]
}

# Guard 3 — karg_conflicts: two profiles set the single-value key "mitigations"
# to differing values. Red-green: revert the karg_conflicts precondition and this
# run stops failing.
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
    nodes = [
      { hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["karg"] },
    ]
  }
  expect_failures = [terraform_data.composition_guards]
}

# Task 2 — multi-value kernel-arg keys (console=) carrying differing values on
# one node must NOT be flagged a conflict (composition.tf _karg_multivalue_keys).
# No expect_failures: a clean plan IS the assertion. Red-green: remove "console"
# from _karg_multivalue_keys and the karg_conflicts precondition fires here,
# turning this run red with an unexpected failure.
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
    nodes = [
      { hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["console"] },
    ]
  }
}
