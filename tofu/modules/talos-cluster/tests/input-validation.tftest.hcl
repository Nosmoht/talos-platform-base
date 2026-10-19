# Offline: the colliding-catalog fixture plans over terraform_data with no provider or network.

variables {
  cluster_name       = "test"
  cluster_endpoint   = "https://192.0.2.1:6443"
  talos_version      = "v1.13.9"
  kubernetes_version = "v1.36.3"

  images = {
    intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [] }
  }

  nodes = {
    cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
  }
}

run "talos_version_rejects_trailing_garbage" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    talos_version = "v1.13.9.4"
  }
  expect_failures = [var.talos_version]
}

run "talos_install_version_rejects_trailing_garbage" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    talos_install_version = "v1.13.9garbage"
  }
  expect_failures = [var.talos_install_version]
}

run "kubernetes_version_rejects_trailing_garbage" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    kubernetes_version = "v1.36.3.1"
  }
  expect_failures = [var.kubernetes_version]
}

run "prerelease_suffix_is_accepted" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    talos_version         = "v1.14.0-beta.1"
    talos_install_version = "v1.14.0-beta.1"
  }
}

# The debugfs leg uses "debugfs=on": hard-constraints-check.yml rejects the forbidden
# value anywhere under tofu/.

run "image_extra_kernel_args_rejects_whitespace" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [], extra_kernel_args = ["hugepagesz=1G intel_iommu=off"] }
    }
  }
  expect_failures = [var.images]
}

run "image_extra_kernel_args_rejects_removal_spelling" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [], extra_kernel_args = ["-intel_iommu"] }
    }
  }
  expect_failures = [var.images]
}

run "image_extra_kernel_args_rejects_an_empty_key" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [], extra_kernel_args = [""] }
    }
  }
  expect_failures = [var.images]
}

run "image_extra_kernel_args_rejects_the_debugfs_key" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [], extra_kernel_args = ["debugfs=on"] }
    }
  }
  expect_failures = [var.images]
}

run "image_extra_kernel_args_accepts_a_well_formed_list" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [], extra_kernel_args = ["hugepagesz=1G", "mitigations=off", "quiet"] }
    }
  }
}

run "cert_approver_provider_ip_prefixes_rejects_empty" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cert_approver_provider_ip_prefixes = []
  }
  expect_failures = [var.cert_approver_provider_ip_prefixes]
}

run "cert_approver_provider_ip_prefixes_rejects_non_cidr" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cert_approver_provider_ip_prefixes = ["not-a-cidr"]
  }
  expect_failures = [var.cert_approver_provider_ip_prefixes]
}

run "cert_approver_provider_regex_rejects_empty" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cert_approver_provider_regex = ""
  }
  expect_failures = [var.cert_approver_provider_regex]
}

run "cert_approver_provider_regex_rejects_whitespace_only" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cert_approver_provider_regex = " "
  }
  expect_failures = [var.cert_approver_provider_regex]
}

run "cert_approver_provider_regex_rejects_document_separator" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cert_approver_provider_regex = "a---b"
  }
  expect_failures = [var.cert_approver_provider_regex]
}

run "cert_approver_provider_regex_rejects_uncompilable" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cert_approver_provider_regex = "[unterminated"
  }
  expect_failures = [var.cert_approver_provider_regex]
}

run "cert_approver_replicas_rejects_zero" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cert_approver_replicas = 0
  }
  expect_failures = [var.cert_approver_replicas]
}

run "cilium_all_off_default_carries_no_observability_keys" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  assert {
    condition     = !contains(keys(output.cilium_effective_values), "prometheus")
    error_message = "default-off: cilium_effective_values must not carry a prometheus key when cilium_agent_metrics is unset (default false)"
  }
  assert {
    condition     = try(output.cilium_effective_values.operator.prometheus, null) == null
    error_message = "default-off: cilium_effective_values.operator must not carry a prometheus key when cilium_operator_metrics is unset (default false)"
  }
  assert {
    condition     = output.cilium_effective_values.hubble.enabled == false
    error_message = "default-off: cilium_effective_values.hubble.enabled must stay the floor's false when cilium_hubble_enabled is unset (default false)"
  }
  assert {
    condition     = output.cilium_self_management_app == ""
    error_message = "default-off: cilium_self_management_app must be the empty string when cilium_self_management is unset (default false)"
  }

  assert {
    condition     = try(output.cilium_effective_values.hubble.metrics, null) == null
    error_message = "default-off: cilium_effective_values.hubble must carry NO metrics key while Hubble is off — reading local.cilium_hubble_metrics_values directly instead of through local.cilium_computed_values leaks `metrics.enabled: []` into the emitted Application"
  }
  assert {
    condition     = output.cilium_effective_values.operator.replicas == 1
    error_message = "default-off: the floor's operator.replicas=1 must survive into cilium_effective_values when no observability input is set"
  }
  assert {
    condition     = try(output.cilium_effective_values.rollOutCiliumPods, null) == true
    error_message = "default-off: the floor's rollOutCiliumPods=true must survive into cilium_effective_values — without it a Day-2 values change reaches the emitted Application's cilium-config and never the running agents"
  }
  assert {
    condition     = !contains(keys(output.cilium_computed_values), "operator")
    error_message = "single-node: cilium_computed_values must carry NO operator key at one node with no operator metrics — an unconditional replicas leg would supersede the floor here and retire the operator sub-merge's only binding contributor"
  }

  assert {
    condition     = !contains(keys(output.cilium_computed_values), "prometheus")
    error_message = "default-off: cilium_computed_values (the seed's values layer) must not carry a prometheus key when cilium_agent_metrics is unset"
  }
  assert {
    condition     = !contains(keys(output.cilium_computed_values), "hubble")
    error_message = "default-off: cilium_computed_values must not carry a hubble key when cilium_hubble_enabled is unset"
  }
  assert {
    condition     = output.cilium_computed_values.kubeProxyReplacement == true
    error_message = "positive anchor: cilium_computed_values must be the real computed map, not an empty object — without this the two absence asserts above pass vacuously on a mis-wired fixture output"
  }

}

run "cilium_observability_ac1_all_three_legs_on" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_agent_metrics    = true
    cilium_operator_metrics = true
    cilium_hubble_enabled   = true
  }
  assert {
    condition     = output.cilium_effective_values.prometheus.enabled == true
    error_message = "AC#1 agent leg: cilium_agent_metrics=true must set cilium_effective_values.prometheus.enabled=true"
  }
  assert {
    condition     = output.cilium_effective_values.operator.prometheus.enabled == true
    error_message = "AC#1 operator leg: cilium_operator_metrics=true must set cilium_effective_values.operator.prometheus.enabled=true"
  }
  assert {
    condition     = output.cilium_effective_values.hubble.enabled == true
    error_message = "AC#1 hubble leg: cilium_hubble_enabled=true must set cilium_effective_values.hubble.enabled=true"
  }
}

run "cilium_hubble_metrics_list_is_carried_through" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_hubble_enabled = true
    cilium_hubble_metrics = ["dns", "drop", "tcp"]
  }
  assert {
    # tolist() on both sides: a tuple literal never equals a list(string) under `==`.
    condition     = tolist(output.cilium_effective_values.hubble.metrics.enabled) == tolist(["dns", "drop", "tcp"])
    error_message = "hubble_metrics leg: cilium_hubble_metrics must be carried verbatim into cilium_effective_values.hubble.metrics.enabled"
  }
}

