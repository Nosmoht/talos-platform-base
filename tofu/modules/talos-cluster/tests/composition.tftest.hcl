# Composition regression suite (ADR base:node-capability-composition).
#
# Proves the γ' composition + its hard-error invariants. command = plan (no
# apply). The valid run resolves the live Image Factory (network) for schematic
# dedup; the expect_failures runs lock in each guard (red-green: revert the guard
# and the matching run stops failing). NETWORK REQUIRED — run via `task tofu:test`,
# NOT part of the offline `task tofu:ci`.
#
# The module-param / sysctl / kernel-arg conflict guards are exercised in the
# sibling conflict-guards.tftest.hcl via a synthetic colliding catalog fixture
# (tests/fixtures/colliding-catalog/) — the shipped base catalog never collides,
# and provisioning_profiles is a module-local constant the variables{} block
# cannot override. That file is offline; this one needs the network.

provider "talos" {}
provider "helm" {}

variables {
  cluster_name       = "test"
  cluster_endpoint   = "https://192.0.2.1:6443"
  talos_version      = "v1.12.6"
  kubernetes_version = "v1.35.0"
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

# Valid topology: dedup + determinism. w-1 and w-2 list the same two capabilities
# in REVERSED order -> identical effective provisioning -> one schematic.
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
}

# Issue #169 (AC1) — a node whose image sets extra_kernel_args: the rendered
# schematic's customization.extraKernelArgs contains those args UNIONED with
# the node's resolved profile kargs. Needs the network (unlike AC2/AC6 in
# tests/image-kernel-args.tftest.hcl): the assert reads the actual rendered
# talos_image_factory_schematic resource, not just the plan-time hash.
# Red-green: drop the image leg from node_effective.kernel_args's concat
# (composition.tf) and this assert fails — extraKernelArgs lacks
# "hugepagesz=1G".
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

# Symmetry FORWARD: a provisioned required-feature with no profile providing it.
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

# Symmetry INVERSE: a selected profile provides an atom the composite omits.
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

# Per-CAPABILITY symmetry (ADR §step-3 "both directions"): two individually
# malformed capabilities that COMPENSATE in the per-node union — a forward
# violator (requires a provisioned atom, no profile) + an inverse violator
# (a profile providing that atom, not in requires) — on ONE node must STILL be
# rejected. Under the prior per-node-union check this pair PASSED (Codex review
# finding). Red-green: revert composition.tf to the per-node-union symmetry and
# this run stops failing.
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

# Variant mismatch: an arm node selecting the iommu profile (variants intel|amd).
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

# Undefined image reference.
run "undefined_image" {
  command = plan
  variables {
    nodes = { cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "ghost", hardware_capabilities = [] } }
  }
  expect_failures = [terraform_data.composition_guards]
}

# Undefined capability reference.
run "undefined_capability" {
  command = plan
  variables {
    nodes = { cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["ghost"] } }
  }
  expect_failures = [terraform_data.composition_guards]
}

# H1: emits_label must be in the platform.io/hardware-capability.* namespace
# (reserved hardware-feature.* forbidden) — a variable validation, fails pre-plan.
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

# argocd-namespace seed carries the PSA floor + the six recommended labels.
# Spec: AGENTS.md §Hard Constraints ("Kubernetes recommended labels on all
# resources") + the PSA floor (enforce: baseline) preserved from the retired
# kubernetes/bootstrap/argocd/namespace.yaml — the module is now the sole creator
# of the namespace, so the create-only inlineManifest seed must carry these
# itself. Red-green: drop labels from local.argocd_namespace_labels (main.tf) and
# both asserts fail. deploy_argocd = true renders the argo-cd chart (NETWORK) and
# needs a prefix-valid age key — already part of the network-gated `task tofu:test`.
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

