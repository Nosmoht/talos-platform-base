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

# --- Cilium observability + ArgoCD self-management (issue #188, ADR-0022) ---
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

  # --- Default pins for the EMITTED engine (metric-overrides / OpenMetrics change) ---
  #
  # The frozen seed is inert for an existing consumer: terraform_data.cilium_render
  # carries ignore_changes=[input], so a seed diff only lands on a fresh bootstrap,
  # a -replace, or a controlplane join. The emitted Application is the path that
  # reaches a RUNNING cluster on the next ArgoCD reconcile with no operator action,
  # and until now nothing pinned its all-defaults shape.
  #
  # The hubble.metrics assert is the specific trap: local.cilium_hubble_metrics_values
  # is NOT empty when Hubble is off (it always carries `enabled = <the list>`), so an
  # implementation that reads it directly in the effective layer instead of back
  # through local.cilium_computed_values.hubble.metrics leaks `hubble.metrics.enabled: []`
  # into the valuesObject of every Hubble-disabled self-managing consumer. Paired with
  # the hubble.enabled assert above, which anchors the parent so this cannot pass
  # vacuously through a dropped `hubble` key.
  assert {
    condition     = try(output.cilium_effective_values.hubble.metrics, null) == null
    error_message = "default-off: cilium_effective_values.hubble must carry NO metrics key while Hubble is off — reading local.cilium_hubble_metrics_values directly instead of through local.cilium_computed_values leaks `metrics.enabled: []` into the emitted Application"
  }
  assert {
    condition     = output.cilium_effective_values.operator.replicas == 1
    error_message = "default-off: the floor's operator.replicas=1 must survive into cilium_effective_values when no observability input is set"
  }
  # The named predicate for issue #270. The golden-fixture comparison further
  # down also moves on this key, but it reports only THAT a byte moved — never
  # which, nor whether the key is one the chart recognises — and refreshing the
  # fixture silences it in one line. This assert names the key, and
  # scripts/check-cilium-rollout-pods-key.sh is the static gate a fixture refresh
  # cannot silence; the render layer is bound in tests/composition.tftest.hcl.
  assert {
    condition     = try(output.cilium_effective_values.rollOutCiliumPods, null) == true
    error_message = "default-off: the floor's rollOutCiliumPods=true must survive into cilium_effective_values — without it a Day-2 values change reaches the emitted Application's cilium-config and never the running agents"
  }
  # The single-node arm of the node-count-derived replicas leg. This fixture
  # declares ONE node, so local.cilium_operator_values is empty and the computed
  # layer must emit NO `operator` key at all — that absence is what leaves the
  # floor as the sole contributor under `operator`, which in turn is what keeps
  # mutant M2 (the dropped `operator` sub-merge, see the floor-preservation run
  # below) detectable. Red-green: make the replicas leg unconditional in
  # cilium-values.tf and this assert fails.
  assert {
    condition     = !contains(keys(output.cilium_computed_values), "operator")
    error_message = "single-node: cilium_computed_values must carry NO operator key at one node with no operator metrics — an unconditional replicas leg would supersede the floor here and retire the operator sub-merge's only binding contributor"
  }

  # --- Default pins for the SEED engine ---
  #
  # Asserted on cilium_computed_values directly, NOT inferred from
  # cilium_effective_values: the effective map ends in explicit sub-merge terms that
  # REPLACE their parent, so it is not a superset of the computed one.
  assert {
    condition     = !contains(keys(output.cilium_computed_values), "prometheus")
    error_message = "default-off: cilium_computed_values (the seed's values layer) must not carry a prometheus key when cilium_agent_metrics is unset"
  }
  assert {
    condition     = !contains(keys(output.cilium_computed_values), "hubble")
    error_message = "default-off: cilium_computed_values must not carry a hubble key when cilium_hubble_enabled is unset"
  }
  # Positive anchor for the two absence asserts above — they are the only
  # references to this map in this run, and both are negative, so a fixture output
  # wired to {} would satisfy both. This key is default-derived and floor-
  # independent, so it holds regardless of the observability inputs.
  assert {
    condition     = output.cilium_computed_values.kubeProxyReplacement == true
    error_message = "positive anchor: cilium_computed_values must be the real computed map, not an empty object — without this the two absence asserts above pass vacuously on a mis-wired fixture output"
  }

  # This run is also the positive control for BOTH check blocks and the format
  # validation. Each check is written `<unset> || <prerequisite>`; the classic
  # miswrite — `&&` for `||`, or dropping the unset-arm — makes the condition
  # false at all-defaults, and `tofu test` promotes a failing check to a run
  # failure, so this run goes red. No extra assert is needed to express that.
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
    error_message = "AC#2: cilium_hubble_enabled=true must force cilium_effective_values.hubble.tls.enabled=false (metrics-only scope, ADR-0022 §g)"
  }
}