run "cilium_hubble_tls_is_forced_off" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_hubble_enabled = true
  }
  assert {
    condition     = output.cilium_effective_values.hubble.tls.enabled == false
    error_message = "AC#2: cilium_hubble_enabled=true must force cilium_effective_values.hubble.tls.enabled=false (metrics-only scope, ADR-0022 §g)"
  }
}

run "cilium_agent_metric_overrides_reach_both_engines" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_agent_metrics          = true
    cilium_agent_metric_overrides = ["+cilium_bpf_map_pressure", "-cilium_node_connectivity_status"]
  }
  assert {
    condition     = output.cilium_computed_values.prometheus.enabled == true
    error_message = "intra-computed collision (M-P1), seed engine: prometheus.enabled from cilium_agent_metrics must survive alongside prometheus.metrics"
  }
  assert {
    condition     = tolist(output.cilium_computed_values.prometheus.metrics) == tolist(["+cilium_bpf_map_pressure", "-cilium_node_connectivity_status"])
    error_message = "seed engine (M-P2): cilium_agent_metric_overrides must reach cilium_computed_values.prometheus.metrics verbatim and in order"
  }
  assert {
    condition     = output.cilium_effective_values.prometheus.enabled == true
    error_message = "intra-computed collision (M-P1), emitted engine: prometheus.enabled must survive into cilium_effective_values alongside prometheus.metrics"
  }
  assert {
    condition     = tolist(output.cilium_effective_values.prometheus.metrics) == tolist(["+cilium_bpf_map_pressure", "-cilium_node_connectivity_status"])
    error_message = "emitted engine (M-P2): cilium_agent_metric_overrides must reach cilium_effective_values.prometheus.metrics verbatim and in order"
  }
}

run "cilium_agent_metrics_without_overrides_emits_no_metrics_key" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_agent_metrics = true
  }
  assert {
    condition     = try(output.cilium_computed_values.prometheus.metrics, null) == null
    error_message = "conditional emission: an empty cilium_agent_metric_overrides must emit NO prometheus.metrics key at all"
  }
  assert {
    condition     = output.cilium_computed_values.prometheus.enabled == true
    error_message = "positive anchor for the absence assert above: cilium_computed_values.prometheus must EXIST, so the absence assert cannot pass through a dropped parent"
  }
  assert {
    condition     = try(output.cilium_effective_values.prometheus.metrics, null) == null
    error_message = "conditional emission, emitted engine: an empty cilium_agent_metric_overrides must add no prometheus.metrics key to the emitted Application's valuesObject"
  }
  assert {
    condition     = output.cilium_effective_values.prometheus.enabled == true
    error_message = "positive anchor on the effective map for the assert above"
  }
}

run "cilium_hubble_open_metrics_reaches_both_engines" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_hubble_enabled      = true
    cilium_hubble_metrics      = ["dns", "drop"]
    cilium_hubble_open_metrics = true
  }
  assert {
    condition     = output.cilium_computed_values.hubble.metrics.enableOpenMetrics == true
    error_message = "seed engine: cilium_hubble_open_metrics=true must set cilium_computed_values.hubble.metrics.enableOpenMetrics=true"
  }
  assert {
    condition     = tolist(output.cilium_computed_values.hubble.metrics.enabled) == tolist(["dns", "drop"])
    error_message = "intra-computed collision (M-H2): hubble.metrics.enabled must survive the enableOpenMetrics sibling under hubble.metrics"
  }
  assert {
    condition     = output.cilium_computed_values.hubble.enabled == true
    error_message = "intra-computed collision (M-H1): hubble.enabled must survive the addition of the enableOpenMetrics contributor"
  }
  assert {
    condition     = output.cilium_computed_values.hubble.tls.enabled == false
    error_message = "intra-computed collision (M-H1) + ADR-0022 §g: hubble.tls.enabled=false must survive the enableOpenMetrics contributor — losing it re-arms the chart's template-time genCA path and de-determinizes the frozen seed render"
  }
  assert {
    condition     = output.cilium_effective_values.hubble.metrics.enableOpenMetrics == true
    error_message = "emitted engine: cilium_hubble_open_metrics=true must reach cilium_effective_values.hubble.metrics.enableOpenMetrics"
  }
}

run "cilium_hubble_on_without_open_metrics_emits_no_key" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_hubble_enabled = true
    cilium_hubble_metrics = ["dns"]
  }
  assert {
    condition     = try(output.cilium_computed_values.hubble.metrics.enableOpenMetrics, null) == null
    error_message = "conditional emission: cilium_hubble_open_metrics=false must emit NO hubble.metrics.enableOpenMetrics key at all"
  }
  assert {
    condition     = tolist(output.cilium_computed_values.hubble.metrics.enabled) == tolist(["dns"])
    error_message = "positive anchor for the absence assert above: cilium_computed_values.hubble.metrics must EXIST, so the absence assert cannot pass through a dropped parent"
  }
  assert {
    condition     = try(output.cilium_effective_values.hubble.metrics.enableOpenMetrics, null) == null
    error_message = "conditional emission, emitted engine: cilium_hubble_open_metrics=false must add no enableOpenMetrics key to the emitted Application's valuesObject"
  }
  assert {
    condition     = tolist(output.cilium_effective_values.hubble.metrics.enabled) == tolist(["dns"])
    error_message = "positive anchor on the effective map for the assert above"
  }
}

run "cilium_both_new_inputs_on" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_agent_metrics          = true
    cilium_agent_metric_overrides = ["+cilium_bpf_map_pressure"]
    cilium_hubble_enabled         = true
    cilium_hubble_metrics         = ["dns"]
    cilium_hubble_open_metrics    = true
  }
  assert {
    condition     = output.cilium_computed_values.prometheus.enabled == true
    error_message = "both-on: prometheus.enabled must survive with both new inputs set"
  }
  assert {
    condition     = tolist(output.cilium_computed_values.prometheus.metrics) == tolist(["+cilium_bpf_map_pressure"])
    error_message = "both-on: prometheus.metrics must survive with both new inputs set"
  }
  assert {
    condition     = tolist(output.cilium_computed_values.hubble.metrics.enabled) == tolist(["dns"])
    error_message = "both-on: hubble.metrics.enabled must survive with both new inputs set"
  }
  assert {
    condition     = output.cilium_computed_values.hubble.metrics.enableOpenMetrics == true
    error_message = "both-on: hubble.metrics.enableOpenMetrics must survive with both new inputs set"
  }
  assert {
    condition     = output.cilium_computed_values.hubble.tls.enabled == false
    error_message = "both-on: hubble.tls.enabled=false must survive with both new inputs set"
  }
  assert {
    condition     = tolist(output.cilium_effective_values.prometheus.metrics) == tolist(["+cilium_bpf_map_pressure"])
    error_message = "both-on, emitted engine: prometheus.metrics must reach cilium_effective_values with both new inputs set"
  }
  assert {
    condition     = output.cilium_effective_values.hubble.metrics.enableOpenMetrics == true
    error_message = "both-on, emitted engine: hubble.metrics.enableOpenMetrics must reach cilium_effective_values with both new inputs set"
  }
  assert {
    condition     = output.cilium_effective_values.hubble.tls.enabled == false
    error_message = "both-on, emitted engine: hubble.tls.enabled=false must survive into cilium_effective_values with both new inputs set"
  }
}

