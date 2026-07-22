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

  nodes = [
    { hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
  ]
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
    # Transcribed verbatim from helm/cilium-values.yaml:41-52 (ordered list —
    # HCL list equality is order-sensitive). Do not copy from plan.md without
    # re-checking the file (builder-addenda.md item 6).
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