# --- Agent metric-override delta list + Hubble OpenMetrics -------------------
#
# Both inputs reach BOTH engines, so every run below asserts on
# cilium_computed_values (the seed's values layer, fed to data.helm_template.cilium)
# AND cilium_effective_values (the emitted Application's valuesObject). Neither is
# derivable from the other: the effective map ends in sub-merge terms that replace
# their parent wholesale.

# The intra-computed `prometheus` collision. Mutants:
#   M-P1 — write the overrides as their OWN merge() term in
#          local.cilium_computed_values instead of folding them into
#          local.cilium_prometheus_values. merge() is shallow, so the second
#          `prometheus` term replaces the first wholesale => the two
#          prometheus.enabled asserts go red while the metrics asserts stay green.
#          This pair is the intra-computed mirror of the operator.replicas pair in
#          run "cilium_floor_preservation_under_observability".
#   M-P2 — drop the metrics leg from local.cilium_prometheus_values => both
#          metrics asserts go red.
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
    # tolist() on both sides — see run "cilium_hubble_metrics_list_is_carried_through".
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

# Conditional emission for the override list. Red-green: drop the
# `length(...) > 0 ?` guard in local.cilium_prometheus_values so `metrics` is
# emitted unconditionally => `prometheus.metrics: []` appears in the emitted
# Application's valuesObject for every existing agent-metrics consumer, a
# live-reconciled diff for someone who changed nothing, and this run goes red.
# The enabled assert is the positive anchor for the try()-based absence assert:
# without it, a mutant that drops the whole `prometheus` parent would leave the
# absence assert vacuously green.
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
  # The rationale for this run is about the EMITTED Application (a key appearing
  # in a live-reconciled valuesObject for a consumer who changed nothing), so the
  # oracle has to assert that object too. It holds transitively today only because
  # `prometheus` passes through the top-level merge untouched — the very property
  # cilium-values.tf's invariant warns will change when a future key forces a
  # sub-merge on this parent.
  assert {
    condition     = try(output.cilium_effective_values.prometheus.metrics, null) == null
    error_message = "conditional emission, emitted engine: an empty cilium_agent_metric_overrides must add no prometheus.metrics key to the emitted Application's valuesObject"
  }
  assert {
    condition     = output.cilium_effective_values.prometheus.enabled == true
    error_message = "positive anchor on the effective map for the assert above"
  }
}

# The intra-computed `hubble.metrics` collision. Mutants:
#   M-H1 — write enableOpenMetrics as its own merge() term in
#          local.cilium_computed_values. The shallow merge replaces the whole
#          computed `hubble` map => hubble.enabled, hubble.tls.enabled AND
#          hubble.metrics.enabled go red together. The tls assert is the expensive
#          one: without tls.enabled=false the chart re-arms its template-time Sprig
#          genCA path and the frozen seed render stops being deterministic
#          (helm/cilium-values.yaml header, ADR-0022 §g).
#   M-H2 — write `metrics = { enableOpenMetrics = true }` inside
#          local.cilium_hubble_metrics_values instead of merging => only the
#          metrics.enabled asserts go red. The pair separates the two collision
#          levels from each other.
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

# Conditional emission for OpenMetrics — same shape as the override run above.
# Red-green: make `enableOpenMetrics` unconditional in
# local.cilium_hubble_metrics_values => the key appears as `false` in the emitted
# Application of every existing Hubble consumer and this run goes red.
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
  # Same reasoning as the sibling run: the stated failure mode is a key appearing
  # in the emitted Application, so assert on that map as well as the seed's.
  assert {
    condition     = try(output.cilium_effective_values.hubble.metrics.enableOpenMetrics, null) == null
    error_message = "conditional emission, emitted engine: cilium_hubble_open_metrics=false must add no enableOpenMetrics key to the emitted Application's valuesObject"
  }
  assert {
    condition     = tolist(output.cilium_effective_values.hubble.metrics.enabled) == tolist(["dns"])
    error_message = "positive anchor on the effective map for the assert above"
  }
}

# The only run setting BOTH new inputs at once. A single-input run cannot see an
# omission or ordering mutant in a fold that has two contributors from two
# different variables; this one can. Red-green: reorder the merge() arguments in
# either hoisted local so the earlier contributor wins, or drop either
# contributor => the corresponding assert goes red while the single-input runs
# above stay green.
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
  # Both engines, since this is the run that exercises every new contributor at
  # once — if a future sub-merge on either parent drops a sibling on the way to
  # the emitted Application, this is where it shows.
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

# The half-on state ADR-0022 §k explicitly blesses (Hubble server up, nothing
# exported) must keep working unchanged. Red-green: gate the hubble.metrics fold
# on a non-empty cilium_hubble_metrics => the enabled assert goes red and a
# documented, supported configuration silently changes behaviour.
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

