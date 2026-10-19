# Synthetic catalog engineered to collide; replaces the real profiles.tf while
# composition.tf and variables.tf are symlinked. provides = [] keeps every
# symmetry and variant guard quiet, so each run triggers exactly one conflict guard.

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

    # --- multi-value kernel-arg (console=): must NOT be flagged a conflict ---
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

  provisioned_atoms = distinct(flatten([for p in local.provisioning_profiles : p.provides]))
}