run "cilium_hubble_half_on_state_is_preserved" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_hubble_enabled = true
    cilium_hubble_metrics = []
  }
  assert {
    condition     = length(output.cilium_computed_values.hubble.metrics.enabled) == 0
    error_message = "half-on (ADR-0022 §k): cilium_hubble_metrics=[] must stay an empty list, not be dropped or defaulted"
  }
  assert {
    condition     = output.cilium_computed_values.hubble.enabled == true
    error_message = "half-on (ADR-0022 §k): the Hubble server must still be enabled with an empty metrics list"
  }
  assert {
    condition     = length(output.cilium_effective_values.hubble.metrics.enabled) == 0
    error_message = "half-on (ADR-0022 §k), emitted engine: the blessed half-on state must reach the emitted Application unchanged too"
  }
}

run "cilium_open_metrics_with_empty_metrics_list_warns" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_hubble_enabled      = true
    cilium_hubble_metrics      = []
    cilium_hubble_open_metrics = true
  }
  expect_failures = [check.cilium_hubble_open_metrics_effective]
}

run "cilium_metric_override_with_embedded_newline_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_agent_metrics          = true
    cilium_agent_metric_overrides = ["x\n  injected-key: pwned"]
  }
  expect_failures = [var.cilium_agent_metric_overrides]
}

run "cilium_metric_override_with_document_separator_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_agent_metrics          = true
    cilium_agent_metric_overrides = ["+ok", "---"]
  }
  expect_failures = [var.cilium_agent_metric_overrides]
}

run "cilium_metric_override_with_embedded_space_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_agent_metrics          = true
    cilium_agent_metric_overrides = ["+ok -smuggled"]
  }
  expect_failures = [var.cilium_agent_metric_overrides]
}

# RE2 `$` is \z, so this is rejected; Python's `$` is not, which is why the schema
# mirror excludes [\n\r] explicitly.
run "cilium_metric_override_with_trailing_newline_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_agent_metrics          = true
    cilium_agent_metric_overrides = ["+cilium_bpf_map_pressure\n"]
  }
  expect_failures = [var.cilium_agent_metric_overrides]
}

run "cilium_metric_override_without_prefix_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_agent_metrics          = true
    cilium_agent_metric_overrides = ["cilium_bpf_map_pressure"]
  }
  expect_failures = [var.cilium_agent_metric_overrides]
}

run "cilium_metric_overrides_wellformed_entries_plan_cleanly" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_agent_metrics          = true
    cilium_agent_metric_overrides = ["+cilium_bpf_map_pressure", "-cilium_node_connectivity_status", "+_leading_underscore"]
  }
  assert {
    condition     = length(output.cilium_computed_values.prometheus.metrics) == 3
    error_message = "negative-space: well-formed +metric / -metric entries must plan cleanly and reach the computed layer"
  }
}

run "cilium_hubble_metric_with_embedded_newline_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_hubble_enabled = true
    cilium_hubble_metrics = ["dns", "x\n  injected-hubble-key: pwned"]
  }
  expect_failures = [var.cilium_hubble_metrics]
}

run "cilium_hubble_metric_with_document_separator_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_hubble_enabled = true
    cilium_hubble_metrics = ["dns", "drop---evil"]
  }
  expect_failures = [var.cilium_hubble_metrics]
}

run "cilium_hubble_metrics_context_syntax_plans_cleanly" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_hubble_enabled = true
    cilium_hubble_metrics = ["dns:query;ignoreAAAA", "flow:sourceContext=pod;destinationContext=pod", "httpV2:exemplars=true"]
  }
  assert {
    condition     = length(output.cilium_computed_values.hubble.metrics.enabled) == 3
    error_message = "negative-space: Hubble's documented context syntax (colons, semicolons, equals signs) must plan cleanly and reach the computed layer"
  }
}

# The chart writes ipv4-native-routing-cidr raw, so an embedded newline would
# inject a sibling cilium-config key; the validation parses the value as a CIDR.

run "cilium_native_routing_cidr_with_embedded_newline_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_routing_mode        = "native"
    cilium_native_routing_cidr = "10.244.0.0/16\n  injected-native-key: pwned"
  }
  expect_failures = [var.cilium_native_routing_cidr]
}

run "cilium_native_routing_cidr_without_prefix_length_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_routing_mode        = "native"
    cilium_native_routing_cidr = "10.244.0.0"
  }
  expect_failures = [var.cilium_native_routing_cidr]
}

run "cilium_native_routing_cidr_documented_forms_plan_cleanly" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_routing_mode        = "native"
    cilium_native_routing_cidr = "10.99.0.0/16"
  }
  assert {
    condition     = output.cilium_computed_values.ipv4NativeRoutingCIDR == "10.99.0.0/16"
    error_message = "negative-space: a well-formed CIDR must plan cleanly and reach the computed values layer verbatim"
  }
}

run "cilium_native_routing_cidr_empty_derives_from_pod_cidr" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_routing_mode        = "native"
    cilium_native_routing_cidr = ""
    pod_cidr                   = ["10.244.0.0/16"]
  }
  assert {
    condition     = output.cilium_computed_values.ipv4NativeRoutingCIDR == "10.244.0.0/16"
    error_message = "negative-space: the empty string must stay accepted and keep deriving the CIDR from the first IPv4 pod_cidr entry"
  }
}

run "cilium_metric_inputs_accept_null_as_their_default" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_agent_metric_overrides = null
    cilium_hubble_open_metrics    = null
    cilium_hubble_metrics         = null
  }
  assert {
    condition     = !contains(keys(output.cilium_computed_values), "prometheus")
    error_message = "nullable=false: a null passed for a metric input must fall back to its declared default, leaving the computed layer at its all-off shape"
  }
}

run "cilium_metric_overrides_without_agent_metrics_warns" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_agent_metrics          = false
    cilium_agent_metric_overrides = ["+cilium_bpf_map_pressure"]
  }
  expect_failures = [check.cilium_agent_metric_overrides_effective]
}

run "cilium_open_metrics_without_hubble_warns" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_hubble_enabled      = false
    cilium_hubble_metrics      = ["dns"]
    cilium_hubble_open_metrics = true
  }
  expect_failures = [check.cilium_hubble_open_metrics_effective]
}

run "cilium_metric_overrides_without_deploy_cilium_warns" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    deploy_cilium                 = false
    cilium_agent_metrics          = true
    cilium_agent_metric_overrides = ["+cilium_bpf_map_pressure"]
  }
  expect_failures = [check.cilium_agent_metric_overrides_effective]
}

run "cilium_open_metrics_without_deploy_cilium_warns" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    deploy_cilium              = false
    cilium_hubble_enabled      = true
    cilium_hubble_metrics      = ["dns"]
    cilium_hubble_open_metrics = true
  }
  expect_failures = [check.cilium_hubble_open_metrics_effective]
}

run "cilium_floor_preservation_under_observability" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_operator_metrics = true
  }
  assert {
    condition     = output.cilium_effective_values.operator.replicas == 1
    error_message = "floor-preservation (M2): operator.replicas from the floor must survive the operator sub-merge alongside operator.prometheus"
  }
  assert {
    condition     = output.cilium_effective_values.cgroup.autoMount.enabled == false
    error_message = "floor-preservation (M1): cgroup.autoMount.enabled from the floor must survive the top-level merge"
  }
  assert {
    # Copy of the floor's ciliumAgent list in helm/cilium-values.yaml; order matters.
    condition = output.cilium_effective_values.securityContext.capabilities.ciliumAgent == [
      "CHOWN", "KILL", "NET_ADMIN", "NET_RAW", "NET_BIND_SERVICE",
      "IPC_LOCK", "SYS_ADMIN", "SYS_RESOURCE", "DAC_OVERRIDE", "FOWNER",
      "SETGID", "SETUID",
    ]
    error_message = "floor-preservation (M1): securityContext.capabilities.ciliumAgent from the floor must survive the top-level merge, verbatim and in order"
  }
}