# OpenMetrics on TOP of the half-on state is inert, and this is the non-obvious
# case: it is not enough for Hubble to be on. Measured against the pinned chart —
# `enable-hubble-open-metrics` sits under the same
# `{{- if or .Values.hubble.metrics.enabled … }}` gate as `hubble-metrics-server`,
# so with an empty metrics list the chart renders NEITHER key and the flag changes
# the exposition format of an endpoint that exports nothing.
#
# Red-green: drop the `length(var.cilium_hubble_metrics) > 0` conjunct from the
# check in cilium-values.tf => this leg reports "Missing expected failure" while
# the hubble-disabled leg below stays green. That conjunct is the whole finding:
# without it the module reports an inert input as effective.
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

# --- Format guard on cilium_agent_metric_overrides --------------------------
#
# The entries render RAW and UNQUOTED into cilium-config, which is baked into the
# create-only controlplane machine config. Each leg below is a corruption vector
# verified against the pinned chart, not a hypothetical. Red-green for all four:
# delete the validation block in variables.tf => every leg reports "Missing
# expected failure" while the positive control stays green.

# The injection vector: an embedded newline with matching indentation escapes the
# plain scalar and writes a standalone cilium-config key.
run "cilium_metric_override_with_embedded_newline_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_agent_metrics          = true
    cilium_agent_metric_overrides = ["x\n  injected-key: pwned"]
  }
  expect_failures = [var.cilium_agent_metric_overrides]
}

# A document separator would split the rendered manifest and silently blank the
# cilium_seed_observability_markers output, which splits on this literal.
run "cilium_metric_override_with_document_separator_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_agent_metrics          = true
    cilium_agent_metric_overrides = ["+ok", "---"]
  }
  expect_failures = [var.cilium_agent_metric_overrides]
}

# An embedded space smuggles a second metric token into the same entry — the
# entries render space-joined into cilium-config, so the guard's character class
# is what keeps one list element to one metric. Same vector the kernel-arg rule W
# leg covers for var.images[*].extra_kernel_args. Red-green: widen the class to
# include a space and this leg alone goes green while the other three stay red.
run "cilium_metric_override_with_embedded_space_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_agent_metrics          = true
    cilium_agent_metric_overrides = ["+ok -smuggled"]
  }
  expect_failures = [var.cilium_agent_metric_overrides]
}

# A TRAILING newline on an otherwise well-formed entry. This is the one leg whose
# outcome depends on the regex engine: OpenTofu's regex() is RE2, where `$` means
# \z and this is rejected; Python's re (which check-jsonschema uses for the schema
# mirror) matches `$` before a trailing newline and would accept it. Pinning the
# behaviour here is what makes the schema mirror's explicit [\n\r] exclusion a
# documented necessity rather than belt-and-braces.
run "cilium_metric_override_with_trailing_newline_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_agent_metrics          = true
    cilium_agent_metric_overrides = ["+cilium_bpf_map_pressure\n"]
  }
  expect_failures = [var.cilium_agent_metric_overrides]
}

# Missing +/- prefix: Cilium reads the list as deltas against its default metric
# set, so an unprefixed entry has no defined meaning.
run "cilium_metric_override_without_prefix_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_agent_metrics          = true
    cilium_agent_metric_overrides = ["cilium_bpf_map_pressure"]
  }
  expect_failures = [var.cilium_agent_metric_overrides]
}

# Negative-space positive control: the guard must not reject the documented
# form. Red-green: tighten the regex (e.g. drop the underscore from the
# character class) => this run fails to plan while the three rejection legs
# above stay green, which is the direction a too-narrow guard fails in.
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

# --- The same corruption class on cilium_hubble_metrics ---------------------
#
# Measured against the pinned chart: an entry "x\n  injected-hubble-key: pwned"
# renders that key as a standalone cilium-config entry, exactly as on the sibling
# input. The guard there is an ALLOWLIST; here it must be an EXCLUSION rule,
# because the legitimate context syntax uses ":", ";", "=" and "," freely — the
# negative-space run below is what keeps that distinction honest.
#
# Red-green for all three: delete the validation on var.cilium_hubble_metrics =>
# both rejection legs report "Missing expected failure" while the context-syntax
# run stays green.

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

# Negative-space control, and the reason the guard is not an allowlist: Hubble's
# documented context syntax must survive. Red-green: replace the exclusion rule
# with an allowlist modelled on the sibling input and this run fails to plan
# while both rejection legs stay green — which is the direction a copy-paste of
# the wrong guard shape fails in.
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

