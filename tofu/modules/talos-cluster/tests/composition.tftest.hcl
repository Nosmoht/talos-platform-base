# Network-bound (seed Helm charts): runs under `task tofu:test` only. Seed asserts
# read data.helm_template directly, because terraform_data output is unknown at plan.

provider "talos" {}
provider "helm" {}

# Stands in for the Image Factory; the superstring name keeps the exact-name filter
# in image-factory.tf load-bearing.
override_data {
  target = data.talos_image_factory_extensions_versions.per_schematic
  values = {
    extensions_info = [
      for name in [
        "siderolabs/drbd",
        "siderolabs/drbd-superstring",
        "siderolabs/intel-ucode",
      ] : { name = name, ref = "", digest = "", author = "", description = "" }
    ]
  }
}

variables {
  cluster_name       = "test"
  cluster_endpoint   = "https://192.0.2.1:6443"
  talos_version      = "v1.13.9"
  kubernetes_version = "v1.36.3"
  deploy_argocd      = false
  deploy_cilium      = false

  images = {
    intel = { architecture = "amd64", cpu_vendor = "intel", extensions = ["siderolabs/intel-ucode"] }
    arm   = { architecture = "arm64", cpu_vendor = "arm", extensions = [], overlay = { name = "rpi_generic", image = "siderolabs/sbc-raspberrypi" } }
  }
  hardware_capabilities = {
    storage-replicated = { requires_features = ["drbd-kernel-module"], provisioning_profiles = ["drbd"], emits_label = "platform.io/hardware-capability.storage-replicated" }
    virt-passthrough   = { requires_features = ["vt-x-or-amd-v", "kvm-kernel-module", "iommu-enabled"], provisioning_profiles = ["iommu"], emits_label = "platform.io/hardware-capability.virt-passthrough" }
  }
  nodes = {
    cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["storage-replicated"] },
  }
}

# w-1 and w-2 list the same capabilities in reverse order.
run "valid_dedup_and_determinism" {
  command = plan
  variables {
    nodes = {
      cp-1     = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["storage-replicated"] },
      w-1      = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = ["storage-replicated", "virt-passthrough"] },
      w-2      = { ip = "192.0.2.22", role = "worker", image = "intel", hardware_capabilities = ["virt-passthrough", "storage-replicated"] },
      node-arm = { ip = "192.0.2.41", role = "worker", image = "arm", hardware_capabilities = [] },
    }
  }
  assert {
    condition     = output.distinct_schematic_count == 3
    error_message = "expected 3 distinct schematics (cp storage / w storage+virt [w-1==w-2 dedup] / arm), got ${output.distinct_schematic_count}"
  }
  assert {
    condition     = output.node_schematic_hashes["w-1"] == output.node_schematic_hashes["w-2"]
    error_message = "determinism: reversed-capability-order nodes w-1 and w-2 must hash identically"
  }
  assert {
    condition     = output.node_schematic_hashes["cp-1"] != output.node_schematic_hashes["w-1"]
    error_message = "storage-only and storage+virt nodes must NOT share a schematic (virt adds IOMMU kernel args)"
  }
  assert {
    condition     = yamldecode(talos_image_factory_schematic.this[output.node_schematic_hashes["w-1"]].schematic).customization.systemExtensions.officialExtensions == ["siderolabs/drbd", "siderolabs/intel-ucode"]
    error_message = "node-image-composition §'Substring expansion cannot bake unrequested extensions': w-1's schematic must bake exactly its declared extensions; got ${jsonencode(yamldecode(talos_image_factory_schematic.this[output.node_schematic_hashes["w-1"]].schematic).customization.systemExtensions.officialExtensions)}"
  }
}

run "image_extra_kernel_args_land_in_the_rendered_schematic" {
  command = plan
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = ["siderolabs/intel-ucode"], extra_kernel_args = ["hugepagesz=1G"] }
    }
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = ["virt-passthrough"] },
    }
  }
  assert {
    condition = alltrue([for a in ["hugepagesz=1G", "intel_iommu=on"] : contains(
      try(yamldecode(talos_image_factory_schematic.this[output.node_schematic_hashes["w-1"]].schematic).customization.extraKernelArgs, []), a
    )])
    error_message = "w-1's rendered schematic customization.extraKernelArgs must contain BOTH the image's extra_kernel_args (hugepagesz=1G) and the resolved profile karg (intel_iommu=on from virt-passthrough -> iommu); got ${jsonencode(try(yamldecode(talos_image_factory_schematic.this[output.node_schematic_hashes["w-1"]].schematic).customization.extraKernelArgs, []))}"
  }
}