run "cilium_operator_replicas_follow_node_count" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition     = output.cilium_effective_values.operator.replicas == 2
    error_message = "multi-node: cilium_effective_values.operator.replicas must be 2 at >= 2 nodes — the emitted self-management Application is the path that reaches a running cluster, so a floor-pinned 1 there leaves the operator without failover"
  }
  assert {
    condition     = output.cilium_computed_values.operator.replicas == 2
    error_message = "multi-node: cilium_computed_values.operator.replicas must be 2 at >= 2 nodes — the seed render reads the computed layer, so asserting only the effective map would leave the bootstrap engine unbound"
  }
}

run "cilium_operator_replicas_and_metrics_coexist" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_operator_metrics = true
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition     = output.cilium_computed_values.operator.replicas == 2
    error_message = "level-B (M-O1): the node-count replicas contributor must survive alongside operator.prometheus — two separate `operator` merge() terms would drop whichever came first"
  }
  assert {
    condition     = output.cilium_computed_values.operator.prometheus.enabled == true
    error_message = "level-B (M-O1): the cilium_operator_metrics contributor must survive alongside operator.replicas — two separate `operator` merge() terms would drop whichever came first"
  }
}

run "cilium_self_management_app_carries_the_node_count_replicas" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management = true
    deploy_argocd          = true
    deploy_cilium          = true
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition     = yamldecode(output.cilium_self_management_app).spec.source.helm.valuesObject.operator.replicas == 2
    error_message = "emitted Application: spec.source.helm.valuesObject.operator.replicas must be 2 at >= 2 nodes — asserting only local.cilium_effective_values leaves the effective-map-to-valuesObject wiring unbound, and that wiring is the whole delivery path for a self-managing consumer"
  }
}

run "cilium_operator_replicas_pin_overrides_the_derivation" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_operator_replicas = 1
    cilium_self_management   = true
    deploy_argocd            = true
    deploy_cilium            = true
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition     = output.cilium_computed_values.operator.replicas == 1
    error_message = "pin: cilium_computed_values.operator.replicas must be the pinned 1 at 2 nodes — a pin that loses to the node-count derivation is not a pin, and the computed layer is what the seed render reads"
  }
  assert {
    condition     = yamldecode(output.cilium_self_management_app).spec.source.helm.valuesObject.operator.replicas == 1
    error_message = "pin: the emitted Application's valuesObject.operator.replicas must be the pinned 1 — this path is the reason the input exists, because cilium_values_override is rejected alongside cilium_self_management and therefore cannot pin here"
  }
}

run "cilium_operator_replicas_pin_applies_where_the_derivation_is_silent" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_operator_replicas = 1
  }
  assert {
    condition     = output.cilium_computed_values.operator.replicas == 1
    error_message = "pin: a pinned 1 must reach the computed layer on a single-node cluster, where the node-count derivation emits nothing at all — otherwise the pin is only ever a filter on the derived value"
  }
  assert {
    condition     = output.cilium_operator_replicas_effective.source == "pin"
    error_message = "provenance: with cilium_operator_replicas set, the effective-count output must attribute the value to `pin` — an operator debugging a Pending replica needs to tell a pin from a derivation, and this is the only surface that answers it"
  }
}

# 2 against the single-node fixture, so only the node-count validation can fire.
run "cilium_operator_replicas_above_the_node_count_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_operator_replicas = 2
  }
  expect_failures = [var.cilium_operator_replicas]
}

# Pin 1 against the single-node fixture, so the node-count validation cannot fire.
run "cilium_operator_replicas_without_cilium_warns" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    deploy_cilium            = false
    cilium_operator_replicas = 1
  }
  expect_failures = [check.cilium_operator_replicas_effective]
}

run "cilium_operator_replicas_zero_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_operator_replicas = 0
  }
  expect_failures = [var.cilium_operator_replicas]
}

run "cilium_operator_replicas_fractional_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_operator_replicas = 1.5
  }
  expect_failures = [var.cilium_operator_replicas]
}

run "cilium_operator_replicas_pin_and_metrics_coexist" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_operator_replicas = 3
    cilium_operator_metrics  = true
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
      w-2  = { ip = "192.0.2.22", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition     = output.cilium_computed_values.operator.replicas == 3
    error_message = "level-B (M-O3): the PINNED replicas contributor must survive alongside operator.prometheus — a separate `operator` merge term for the pin would drop whichever came first"
  }
  assert {
    condition     = output.cilium_computed_values.operator.prometheus.enabled == true
    error_message = "level-B (M-O3): the cilium_operator_metrics contributor must survive alongside a pinned operator.replicas — a separate `operator` merge term for the pin would drop whichever came first"
  }
}

# The fixture's cilium_operator_replicas_effective output is a copy of the module's.
run "cilium_operator_replicas_provenance_is_node_count_when_derived" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition     = output.cilium_operator_replicas_effective == { count = 2, source = "node-count" }
    error_message = "provenance: an unpinned two-node cluster must report count 2 from `node-count` — the whole object is asserted so a count without its source, or a source without its count, cannot pass"
  }
}

run "cilium_operator_replicas_provenance_is_floor_when_silent" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  assert {
    condition     = output.cilium_operator_replicas_effective == { count = 1, source = "floor" }
    error_message = "provenance: an unpinned single-node cluster must report the floor's 1 from `floor` — this is also the only assert anywhere that reads the floor file's operator.replicas value, so deleting that key from helm/cilium-values.yaml turns it red instead of silently retiring two other gates"
  }
}

run "cilium_self_management_app_on_shape" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management = true
    deploy_argocd          = true
    deploy_cilium          = true
  }
  assert {
    condition     = output.cilium_self_management_app != ""
    error_message = "app-on: cilium_self_management_app must be non-empty when cilium_self_management=true"
  }
  assert {
    condition     = yamldecode(output.cilium_self_management_app).spec.source.targetRevision == var.cilium_chart_version
    error_message = "app-on shape: spec.source.targetRevision must equal var.cilium_chart_version"
  }
  assert {
    condition     = yamldecode(output.cilium_self_management_app).spec.destination.server == "https://kubernetes.default.svc"
    error_message = "app-on shape: spec.destination.server must be the in-cluster API server"
  }
  assert {
    condition     = yamldecode(output.cilium_self_management_app).spec.destination.namespace == var.cilium_namespace
    error_message = "app-on shape: spec.destination.namespace must equal var.cilium_namespace"
  }
  assert {
    condition     = yamldecode(output.cilium_self_management_app).metadata.namespace == var.argocd_namespace
    error_message = "app-on shape: metadata.namespace must equal var.argocd_namespace (the Application lives where ArgoCD watches)"
  }
  assert {
    condition     = yamldecode(output.cilium_self_management_app).spec.project == "default"
    error_message = "app-on shape: spec.project must default to \"default\" (the always-present permissive AppProject)"
  }
  assert {
    condition     = yamldecode(output.cilium_self_management_app).metadata.labels["app.kubernetes.io/managed-by"] == "argocd"
    error_message = "app-on shape: metadata.labels must carry the recommended app.kubernetes.io/managed-by=argocd label"
  }
  assert {
    condition     = !contains(keys(yamldecode(output.cilium_self_management_app).spec), "syncPolicy")
    error_message = "app-on shape: spec must carry NO syncPolicy (consumer controls sync timing — README)"
  }
}