# --- The same corruption class on cilium_native_routing_cidr ----------------
#
# The third sibling reaching the same rendered cilium-config document, and the
# one the first pass of this suite left uncovered. Measured against the pinned
# chart (1.20.0): the chart writes `ipv4-native-routing-cidr: {{ . }}` raw and
# unquoted, so the value "10.244.0.0/16\n  injected-native-key: pwned" renders
# `injected-native-key` as a standalone cilium-config key.
#
# The guard here is neither an allowlist nor an exclusion rule but a SEMANTIC
# predicate — can(cidrhost(...)) — because unlike the two metric lists this
# input's value space is a computable type. It admits exactly the shape the
# input is for, so every corruption vector is rejected without enumerating one.
#
# Red-green for both rejection legs: delete the validation block on
# var.cilium_native_routing_cidr in variables.tf => both report "Missing
# expected failure" while the negative-space run below stays green.

run "cilium_native_routing_cidr_with_embedded_newline_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_routing_mode        = "native"
    cilium_native_routing_cidr = "10.244.0.0/16\n  injected-native-key: pwned"
  }
  expect_failures = [var.cilium_native_routing_cidr]
}

# A bare address with no prefix length is not a CIDR. This leg is what
# distinguishes the semantic predicate from a mere newline exclusion: an
# exclusion rule modelled on the sibling guards would accept this and hand Cilium
# a value it cannot parse. Red-green: swap the predicate for a `[\n\r]`
# exclusion and this leg alone goes green while the newline leg stays red.
run "cilium_native_routing_cidr_without_prefix_length_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_routing_mode        = "native"
    cilium_native_routing_cidr = "10.244.0.0"
  }
  expect_failures = [var.cilium_native_routing_cidr]
}

# Negative-space control: both documented forms — an explicit CIDR and the empty
# string that means "derive from pod_cidr" — must survive. Red-green: drop the
# `== ""` arm of the condition and the default-valued runs across this whole
# suite fail to plan, which is the direction a too-narrow guard fails in.
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

# nullable = false on both new inputs, and now on cilium_hubble_metrics too. The
# shipped shim reads cluster.yaml through try(), which does NOT catch a key
# written with an empty value — `hubble_metrics:` in YAML is null, try() passes it
# through, and a null reaches conditions that cannot accept it. Red-green: drop
# `nullable = false` from any of the three and this run fails with a null-value
# error instead of planning.
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

# --- Inert-input check blocks -----------------------------------------------
#
# A check block is a checkable object, so expect_failures binds it directly — the
# same mechanism the variable validations use, no warning-only escape hatch
# needed. In `tofu plan`/`apply` these same blocks are WARNINGS, which is the
# tier the cilium_values_override case requires; `tofu test` promotes them to
# failures, which is what makes them testable at all.
#
# Leg isolation, exactly as for the validation legs: each run leaves the OTHER
# check's input at its default so only one block can fire. Without that, deleting
# one block would leave its leg green via the other's failure.
#
# Red-green for both: delete the named check block in cilium-values.tf => that
# leg reports "Missing expected failure" while the other stays green.

run "cilium_metric_overrides_without_agent_metrics_warns" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_agent_metrics          = false
    cilium_agent_metric_overrides = ["+cilium_bpf_map_pressure"]
  }
  expect_failures = [check.cilium_agent_metric_overrides_effective]
}

# The Hubble-off arm. cilium_hubble_metrics is non-empty so this leg is
# distinguishable from the empty-list arm above — both fire the same block, but
# each pins a different conjunct, so dropping either one leaves a leg red.
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

# The deploy_cilium arm, for both checks. With Cilium not delivered there is no
# seed and no emitted Application, so every metric input is inert regardless of
# its own prerequisites — which are all satisfied here, so only the deploy_cilium
# conjunct can be what fires. Red-green: drop `var.deploy_cilium` from either
# check's condition => the matching leg reports "Missing expected failure".
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

# Operator replicas follow the node count — the multi-node arm.
#
# Spec: openspec/specs/cilium-cni-delivery §"Cluster-agnostic floor values with
# layered configuration" → scenario "Operator replicas follow the cluster's node
# count". The floor's replicas=1 is the single-node boundary condition (the
# chart's operator podAntiAffinity is requiredDuringScheduling on hostname, so a
# second replica cannot be placed on a one-node cluster); at two or more nodes
# the module emits the chart's own default of 2. The RATIONALE for that value
# lives in exactly one place — local.cilium_operator_replicas in cilium-values.tf
# — and is deliberately not restated here: an earlier version of this comment
# carried a failover claim that was later retracted, and it outlived the
# correction because a copy has no reason to be revisited.
#
# Red-green: delete the `length(local.nodes_checked) >= 2 ? 2 : null` arm of
# local.cilium_operator_replicas in cilium-values.tf and BOTH asserts here go red
# (effective falls back to the floor's 1, computed loses the key), while every
# single-node run in this file stays green. That asymmetry is the binding: the
# pair is sensitive to the node-count leg specifically, not to the merge as a
# whole.
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

