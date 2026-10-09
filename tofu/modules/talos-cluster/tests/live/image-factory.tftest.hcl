# Checks the catalog's extension names against the live Talos Image Factory at
# both supported Talos lines. Run via `task tofu:test:image-factory`; the
# offline suites in tests/ never contact the Factory.

provider "talos" {}
provider "helm" {}

variables {
  cluster_name     = "test"
  cluster_endpoint = "https://192.0.2.1:6443"
  deploy_argocd    = false
  deploy_cilium    = false

  images = {
    intel = { architecture = "amd64", cpu_vendor = "intel", extensions = ["siderolabs/intel-ucode"] }
  }
  hardware_capabilities = {
    all-profiles = {
      requires_features     = ["drbd-kernel-module", "iommu-enabled"]
      provisioning_profiles = ["drbd", "iommu", "nvidia-lts"]
      emits_label           = "platform.io/hardware-capability.all-profiles"
    }
  }
  nodes = {
    cp = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["all-profiles"] }
  }
}

run "native_114_factory_catalog" {
  command = plan
  variables {
    talos_version      = "v1.14.2"
    kubernetes_version = "v1.37.1"
  }
  assert {
    condition     = toset(keys(local.provisioning_profiles)) == toset(flatten([for c in var.hardware_capabilities : c.provisioning_profiles]))
    error_message = "this file's capabilities must select every catalog profile in profiles.tf, or a new profile's extensions are never checked; catalog: ${jsonencode(keys(local.provisioning_profiles))}"
  }
  assert {
    condition = alltrue([for hash, extensions in local.official_extensions_by_schematic :
      alltrue([for requested in local.schematics[hash].extensions : contains(extensions, requested)])
    ])
    error_message = "Every requested extension must resolve at Talos 1.14.2."
  }
}

run "legacy_113_factory_catalog" {
  command = plan
  variables {
    talos_version      = "v1.13.9"
    kubernetes_version = "v1.36.3"
  }
  assert {
    condition = alltrue([for hash, extensions in local.official_extensions_by_schematic :
      alltrue([for requested in local.schematics[hash].extensions : contains(extensions, requested)])
    ])
    error_message = "Every requested extension must resolve at Talos 1.13.9."
  }
}
