# Input-validation regression suite — fully anchored version patterns.
#
# The talos_version / talos_install_version / kubernetes_version validations in
# variables.tf are `$`-anchored so trailing garbage after the PATCH segment is
# rejected (a `-`/`+` pre-release/build suffix stays accepted; mirrored by
# schemas/cluster.schema.json — the schema side is bound red-green via
# schemas/fixtures/cluster.invalid.yaml in gitops-validate.yml). Each run below
# feeds one malformed value and expects exactly that variable's validation to
# fail. Red-green: revert a `$` anchor in variables.tf and the matching run
# stops failing ("Missing expected failure").
#
# Uses the ./tests/fixtures/colliding-catalog stand-in module (symlinked real
# variables.tf) for the same reason as conflict-guards.tftest.hcl: pure plan
# over terraform_data — NO network, NO provider (unlike composition.tftest.hcl).

variables {
  cluster_name       = "test"
  cluster_endpoint   = "https://192.0.2.1:6443"
  talos_version      = "v1.12.6"
  kubernetes_version = "v1.35.0"

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
    talos_version = "v1.12.6.4"
  }
  expect_failures = [var.talos_version]
}

run "talos_install_version_rejects_trailing_garbage" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    talos_install_version = "v1.12.7garbage"
  }
  expect_failures = [var.talos_install_version]
}

run "kubernetes_version_rejects_trailing_garbage" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    kubernetes_version = "v1.35.0.1"
  }
  expect_failures = [var.kubernetes_version]
}

run "prerelease_suffix_is_accepted" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    talos_version         = "v1.13.0-beta.1"
    talos_install_version = "v1.13.0-beta.1"
  }
}

# --- AC9: var.images[*].extra_kernel_args lexical rules (issue #169) -------
#
# One malformed element per run, each expecting a var.images validation
# failure, each fixture valid against the OTHER six var.images validations
# (traced per-rule so each isolates the ONE rule under test — see plan.md
# Step 7 for the trace). The
# debugfs fixture uses a NON-forbidden value ("debugfs=on"): the rule matches
# the KEY, so this tests the rule without writing the AGENTS.md §Hard
# Constraints forbidden value literal into any tofu/** file (that constraint;
# hard-constraints-check.yml greps changed-file content at HEAD).

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

# Positive control: binds the spec delta's "accepted well-formed list"
# scenario and proves the bare-key form (quiet, no "=") is accepted. NOT a
# minimal pair with the four negative fixtures above (its list shares no
# element with any of them) — it proves its OWN list is valid against all
# seven validations, not that each negative fixture is valid against the
# other six (that per-fixture isolation is authoring-time reasoning, traced in
# the plan; see plan.md §Verification disclosure 8 for the declined
# per-rule-minimal-pair alternative and its cost/benefit).
run "image_extra_kernel_args_accepts_a_well_formed_list" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [], extra_kernel_args = ["hugepagesz=1G", "mitigations=off", "quiet"] }
    }
  }
}

# --- cert-approver per-cluster config validations (adr-0019) ---
# Red-green: delete the matching validation in variables.tf and the run stops
# failing ("Missing expected failure").

run "cert_approver_provider_ip_prefixes_rejects_empty" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cert_approver_provider_ip_prefixes = []
  }
  # Empty set denies every CSR carrying an IP SAN (source-verified WhitelistedIPCheck)
  # — the deny-all footgun the non-empty guard exists to prevent.
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
  # postfinance v1.2.14 exits fatally at startup on an empty PROVIDER_REGEX
  # (source-verified internal/cmd/cmd.go) — the guard prevents a CrashLoop seed.
  expect_failures = [var.cert_approver_provider_regex]
}

run "cert_approver_provider_regex_rejects_whitespace_only" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cert_approver_provider_regex = " "
  }
  # A whitespace-only regex is not caught by the empty-string check but compiles
  # to a deny-all pattern (matches no DNS SAN) — the trimspace() guard rejects it.
  expect_failures = [var.cert_approver_provider_regex]
}