# Level-B preservation for the `operator` parent — the intra-computed mirror of
# the M2 pair above, and the assert the file's own two-engine-drift invariant
# demands for any parent that gains a second contributor (see cilium-values.tf,
# "ANY future key added under a parent already written by another contributor").
#
# Red-green (M-O1): split local.cilium_operator_values back into two `operator`
# merge() terms in local.cilium_computed_values => the later term replaces the
# earlier wholesale, so exactly one of the two asserts below goes red depending on
# term order, while the run above (replicas alone) stays green. That is what
# distinguishes this pair from a plain "both keys present" check.
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

# The spec scenario names the EMITTED Application, not an intermediate local.
# `cilium_effective_values` only becomes the Application's valuesObject through
# cilium-values.tf's `helm = { valuesObject = local.cilium_effective_values }`;
# asserting the local alone leaves that one wiring line with no oracle anywhere
# in the suite, and this is the path that reaches a RUNNING cluster on the next
# ArgoCD reconcile (the seed is frozen for an existing consumer). Red-green:
# repoint valuesObject at local.cilium_floor_values or drop the `helm` block and
# this run goes red while every other run in the file stays green.
#
# Spec: openspec/specs/cilium-cni-delivery §"Operator replicas follow the
# cluster's node count" — "both the seed's computed values layer AND the emitted
# self-management Application carry operator.replicas: 2".
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

# --- cilium_operator_replicas: the pin overriding the derivation ---------------
#
# The pin's whole reason to exist is the SELF-MANAGEMENT path: cilium_values_override
# reaches only the seed and is hard-rejected alongside cilium_self_management, so
# before this input the emitted Application had no per-cluster opt-out at all
# (recorded as ADR-0022 Addendum residual 2, now discharged).
#
# The DOWNWARD direction is the one under test — pin 1 against a 2-node set. An
# upward pin would agree with the derivation on this shape and prove nothing.
#
# Red-green (M-O2): delete the `var.cilium_operator_replicas != null ? ... :` arm
# of local.cilium_operator_replicas in cilium-values.tf => the derivation wins,
# both asserts below go red, and the derivation runs above stay green.
#
# Spec: openspec/specs/cilium-cni-delivery §"An explicit operator replica count
# overrides the derivation on both paths".
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

# The arm where the derivation emits NOTHING — the file-level single-node
# fixture. A pin of 1 is NOT indistinguishable from the floor here: the floor
# never reaches the COMPUTED map (it is a separate merge layer), and the
# single-node absence assert on the default-off run above proves the computed
# map carries no `operator` key at all without a pin. So `computed.operator
# .replicas == 1` can only come from the pin, and it needs no over-count.
#
# This also shows the pin does not weaken mutant M2's binding: M2's arm is "no
# count resolves", which a pin cannot enter by construction.
#
# Red-green: delete the pin arm of local.cilium_operator_replicas (M-O2) => the
# computed map loses the `operator` key, `.operator.replicas` fails to resolve,
# and both asserts go red while the derivation runs stay green.
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

# The over-count REJECTION, at the variable rather than the check: a pin above
# the node count cannot converge, and the value is baked into a create-only
# inlineManifest, so a later apply cannot walk it back.
#
# Its own run and its own leg — the value is 2 against the single-node fixture,
# so only the node-count validation can fire (2 >= 1 and 2 is integral).
#
# Red-green: delete the second validation block on var.cilium_operator_replicas
# => "Missing expected failure" here while every other replica run stays green.
run "cilium_operator_replicas_above_the_node_count_is_rejected" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_operator_replicas = 2
  }
  expect_failures = [var.cilium_operator_replicas]
}

# The deploy_cilium arm — the inert-input WARNING tier, and the one place the
# pin's two tiers are visibly different: an over-count is REJECTED (the run
# above), an ineffective pin only warns. The pin is 1 against the single-node
# fixture so the node-count validation cannot also fire and steal the leg.
#
# Red-green: delete check "cilium_operator_replicas_effective" => "Missing
# expected failure" here while every other replica run stays green.
run "cilium_operator_replicas_without_cilium_warns" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    deploy_cilium            = false
    cilium_operator_replicas = 1
  }
  expect_failures = [check.cilium_operator_replicas_effective]
}

# The validation's two rejected shapes, one run each — a merged run would leave
# whichever conjunct it did not exercise untested.
#
# Red-green: drop the `>= 1` conjunct => the zero run reports "Missing expected
# failure"; drop the floor() conjunct => the fractional run does.
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