run "symmetry_forward_violation" {
  command = plan
  variables {
    hardware_capabilities = {
      bad = { requires_features = ["drbd-kernel-module"], provisioning_profiles = [], emits_label = "platform.io/hardware-capability.bad" }
    }
    nodes = { cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["bad"] } }
  }
  expect_failures = [terraform_data.composition_guards]
}

run "symmetry_inverse_violation" {
  command = plan
  variables {
    hardware_capabilities = {
      bad = { requires_features = [], provisioning_profiles = ["drbd"], emits_label = "platform.io/hardware-capability.bad" }
    }
    nodes = { cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["bad"] } }
  }
  expect_failures = [terraform_data.composition_guards]
}

run "symmetry_per_capability_not_masked_by_union" {
  command = plan
  variables {
    hardware_capabilities = {
      label_only     = { requires_features = ["drbd-kernel-module"], provisioning_profiles = [], emits_label = "platform.io/hardware-capability.label-only" }
      provision_only = { requires_features = [], provisioning_profiles = ["drbd"], emits_label = "platform.io/hardware-capability.provision-only" }
    }
    nodes = { cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["label_only", "provision_only"] } }
  }
  expect_failures = [terraform_data.composition_guards]
}

run "variant_mismatch" {
  command = plan
  variables {
    hardware_capabilities = {
      vp = { requires_features = ["iommu-enabled"], provisioning_profiles = ["iommu"], emits_label = "platform.io/hardware-capability.vp" }
    }
    nodes = {
      cp-1  = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      arm-1 = { ip = "192.0.2.41", role = "worker", image = "arm", hardware_capabilities = ["vp"] },
    }
  }
  expect_failures = [terraform_data.composition_guards]
}

run "unresolved_extension_fails_the_plan" {
  command = plan
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = ["siderolabs/intel-ucod"] }
    }
    nodes = { cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] } }
  }
  expect_failures = [talos_image_factory_schematic.this]
}

run "duplicate_resolution_fails_the_plan" {
  command = plan
  override_data {
    target = data.talos_image_factory_extensions_versions.per_schematic
    values = {
      extensions_info = [
        for name in ["siderolabs/intel-ucode", "siderolabs/intel-ucode"] :
        { name = name, ref = "", digest = "", author = "", description = "" }
      ]
    }
  }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = ["siderolabs/intel-ucode", "siderolabs/drbd"] }
    }
    nodes = { cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] } }
  }
  expect_failures = [talos_image_factory_schematic.this]
}

run "undefined_image" {
  command = plan
  variables {
    nodes = { cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "ghost", hardware_capabilities = [] } }
  }
  expect_failures = [terraform_data.composition_guards]
}

run "undefined_capability" {
  command = plan
  variables {
    nodes = { cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["ghost"] } }
  }
  expect_failures = [terraform_data.composition_guards]
}

run "emits_label_reserved_namespace_rejected" {
  command = plan
  variables {
    hardware_capabilities = {
      forge = { requires_features = [], provisioning_profiles = [], emits_label = "platform.io/hardware-feature.iommu-enabled" }
    }
    nodes = { cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] } }
  }
  expect_failures = [var.hardware_capabilities]
}

