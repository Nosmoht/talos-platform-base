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
#
# Issue #169 (consumer-supplied schematic extra_kernel_args) adds FOUR more runs
# below that use the REAL ./tests/fixtures/real-catalog fixture and cross-source
# inputs (a var.images[*].extra_kernel_args value colliding with, or coexisting
# with, a selected profile's kernel arg). Those four runs' capability declares a
# non-empty requires_features (["iommu-enabled"]) because the shipped `iommu`
# profile carries `provides = ["iommu-enabled"]` — the caveat above ("every
# fixture profile has provides=[]") does not cover them; their isolation instead
# rests on AC4 being a genuine minimal pair with AC3 (same fixture shape, same
# node cp-1, one value changed) — see the runs themselves for the argument.

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
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["modparam"] },
    }
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
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["sysctl"] },
    }
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
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["karg"] },
    }
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
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["console"] },
    }
  }
  assert {
    condition     = contains(output.node_kernel_args["cp-1"], "console=ttyS0,115200n8") && contains(output.node_kernel_args["cp-1"], "console=tty0")
    error_message = "both multi-value console= args must survive into the union; got ${jsonencode(output.node_kernel_args["cp-1"])}"
  }
}

# --- Issue #169: cross-source conflict guard (AC3/AC4) ---------------------
#
# AC3 and AC4 are a genuine minimal pair: same node (cp-1), same real-catalog
# fixture, image intel, capability virt selecting the shipped iommu profile
# (provides intel_iommu on this vendor). AC3's image karg sets intel_iommu to a
# DIFFERING value than the profile's intel_iommu=on -> the cross-source guard
# fires. AC4 is identical except the image RESTATES the profile's value
# verbatim -> no conflict (distinct() collapses the duplicate). Because AC4
# plans clean on the IDENTICAL shape, any OTHER precondition firing on this
# shape (e.g. the symmetry guard, if requires_features/provides were
# mismatched) would turn AC4 red — this commits the isolation, no throwaway
# probe needed.
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

# The binding for the owner-decided cross-source scoping (plan.md §Assumptions):
# a key NO selected profile contributes is never guarded, even when the
# consumer's own list carries the SAME key at differing values (the legitimate
# multi-hugepage-size idiom). The mutant this run uniquely kills is the issue
# body's literal prescription — re-sourcing the profile-side iteration onto the
# UNIONED node_effective.kernel_args instead of node_profile_resolved alone;
# every other planned run in this suite stays green under that mutant (AC3
# still fires, AC4 still dedups, the exempt-key run's key is exempt). Under
# that mutant this run's four consumer args group by key (hugepagesz => two
# values, hugepages => two values), neither key is exempt, and the plan
# hard-fails with "Unexpected failure".
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

# The multi-value exemption's cross-source coexistence: a profile-contributed
# exempt key (console=) and an IMAGE-contributed value for the same key must
# coexist, not conflict — the exemption is consulted for a key a PROFILE
# contributes, and the image side must not bypass it. The mutant this run
# uniquely kills is an implementation that exempts only PROFILE-only keys (see
# the plan for the exact wrong-implementation shape); dropping the exemption
# check outright is already killed by console_multivalue_is_not_a_conflict
# above.
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