run "cert_approver_provider_regex_rejects_document_separator" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cert_approver_provider_regex = "a---b"
  }
  # A compilable regex containing "---" would corrupt the split("---") audit outputs.
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

# --- Cilium observability + ArgoCD self-management (issue #188, ADR-0021) ---
#
# Uses the fixture's cilium_effective_values / cilium_self_management_app
# outputs (cilium-values.tf is pure var.*-derived locals, so it is
# provider-less-fixture-safe — see the fixture symlinks). Red-green bindings
# are recorded per run below per rules/ai-written-tests.md §Required
# practices #6 and cross-referenced against plan.md §Red-green binding.

run "cilium_all_off_default_carries_no_observability_keys" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  # No cilium_* observability/self-management variables set — all defaults.
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
}

# AC #1 — all three observability legs on. Red-green: dropping any one of the
# three `cilium_*_metrics ? {...} : {}` / `cilium_hubble_enabled ? {...} : {}`
# folds in cilium-values.tf's local.cilium_computed_values makes the matching
# assert below fail (plan.md §Red-green binding, AC #1 offline agent/operator/
# hubble legs).
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

# AC #1 Round-3 residual (a) — hubble_metrics is a real list, not a literal
# true/false. Red-green: replacing `var.cilium_hubble_metrics` with a literal
# `[]` in the hubble fold (cilium-values.tf) makes this equality assert fail.
run "cilium_hubble_metrics_list_is_carried_through" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_hubble_enabled = true
    cilium_hubble_metrics = ["dns", "drop", "tcp"]
  }
  assert {
    # tolist() on both sides: a bare tuple literal compares unequal to a
    # list(string)-typed value under OpenTofu's test-assertion `==` despite
    # identical elements (verified empirically) — normalize both to list.
    condition     = tolist(output.cilium_effective_values.hubble.metrics.enabled) == tolist(["dns", "drop", "tcp"])
    error_message = "hubble_metrics leg: cilium_hubble_metrics must be carried verbatim into cilium_effective_values.hubble.metrics.enabled"
  }
}

# AC #2 (steer 2 / team-red C1) — Hubble TLS is forced off (metrics-only
# scope). Red-green: dropping `tls = { enabled = false }` from the hubble
# fold leaves the chart default (tls.enabled unset/true) → this assert fails.
run "cilium_hubble_tls_is_forced_off" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_hubble_enabled = true
  }
  assert {
    condition     = output.cilium_effective_values.hubble.tls.enabled == false
    error_message = "AC#2: cilium_hubble_enabled=true must force cilium_effective_values.hubble.tls.enabled=false (metrics-only scope, ADR-0021 §g)"
  }
}

# Floor-preservation (steer 1) — the bounded floor⊕computed merge must not
# drop floor-only keys when the observability layer is active. Two mutants
# bind these asserts (plan.md §Red-green binding):
#   M1 — drop the floor layer from cilium_effective_values entirely: all
#        three floor-invariant asserts below fail (the ciliumAgent assert is
#        a POSITIVE equality to the transcribed floor list, so an absent key
#        is caught, not just an excluded-value negative check).
#   M2 — plain `merge(floor, computed)` with no explicit `operator` sub-merge:
#        operator.replicas drops (this run's operator.replicas assert fails)
#        while operator.prometheus.enabled still passes — the pair binds the
#        deep-merge specifically to the one colliding parent (`operator`).
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
    # Transcribed verbatim from the floor's ciliumAgent list in
    # helm/cilium-values.yaml (ordered list — HCL list equality is
    # order-sensitive). Do not copy from a plan without re-checking the file.
    #
    # WHAT this pins and WHY (issue #214): it pins that the FLOOR's list — not the
    # chart's — reaches the effective values, i.e. that the top-level merge does
    # not let the computed layer replace it. It deliberately does NOT justify the
    # fork from the chart default; the floor withholds SYS_MODULE and SYSLOG
    # (Talos invariants, see the floor header) and adds NET_BIND_SERVICE (retained
    # defensively for embedded-Envoy consumers — justification and the case for
    # dropping it are open in #214). So a chart-side change to the default list
    # will NOT fail this assert: it binds the merge, not the divergence.
    condition = output.cilium_effective_values.securityContext.capabilities.ciliumAgent == [
      "CHOWN", "KILL", "NET_ADMIN", "NET_RAW", "NET_BIND_SERVICE",
      "IPC_LOCK", "SYS_ADMIN", "SYS_RESOURCE", "DAC_OVERRIDE", "FOWNER",
      "SETGID", "SETUID",
    ]
    error_message = "floor-preservation (M1): securityContext.capabilities.ciliumAgent from the floor must survive the top-level merge, verbatim and in order"
  }
}

