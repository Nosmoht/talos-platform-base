# Base-owned provisioning-profile catalog (ADR base:node-capability-composition).
#
# MODULE-LOCAL constant — NOT a `var`, so a consumer can select profiles by id
# from a composite's `provisioning_profiles` but cannot author or redefine one
# (closes the consumer-redefine vector mechanically). It lives in tofu/** so the
# hard-constraints-check greps (SecureBoot, debugfs) cover any kernel_args it
# carries. A profile binds the parts of a PROVISIONED hardware feature so they
# cannot drift:
#
#   provides       the talos-machine-config atom this profile satisfies (drives
#                  label emission + the symmetry check; [] for a profile that
#                  provisions content for an NFD-DETECTED atom, e.g. nvidia)
#   extensions     Image-Factory system extensions      -> schematic
#   kernel_args    boot-time kernel cmdline args         -> schematic
#                  customization.extraKernelArgs (the v1.10+ UKI-correct sink)
#   kernel_modules modules to load                       -> machine.kernel.modules
#   sysctls        sysctl key/values                     -> machine.sysctls
#   variants       vendor-specific kernel_args, resolved by the node image's
#                  cpu_vendor; a profile with variants ignores its top-level
#                  kernel_args and uses the matched variant's (no match -> hard
#                  error, see composition.tf).
#
# Every profile carries the full key set (empty where unused) so the map has a
# uniform object type for the for-expressions in composition.tf.

locals {
  provisioning_profiles = {
    drbd = {
      provides    = ["drbd-kernel-module"]
      extensions  = ["siderolabs/drbd"]
      kernel_args = []
      kernel_modules = [
        { name = "drbd", parameters = ["usermode_helper=disabled"] },
        { name = "drbd_transport_tcp", parameters = [] },
      ]
      sysctls  = {}
      variants = {}
    }

    iommu = {
      provides       = ["iommu-enabled"]
      extensions     = []
      kernel_args    = [] # vendor-resolved via variants below
      kernel_modules = [{ name = "vfio-pci", parameters = [] }]
      sysctls        = {}
      variants = {
        intel = { kernel_args = ["intel_iommu=on", "iommu=pt"] }
        amd   = { kernel_args = ["amd_iommu=on", "iommu=pt"] }
      }
    }

    nvidia-lts = {
      # No `provides`: nvidia-gpu is an NFD-DETECTED presence atom, not a
      # provisioned one — this profile bakes the driver stack but does not emit a
      # platform.io/hardware-feature label (the device plugin / NFD owns it).
      # Extension name MUST match the device-plugin nodeAffinity selector
      # (extensions.talos.dev/nvidia-open-gpu-kernel-modules-lts).
      provides    = []
      extensions  = ["siderolabs/nvidia-open-gpu-kernel-modules-lts", "siderolabs/nvidia-container-toolkit-lts"]
      kernel_args = []
      kernel_modules = [
        { name = "nvidia", parameters = [] },
        { name = "nvidia_uvm", parameters = [] },
        { name = "nvidia_drm", parameters = [] },
        { name = "nvidia_modeset", parameters = [] },
      ]
      sysctls  = { "net.core.bpf_jit_harden" = "1" }
      variants = {}
    }
  }

  # An atom is "provisioned" iff some catalog profile `provides` it (self-contained;
  # equal by construction to the registry's discovery_source: talos-machine-config
  # set — a CI cross-reference gate guards the equivalence). The module does NOT
  # read platform-hardware-features.yaml at plan time.
  provisioned_atoms = distinct(flatten([for p in local.provisioning_profiles : p.provides]))
}