# Level-B preservation for the PIN, not the derivation. The pair above
# (`..._and_metrics_coexist`) exercises the derived count with metrics; nothing
# exercised the PIN with metrics, and the pin is the new contributor to the
# `operator` parent — exactly what the two-engine-drift invariant in
# cilium-values.tf obliges a preservation assert for.
#
# Red-green (M-O3): give the pin its own `operator` merge term in
# local.cilium_computed_values — `var.cilium_operator_replicas != null ?
# { operator = { replicas = var.cilium_operator_replicas } } : {}` — instead of
# folding it through local.cilium_operator_values. That is the natural "handle
# the pin separately" refactor, and it is silent everywhere else: the shallow
# merge replaces the whole `operator` map, so a pinned cluster with operator
# metrics on loses operator.prometheus.enabled with no error, on BOTH delivery
# paths. Exactly one of the two asserts below goes red depending on term order,
# while every other run in the file stays green.
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

# The provenance output's other two arms. `pin` is bound by the single-node pin
# run above; these bind `node-count` and `floor`, so all three literals the
# output can emit are asserted somewhere and a collapsed conditional cannot pass.
#
# Red-green: invert either arm of the `source` conditional in the fixture's
# cilium_operator_replicas_effective output (and the real module's — they are
# copies) and exactly one of these two runs goes red.
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

# Leg C moved: the override-drop hard reject it used to bind was replaced by a
# values-source REQUIREMENT in issue #265, and its single leg now lives with the
# other values-source legs below as
# `cilium_self_management_guard_leg_c_requires_values_source`. One leg per
# predicate — a second copy under the retired framing would misdirect a reader
# mapping legs to guards.

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

# --- Day-2 override delivery: the multi-source arm (issue #265) --------------
#
# adr-0028 §(b). The override reaches the emitted Application as a LATER Helm
# values layer than floor ⊕ computed, and the ordering lives in the valueFiles
# LIST — module-set layer first, consumer override second, so Helm's later-wins
# merge gives the consumer precedence at arbitrary depth.
#
# Verified against ArgoCD v3.5.2 before this shape was built: `$values/...`
# resolves ONLY through a sibling spec.sources[] entry carrying `ref`
# (util/argo/argo.go GetRefSources), which is why a single-source chart
# Application cannot address a consumer-committed file at all.
#
# Red-green: revert cilium-values.tf's cilium_self_management_spec to the
# single-source-only form and every assert in this run fails at the first
# spec.sources index.
run "cilium_self_management_multi_source_carries_the_override" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management = true
    deploy_argocd          = true
    deploy_cilium          = true
    cilium_values_override = "bgpControlPlane:\n  enabled: true\n"
    # Scoped project: the multi-source arm names a values repo of its own, so the
    # permissive "default" AppProject warns (check
    # cilium_self_management_values_source_on_permissive_project, bound by its own
    # leg below). Every leg here that must plan CLEAN therefore scopes it.
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

  # THE acceptance assertion for issue #265: the override is present, and it is
  # LAST. Asserting the whole list rather than membership binds the ORDER, which
  # is the entire precedence mechanism — a reversed list plans identically and
  # silently loses the override.
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

  # Joint-key re-assertion (adr-0028 §(d)). These three keys live nowhere but the
  # module-set layer, which on this arm is a file the consumer may commit stale
  # or not at all; re-asserting them in valuesObject — the last layer — is what
  # keeps a missing file from stranding the cluster with no kube-proxy
  # replacement while Talos already carries cluster.proxy.disabled.
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
  # The override must NOT be in valuesObject: that slot is applied after the
  # valueFiles, so an override placed there would beat the joint-key
  # re-assertion — and it would put consumer secret material into a manifest the
  # module emits, which is why var.cilium_values_override is sensitive.
  # The KEY SET, not memberships: `valuesObject = merge(cilium_effective_values,
  # cilium_joint_keys)` satisfies every membership assertion above while beating
  # the consumer's valueFiles override on every module-set key — the exact failure
  # this change exists to prevent. The spec says "the joint keys and nothing else".
  assert {
    condition     = join(",", sort(keys(yamldecode(output.cilium_self_management_app).spec.sources[1].helm.valuesObject))) == "k8sServiceHost,k8sServicePort,kubeProxyReplacement"
    error_message = "multi-source: valuesObject must carry the three joint keys AND NOTHING ELSE — it is applied after every valueFiles entry, so any additional key there silently beats the consumer's override"
  }

  # The module-set layer as the consumer commits it, and the digest that is the
  # only mechanical link between the two independently-committed artifacts.
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
  # …and the digest is bound to its SUBJECT. The assertion above compares two
  # readings of the same local, so it stays green if the digest is computed over
  # the wrong content (or over a constant) — and a digest that does not move when
  # the module-set layer moves detects no stale file at all, which is the whole
  # function the spec assigns it.
  assert {
    condition     = regex("values-digest: ([0-9a-f]{64})", output.cilium_self_management_values)[0] == sha256(yamlencode(output.cilium_effective_values))
    error_message = "multi-source: the values-digest must be sha256(yamlencode(<module-set layer>)) — computed over anything else it cannot detect a stale values file, which is the only thing it exists for"
  }
}