# Kubelet serving-cert rotation (serverTLSBootstrap) + cert-approver substrate
# seed — knowledge/decisions/0013-kubelet-serving-cert-rotation.md. Binds both deliverables to the EXACT per-role patch lists
# the data.talos_machine_configuration sources receive (via the named locals
# main.tf exposes through outputs). Red-green: drop [local.base_kubelet_rotation_patch]
# from a role's concat in main.tf and that role's rotation assert fails; drop
# local.cert_approver_controlplane_patch from the controlplane concat and
# cert_approver_seeded fails. NETWORK (Image Factory) like the other plan runs.
run "kubelet_serving_cert_rotation_and_cert_approver_seed" {
  command = plan
  variables {
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }

  # Rotation is per-kubelet -> must be wired into BOTH roles' patch lists.
  assert {
    condition     = output.kubelet_serving_cert_rotation.controlplane
    error_message = "adr-0013 (plan Goal 1): kubelet serving-cert rotation must be wired into the controlplane machine-config patch list"
  }
  assert {
    condition     = output.kubelet_serving_cert_rotation.worker
    error_message = "adr-0013 (plan Goal 1): kubelet serving-cert rotation must be wired into the WORKER machine-config patch list — the serving cert is per kubelet, workers need it too"
  }
  # Mechanism: the non-deprecated KubeletConfiguration field, not the deprecated flag.
  assert {
    condition     = try(output.kubelet_rotation_setting.machine.kubelet.extraConfig.serverTLSBootstrap, null) == true
    error_message = "adr-0013 + no-deprecated-options directive: rotation must use machine.kubelet.extraConfig.serverTLSBootstrap = true (KubeletConfiguration), NOT the deprecated --rotate-server-certificates extraArgs flag"
  }
  # No-deprecated-options directive (negative): the base rotation patch must NOT
  # carry the deprecated extraArgs.rotate-server-certificates flag.
  assert {
    condition     = try(output.kubelet_rotation_setting.machine.kubelet.extraArgs["rotate-server-certificates"], null) == null
    error_message = "no-deprecated-options directive: the deprecated machine.kubelet.extraArgs.rotate-server-certificates flag must be absent (use extraConfig.serverTLSBootstrap instead)"
  }
  # cert-approver seeded as a controlplane inlineManifest (unconditional substrate).
  assert {
    condition     = output.cert_approver_seeded
    error_message = "adr-0013 (plan Goal 2): the cert-approver inlineManifest seed must be wired into the controlplane machine-config patch list"
  }
  # Seeded namespace runs under PSA restricted (single-replica controller, no host access).
  assert {
    condition     = lookup(output.cert_approver_namespace_labels, "pod-security.kubernetes.io/enforce", "<absent>") == "restricted"
    error_message = "adr-0013 + namespace PSA floor: the cert-approver namespace must enforce PSA restricted; got '${lookup(output.cert_approver_namespace_labels, "pod-security.kubernetes.io/enforce", "<absent>")}'"
  }
  # AGENTS.md Hard Constraint: all six recommended labels on the seeded namespace.
  assert {
    condition = length(setsubtract(
      ["app.kubernetes.io/name", "app.kubernetes.io/instance", "app.kubernetes.io/version", "app.kubernetes.io/component", "app.kubernetes.io/part-of", "app.kubernetes.io/managed-by"],
      keys(output.cert_approver_namespace_labels)
    )) == 0
    error_message = "AGENTS.md §Hard Constraints: all six app.kubernetes.io/* recommended labels must be seeded on the cert-approver namespace; missing: ${jsonencode(setsubtract(["app.kubernetes.io/name", "app.kubernetes.io/instance", "app.kubernetes.io/version", "app.kubernetes.io/component", "app.kubernetes.io/part-of", "app.kubernetes.io/managed-by"], keys(output.cert_approver_namespace_labels)))}"
  }
  # H7: the approver's RBAC `approve` verb is signer-scoped to kubelet-serving ONLY
  # (not "*", not empty) — binds the SCOPE, not mere signer-string presence.
  assert {
    condition     = output.cert_approver_approve_resource_names == ["kubernetes.io/kubelet-serving"]
    error_message = "adr-0013 §Security (H7): the cert-approver ClusterRole `approve` verb must be resourceNames-scoped to exactly [kubernetes.io/kubelet-serving]; got ${jsonencode(output.cert_approver_approve_resource_names)}"
  }
  # The assembled controlplane list (the data source's actual input) must BEGIN with
  # controlplane_base_patches, so the base-sublist wiring checks above transitively
  # bind the final list (the sensitive argocd/cilium seeds are only appended).
  assert {
    condition     = output.controlplane_base_is_prefix_of_final
    error_message = "adr-0013 §Validation: controlplane_machine_config_patches must begin with controlplane_base_patches (sensitive seeds appended after); the base-sublist wiring assertions only bind the final list if this prefix invariant holds"
  }
  # AGENTS.md Hard Constraint (all six app.kubernetes.io/* labels on all resources):
  # the seed ships as a Talos inlineManifest, OUTSIDE the kustomize render/conftest
  # label gate, so bind the invariant to the vendored manifest here. Red-green: drop
  # any of the six labels from any object in cert-approver.yaml and this list becomes
  # non-empty. Codex cross-family review [P2], 2026-07-01.
  assert {
    condition     = length(output.cert_approver_seed_missing_labels) == 0
    error_message = "AGENTS.md §Hard Constraints: every object in the cert-approver seed must carry all six app.kubernetes.io/* recommended labels; object-flattened missing set: ${jsonencode(output.cert_approver_seed_missing_labels)}"
  }
  # ADR-0019: the per-cluster config surface defaults keep every cluster booting +
  # approving out-of-the-box. Empty provider_ip_prefixes would DENY all IP-SAN CSRs
  # (source-verified WhitelistedIPCheck), so the safe floor is all-IPs, not empty.
  assert {
    condition     = output.cert_approver_env["PROVIDER_REGEX"] == ".*" && output.cert_approver_env["PROVIDER_IP_PREFIXES"] == "0.0.0.0/0,::/0" && output.cert_approver_env["BYPASS_DNS_RESOLUTION"] == "true"
    error_message = "adr-0019: default cert-approver config must inject PROVIDER_REGEX='.*', PROVIDER_IP_PREFIXES='0.0.0.0/0,::/0' (the all-IPs floor, NOT empty), BYPASS_DNS_RESOLUTION='true'; got ${jsonencode(output.cert_approver_env)}"
  }
  # Restricted-PSA hardening bound to the rendered Deployment (base CI runs no live
  # PSA admission) — a re-vendor dropping a field fails here, not silently at runtime.
  assert {
    condition     = try(output.cert_approver_pod_security_context.runAsNonRoot, false) == true && try(output.cert_approver_pod_security_context.readOnlyRootFilesystem, false) == true && try(output.cert_approver_pod_security_context.seccompProfile.type, "") == "RuntimeDefault" && contains(try(output.cert_approver_pod_security_context.capabilities.drop, []), "ALL")
    error_message = "adr-0019 + restricted PSA: the cert-approver container securityContext must set runAsNonRoot, readOnlyRootFilesystem, drop [ALL] and RuntimeDefault seccomp; got ${jsonencode(output.cert_approver_pod_security_context)}"
  }
  # Default replicas:1 keeps least privilege: no leader-election arg AND no
  # namespaced leases Role at all (that grant renders ONLY at replicas > 1).
  assert {
    condition     = output.cert_approver_replicas == 1 && !contains(output.cert_approver_container_args, "-leader-election")
    error_message = "adr-0019: default cert_approver_replicas must be 1 with no -leader-election arg; replicas=${output.cert_approver_replicas}, args=${jsonencode(output.cert_approver_container_args)}"
  }
  assert {
    condition     = length(output.cert_approver_leaderelection_role_rules) == 0
    error_message = "adr-0019 least privilege: at replicas:1 no leader-election Role (coordination.k8s.io/leases) must render; got ${jsonencode(output.cert_approver_leaderelection_role_rules)}"
  }
  # ClusterRole CLOSURE (H7): the cluster-scoped role is INVARIANT — exactly the
  # three rules below, bound by FULL signature (apiGroups + resources + VERBS +
  # resourceNames). A re-vendor adding a rule/resource/verb (e.g. `sign` on
  # signers → cert issuance), widening apiGroups, or dropping the signer scope
  # changes a signature and fails here. Combined with the UNSCOPED-approve sentinel
  # and the binding closure below, this binds the whole cluster-wide RBAC surface.
  assert {
    condition = toset(output.cert_approver_clusterrole_signature) == toset([
      "g=certificates.k8s.io|r=certificatesigningrequests|v=get,list,watch|n=",
      "g=certificates.k8s.io|r=certificatesigningrequests/approval|v=update|n=",
      "g=certificates.k8s.io|r=signers|v=approve|n=kubernetes.io/kubelet-serving",
    ])
    error_message = "adr-0019 §Security (H7 closure): the cert-approver ClusterRole signature must be exactly the three signer-scoped CSR rules; got ${jsonencode(output.cert_approver_clusterrole_signature)}"
  }
  # Binding closure: exactly ONE ClusterRoleBinding, to the scoped ClusterRole, for
  # the approver SA only — a re-vendor adding a second binding (e.g. → cluster-admin)
  # or repointing roleRef fails here (the rule signature alone cannot see bindings).
  assert {
    condition = output.cert_approver_clusterrolebinding_targets == [{
      role     = "kubelet-csr-approver"
      subjects = ["ServiceAccount/kubelet-csr-approver/kubelet-csr-approver"]
    }]
    error_message = "adr-0019 §Security: exactly one ClusterRoleBinding (approver SA → the scoped ClusterRole) must exist; got ${jsonencode(output.cert_approver_clusterrolebinding_targets)}"
  }
  # ALLOWED_DNS_NAMES / -max-sans is dead config in postfinance v1.2.14 (the
  # controller never reads it) and a value of "1" would misrepresent an enforced
  # 1-DNS-SAN cap that a legitimate node exceeds (NodeHostName + NodeInternalDNS +
  # NodeExternalDNS). The seed omits it; a re-vendor re-introducing it is caught here.
  assert {
    condition     = !contains(keys(output.cert_approver_env), "ALLOWED_DNS_NAMES")
    error_message = "adr-0019: ALLOWED_DNS_NAMES must not be shipped (dead+misleading config); got '${try(output.cert_approver_env["ALLOWED_DNS_NAMES"], "<absent>")}'"
  }
  # Symmetric guard on the flag form: the same dead cap can re-enter as a
  # `-max-sans` container arg (chart-alt of the env var) and evade the env assert.
  assert {
    condition     = !contains(output.cert_approver_container_args, "-max-sans")
    error_message = "adr-0019: the -max-sans cap flag must not be shipped (dead+misleading, flag form of ALLOWED_DNS_NAMES); got ${jsonencode(output.cert_approver_container_args)}"
  }
}