# AC #3 — the emitted self-management Application's shape. Red-green: drop
# or mis-set any one field (chart version / destination.server / destination.
# namespace / metadata.namespace / project / a recommended label / adding a
# syncPolicy) and the corresponding assert below fails (plan.md §Red-green
# binding, "app-on shape").
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

# A caller passing `null` for a chart-version input must receive the module's
# DECLARED DEFAULT, not null. This is the mechanism the example shim relies on so
# a consumer who omits substrate.cilium.chart_version from cluster.yaml inherits
# every future base pin instead of freezing the literal their shim was copied
# with (issue #210). It works ONLY because the variable declares
# `nullable = false`; a passed null otherwise stays null.
#
# Red-green: remove `nullable = false` from variable "cilium_chart_version" in
# variables.tf and re-run `tofu test -filter=tests/input-validation.tftest.hcl`
# — targetRevision becomes null and the first assert below fails.
#
# Deliberately asserts the SHAPE of the substituted value, never the literal
# version: hard-coding "1.20.0" here would add back the fourth copy of the pin
# that #210 exists to remove.
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

# AC #3 guard leg A — deploy-prereq guard fires when deploy_argocd is false.
# Red-green: deleting the deploy-prereq validation block in variables.tf turns
# this run's expect_failures into "Missing expected failure".
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

# AC #3 guard leg B — deploy-prereq guard fires when deploy_cilium is false.
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

# AC #3 guard leg C — the override-drop hard-reject guard. deploy_argocd AND
# deploy_cilium are kept explicitly TRUE (builder-addenda.md item 5) so this
# leg is isolated to the SECOND validation block (override-drop), not the
# deploy-prereq one legs A/B already bind. Red-green: deleting the
# override-drop validation block turns this run's expect_failures into
# "Missing expected failure" while legs A/B stay green.
run "cilium_self_management_guard_leg_c_rejects_override" {
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

# Negative-space positive control (builder-addenda.md item 1, HARD-REQUIRED).
# An override-only consumer who never touches self-management must NOT be
# rejected by the guard added for leg C above. Red-green: miswriting the
# guard condition to drop the `cilium_self_management` conjunct (or flipping
# `&&`→`||`) makes the guard fire on a bare override → this run's
# expected-success plan hard-fails (run 9/leg-C stays green under that
# miswrite — this run is what catches it).
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

# --- Node identity: one node, one definition place (issue #204) -------------
#
# var.nodes is a MAP keyed by node name, so a duplicate NAME is structurally
# impossible (no test can express it). What still needs guarding is everything
# the key does not cover: a duplicate IP, an even control-plane count, a key
# Talos would silently rewrite, two keys collapsing onto one OS hostname, and a
# dotted key whose domain never reaches Kubernetes.
#
# Red-green per run is recorded inline: delete the named validation in
# variables.tf and exactly that run reports "Missing expected failure".

run "duplicate_ip_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.11", role = "worker", image = "intel", hardware_capabilities = [] },
    }
  }
  # Red-green: the ip-distinct validation. Its structural backstop (nodes.tf's
  # nodes_by_ip "Duplicate object key") would still fail the plan without it, but
  # with an unreadable error — this run pins the readable one as first-fired.
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
  # etcd quorum: 2 tolerates 0 failures, exactly like 1. Red-green: the `% 2 == 1`
  # validation.
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

# Positive control for the parity rule: without it the rule could degenerate
# into "more than one control plane always fails" and every negative run above
# would still pass.
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