# The override entry is absent when there is no override, so a consumer using the
# multi-source arm for the module-set layer alone gets a one-entry list rather
# than a `$values/` path to a file they never wrote.
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

# The emptied-override check's red-green binding. It fires on the state that says
# an override was REMOVED — an override_path configured with nothing to put in it
# — and NOT on the supported "module-set layer only" shape above, which is why
# that run carries no expect_failures. A `check` block is a checkable object, so
# `tofu test` promotes its warning to a failure and expect_failures binds it
# directly; deleting the block turns this into "Missing expected failure".
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

# A values source with self-management off reaches nothing, and the module's
# warning tier says so rather than planning silently.
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

# --- Raw-render guards on the values-source strings --------------------------
#
# repo_url and both paths are interpolated into the generated values document's
# `#` header lines by bare string join, so a newline breaks out of the comment
# and injects a TOP-LEVEL key into the module-set values layer — the first
# valueFiles entry of an Application rendering a privileged, host-networked
# DaemonSet. Same class and same measured vector as
# cilium_native_routing_cidr and cilium_k8s_service_host.
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

# Negative-space control for the charset guard: the documented path form must
# still be accepted, so a future tightening cannot quietly reject real paths.
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

# The override digest replaces the plan-time change signal the sensitive marking
# removes. Red-green: drop the digest local and this run cannot resolve.
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

# Negative-space control for the arm switch. The single-source shape is what a
# consumer who configures no values source gets, and setting or leaving unset
# `cilium_self_management_values_source` must not move it AT ONE BASE REVISION:
# no sources[], no annotation, and the module-set layer still inline in
# valuesObject. It is NOT a promise across revisions — a floor change moves this
# document on purpose, and issue #270 did (rollOutCiliumPods). Red-green: key the
# bifurcation on the override's content instead of on the values-source input and
# this run fails the moment an override is set.
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

  # Whole-document identity against the golden. The presence/absence assertions
  # above name the facts a reader cares about; this one fails on any byte the
  # others do not look at, which is what makes an unnoticed manifest move
  # impossible. yamlencode's own output is stable for a given value, so this is a
  # value comparison, not a formatting one. It detects MOVEMENT and certifies no
  # key's correctness, and a fixture refresh silences it — the per-key assertions
  # and scripts/check-cilium-rollout-pods-key.sh are what survive that.
  assert {
    condition     = output.cilium_self_management_app == replace(file("tests/fixtures/cilium-self-management-app-single-source.yaml"), "/(?m)^#.*\n/", "")
    error_message = "single-source arm: the emitted Application must be BYTE-IDENTICAL to tests/fixtures/cilium-self-management-app-single-source.yaml for this input set. A byte moved — every single-source consumer's manifest moved with it, so decide whether that belongs in CHANGELOG/UPGRADING and the next MAJOR before refreshing the fixture."
  }
}

# AC #3 guard leg C, REPLACED (issue #265): the hard reject is no longer
# "self-management with any override" but "self-management with an override and
# nowhere for the Application to read it from". Without a values source the
# emitted Application falls back to the single-source shape, whose valuesObject
# carries no override term — the same silent drop the old guard prevented.
# deploy_argocd/deploy_cilium stay explicitly TRUE so this leg is isolated to the
# second validation block, not the deploy-prereq one legs A/B bind. The override
# deliberately names NO adr-0028 §(d) joint key, or the joint-key validation on
# cilium_values_override would fire instead and expect_failures would match the
# wrong variable.
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

# --- adr-0028 §(d) joint keys: rejected in the override ----------------------
#
# One leg per key, never merged: expect_failures matches the VARIABLE, so a
# single leg would leave two thirds of the key set untested. Each override is a
# well-formed MAPPING so the map-shape validation on the same variable cannot be
# what fires. self_management stays off so no self-management guard is in play.
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

# Negative-space control: an override naming a key that merely LOOKS adjacent
# must not be rejected. Red-green: widen the guard to a substring match instead
# of a key-set intersection and this run hard-fails.
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

# --- Override document shape -------------------------------------------------
#
# A comment-only override decodes to null and a list-rooted one to a tuple.
# Either would reach the seed's values list and the emitted Application as a
# non-object, so the reject belongs on the input rather than on the artifact.
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

# --- Values-source coordinate guards ----------------------------------------
#
# Each leg trips EXACTLY ONE of the three validation blocks on
# cilium_self_management_values_source; the others are satisfied by construction,
# which is what keeps expect_failures meaningful on a variable carrying three.
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

# The override needs its own path or it has no way into the Application — the
# silent drop again, one layer below the cilium_self_management guard.
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

# --- Typed API-server endpoint inputs (issue #227, closed by #265) ----------
#
# These exist to make the §(d) joint-key rejection cost no capability: the value
# is reachable, just not through the override. Cilium documents these values as
# endpoint-derived in general and Talos KubePrism is one source of them, so the
# defaults are KubePrism and the inputs are what a cluster without it uses.
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