run "argocd_namespace_seed_carries_psa_floor_and_recommended_labels" {
  command = plan
  variables {
    deploy_argocd = true
    sops_age_key  = "AGE-SECRET-KEY-1TESTONLYPLACEHOLDERNOTAREALKEY00000000000000000000000000000"
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition     = lookup(output.argocd_namespace_labels, "pod-security.kubernetes.io/enforce", "<absent>") == "baseline"
    error_message = "AGENTS.md §Hard Constraints + namespace.yaml PSA floor: the module-seeded argocd namespace must enforce PSA baseline; got '${lookup(output.argocd_namespace_labels, "pod-security.kubernetes.io/enforce", "<absent>")}'"
  }
  assert {
    condition = length(setsubtract(
      ["app.kubernetes.io/name", "app.kubernetes.io/instance", "app.kubernetes.io/version", "app.kubernetes.io/component", "app.kubernetes.io/part-of", "app.kubernetes.io/managed-by"],
      keys(output.argocd_namespace_labels)
    )) == 0
    error_message = "AGENTS.md §Hard Constraints: all six app.kubernetes.io/* recommended labels must be seeded on the argocd namespace; missing: ${jsonencode(setsubtract(["app.kubernetes.io/name", "app.kubernetes.io/instance", "app.kubernetes.io/version", "app.kubernetes.io/component", "app.kubernetes.io/part-of", "app.kubernetes.io/managed-by"], keys(output.argocd_namespace_labels)))}"
  }
}