# null must resolve to the declared default (`nullable = false`). Asserts the
# shape, not the literal, so the pin keeps a single copy.
run "null_chart_version_falls_back_to_the_declared_default" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management = true
    deploy_argocd          = true
    deploy_cilium          = true
    cilium_chart_version   = null
  }
  assert {
    condition     = yamldecode(output.cilium_self_management_app).spec.source.targetRevision != null
    error_message = "module-interface-contract §'Grouped typed input surface': cilium_chart_version = null must resolve to the variable's declared default (nullable = false); got null in spec.source.targetRevision"
  }
  assert {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", yamldecode(output.cilium_self_management_app).spec.source.targetRevision))
    error_message = "module-interface-contract §'Grouped typed input surface': the default substituted for a null cilium_chart_version must be a bare semver chart version"
  }
}

run "cilium_self_management_guard_leg_a_requires_argocd" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management = true
    deploy_argocd          = false
    deploy_cilium          = true
  }
  expect_failures = [var.cilium_self_management]
}

run "cilium_self_management_guard_leg_b_requires_cilium" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management = true
    deploy_argocd          = true
    deploy_cilium          = false
  }
  expect_failures = [var.cilium_self_management]
}

run "cilium_self_management_off_with_override_set_plans_clean" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_values_override = "bgpControlPlane:\n  enabled: true\n"
    cilium_self_management = false
  }
  assert {
    condition     = output.cilium_self_management_app == ""
    error_message = "negative-space: an override-only consumer (self_management=false) must plan cleanly with an empty emitted app, never rejected by the override-drop guard"
  }
}

run "cilium_self_management_multi_source_carries_the_override" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management = true
    deploy_argocd          = true
    deploy_cilium          = true
    cilium_values_override = "bgpControlPlane:\n  enabled: true\n"
    # A scoped project keeps the permissive-project check from firing.
    cilium_self_management_project = "platform-substrate"
    cilium_self_management_values_source = {
      repo_url      = "https://git.example.com/consumer/cluster.git"
      revision      = "v1.2.3"
      values_path   = "cilium/module-values.yaml"
      override_path = "cilium/override.yaml"
    }
  }

  assert {
    condition     = !contains(keys(yamldecode(output.cilium_self_management_app).spec), "source")
    error_message = "multi-source: spec must carry sources[], never the singular source — ArgoCD treats the two as mutually exclusive"
  }
  assert {
    condition     = yamldecode(output.cilium_self_management_app).spec.sources[0].ref == "values"
    error_message = "multi-source: sources[0] must be the ref source named \"values\" — $values/... resolves through nothing else"
  }
  assert {
    condition     = yamldecode(output.cilium_self_management_app).spec.sources[0].repoURL == "https://git.example.com/consumer/cluster.git"
    error_message = "multi-source: sources[0].repoURL must be the values source's repo_url"
  }
  assert {
    condition     = yamldecode(output.cilium_self_management_app).spec.sources[0].targetRevision == "v1.2.3"
    error_message = "multi-source: sources[0].targetRevision must be the values source's revision, so the values half is pinned like the chart half"
  }
  assert {
    condition     = !contains(keys(yamldecode(output.cilium_self_management_app).spec.sources[0]), "chart")
    error_message = "multi-source: sources[0] is ref-only and must declare no chart (it generates no manifests)"
  }

  # The whole list, not membership: the order is the precedence.
  assert {
    condition = yamldecode(output.cilium_self_management_app).spec.sources[1].helm.valueFiles == [
      "$values/cilium/module-values.yaml",
      "$values/cilium/override.yaml",
    ]
    error_message = "multi-source: sources[1].helm.valueFiles must be [module-set layer, consumer override] IN THAT ORDER — the order is the precedence, and reversing it silently drops the override"
  }
  assert {
    condition     = yamldecode(output.cilium_self_management_app).spec.sources[1].helm.ignoreMissingValueFiles == false
    error_message = "multi-source: ignoreMissingValueFiles must be explicitly false — it is the switch that turns a wrong values path from a loud sync error into a silent render against chart defaults"
  }
  assert {
    condition     = yamldecode(output.cilium_self_management_app).spec.sources[1].chart == "cilium"
    error_message = "multi-source: sources[1] must be the Cilium chart source"
  }

  assert {
    condition     = yamldecode(output.cilium_self_management_app).spec.sources[1].helm.valuesObject.kubeProxyReplacement == true
    error_message = "multi-source: valuesObject must re-assert kubeProxyReplacement as the last values layer"
  }
  assert {
    condition     = yamldecode(output.cilium_self_management_app).spec.sources[1].helm.valuesObject.k8sServiceHost == "localhost"
    error_message = "multi-source: valuesObject must re-assert k8sServiceHost as the last values layer"
  }
  assert {
    condition     = yamldecode(output.cilium_self_management_app).spec.sources[1].helm.valuesObject.k8sServicePort == "7445"
    error_message = "multi-source: valuesObject must re-assert k8sServicePort as the last values layer"
  }
  # The key set, not memberships: valuesObject carries the joint keys and nothing else.
  assert {
    condition     = join(",", sort(keys(yamldecode(output.cilium_self_management_app).spec.sources[1].helm.valuesObject))) == "k8sServiceHost,k8sServicePort,kubeProxyReplacement"
    error_message = "multi-source: valuesObject must carry the three joint keys AND NOTHING ELSE — it is applied after every valueFiles entry, so any additional key there silently beats the consumer's override"
  }

  assert {
    condition     = yamldecode(output.cilium_self_management_values).cni.exclusive == false
    error_message = "multi-source: cilium_self_management_values must carry the shipped floor (cni.exclusive=false) — it is the module-set layer the Application's first valueFiles entry reads"
  }
  assert {
    condition     = yamldecode(output.cilium_self_management_values).kubeProxyReplacement == true
    error_message = "multi-source: cilium_self_management_values must carry the computed layer too, not the floor alone"
  }
  assert {
    condition     = regex("values-digest: ([0-9a-f]{64})", output.cilium_self_management_values)[0] == yamldecode(output.cilium_self_management_app).metadata.annotations["talos-platform-base.io/values-digest"]
    error_message = "multi-source: the values file's header digest must equal the Application's talos-platform-base.io/values-digest annotation — it is the only thing a consumer-side gate can compare to catch a stale values file"
  }
  assert {
    condition     = regex("values-digest: ([0-9a-f]{64})", output.cilium_self_management_values)[0] == sha256(yamlencode(output.cilium_effective_values))
    error_message = "multi-source: the values-digest must be sha256(yamlencode(<module-set layer>)) — computed over anything else it cannot detect a stale values file, which is the only thing it exists for"
  }
}

