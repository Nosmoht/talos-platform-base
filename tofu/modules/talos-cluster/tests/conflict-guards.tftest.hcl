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
# synthetic profiles.tf (the CATALOG is synthetic; the conflict-detection locals
# module_conflicts / sysctl_conflicts / karg_conflicts / _karg_multivalue_keys and
# their guard preconditions are the REAL symlinked composition.tf). Revert a guard
# in composition.tf and the matching run stops failing ("Missing expected
# failure"). Pure plan over terraform_data — NO network, NO provider — offline
# (unlike composition.tftest.hcl).
#
# BINDING CAVEAT (keep this binding intact): the red-green binding holds only while
# those four conflict-detection locals live IN composition.tf. Moving any of them
# into profiles.tf/main.tf would make the fixture's own profiles.tf shadow it (or
# drop it), and these runs would test a stale/synthetic copy while production goes
# untested. Per-guard isolation rests on every fixture profile having provides=[]
# and every capability requires_features=[] (so the symmetry/variant guards stay
# inert) — do NOT add a `provides` to a fixture profile without re-checking which
# precondition fires.
#
# PORTABILITY: the fixture uses git symlinks; on Windows checkouts with
# core.symlinks=false they materialise as text files and tofu fails to parse them
# (`git config core.symlinks true`). CI runs Linux, so it is unaffected.
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
# one node must NOT be flagged a conflict (composition.tf _karg_multivalue_keys),
# AND both values must be carried into the unioned kernel_args (the union-
# correctness half of composition.tf:223-227, not just "no conflict raised").
# Red-green: remove "console" from _karg_multivalue_keys and the karg_conflicts
# precondition fires → unexpected failure → red; break the union and the assert
# below goes red.
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
  assert {
    condition     = contains(output.node_kernel_args["cp-1"], "console=ttyS0,115200n8") && contains(output.node_kernel_args["cp-1"], "console=tty0")
    error_message = "both multi-value console= args must survive into the union; got ${jsonencode(output.node_kernel_args["cp-1"])}"
  }
}