run "kubelet_serving_cert_rotation_and_cert_approver_seed" {
  command = plan
  variables {
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }

  assert {
    condition     = output.kubelet_serving_cert_rotation.controlplane
    error_message = "adr-0013 (plan Goal 1): kubelet serving-cert rotation must be wired into the controlplane machine-config patch list"
  }
  assert {
    condition     = output.kubelet_serving_cert_rotation.worker
    error_message = "adr-0013 (plan Goal 1): kubelet serving-cert rotation must be wired into the WORKER machine-config patch list — the serving cert is per kubelet, workers need it too"
  }
  assert {
    condition     = try(output.kubelet_rotation_setting.machine.kubelet.extraConfig.serverTLSBootstrap, null) == true
    error_message = "adr-0013 + no-deprecated-options directive: rotation must use machine.kubelet.extraConfig.serverTLSBootstrap = true (KubeletConfiguration), NOT the deprecated --rotate-server-certificates extraArgs flag"
  }
  assert {
    condition     = try(output.kubelet_rotation_setting.machine.kubelet.extraArgs["rotate-server-certificates"], null) == null
    error_message = "no-deprecated-options directive: the deprecated machine.kubelet.extraArgs.rotate-server-certificates flag must be absent (use extraConfig.serverTLSBootstrap instead)"
  }
  assert {
    condition     = output.cert_approver_seeded
    error_message = "adr-0013 (plan Goal 2): the cert-approver inlineManifest seed must be wired into the controlplane machine-config patch list"
  }
  assert {
    condition     = lookup(output.cert_approver_namespace_labels, "pod-security.kubernetes.io/enforce", "<absent>") == "restricted"
    error_message = "adr-0013 + namespace PSA floor: the cert-approver namespace must enforce PSA restricted; got '${lookup(output.cert_approver_namespace_labels, "pod-security.kubernetes.io/enforce", "<absent>")}'"
  }
  assert {
    condition = length(setsubtract(
      ["app.kubernetes.io/name", "app.kubernetes.io/instance", "app.kubernetes.io/version", "app.kubernetes.io/component", "app.kubernetes.io/part-of", "app.kubernetes.io/managed-by"],
      keys(output.cert_approver_namespace_labels)
    )) == 0
    error_message = "AGENTS.md §Hard Constraints: all six app.kubernetes.io/* recommended labels must be seeded on the cert-approver namespace; missing: ${jsonencode(setsubtract(["app.kubernetes.io/name", "app.kubernetes.io/instance", "app.kubernetes.io/version", "app.kubernetes.io/component", "app.kubernetes.io/part-of", "app.kubernetes.io/managed-by"], keys(output.cert_approver_namespace_labels)))}"
  }
  assert {
    condition     = output.cert_approver_approve_resource_names == ["kubernetes.io/kubelet-serving"]
    error_message = "adr-0013 §Security (H7): the cert-approver ClusterRole `approve` verb must be resourceNames-scoped to exactly [kubernetes.io/kubelet-serving]; got ${jsonencode(output.cert_approver_approve_resource_names)}"
  }
  assert {
    condition     = output.controlplane_base_is_prefix_of_final
    error_message = "adr-0013 §Validation: controlplane_machine_config_patches must begin with controlplane_base_patches (sensitive seeds appended after); the base-sublist wiring assertions only bind the final list if this prefix invariant holds"
  }
  # The seed bypasses the kustomize label gate, so the labels are asserted here.
  assert {
    condition     = length(output.cert_approver_seed_missing_labels) == 0
    error_message = "AGENTS.md §Hard Constraints: every object in the cert-approver seed must carry all six app.kubernetes.io/* recommended labels; object-flattened missing set: ${jsonencode(output.cert_approver_seed_missing_labels)}"
  }
  # Empty provider_ip_prefixes would deny every IP-SAN CSR, so the default is all IPs.
  assert {
    condition     = output.cert_approver_env["PROVIDER_REGEX"] == ".*" && output.cert_approver_env["PROVIDER_IP_PREFIXES"] == "0.0.0.0/0,::/0" && output.cert_approver_env["BYPASS_DNS_RESOLUTION"] == "true"
    error_message = "adr-0019: default cert-approver config must inject PROVIDER_REGEX='.*', PROVIDER_IP_PREFIXES='0.0.0.0/0,::/0' (the all-IPs floor, NOT empty), BYPASS_DNS_RESOLUTION='true'; got ${jsonencode(output.cert_approver_env)}"
  }
  assert {
    condition     = try(output.cert_approver_pod_security_context.runAsNonRoot, false) == true && try(output.cert_approver_pod_security_context.readOnlyRootFilesystem, false) == true && try(output.cert_approver_pod_security_context.seccompProfile.type, "") == "RuntimeDefault" && contains(try(output.cert_approver_pod_security_context.capabilities.drop, []), "ALL")
    error_message = "adr-0019 + restricted PSA: the cert-approver container securityContext must set runAsNonRoot, readOnlyRootFilesystem, drop [ALL] and RuntimeDefault seccomp; got ${jsonencode(output.cert_approver_pod_security_context)}"
  }
  assert {
    condition     = output.cert_approver_replicas == 1 && !contains(output.cert_approver_container_args, "-leader-election")
    error_message = "adr-0019: default cert_approver_replicas must be 1 with no -leader-election arg; replicas=${output.cert_approver_replicas}, args=${jsonencode(output.cert_approver_container_args)}"
  }
  assert {
    condition     = length(output.cert_approver_leaderelection_role_rules) == 0
    error_message = "adr-0019 least privilege: at replicas:1 no leader-election Role (coordination.k8s.io/leases) must render; got ${jsonencode(output.cert_approver_leaderelection_role_rules)}"
  }
  assert {
    condition = toset(output.cert_approver_clusterrole_signature) == toset([
      "g=certificates.k8s.io|r=certificatesigningrequests|v=get,list,watch|n=",
      "g=certificates.k8s.io|r=certificatesigningrequests/approval|v=update|n=",
      "g=certificates.k8s.io|r=signers|v=approve|n=kubernetes.io/kubelet-serving",
    ])
    error_message = "adr-0019 §Security (H7 closure): the cert-approver ClusterRole signature must be exactly the three signer-scoped CSR rules; got ${jsonencode(output.cert_approver_clusterrole_signature)}"
  }
  assert {
    condition = output.cert_approver_clusterrolebinding_targets == [{
      role     = "kubelet-csr-approver"
      subjects = ["ServiceAccount/kubelet-csr-approver/kubelet-csr-approver"]
    }]
    error_message = "adr-0019 §Security: exactly one ClusterRoleBinding (approver SA → the scoped ClusterRole) must exist; got ${jsonencode(output.cert_approver_clusterrolebinding_targets)}"
  }
  # ALLOWED_DNS_NAMES / -max-sans is dead config in postfinance v1.2.14; the seed omits it.
  assert {
    condition     = !contains(keys(output.cert_approver_env), "ALLOWED_DNS_NAMES")
    error_message = "adr-0019: ALLOWED_DNS_NAMES must not be shipped (dead+misleading config); got '${try(output.cert_approver_env["ALLOWED_DNS_NAMES"], "<absent>")}'"
  }
  assert {
    condition     = !contains(output.cert_approver_container_args, "-max-sans")
    error_message = "adr-0019: the -max-sans cap flag must not be shipped (dead+misleading, flag form of ALLOWED_DNS_NAMES); got ${jsonencode(output.cert_approver_container_args)}"
  }
}