# ADR-0019: HA opt-in + per-cluster config override. replicas>1 auto-enables
# leader-election + the leases RBAC; provider_* flow through as env; a
# metacharacter-bearing regex (colon) still renders a parseable manifest (the
# jsonencode escaping guard). Red-green: revert the templatefile wiring and these
# flip. NETWORK (Image Factory) like the other plan runs.
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
  # HA adds the leases/events grant as a NAMESPACED Role (not the ClusterRole),
  # and the ClusterRole stays INVARIANT at its 3 signer-scoped rules — so HA never
  # widens the cluster-wide surface.
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
  # Config override flows through AND the colon-bearing regex round-trips exactly —
  # proving the jsonencode escaping (an unescaped colon would corrupt the YAML scalar).
  assert {
    condition     = output.cert_approver_env["PROVIDER_REGEX"] == "^node:[0-9]+$" && output.cert_approver_env["PROVIDER_IP_PREFIXES"] == "192.0.2.0/24"
    error_message = "adr-0019: overridden provider_regex/provider_ip_prefixes must flow through unchanged (escaping intact); got ${jsonencode(output.cert_approver_env)}"
  }
  # The approve scope is unchanged in HA mode (signer-restricted, not broadened).
  assert {
    condition     = output.cert_approver_approve_resource_names == ["kubernetes.io/kubelet-serving"]
    error_message = "adr-0019 §Security: the approve verb must stay resourceNames-scoped to [kubernetes.io/kubelet-serving] in HA mode; got ${jsonencode(output.cert_approver_approve_resource_names)}"
  }
}

