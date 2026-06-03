# Mixed amd64 + arm64 homelab topology:
#   - 3 controlplane (amd64, class "standard")
#   - 4 workers       (amd64, class "kubevirt": drbd + kubevirt host prereqs)
#   - 1 GPU worker    (amd64, class "gpu": nvidia extensions, own NIC)
#   - 1 Raspberry Pi  (arm64, class "pi": rpi_generic overlay)
#
# Kubernetes roles are ONLY controlplane / worker; GPU and Pi are classes, not
# roles. The arm64 Pi worker is the case the pre-extension module could not
# express (amd64 was hardcoded).
#
# IPs are RFC5737 documentation addresses (192.0.2.0/24) — validate-only.

locals {
  # Shared system extensions on every x86 node (drbd storage + gvisor runtime +
  # intel firmware/microcode). The GPU class adds nvidia on top.
  base_extensions = [
    "siderolabs/drbd",
    "siderolabs/gvisor",
    "siderolabs/i915",
    "siderolabs/intel-ucode",
    "siderolabs/nvme-cli",
  ]

  # Per-class machine-config patch demonstrating var.classes[*].config_patches:
  # kubevirt host prerequisites (IOMMU) applied to every node of the class.
  kubevirt_patch = yamlencode({
    machine = {
      install = {
        extraKernelArgs = ["intel_iommu=on", "iommu=pt"]
      }
    }
  })

  # Per-node patch demonstrating node.config_patches: the GPU node sits on a
  # different NIC, so its bridge binding is rendered per-node (the value the old
  # ${NIC_NAME} placeholder used to carry).
  gpu_nic_patch = yamlencode({
    machine = {
      network = {
        interfaces = [{
          interface = "enp0s20f0u2"
          dhcp      = true
        }]
      }
    }
  })
}

module "homelab" {
  source = "../../"

  cluster_name = "homelab"
  # Schema-pin fixed at bootstrap; install-pin bumped for an OS upgrade — the two
  # differ here to exercise the schema-pin-vs-install-pin split.
  talos_version         = "v1.12.6"
  talos_install_version = "v1.12.7"
  kubernetes_version    = "v1.35.0"
  cluster_endpoint      = "https://192.0.2.1:6443"

  nodes = [
    { hostname = "node-cp-1", ip = "192.0.2.11", role = "controlplane", class = "standard" },
    { hostname = "node-cp-2", ip = "192.0.2.12", role = "controlplane", class = "standard" },
    { hostname = "node-cp-3", ip = "192.0.2.13", role = "controlplane", class = "standard" },
    { hostname = "node-w-1", ip = "192.0.2.21", role = "worker", class = "kubevirt" },
    { hostname = "node-w-2", ip = "192.0.2.22", role = "worker", class = "kubevirt" },
    { hostname = "node-w-3", ip = "192.0.2.23", role = "worker", class = "kubevirt" },
    { hostname = "node-w-4", ip = "192.0.2.24", role = "worker", class = "kubevirt" },
    {
      hostname       = "node-gpu-1"
      ip             = "192.0.2.31"
      role           = "worker"
      class          = "gpu"
      config_patches = [local.gpu_nic_patch] # per-node NIC binding
    },
    { hostname = "node-pi-1", ip = "192.0.2.41", role = "worker", class = "pi" },
  ]

  classes = {
    standard = {
      architecture = "amd64"
      extensions   = local.base_extensions
    }
    kubevirt = {
      architecture   = "amd64"
      extensions     = local.base_extensions
      config_patches = [local.kubevirt_patch]
    }
    gpu = {
      architecture = "amd64"
      extensions = concat(local.base_extensions, [
        "siderolabs/nvidia-container-toolkit-lts",
        "siderolabs/nvidia-open-gpu-kernel-modules-lts",
        "siderolabs/realtek-firmware",
      ])
    }
    pi = {
      architecture = "arm64"
      extensions   = [] # the RPi schematic carries the board overlay, not extensions
      overlay = {
        name  = "rpi_generic"
        image = "siderolabs/sbc-raspberrypi"
      }
    }
  }

  # Cluster-wide patches the caller owns (NTP, registry mirrors, install disk).
  # NTP is supplied here because the module injects none of its own — the value
  # the old cluster.yaml .cluster.ntp_servers used to carry.
  config_patches = [
    yamlencode({
      machine = {
        time = {
          servers = ["192.0.2.123"]
        }
      }
    })
  ]

  # Role tier — applied to controlplane nodes only (exercises the role pass).
  controlplane_config_patches = [
    yamlencode({
      cluster = {
        apiServer = {
          extraArgs = {
            "event-ttl" = "1h0m0s"
          }
        }
      }
    })
  ]

  # ArgoCD ships with the bootstrap (deploy_argocd defaults to true, Layer-1
  # substrate). It MUST get an age key for the ksops repoServer — here a dummy
  # RFC-shaped placeholder so `tofu plan`/`validate` exercises the now-core path.
  # A real cluster supplies its actual age private key via the caller (SOPS/env);
  # NEVER commit a real key. Set deploy_argocd = false to opt out.
  sops_age_key = "AGE-SECRET-KEY-1EXAMPLE0000000000000000000000000000000000000000000000000000000PLACEHOLDER"
}