run "cert_approver_ha_and_config_override" {
  command = plan
  variables {
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
    }
    cert_approver_replicas             = 2
    cert_approver_provider_regex       = "^node:[0-9]+$"
    cert_approver_provider_ip_prefixes = ["192.0.2.0/24"]
  }

  assert {
    condition     = output.cert_approver_replicas == 2 && contains(output.cert_approver_container_args, "-leader-election")
    error_message = "adr-0019 HA: cert_approver_replicas=2 must render replicas:2 AND the -leader-election arg; replicas=${output.cert_approver_replicas}, args=${jsonencode(output.cert_approver_container_args)}"
  }
  assert {
    condition     = contains(flatten([for r in output.cert_approver_leaderelection_role_rules : try(r.apiGroups, [])]), "coordination.k8s.io")
    error_message = "adr-0019 HA: replicas>1 must add the namespaced coordination.k8s.io/leases Role; role rules=${jsonencode(output.cert_approver_leaderelection_role_rules)}"
  }
  assert {
    condition = toset(output.cert_approver_clusterrole_signature) == toset([
      "g=certificates.k8s.io|r=certificatesigningrequests|v=get,list,watch|n=",
      "g=certificates.k8s.io|r=certificatesigningrequests/approval|v=update|n=",
      "g=certificates.k8s.io|r=signers|v=approve|n=kubernetes.io/kubelet-serving",
    ])
    error_message = "adr-0019 §Security: the ClusterRole signature must stay the three signer-scoped rules in HA mode (leases go to a namespaced Role); got ${jsonencode(output.cert_approver_clusterrole_signature)}"
  }
  assert {
    condition     = output.cert_approver_env["PROVIDER_REGEX"] == "^node:[0-9]+$" && output.cert_approver_env["PROVIDER_IP_PREFIXES"] == "192.0.2.0/24"
    error_message = "adr-0019: overridden provider_regex/provider_ip_prefixes must flow through unchanged (escaping intact); got ${jsonencode(output.cert_approver_env)}"
  }
  assert {
    condition     = output.cert_approver_approve_resource_names == ["kubernetes.io/kubelet-serving"]
    error_message = "adr-0019 §Security: the approve verb must stay resourceNames-scoped to [kubernetes.io/kubelet-serving] in HA mode; got ${jsonencode(output.cert_approver_approve_resource_names)}"
  }
}

