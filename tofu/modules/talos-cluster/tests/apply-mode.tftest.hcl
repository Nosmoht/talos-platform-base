# mock_provider, not a fixture: apply_mode lives on talos_machine_configuration_apply.
# deploy_argocd = false because a mocked helm_template renders nothing.
# Node names vary between role-shaped and role-free so key-based routing fails.

mock_provider "talos" {}
mock_provider "helm" {}
mock_provider "local" {}
mock_provider "null" {}

variables {
  cluster_name       = "test"
  cluster_endpoint   = "https://192.0.2.1:6443"
  talos_version      = "v1.13.9"
  kubernetes_version = "v1.36.3"
  deploy_argocd      = false

  images = {
    intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [] }
  }
}

run "default_is_auto_single_node" {
  command = plan
  variables {
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition     = talos_machine_configuration_apply.this["cp-1"].apply_mode == "auto"
    error_message = "single-node default apply_mode must be auto (Day-0 install path)"
  }
}

run "default_is_auto_multi_node" {
  command = plan
  variables {
    nodes = {
      alpha-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      alpha-2 = { ip = "192.0.2.12", role = "controlplane", image = "intel", hardware_capabilities = [] },
      alpha-3 = { ip = "192.0.2.13", role = "controlplane", image = "intel", hardware_capabilities = [] },
      beta-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
      beta-2  = { ip = "192.0.2.22", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition = alltrue([
      for k, r in talos_machine_configuration_apply.this : r.apply_mode == "auto"
    ])
    error_message = "multi-node default apply_mode must be auto on every node"
  }
}

run "staged_workers_only_multi_node" {
  command = plan
  variables {
    worker_apply_mode = "staged"
    nodes = {
      alpha-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      alpha-2 = { ip = "192.0.2.12", role = "controlplane", image = "intel", hardware_capabilities = [] },
      alpha-3 = { ip = "192.0.2.13", role = "controlplane", image = "intel", hardware_capabilities = [] },
      beta-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
      beta-2  = { ip = "192.0.2.22", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition = alltrue([
      for k, r in talos_machine_configuration_apply.this :
      r.apply_mode == (var.nodes[k].role == "controlplane" ? "auto" : "staged")
    ])
    error_message = "worker_apply_mode must reach workers only; controlplanes stay on their own input"
  }
}

run "staged_controlplane_only_single_node" {
  command = plan
  variables {
    controlplane_apply_mode = "staged"
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition     = talos_machine_configuration_apply.this["cp-1"].apply_mode == "staged"
    error_message = "controlplane_apply_mode must reach a single-node cluster's only node"
  }
}

run "accepts_in_set_values_per_role" {
  command = plan
  variables {
    controlplane_apply_mode = "reboot"
    worker_apply_mode       = "no_reboot"
    nodes = {
      alpha-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      beta-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition = (
      talos_machine_configuration_apply.this["alpha-1"].apply_mode == "reboot" &&
      talos_machine_configuration_apply.this["beta-1"].apply_mode == "no_reboot"
    )
    error_message = "in-set non-default values must be accepted and routed per role"
  }
}

run "rejects_out_of_set_controlplane_mode" {
  command = plan
  variables {
    controlplane_apply_mode = "staged_if_needing_reboot"
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  expect_failures = [var.controlplane_apply_mode]
}

run "rejects_out_of_set_worker_mode" {
  command = plan
  variables {
    worker_apply_mode = ""
    nodes = {
      alpha-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      beta-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
  expect_failures = [var.worker_apply_mode]
}

# Two apply runs sharing state: the second exercises Update, not Create.
run "transition_baseline_apply_is_auto" {
  command = apply
  variables {
    nodes = {
      alpha-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      beta-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition = alltrue([
      for k, r in talos_machine_configuration_apply.this : r.apply_mode == "auto"
    ])
    error_message = "baseline apply must write auto on every node"
  }
}

run "transition_opening_a_window_touches_only_the_staged_role" {
  command = apply
  variables {
    worker_apply_mode = "staged"
    nodes = {
      alpha-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      beta-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition = alltrue([
      for k, r in talos_machine_configuration_apply.this :
      r.apply_mode == (var.nodes[k].role == "controlplane" ? "auto" : "staged")
    ])
    error_message = "opening a window must move only the staged role's nodes"
  }
}

run "explicit_null_resolves_to_the_default" {
  command = plan
  variables {
    controlplane_apply_mode = null
    worker_apply_mode       = null
    nodes = {
      alpha-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      beta-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition = alltrue([
      for k, r in talos_machine_configuration_apply.this : r.apply_mode == "auto"
    ])
    error_message = "an explicit null must resolve to the default, not to an unset or invalid mode"
  }
}