# With kube-proxy present, Cilium reaches the API server through the ClusterIP
# kube-proxy provides, so the endpoint keys must be ABSENT rather than set — and
# the joint-key re-assertion must not put them back.
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

# The same measured reason cilium_native_routing_cidr carries a format guard: the
# chart renders this value raw into cilium-config, which is baked into the
# create-only machine config, so a newline can inject a standalone key.
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

# The permissive-project warning. The multi-source arm is the first shape that
# names a values repo of its own, and the always-present "default" AppProject
# carries sourceRepos: ['*'] — so a cluster.yaml edit repointing repo_url feeds
# attacker-chosen Helm values to a privileged, host-networked DaemonSet with
# nothing but PR review in the way. Red-green: delete the check and this run
# reports "missing expected failure".
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

# --- repo_url scheme allowlist ------------------------------------------------
#
# repo_url becomes spec.sources[0].repoURL verbatim. The allowlist is the three
# forms ArgoCD resolves for a git source; a bare token, a file:// path, or an
# embedded credential are all rejected.
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

# Negative space for the allowlist: all three accepted forms must still plan.
# ssh:// is asserted here because no other leg uses it, and the accepted-path leg
# above covers the scp-like git@host:path form.
run "values_source_accepts_an_ssh_scheme_repo_url" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_self_management         = true
    deploy_argocd                  = true
    deploy_cilium                  = true
    cilium_self_management_project = "platform-substrate"
    cilium_self_management_values_source = {
      # The DOCUMENTED ssh form, username and all — the shape the first draft of
      # this allowlist rejected because it excluded every "@", while the README
      # and the variable's own error message named it as valid. A leg using a
      # userless ssh:// URL passed and hid that.
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

# --- path distinctness --------------------------------------------------------
#
# One path for both layers makes the same $values/ entry appear twice and, with
# the local_file write UPGRADING prescribes, overwrites the consumer's override
# document with the module-set layer. Every other guard stays green on that
# state: the override variable is still non-empty, so the emptied-override check
# does not fire, and the values-digest pair still matches because the digest
# covers the module-set layer only.
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

# --- endpoint inputs: the guards the merged port condition used to hide -------
#
# The port's two predicates are separate validation blocks, so each is bindable:
# a non-numeric value reaches the FORMAT block's message rather than crashing a
# tonumber() inside a merged condition, and the range legs bind the range block.
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

# Positive control for the host guard's IPv6 branch, UNBRACKETED. The bracketed
# spelling is the broken one and has its own rejection leg below: the chart puts
# this value in KUBERNETES_SERVICE_HOST and client-go joins it with the port via
# net.JoinHostPort, which brackets a colon-bearing host again — so a bracketed
# input reaches the API server as "[[2001:db8::1]]:6443". Both directions need a
# leg, or the guard could be "fixed" back to the broken form silently.
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

# The two-colon floor: this is what keeps a "host:port" pair whose halves happen
# to be hex out of the IPv6 branch. One colon is never an IPv6 literal.
run "k8s_service_host_rejects_a_hex_host_port_pair" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_k8s_service_host = "abc:6443"
  }
  expect_failures = [var.cilium_k8s_service_host]
}

# An SSH username is not secret material and is the documented form; a PASSWORD
# is. Both halves need their own leg, or the split between them is untested.
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

# Distinctness cannot be spelled around. "./x" and "x" name ONE file, and the
# consequence is the destructive one the distinctness guard exists to stop: the
# module-set layer overwrites the consumer's override, with the emptied-override
# check silent (the override variable is still non-empty) and the values-digest
# pair still matching (the digest covers the module-set layer only).
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

# The IPv6 branch is a cidrhost() round trip, not a character class, so a string
# that merely LOOKS like a literal is rejected. Each leg below passes the old
# shape guard (`^[0-9a-fA-F:]+$` plus two colons) and fails the parse.
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

# The round trip normalizes, so a non-canonical spelling does not equal its
# input. Deliberate and shared with var.nodes (ipv4_mapped_ipv6_is_rejected):
# the accepted value is the one the parser prints back.
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

# The endpoint inputs are emitted only alongside kubeProxyReplacement, so a
# non-default value with the toggle off reaches nothing. Warning tier, not a
# reject: the configuration still works, it just does not carry the endpoint.
run "k8s_service_endpoint_without_kube_proxy_replacement_warns" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cilium_kube_proxy_replacement = false
    cilium_k8s_service_host       = "api.cluster.example"
  }
  expect_failures = [check.cilium_k8s_service_endpoint_effective]
}

# Negative space for the check: the DEFAULT endpoint with the toggle off is the
# ordinary configuration and must NOT warn.
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