# operator_metrics is not asserted: the chart renders it regardless of the toggle.
run "cilium_seed_render_carries_observability_markers" {
  command = plan
  variables {
    deploy_cilium                 = true
    cilium_agent_metrics          = true
    cilium_operator_metrics       = true
    cilium_hubble_enabled         = true
    cilium_hubble_metrics         = ["dns"]
    cilium_agent_metric_overrides = ["+cilium_bpf_map_pressure"]
    cilium_hubble_open_metrics    = true
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition = anytrue([
      for doc in split("---", data.helm_template.cilium[0].manifest) : (
        try(yamldecode(doc).kind, "") == "ConfigMap" &&
        try(yamldecode(doc).metadata.name, "") == "cilium-config" &&
        contains(keys(try(yamldecode(doc).data, {})), "prometheus-serve-addr")
      )
    ])
    error_message = "AC#1 network seed-marker: the rendered cilium-config ConfigMap must carry prometheus-serve-addr when cilium_agent_metrics=true"
  }
  assert {
    condition = anytrue([
      for doc in split("---", data.helm_template.cilium[0].manifest) : (
        try(yamldecode(doc).kind, "") == "ConfigMap" &&
        try(yamldecode(doc).metadata.name, "") == "cilium-config" &&
        try(yamldecode(doc).data["enable-hubble"], "false") == "true"
      )
    ])
    error_message = "AC#1 network seed-marker: the rendered cilium-config ConfigMap must carry enable-hubble=true when cilium_hubble_enabled=true"
  }
  assert {
    condition = anytrue([
      for doc in split("---", data.helm_template.cilium[0].manifest) : (
        try(yamldecode(doc).kind, "") == "ConfigMap" &&
        try(yamldecode(doc).metadata.name, "") == "cilium-config" &&
        contains(keys(try(yamldecode(doc).data, {})), "hubble-metrics-server")
      )
    ])
    error_message = "AC#1 network seed-marker: the rendered cilium-config ConfigMap must carry hubble-metrics-server when cilium_hubble_metrics is non-empty"
  }
  assert {
    condition = anytrue([
      for doc in split("---", data.helm_template.cilium[0].manifest) : (
        try(yamldecode(doc).kind, "") == "Service" &&
        try(yamldecode(doc).metadata.name, "") == "hubble-metrics" &&
        contains([for p in try(yamldecode(doc).spec.ports, []) : try(p.port, 0)], 9965)
      )
    ])
    error_message = "ADR-0022 §g (C1 grounding): the render must carry the hubble-metrics Service on port 9965 even though hubble.tls.enabled=false — the Hubble metrics scrape endpoint must NOT be disabled by turning observer-API TLS off"
  }

  # Helm ignores unknown keys; only these render asserts catch a misspelled values path.
  assert {
    condition = anytrue([
      for doc in split("---", data.helm_template.cilium[0].manifest) : (
        try(yamldecode(doc).kind, "") == "ConfigMap" &&
        try(yamldecode(doc).metadata.name, "") == "cilium-config" &&
        strcontains(try(yamldecode(doc).data["metrics"], ""), "+cilium_bpf_map_pressure")
      )
    ])
    error_message = "chart-key spelling: cilium_agent_metric_overrides must reach the rendered cilium-config `metrics` key — if this is the only red assert, the Helm path `prometheus.metrics` is misspelled in cilium-values.tf and the input is a silent no-op"
  }
  assert {
    condition = anytrue([
      for doc in split("---", data.helm_template.cilium[0].manifest) : (
        try(yamldecode(doc).kind, "") == "ConfigMap" &&
        try(yamldecode(doc).metadata.name, "") == "cilium-config" &&
        try(yamldecode(doc).data["enable-hubble-open-metrics"], "false") == "true"
      )
    ])
    error_message = "chart-key spelling: cilium_hubble_open_metrics must set the rendered cilium-config enable-hubble-open-metrics=true — if this is the only red assert, the Helm path `hubble.metrics.enableOpenMetrics` is misspelled in cilium-values.tf and the input is a silent no-op"
  }
}

run "cilium_seed_render_metric_inputs_default_off" {
  command = plan
  variables {
    deploy_cilium         = true
    cilium_agent_metrics  = true
    cilium_hubble_enabled = true
    cilium_hubble_metrics = ["dns"]
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition = anytrue([
      for doc in split("---", data.helm_template.cilium[0].manifest) : (
        try(yamldecode(doc).kind, "") == "ConfigMap" &&
        try(yamldecode(doc).metadata.name, "") == "cilium-config" &&
        !contains(keys(try(yamldecode(doc).data, {})), "metrics")
      )
    ])
    error_message = "marker discrimination: with cilium_agent_metrics on and NO delta list, the rendered cilium-config must carry no `metrics` key — otherwise cilium_seed_observability_markers.agent_metric_overrides reads true for every agent-metrics consumer and discriminates nothing"
  }
  assert {
    condition = anytrue([
      for doc in split("---", data.helm_template.cilium[0].manifest) : (
        try(yamldecode(doc).kind, "") == "ConfigMap" &&
        try(yamldecode(doc).metadata.name, "") == "cilium-config" &&
        try(yamldecode(doc).data["enable-hubble-open-metrics"], "") == "false"
      )
    ])
    error_message = "chart-default sentinel: with Hubble on and cilium_hubble_open_metrics off, the rendered enable-hubble-open-metrics must be \"false\" — if the chart default flips, the ON-state spelling oracle turns green-forever and stops discriminating"
  }
}

# The OFF run below keeps this one discriminating against a chart that always
# emits the checksum annotation.
run "cilium_seed_render_rolls_agents_on_configmap_change" {
  command = plan
  variables {
    deploy_cilium = true
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition = anytrue([
      for doc in split("---", data.helm_template.cilium[0].manifest) : (
        try(yamldecode(doc).kind, "") == "DaemonSet" &&
        try(yamldecode(doc).metadata.name, "") == "cilium" &&
        contains(
          keys(try(yamldecode(doc).spec.template.metadata.annotations, {})),
          "cilium.io/cilium-configmap-checksum",
        )
      )
    ])
    error_message = "roll claim: the cilium DaemonSet pod template must carry cilium.io/cilium-configmap-checksum — without it a ConfigMap-only Day-2 change syncs green and never reaches the agents, and every document that stopped telling operators to restart manually (variables.tf, README.md, schemas/cluster.schema.json, UPGRADING.md) is now wrong"
  }
}