# AC #1 network seed-marker binding (issue #188, ADR-0022) — proves the
# observability fold reaches the ACTUAL rendered bootstrap seed manifest, not
# just the offline cilium_effective_values map (tests/input-validation.tftest.hcl
# already binds that half). Also binds addendum-2's render-level check: with
# cilium_hubble_enabled=true + a non-empty hubble_metrics + the module's forced
# hubble.tls.enabled=false, the rendered manifest still carries the
# hubble-metrics Service / :9965 scrape endpoint — mechanically confirming the
# C1 grounding (ADR-0022 §g) at the PINNED chart version actually shipped, not
# just via the T1 docs citation.
#
# Reads data.helm_template.cilium[0].manifest DIRECTLY rather than through
# terraform_data.cilium_render[0].output (which cilium_seed_observability_markers,
# outputs.tf, reads for REAL post-apply consumers). Empirically confirmed
# (issue #188 implementation): terraform_data's `output` attribute is ALWAYS
# "(known after apply)" at plan time for a resource being newly created —
# by design, since its whole purpose is to freeze a value AT create time — so
# it cannot be asserted against under this file's command = plan convention
# (no apply: this suite never touches a live cluster, and 192.0.2.11 is an
# RFC5737 documentation IP with no reachable Talos API to apply against). The
# underlying data source has no such limitation (data sources resolve at plan
# time when their own inputs are fully known, which they are here — verified
# empirically). For this first-ever plan there is no prior frozen state to
# diverge from, so reading the data source directly proves exactly the same
# render the freeze would capture.
#
# Red-green (AC#1 network seed-marker): drop the observability fold from
# local.cilium_computed_values (cilium-values.tf) -> the agent_metrics/hubble/
# hubble_metrics asserts below all fail (the ConfigMap keys they check for
# become absent). (operator_metrics is NOT asserted here as a discriminating
# marker — the upstream chart's own default already renders
# operator-prometheus-serve-addr regardless of the toggle (verified against
# the pinned chart, ADR-0022 §l caveat); the offline
# cilium_effective_values.operator.prometheus.enabled assertion in
# tests/input-validation.tftest.hcl is what genuinely binds the
# operator-metrics leg of AC #1.)
#
# Red-green (Hubble-metrics render, addendum 2): drop the hubble-metrics
# Service from the render by disabling metrics (reverting this run's
# cilium_hubble_metrics to [] makes the hubble-metrics Service assert below
# fail, since an empty metrics list is the documented half-on state with no
# exported scrape endpoint).
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
  # Addendum 2 — render-level confirmation that hubble.tls.enabled=false (the
  # module's forced setting) does NOT disable the hubble-metrics scrape
  # endpoint at the pinned chart version. Filters the rendered multi-doc YAML
  # for the hubble-metrics headless Service and its :9965 port.
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

  # --- Chart-key SPELLING oracle for the two metric inputs ---
  #
  # This is the ONLY oracle in the repo that can catch a mistyped Helm value path.
  # Helm silently ignores an unknown key, so `prometheus.metricz` or
  # `hubble.metrics.enableOpenMetric` would sail through every offline assert
  # (which only checks that the module put SOMETHING in its own values map) and
  # ship an input that does nothing. Rendering the pinned chart is what turns the
  # module's spelling into an observable fact.
  #
  # Red-green: misspell either path in cilium-values.tf => the matching assert
  # goes red here while the whole offline suite stays green.
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

  # The agent DaemonSet must be byte-identical to its no-OpenMetrics form: the
  # chart emits no config checksum for this key, so enabling it does NOT roll the
  # pods. That is a documented operational obligation (a rollout restart is
  # required to make the exposition-format switch effective — see variables.tf and
  # UPGRADING.md), and this assert is what keeps the claim true across chart bumps:
  # if a future chart DOES add a checksum annotation, this goes red and the docs
  # need updating rather than silently misleading an operator.
  assert {
    condition = alltrue([
      for doc in split("---", data.helm_template.cilium[0].manifest) : (
        try(yamldecode(doc).kind, "") != "DaemonSet" ||
        try(yamldecode(doc).metadata.name, "") != "cilium" ||
        !anytrue([
          for k in keys(try(yamldecode(doc).spec.template.metadata.annotations, {})) : strcontains(k, "checksum")
        ])
      )
    ])
    error_message = "no-roll claim: the cilium DaemonSet pod template must carry no checksum annotation — if the chart gained one, cilium_hubble_open_metrics now DOES roll the agents and both variables.tf and UPGRADING.md must stop telling operators to restart manually"
  }
}

