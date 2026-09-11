# apply_mode routing oracle — Day-0 default and the Day-2 per-role window.
#
# mock_provider (not the ./tests/fixtures stand-in modules) because the property
# under test is an attribute of talos_machine_configuration_apply, which lives in
# main.tf and no fixture symlinks. The mocks keep it offline: no Image Factory,
# no node contact. deploy_argocd = false because a mocked data.helm_template
# returns nothing and the CRD-projection precondition would fail on that, not on
# anything this file tests.
#
# Red-green, per mutant (each verified, not asserted): reverting the apply_mode
# line in main.tf turns runs 1-5 red — runs 6-7 fail at variable validation
# before the resource is planned, so that mutant cannot reach them; swapping the
# two arms of local.node_apply_mode in nodes.tf turns runs 3-5 red; dropping a
# member from either contains() list in variables.tf turns run 5 red; routing on
# the map KEY instead of the node's role turns run 4 red.
#
# Node names are deliberately inconsistent across runs — role-shaped (cp-/w-) in
# some, role-free (alpha-/beta-) in others. That is what kills the key-routing
# mutant: with one naming scheme everywhere, name would be a perfect proxy for
# role and a mutant branching on the key would pass every run.

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

# Day-0, single node: the default must be "auto". The first apply to a
# maintenance-mode node IS the install, so any staging mode leaves the node in
# maintenance and talos_machine_bootstrap runs against an uninstalled node.
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

# Day-2 window: workers staged, controlplanes untouched. Distinct values per role,
# so a swapped ternary or a collapsed arm turns this red.
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
  # Keyed on the node's declared ROLE, never on its name: the names here are
  # deliberately not role-shaped, so a routing mutant that branches on the map
  # key instead of the role turns this red.
  assert {
    condition = alltrue([
      for k, r in talos_machine_configuration_apply.this :
      r.apply_mode == (var.nodes[k].role == "controlplane" ? "auto" : "staged")
    ])
    error_message = "worker_apply_mode must reach workers only; controlplanes stay on their own input"
  }
}

# Routing oracle only. A single-node controlplane left at "staged" through a
# Day-0 apply would never install — the module does not guard that, and this run
# asserts where the value lands, not that the combination is safe to use.
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

# Positive control over the whole accepted set: every value the module admits is
# exercised across runs 1-5 ("auto" in 1-2, "staged" in 3-4, "reboot" and
# "no_reboot" here), so dropping a member from either contains() list turns one
# of them red while the two rejection runs below stay green.
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

# The operator procedure is a TRANSITION on an existing cluster, not a fresh
# plan: open the window, then close it. These two runs are `command = apply` and
# share state, so run 9 exercises the provider's Update path on an existing
# resource rather than Create — the path that decides whether flipping the input
# back to "auto" re-applies to nodes whose config is still staged.
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

# An explicit null lands on the default rather than erroring — that is what
# nullable = false buys. Without it a null reaches contains() and OpenTofu raises
# "argument must not be null", naming neither the variable nor the accepted
# values. Red-green: drop nullable = false from either variable and this run
# turns red. It matters because a consumer shim reads these through try().
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