run "cilium_self_management_multi_source_without_override_has_one_value_file" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management         = true
    deploy_argocd                  = true
    deploy_cilium                  = true
    cilium_self_management_project = "platform-substrate"
    cilium_self_management_values_source = {
      repo_url    = "https://git.example.com/consumer/cluster.git"
      revision    = "v1.2.3"
      values_path = "cilium/module-values.yaml"
    }
  }
  assert {
    condition     = yamldecode(output.cilium_self_management_app).spec.sources[1].helm.valueFiles == ["$values/cilium/module-values.yaml"]
    error_message = "multi-source without override: valueFiles must carry the module-set layer alone, not a path to an override file the consumer never wrote"
  }

}

run "emptied_override_with_a_configured_override_path_warns" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management         = true
    deploy_argocd                  = true
    deploy_cilium                  = true
    cilium_self_management_project = "platform-substrate"
    cilium_self_management_values_source = {
      repo_url      = "https://git.example.com/consumer/cluster.git"
      revision      = "v1.2.3"
      values_path   = "cilium/module-values.yaml"
      override_path = "cilium/override.yaml"
    }
  }
  expect_failures = [check.cilium_values_override_emptied_while_day2_wired]
}

run "values_source_without_self_management_warns" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management = false
    cilium_self_management_values_source = {
      repo_url    = "https://git.example.com/consumer/cluster.git"
      revision    = "v1.2.3"
      values_path = "cilium/module-values.yaml"
    }
  }
  expect_failures = [check.cilium_self_management_values_source_is_inert]
}

run "values_source_rejects_an_injected_newline_in_a_path" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management_values_source = {
      repo_url    = "https://git.example.com/consumer/cluster.git"
      revision    = "v1.2.3"
      values_path = "cilium/values.yaml\nhostNetwork: true"
    }
  }
  expect_failures = [var.cilium_self_management_values_source]
}

run "values_source_rejects_an_injected_newline_in_the_repo_url" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management_values_source = {
      repo_url    = "https://git.example.com/consumer/cluster.git\nhostNetwork: true"
      revision    = "v1.2.3"
      values_path = "cilium/module-values.yaml"
    }
  }
  expect_failures = [var.cilium_self_management_values_source]
}

run "values_source_accepts_the_documented_path_form" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management         = true
    deploy_argocd                  = true
    deploy_cilium                  = true
    cilium_values_override         = "bgpControlPlane:\n  enabled: true\n"
    cilium_self_management_project = "platform-substrate"
    cilium_self_management_values_source = {
      repo_url      = "git@git.example.com:consumer/cluster.git"
      revision      = "v1.2.3"
      values_path   = "clusters/prod-1/cilium/module-values.yaml"
      override_path = "clusters/prod-1/cilium/values-override.yaml"
    }
  }
  assert {
    condition     = length(yamldecode(output.cilium_self_management_app).spec.sources[1].helm.valueFiles) == 2
    error_message = "charset guard negative space: a nested repo-relative path and an SSH repo URL must plan cleanly"
  }
}

run "override_digest_tracks_the_override" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_values_override = "bgpControlPlane:\n  enabled: true\n"
  }
  assert {
    condition     = can(regex("^[0-9a-f]{64}$", output.cilium_values_override_digest))
    error_message = "override digest: a non-empty override must yield a sha256 hex digest"
  }
}

run "override_digest_is_empty_without_an_override" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  assert {
    condition     = output.cilium_values_override_digest == ""
    error_message = "override digest: an unset override must read as unset, not as the hash of the empty string"
  }
}

run "cilium_self_management_single_source_arm_is_unchanged" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management = true
    deploy_argocd          = true
    deploy_cilium          = true
  }
  assert {
    condition     = contains(keys(yamldecode(output.cilium_self_management_app).spec), "source")
    error_message = "single-source arm: spec.source must still be present with no values source configured"
  }
  assert {
    condition     = !contains(keys(yamldecode(output.cilium_self_management_app).spec), "sources")
    error_message = "single-source arm: spec.sources must be absent — the multi-source shape is opt-in via cilium_self_management_values_source"
  }
  assert {
    condition     = !contains(keys(yamldecode(output.cilium_self_management_app).metadata), "annotations")
    error_message = "single-source arm: metadata must carry no annotations — the values-digest describes a file this arm does not have, and adding a key here moves every existing consumer's manifest"
  }
  assert {
    condition     = output.cilium_self_management_values == ""
    error_message = "single-source arm: cilium_self_management_values must be empty — the module-set layer rides inline in valuesObject, there is no file to commit"
  }

  assert {
    condition     = output.cilium_self_management_app == replace(file("tests/fixtures/cilium-self-management-app-single-source.yaml"), "/(?m)^#.*\n/", "")
    error_message = "single-source arm: the emitted Application must be BYTE-IDENTICAL to tests/fixtures/cilium-self-management-app-single-source.yaml for this input set. A byte moved — every single-source consumer's manifest moved with it, so decide whether that belongs in UPGRADING.md, with the release class ADR-0029 assigns, before refreshing the fixture."
  }
}

# The override names no joint key, so only the values-source validation fires.
run "cilium_self_management_guard_leg_c_requires_values_source" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management = true
    deploy_argocd          = true
    deploy_cilium          = true
    cilium_values_override = "bgpControlPlane:\n  enabled: true\n"
  }
  expect_failures = [var.cilium_self_management]
}

# Each override is a well-formed mapping, so only the joint-key validation fires.
run "cilium_values_override_rejects_kube_proxy_replacement" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_values_override = "kubeProxyReplacement: false\n"
  }
  expect_failures = [var.cilium_values_override]
}

run "cilium_values_override_rejects_k8s_service_host" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_values_override = "k8sServiceHost: 192.0.2.10\n"
  }
  expect_failures = [var.cilium_values_override]
}

run "cilium_values_override_rejects_k8s_service_port" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_values_override = "k8sServicePort: \"6443\"\n"
  }
  expect_failures = [var.cilium_values_override]
}

run "cilium_values_override_accepts_neighbouring_keys" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_values_override = "k8sServiceHostOverrideNote: keep\nkubeProxyReplacementHealthzBindAddr: \"0.0.0.0:10256\"\n"
  }
  assert {
    condition     = output.cilium_self_management_app == ""
    error_message = "joint-key guard: only the three exact key names are closed — a neighbouring key must plan cleanly"
  }
}

run "cilium_values_override_rejects_a_comment_only_document" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_values_override = "# nothing configured yet\n"
  }
  expect_failures = [var.cilium_values_override]
}

run "cilium_values_override_rejects_a_sequence_document" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_values_override = "- bgpControlPlane\n- hubble\n"
  }
  expect_failures = [var.cilium_values_override]
}

# Each leg trips exactly one of the three validations on the variable.
run "values_source_rejects_a_missing_values_path" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management_values_source = {
      repo_url    = "https://git.example.com/consumer/cluster.git"
      revision    = "v1.2.3"
      values_path = ""
    }
  }
  expect_failures = [var.cilium_self_management_values_source]
}

run "values_source_rejects_an_absolute_path" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management_values_source = {
      repo_url    = "https://git.example.com/consumer/cluster.git"
      revision    = "v1.2.3"
      values_path = "/etc/cilium/values.yaml"
    }
  }
  expect_failures = [var.cilium_self_management_values_source]
}

run "values_source_rejects_a_parent_traversal_path" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management_values_source = {
      repo_url    = "https://git.example.com/consumer/cluster.git"
      revision    = "v1.2.3"
      values_path = "cilium/../../secrets/values.yaml"
    }
  }
  expect_failures = [var.cilium_self_management_values_source]
}