# Seed cilium-config surface binding (issue #212). The Cilium seed bypasses the
# kustomize/conftest render gate, and until this run nothing pinned a single key
# in its rendered cilium-config — so a chart bump could move a datapath- or
# security-relevant default straight into the create-only controlplane machine
# config with nothing failing. The Cilium 1.20 bump proved it: the chart forces
# `bpf-lb-algorithm-annotation` from "false" to "true" whenever gatewayAPI is
# enabled (the base default), which makes a previously inert
# `service.cilium.io/lb-algorithm` Service annotation live. That was found only by
# a hand-run render diff, not by this suite.
#
# Two layers, deliberately:
#   1. The KEY SET is compared against tests/fixtures/cilium-config-keys.txt, so a
#      chart bump that adds or removes any key fails until the fixture is
#      refreshed on purpose. Catches the class, not just the keys someone thought
#      to enumerate.
#   2. A curated set of VALUES is pinned below. The key set alone would not have
#      caught the 1.20 regression, because `bpf-lb-algorithm-annotation` exists in
#      both charts and only its value moved.
#
# Refresh procedure for a deliberate bump: render the pinned chart with the floor
# (helm/cilium-values.yaml) plus the module's computed layer for default inputs,
# take `sort(keys(.data))` of the cilium-config ConfigMap, and rewrite the fixture.
# Review the diff — every added, removed or changed key is a consumer-facing
# question, and UPGRADING.md is where the answer goes.
#
# Red-green: delete any line from the fixture, or change any pinned value below,
# and this run fails.
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

  # Curated value pins. One predicate per assert so a failure names the key.
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
