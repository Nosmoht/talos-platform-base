# Base-owned catalog: consumers select profiles but cannot redefine them.
# Keep every profile structurally uniform; kernel args express hardware predicates, not host tuning.

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
        intel = { kernel_args = ["intel_iommu=on"] }
        amd   = { kernel_args = ["amd_iommu=on"] }
      }
    }

    nvidia-lts = {
      # NFD detects GPU presence; installing drivers alone must not emit a hardware-feature label.
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

  provisioned_atoms = distinct(flatten([for p in local.provisioning_profiles : p.provides]))
}