run "values_source_rejects_a_missing_override_path_while_an_override_is_set" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management = true
    deploy_argocd          = true
    deploy_cilium          = true
    cilium_values_override = "bgpControlPlane:\n  enabled: true\n"
    cilium_self_management_values_source = {
      repo_url    = "https://git.example.com/consumer/cluster.git"
      revision    = "v1.2.3"
      values_path = "cilium/module-values.yaml"
    }
  }
  expect_failures = [var.cilium_self_management_values_source]
}

run "k8s_service_endpoint_defaults_to_kubeprism" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    deploy_cilium = true
  }
  assert {
    condition     = output.cilium_computed_values.k8sServiceHost == "localhost"
    error_message = "endpoint defaults: k8sServiceHost must default to Talos KubePrism's localhost"
  }
  assert {
    condition     = output.cilium_computed_values.k8sServicePort == "7445"
    error_message = "endpoint defaults: k8sServicePort must default to Talos KubePrism's 7445"
  }
}

run "k8s_service_endpoint_inputs_reach_the_computed_layer" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    deploy_cilium           = true
    cilium_k8s_service_host = "api.cluster.example"
    cilium_k8s_service_port = "6443"
  }
  assert {
    condition     = output.cilium_computed_values.k8sServiceHost == "api.cluster.example"
    error_message = "endpoint inputs: cilium_k8s_service_host must reach the computed layer, which is what both delivery paths read"
  }
  assert {
    condition     = output.cilium_computed_values.k8sServicePort == "6443"
    error_message = "endpoint inputs: cilium_k8s_service_port must reach the computed layer"
  }
  assert {
    condition     = output.cilium_joint_keys.k8sServiceHost == "api.cluster.example"
    error_message = "endpoint inputs: the joint-key re-assertion must carry the configured host, not a hardcoded KubePrism literal"
  }
}

run "k8s_service_endpoint_is_absent_without_kube_proxy_replacement" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    deploy_cilium                 = true
    cilium_kube_proxy_replacement = false
  }
  assert {
    condition     = !contains(keys(output.cilium_computed_values), "k8sServiceHost")
    error_message = "endpoint gating: k8sServiceHost must not be emitted when cilium_kube_proxy_replacement is false"
  }
  assert {
    condition     = keys(output.cilium_joint_keys) == ["kubeProxyReplacement"]
    error_message = "endpoint gating: the joint-key re-assertion must carry kubeProxyReplacement alone when the toggle is off"
  }
}

run "k8s_service_host_rejects_a_scheme" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_k8s_service_host = "https://api.cluster.example"
  }
  expect_failures = [var.cilium_k8s_service_host]
}

run "k8s_service_host_rejects_an_embedded_port" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_k8s_service_host = "api.cluster.example:6443"
  }
  expect_failures = [var.cilium_k8s_service_host]
}

run "k8s_service_host_rejects_an_injected_newline" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_k8s_service_host = "localhost\n  injected-key: pwned"
  }
  expect_failures = [var.cilium_k8s_service_host]
}

run "k8s_service_port_rejects_an_out_of_range_port" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_k8s_service_port = "70000"
  }
  expect_failures = [var.cilium_k8s_service_port]
}

run "k8s_service_port_rejects_a_non_numeric_port" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_k8s_service_port = "kubeprism"
  }
  expect_failures = [var.cilium_k8s_service_port]
}

run "duplicate_ip_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.11", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
  expect_failures = [var.nodes]
}

run "even_controlplane_count_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      cp-2 = { ip = "192.0.2.12", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  expect_failures = [var.nodes]
}

run "four_controlplanes_are_rejected_too" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      cp-2 = { ip = "192.0.2.12", role = "controlplane", image = "intel", hardware_capabilities = [] },
      cp-3 = { ip = "192.0.2.13", role = "controlplane", image = "intel", hardware_capabilities = [] },
      cp-4 = { ip = "192.0.2.14", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  expect_failures = [var.nodes]
}

run "three_controlplanes_plan_cleanly" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      cp-2 = { ip = "192.0.2.12", role = "controlplane", image = "intel", hardware_capabilities = [] },
      cp-3 = { ip = "192.0.2.13", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
}

run "uppercase_node_key_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      CP-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  expect_failures = [var.nodes]
}

run "underscore_node_key_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      cp_1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  expect_failures = [var.nodes]
}

run "leading_dash_node_key_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      "-cp-1" = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  expect_failures = [var.nodes]
}

run "overlong_label_node_key_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      # 64 chars — one over the DNS label limit.
      "cp-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  expect_failures = [var.nodes]
}

run "trailing_dash_node_key_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      "cp-1-" = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  expect_failures = [var.nodes]
}

# 4 x 63 + 3 dots = 255: every label fits, so only the total-length rule fires.
run "overlong_total_node_key_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    register_with_fqdn = true
    nodes = {
      "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb.ccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc.ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd" = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  expect_failures = [var.nodes]
}

run "sixty_three_character_label_plans_cleanly" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      "cp-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
}

# Both the first-label and the dotted-key rule fire; the next two runs separate them.
run "colliding_first_labels_are_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    register_with_fqdn = false
    nodes = {
      "node-a.site1.example.org" = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      "node-a.site2.example.org" = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
  expect_failures = [var.nodes]
}

run "dotted_key_without_register_with_fqdn_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    register_with_fqdn = false
    nodes = {
      "node-a.site1.example.org" = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  # One node, so only the dotted-key rule can fire.
  expect_failures = [var.nodes]
}

run "colliding_first_labels_are_legal_with_register_with_fqdn" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    register_with_fqdn = true
    nodes = {
      "node-a.site1.example.org" = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      "node-a.site2.example.org" = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
}

run "distinct_fqdn_keys_with_register_with_fqdn_plan_cleanly" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    register_with_fqdn = true
    nodes = {
      "node-a.site1.example.org" = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      "node-b.site2.example.org" = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
}

# The parity rule's `count == 0` arm keeps it from firing here.
run "node_set_without_controlplane_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      w-1 = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
  expect_failures = [var.nodes]
}

# One valid controlplane keeps the parity and at-least-one rules from firing.
run "invalid_node_role_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.21", role = "master", image = "intel", hardware_capabilities = [] },
    }
  }
  expect_failures = [var.nodes]
}

run "non_canonical_ipv4_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      cp-1 = { ip = "192.0.2.011", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  expect_failures = [var.nodes]
}

run "ipv4_mapped_ipv6_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      cp-1 = { ip = "::ffff:192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  expect_failures = [var.nodes]
}

run "canonical_ipv6_plans_cleanly" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      cp-1 = { ip = "2001:db8::1", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
}

run "register_with_fqdn_emits_the_kubelet_patch" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    register_with_fqdn = true
  }
  assert {
    condition     = length(output.register_with_fqdn_patch) == 1
    error_message = "register_with_fqdn = true must emit exactly one all-nodes patch"
  }
  assert {
    condition     = yamldecode(output.register_with_fqdn_patch[0]).machine.kubelet.registerWithFQDN == true
    error_message = "the emitted patch must set machine.kubelet.registerWithFQDN = true"
  }
}

run "register_with_fqdn_default_emits_no_patch" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  assert {
    condition     = length(output.register_with_fqdn_patch) == 0
    error_message = "register_with_fqdn defaults to false and must then emit no patch at all"
  }
}

