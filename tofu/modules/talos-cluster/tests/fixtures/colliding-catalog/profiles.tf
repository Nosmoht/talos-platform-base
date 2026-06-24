# TEST-ONLY synthetic provisioning-profile catalog (issue #136, Task 1).
#
# The real catalog (../../../profiles.tf) ships no colliding profiles, so the
# three conflict guards in composition.tf (module-param / sysctl / kernel-arg)
# have no triggerable input through real data and therefore no red-green binding.
# `local.provisioning_profiles` is a module-local constant (NOT a var) — closing
# the consumer-redefine vector mechanically — so `tofu test` cannot override it
# via the `variables {}` block.
#
# This fixture directory is a stand-in module: it SYMLINKS the real
# composition.tf + variables.tf (so the guards under test are the REAL code —
# revert a guard in composition.tf and the matching run here stops failing) and
# substitutes ONLY this profiles.tf with a catalog engineered to collide. The
# conflict-guards.tftest.hcl runs point at this directory via `run { module {} }`.
#
# Every profile sets `provides = []` and `requires_features` on the selecting
# capability is left empty, so the per-capability symmetry guards (forward /
# inverse) and the variant-mismatch guard never fire — each run isolates exactly
# one conflict guard. The object shape mirrors the real catalog (provides /
# extensions / kernel_args / kernel_modules / sysctls / variants) so the symlinked
# composition.tf for-expressions type-check unchanged.

locals {
  provisioning_profiles = {
    # --- module-param conflict: same module name, differing parameters ------
    modparam_a = {
      provides       = []
      extensions     = []
      kernel_args    = []
      kernel_modules = [{ name = "zfs", parameters = ["zfs_arc_max=1073741824"] }]
      sysctls        = {}
      variants       = {}
    }
    modparam_b = {
      provides       = []
      extensions     = []
      kernel_args    = []
      kernel_modules = [{ name = "zfs", parameters = ["zfs_arc_max=2147483648"] }]
      sysctls        = {}
      variants       = {}
    }

    # --- sysctl conflict: same key, differing value -------------------------
    sysctl_a = {
      provides       = []
      extensions     = []
      kernel_args    = []
      kernel_modules = []
      sysctls        = { "vm.swappiness" = "10" }
      variants       = {}
    }
    sysctl_b = {
      provides       = []
      extensions     = []
      kernel_args    = []
      kernel_modules = []
      sysctls        = { "vm.swappiness" = "60" }
      variants       = {}
    }

    # --- kernel-arg conflict: same SINGLE-value key, differing value --------
    karg_a = {
      provides       = []
      extensions     = []
      kernel_args    = ["mitigations=off"]
      kernel_modules = []
      sysctls        = {}
      variants       = {}
    }
    karg_b = {
      provides       = []
      extensions     = []
      kernel_args    = ["mitigations=auto"]
      kernel_modules = []
      sysctls        = {}
      variants       = {}
    }

    # --- multi-value kernel-arg (console=): same key, differing value, must
    #     NOT be flagged a conflict (composition.tf _karg_multivalue_keys) -----
    console_a = {
      provides       = []
      extensions     = []
      kernel_args    = ["console=ttyS0,115200n8"]
      kernel_modules = []
      sysctls        = {}
      variants       = {}
    }
    console_b = {
      provides       = []
      extensions     = []
      kernel_args    = ["console=tty0"]
      kernel_modules = []
      sysctls        = {}
      variants       = {}
    }
  }

  # Mirrors the real profiles.tf derivation so the symlinked composition.tf
  # references resolve. All profiles provide [], so this is the empty set.
  provisioned_atoms = distinct(flatten([for p in local.provisioning_profiles : p.provides]))
}