# The override is the last values layer on the seed path, so it wins over the floor.
run "cilium_seed_render_roll_is_overridable" {
  command = plan
  variables {
    deploy_cilium          = true
    cilium_values_override = "rollOutCiliumPods: false\n"
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition = anytrue([
      for doc in split("---", data.helm_template.cilium[0].manifest) : (
        try(yamldecode(doc).kind, "") == "DaemonSet" &&
        try(yamldecode(doc).metadata.name, "") == "cilium" &&
        !contains(
          keys(try(yamldecode(doc).spec.template.metadata.annotations, {})),
          "cilium.io/cilium-configmap-checksum",
        )
      )
    ])
    error_message = "opt-out: rollOutCiliumPods: false in cilium_values_override must remove the pod-template checksum annotation — if it does not, the opt-out UPGRADING.md documents for the seed and multi-source arms does not exist, and the run above has stopped discriminating"
  }
}

# Key set pinned in tests/fixtures/cilium-config-keys.txt, curated values below. On a
# chart bump, regenerate the fixture from sort(keys(.data)) of the default render.
run "cilium_seed_config_surface_is_pinned" {
  command = plan
  variables {
    deploy_cilium = true
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }

  assert {
    condition = join("\n", sort(keys(one([
      for doc in split("---", data.helm_template.cilium[0].manifest) : yamldecode(doc).data
      if try(yamldecode(doc).kind, "") == "ConfigMap" && try(yamldecode(doc).metadata.name, "") == "cilium-config"
    ])))) == trimspace(file("${path.module}/tests/fixtures/cilium-config-keys.txt"))
    error_message = "cilium-cni-delivery §'Seed configuration surface is pinned': the seed's cilium-config key set diverged from tests/fixtures/cilium-config-keys.txt — a chart bump added or removed a key. Refresh the fixture ON PURPOSE and answer the consumer-facing question in UPGRADING.md; do not silently re-generate it."
  }

  assert {
    condition = try(one([
      for doc in split("---", data.helm_template.cilium[0].manifest) : yamldecode(doc).data
      if try(yamldecode(doc).kind, "") == "ConfigMap" && try(yamldecode(doc).metadata.name, "") == "cilium-config"
    ])["bpf-lb-algorithm-annotation"], "") == "true"
    error_message = "seed config pin: bpf-lb-algorithm-annotation must be \"true\" (chart 1.20 forces it on with gatewayAPI enabled). A flip back to \"false\" silently makes every service.cilium.io/lb-algorithm annotation inert again"
  }
  assert {
    condition = try(one([
      for doc in split("---", data.helm_template.cilium[0].manifest) : yamldecode(doc).data
      if try(yamldecode(doc).kind, "") == "ConfigMap" && try(yamldecode(doc).metadata.name, "") == "cilium-config"
    ])["kube-proxy-replacement"], "") == "true"
    error_message = "seed config pin: kube-proxy-replacement must be \"true\" at the module default — it is paired with Talos cluster.proxy.disabled, so a silent flip leaves the cluster with no service load-balancer at all"
  }
  assert {
    condition = try(one([
      for doc in split("---", data.helm_template.cilium[0].manifest) : yamldecode(doc).data
      if try(yamldecode(doc).kind, "") == "ConfigMap" && try(yamldecode(doc).metadata.name, "") == "cilium-config"
    ])["enable-host-firewall"], "") == "false"
    error_message = "seed config pin: enable-host-firewall must stay \"false\" — the base ships no host-policy set, so enabling it by chart default would filter host traffic against an empty policy"
  }
  assert {
    condition = try(one([
      for doc in split("---", data.helm_template.cilium[0].manifest) : yamldecode(doc).data
      if try(yamldecode(doc).kind, "") == "ConfigMap" && try(yamldecode(doc).metadata.name, "") == "cilium-config"
    ])["enable-datapath-plugins"], "") == "false"
    error_message = "seed config pin: enable-datapath-plugins must stay \"false\" — it opens a plugin-loading surface the base does not use"
  }
  assert {
    condition = try(one([
      for doc in split("---", data.helm_template.cilium[0].manifest) : yamldecode(doc).data
      if try(yamldecode(doc).kind, "") == "ConfigMap" && try(yamldecode(doc).metadata.name, "") == "cilium-config"
    ])["gateway-api-use-remote-address"], "") == "true"
    error_message = "seed config pin: gateway-api-use-remote-address must be \"true\" — \"false\" makes a client-supplied X-Forwarded-For authoritative for the Gateway's source IP, which is only safe behind a trusted proxy"
  }
}

