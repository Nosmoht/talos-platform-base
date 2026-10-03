# Installer routing and patch precedence must follow the schema pin, not the OS
# image version. Network and node contact are mocked; patch composition is real.
mock_provider "talos" {
  mock_data "talos_machine_configuration" {
    defaults = {
      machine_configuration = "apiVersion: v1alpha1\nkind: UnattendedInstallConfig\ninstaller:\n  image: factory.talos.dev/metal-installer/generated:v1.14.0\nprovisioning:\n  diskSelector:\n    match: disk.dev_path == '/dev/sda'\n  wipe: false\n"
    }
  }
  mock_data "talos_image_factory_urls" {
    defaults = {
      urls = {
        disk_image            = ""
        disk_image_secureboot = ""
        initramfs             = ""
        installer_secureboot  = ""
        iso                   = ""
        iso_secureboot        = ""
        kernel                = ""
        kernel_command_line   = ""
        pxe                   = ""
        uki                   = ""
        installer             = "factory.talos.dev/metal-installer/test-schematic:v1.14.2"
      }
    }
  }
}
mock_provider "helm" {}
mock_provider "local" {}
mock_provider "null" {}

variables {
  cluster_name       = "native-config-test"
  cluster_endpoint   = "https://192.0.2.1:6443"
  talos_version      = "v1.14.2"
  kubernetes_version = "v1.37.1"
  deploy_argocd      = false
  deploy_cilium      = false
  images             = { intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [] } }
  nodes = {
    cp     = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] }
    worker = { ip = "192.0.2.12", role = "worker", image = "intel", hardware_capabilities = [] }
  }
}

run "native_install_uses_per_node_factory_url" {
  command = apply
  assert {
    condition = alltrue([for node in values(talos_machine_configuration_apply.this) :
      yamldecode(node.config_patches[0]).kind == "UnattendedInstallConfig" &&
      yamldecode(node.config_patches[0]).installer.image == "factory.talos.dev/metal-installer/test-schematic:v1.14.2" &&
      !can(yamldecode(node.config_patches[0]).machine.install)
    ])
    error_message = "Native schemas must put the per-node Factory URL in exactly one native install patch."
  }
  assert {
    condition     = output.kubelet_rotation_setting.kind == "KubeletConfig" && output.kubelet_rotation_setting.config.serverTLSBootstrap
    error_message = "Native kubelet rotation must use KubeletConfig.config.serverTLSBootstrap."
  }
}

run "os_upgrade_keeps_legacy_schema" {
  command = apply
  variables {
    talos_version         = "v1.13.10"
    talos_install_version = "v1.14.2"
  }
  assert {
    condition = alltrue([for node in values(talos_machine_configuration_apply.this) :
      yamldecode(node.config_patches[0]).machine.install.image == "factory.talos.dev/metal-installer/test-schematic:v1.14.2" &&
      !can(yamldecode(node.config_patches[0]).kind)
    ])
    error_message = "An OS-only upgrade must retain the existing machine.install patch contract."
  }
}

run "native_node_override_remains_after_module_install" {
  command = apply
  variables {
    nodes = {
      cp = {
        ip             = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = []
        config_patches = ["apiVersion: v1alpha1\nkind: UnattendedInstallConfig\ninstaller:\n  image: factory.talos.dev/metal-installer/custom:v1.14.2\nprovisioning:\n  diskSelector:\n    match: disk.dev_path == '/dev/nvme0n1'\n"]
      }
    }
  }
  assert {
    condition = (
      yamldecode(talos_machine_configuration_apply.this["cp"].config_patches[0]).installer.image !=
      yamldecode(talos_machine_configuration_apply.this["cp"].config_patches[2]).installer.image &&
      yamldecode(talos_machine_configuration_apply.this["cp"].config_patches[2]).provisioning.diskSelector.match == "disk.dev_path == '/dev/nvme0n1'"
    )
    error_message = "Per-node image and disk overrides must follow the module default."
  }
}