# The four key-format runs feed values Talos ACCEPTS and then silently rewrites
# (HostnameConfigV1Alpha1.Validate is length-only; nodename.FromHostname
# lowercases, maps '_'->'-', drops other runes and trims '-'/'.'). Without the
# module-side rule they would reach Kubernetes as a DIFFERENT name than declared.
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
      # 64 chars — one over the DNS label limit Talos itself enforces.
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

# The <= 253 total-length conjunct, isolated: every label is 63 or shorter (so the
# per-label clause cannot fire) and the key is a single node with register_with_fqdn
# on (so neither the first-label nor the dotted-key rule fires). 4 x 63 + 3 dots = 255.
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

# Accept-side control for the label limit: exactly 63 characters must PASS, so a
# mutant tightening the bound to 62 is caught (every negative fixture above stays
# red under that mutant and would not reveal it).
run "sixty_three_character_label_plans_cleanly" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      "cp-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
}

# Two DIFFERENT machines whose keys share a first label. Talos splits at the first
# dot, so both get OS hostname "node-a" — and while register_with_fqdn is off,
# both kubelets would claim the Kubernetes node "node-a". Isolated from the
# dotted-key rule by leaving the flag ON is NOT possible here (that would make
# this case legal), so the flag stays off and BOTH rules fire — recorded honestly:
# this run binds "first-label OR dotted-key", and the next two runs separate them.
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
  # ONE node, so the first-label rule cannot fire — this isolates the dotted-key
  # rule. Red-green: drop the `var.register_with_fqdn ||` conjunct from it.
  expect_failures = [var.nodes]
}

# The multi-site topology register_with_fqdn exists for: same short name, different
# domains, FQDN registration on. Kubernetes sees two distinct nodes, so this is
# LEGAL — it is the case the first-label rule must NOT reject. Red-green: make the
# first-label rule unconditional again and this run hard-fails.
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

# Positive control for the dotted-key rule: distinct first labels + the switch on
# must plan cleanly, so the rule cannot degenerate into "dots always fail".
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

# A node set with NO controlplane. Isolated from the parity rule by its `count == 0`
# arm, so this binds the at-least-one rule alone. Red-green: delete that validation
# and the run reports "Missing expected failure" (before the arm existed, parity
# would have fired instead and hidden the deletion).
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

# The role enum. One valid controlplane keeps the parity and at-least-one rules
# green, so only the enum can fire.
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

# Non-canonical IP spellings. Each names the same host as a canonical form, so
# without this rule the ip-uniqueness check (a string comparison) would pass and
# two apply resources would target one machine.
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

# Accept-side control: a canonical IPv6 address must plan cleanly, so the rule
# cannot degenerate into "IPv4 only".
run "canonical_ipv6_plans_cleanly" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    nodes = {
      cp-1 = { ip = "2001:db8::1", role = "controlplane", image = "intel", hardware_capabilities = [] },
    }
  }
}

# The ONLY behaviour var.register_with_fqdn has: an all-nodes machine-config patch.
# Without this, the flag could stop emitting anything, every validation would still
# pass, dotted keys would still be accepted — and the kubelet would keep registering
# the short name, which is exactly the declared-name-vs-live-name drift this whole
# change exists to remove.
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

# Default-off must emit NOTHING, so adopting this module version produces a
# byte-identical machine config for a consumer that sets nothing.
run "register_with_fqdn_default_emits_no_patch" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  assert {
    condition     = length(output.register_with_fqdn_patch) == 0
    error_message = "register_with_fqdn defaults to false and must then emit no patch at all"
  }
}

# The projections and the bootstrap target. The node set deliberately contains a
# WORKER whose name sorts below every controlplane (`a-w`), so a bootstrap-target
# refactor to "first key overall" picks the wrong node and this run catches it —
# the ordering asserts alone would not.
#
# NOTE on the ordering contract's red-green: there is no sort() to remove. A map's
# `for` expression and keys() are lexicographically ordered by definition, so name
# ordering is a property of var.nodes being a MAP, not of a call that could be
# deleted. The binding mutant is a TYPE change (map -> list), which these asserts
# do catch — a list-shaped input reaches the projections in declaration order.
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