# Helm drops unknown keys silently, so only the render shows whether the replica
# count arrives.
run "cilium_seed_render_carries_the_derived_operator_replicas" {
  command = plan
  variables {
    deploy_cilium = true
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition = try(one([
      for doc in split("\n---\n", data.helm_template.cilium[0].manifest) : yamldecode(doc).spec.replicas
      if try(yamldecode(doc).kind, "") == "Deployment" && try(yamldecode(doc).metadata.name, "") == "cilium-operator"
    ]), null) == 2
    error_message = "render layer: the seed's cilium-operator Deployment must carry spec.replicas 2 at >= 2 nodes — a values key the chart does not recognise is dropped without error, so a values-map assertion alone cannot tell a delivered 2 from a silently defaulted one"
  }
}

# Three nodes and a pin of 3: no other layer (floor 1, chart 2, derivation 2) yields 3.
run "cilium_seed_render_carries_the_pinned_operator_replicas" {
  command = plan
  variables {
    deploy_cilium            = true
    cilium_operator_replicas = 3
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
      w-2  = { ip = "192.0.2.22", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
  assert {
    condition = try(one([
      for doc in split("\n---\n", data.helm_template.cilium[0].manifest) : yamldecode(doc).spec.replicas
      if try(yamldecode(doc).kind, "") == "Deployment" && try(yamldecode(doc).metadata.name, "") == "cilium-operator"
    ]), null) == 3
    error_message = "render layer: a pinned cilium_operator_replicas = 3 must reach the seed's cilium-operator Deployment — 3 is produced by neither the floor (1), the chart default (2), nor the node-count derivation (2), so this value can only come from the pin actually arriving at the render"
  }
}

# k8sServiceHost/Port render into the agents' KUBERNETES_SERVICE_HOST/_PORT env
# vars, not into cilium-config.
run "cilium_seed_render_carries_the_typed_api_server_endpoint" {
  command = plan
  variables {
    deploy_cilium                 = true
    cilium_kube_proxy_replacement = true
    cilium_k8s_service_host       = "api.cluster.example"
    cilium_k8s_service_port       = "6443"
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }

  assert {
    condition = anytrue(flatten([
      for doc in split("---", data.helm_template.cilium[0].manifest) : [
        for c in try(yamldecode(doc).spec.template.spec.containers, []) : anytrue([
          for e in try(c.env, []) : try(e.name, "") == "KUBERNETES_SERVICE_HOST" && try(e.value, "") == "api.cluster.example"
        ])
      ] if try(yamldecode(doc).kind, "") == "DaemonSet"
    ]))
    error_message = "cilium-cni-delivery render-layer rule: cilium_k8s_service_host must reach the rendered agent DaemonSet as KUBERNETES_SERVICE_HOST — a values-map assertion alone cannot tell a recognised key from a discarded one"
  }

  assert {
    condition = anytrue(flatten([
      for doc in split("---", data.helm_template.cilium[0].manifest) : [
        for c in try(yamldecode(doc).spec.template.spec.containers, []) : anytrue([
          for e in try(c.env, []) : try(e.name, "") == "KUBERNETES_SERVICE_PORT" && try(e.value, "") == "6443"
        ])
      ] if try(yamldecode(doc).kind, "") == "DaemonSet"
    ]))
    error_message = "cilium-cni-delivery render-layer rule: cilium_k8s_service_port must reach the rendered agent DaemonSet as KUBERNETES_SERVICE_PORT — the string shape the module emits is the shape the chart consumes"
  }
}
