# Upstream check against the live Talos Image Factory: every catalog extension
# resolves at the supported native version. A red run here means factory.talos.dev
# is unreachable or has renamed a package — never a module regression, which the
# offline suites in tests/ cover. Run via `task tofu:test:image-factory`.

provider "talos" {}
provider "helm" {}

variables {
  cluster_name       = "test"
  cluster_endpoint   = "https://192.0.2.1:6443"
  talos_version      = "v1.14.2"
  kubernetes_version = "v1.37.1"
  deploy_argocd      = false
  deploy_cilium      = false

  images = {
    intel = { architecture = "amd64", cpu_vendor = "intel", extensions = ["siderolabs/intel-ucode"] }
    arm   = { architecture = "arm64", cpu_vendor = "arm", extensions = [], overlay = { name = "rpi_generic", image = "siderolabs/sbc-raspberrypi" } }
  }
  hardware_capabilities = {
    all-profiles = {
      requires_features     = ["drbd-kernel-module", "iommu-enabled"]
      provisioning_profiles = ["drbd", "iommu", "nvidia-lts"]
      emits_label           = "platform.io/hardware-capability.all-profiles"
    }
  }
  nodes = {
    cp  = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["all-profiles"] }
    arm = { ip = "192.0.2.12", role = "worker", image = "arm", hardware_capabilities = [] }
  }
}

run "native_114_factory_catalog" {
  command = plan
  assert {
    condition = alltrue([for hash, extensions in local.official_extensions_by_schematic :
      alltrue([for requested in local.schematics[hash].extensions : contains(extensions, requested)])
    ])
    error_message = "Every requested extension must resolve at Talos 1.14.2."
  }
  assert {
    condition     = length(data.talos_image_factory_extensions_versions.per_schematic) == 2
    error_message = "The native Factory check must cover amd64 and arm64."
  }
}