# `a-w` sorts below every controlplane, so a "first key overall" bootstrap target fails.
run "projections_and_bootstrap_target_follow_node_name" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      w-2  = { ip = "192.0.2.22", role = "worker", image = "intel", hardware_capabilities = [] },
      cp-3 = { ip = "192.0.2.13", role = "controlplane", image = "intel", hardware_capabilities = [] },
      a-w  = { ip = "192.0.2.20", role = "worker", image = "intel", hardware_capabilities = [] },
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      cp-2 = { ip = "192.0.2.12", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition     = tolist(output.controlplane_ips) == tolist(["192.0.2.11", "192.0.2.12", "192.0.2.13"])
    error_message = "controlplane_ips must carry the controlplane IPs in node-name order (cp-1, cp-2, cp-3)"
  }
  assert {
    condition     = tolist(output.worker_ips) == tolist(["192.0.2.20", "192.0.2.22"])
    error_message = "worker_ips must carry the worker IPs in node-name order (a-w, w-2)"
  }
  assert {
    condition     = tolist(output.node_ips) == tolist(["192.0.2.20", "192.0.2.11", "192.0.2.12", "192.0.2.13", "192.0.2.22"])
    error_message = "node_ips must carry every node's IP in node-name order across both roles (a-w, cp-1, cp-2, cp-3, w-2)"
  }
  assert {
    condition     = output.first_controlplane_ip == "192.0.2.11"
    error_message = "the bootstrap target must be the lowest-named CONTROLPLANE (cp-1) — not the lowest-named node overall (a-w, a worker)"
  }
}

run "values_source_on_the_default_project_warns" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management = true
    deploy_argocd          = true
    deploy_cilium          = true
    cilium_self_management_values_source = {
      repo_url    = "https://git.example.com/consumer/cluster.git"
      revision    = "v1.2.3"
      values_path = "cilium/module-values.yaml"
    }
  }
  expect_failures = [check.cilium_self_management_values_source_on_permissive_project]
}

run "values_source_rejects_a_non_git_repo_url_scheme" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management_values_source = {
      repo_url    = "file:///etc/cilium/values"
      revision    = "v1.2.3"
      values_path = "cilium/module-values.yaml"
    }
  }
  expect_failures = [var.cilium_self_management_values_source]
}

run "values_source_rejects_embedded_credentials_in_the_repo_url" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management_values_source = {
      repo_url    = "https://oauth2:ghp_exampletokenvalue@git.example.com/consumer/cluster.git"
      revision    = "v1.2.3"
      values_path = "cilium/module-values.yaml"
    }
  }
  expect_failures = [var.cilium_self_management_values_source]
}

run "values_source_accepts_an_ssh_scheme_repo_url" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management         = true
    deploy_argocd                  = true
    deploy_cilium                  = true
    cilium_self_management_project = "platform-substrate"
    cilium_self_management_values_source = {
      # The documented ssh form, username included.
      repo_url    = "ssh://git@git.example.com:2222/consumer/cluster.git"
      revision    = "v1.2.3"
      values_path = "cilium/module-values.yaml"
    }
  }
  assert {
    condition     = yamldecode(output.cilium_self_management_app).spec.sources[0].repoURL == "ssh://git@git.example.com:2222/consumer/cluster.git"
    error_message = "allowlist negative space: the documented ssh://user@host:port/path git remote must plan cleanly and reach sources[0].repoURL verbatim"
  }
}

run "values_source_rejects_one_path_for_both_layers" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management = true
    deploy_argocd          = true
    deploy_cilium          = true
    cilium_values_override = "bgpControlPlane:\n  enabled: true\n"
    cilium_self_management_values_source = {
      repo_url      = "https://git.example.com/consumer/cluster.git"
      revision      = "v1.2.3"
      values_path   = "cilium/values.yaml"
      override_path = "cilium/values.yaml"
    }
  }
  expect_failures = [var.cilium_self_management_values_source]
}

run "k8s_service_port_rejects_an_injected_newline" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_k8s_service_port = "7445\n  injected-key: pwned"
  }
  expect_failures = [var.cilium_k8s_service_port]
}

run "k8s_service_port_rejects_zero" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_k8s_service_port = "0"
  }
  expect_failures = [var.cilium_k8s_service_port]
}

run "k8s_service_host_accepts_a_bare_ipv6_literal" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_k8s_service_host = "2001:db8::1"
  }
  assert {
    condition     = output.cilium_joint_keys.k8sServiceHost == "2001:db8::1"
    error_message = "host guard negative space: an unbracketed IPv6 literal is the form client-go expects and must plan cleanly, reaching the joint keys verbatim"
  }
}

run "k8s_service_host_rejects_a_bracketed_ipv6_literal" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_k8s_service_host = "[2001:db8::1]"
  }
  expect_failures = [var.cilium_k8s_service_host]
}

run "k8s_service_host_rejects_a_hex_host_port_pair" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_k8s_service_host = "abc:6443"
  }
  expect_failures = [var.cilium_k8s_service_host]
}

run "values_source_rejects_a_password_in_an_ssh_repo_url" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management_values_source = {
      repo_url    = "ssh://git:hunter2@git.example.com/consumer/cluster.git"
      revision    = "v1.2.3"
      values_path = "cilium/module-values.yaml"
    }
  }
  expect_failures = [var.cilium_self_management_values_source]
}

run "values_source_rejects_a_non_normalized_path_segment" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management_values_source = {
      repo_url      = "https://git.example.com/consumer/cluster.git"
      revision      = "v1.2.3"
      values_path   = "cilium/values.yaml"
      override_path = "./cilium/values.yaml"
    }
  }
  expect_failures = [var.cilium_self_management_values_source]
}

run "values_source_rejects_a_doubled_path_separator" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management_values_source = {
      repo_url    = "https://git.example.com/consumer/cluster.git"
      revision    = "v1.2.3"
      values_path = "cilium//module-values.yaml"
    }
  }
  expect_failures = [var.cilium_self_management_values_source]
}

run "k8s_service_host_rejects_a_non_parsing_hex_colon_string" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_k8s_service_host = "1:2:3"
  }
  expect_failures = [var.cilium_k8s_service_host]
}

run "k8s_service_host_rejects_an_oversized_hex_group" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_k8s_service_host = "fffff:1:2"
  }
  expect_failures = [var.cilium_k8s_service_host]
}

run "k8s_service_host_rejects_a_nine_group_literal" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_k8s_service_host = "1:2:3:4:5:6:7:8:9"
  }
  expect_failures = [var.cilium_k8s_service_host]
}

run "k8s_service_host_rejects_a_non_canonical_spelling" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_k8s_service_host = "2001:0db8::1"
  }
  expect_failures = [var.cilium_k8s_service_host]
}

run "k8s_service_host_rejects_an_ipv4_embedded_literal" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_k8s_service_host = "::ffff:192.0.2.1"
  }
  expect_failures = [var.cilium_k8s_service_host]
}

run "k8s_service_endpoint_without_kube_proxy_replacement_warns" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_kube_proxy_replacement = false
    cilium_k8s_service_host       = "api.cluster.example"
  }
  expect_failures = [check.cilium_k8s_service_endpoint_effective]
}

run "default_endpoint_without_kube_proxy_replacement_is_silent" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_kube_proxy_replacement = false
  }
  assert {
    condition     = output.cilium_effective_values.kubeProxyReplacement == false
    error_message = "with kube-proxy replacement off the computed layer must still carry the toggle itself — only the endpoint keys drop out"
  }
}
