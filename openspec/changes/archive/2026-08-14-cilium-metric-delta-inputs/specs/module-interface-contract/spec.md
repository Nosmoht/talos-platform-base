## ADDED Requirements

### Requirement: Inert typed inputs warn rather than reject

An input whose only failure mode is having no effect SHALL be reported by a
plan-time `check` block, not by a variable `validation`. The module reserves
hard rejection for inputs whose misuse causes silent BREAKAGE — a dropped
datapath override, a fatally-exiting workload, an emitted resource with
nothing to reconcile — and an input that merely does nothing is a lower tier.

The distinction is load-bearing rather than stylistic: a prerequisite may be
satisfied through `cilium_values_override`, an opaque string the module cannot
introspect, so a hard rejection would refuse a configuration that works. The
warning tier lets that consumer proceed while still surfacing the far more
common case, where the prerequisite really is missing.

Each such check SHALL be its own block. `expect_failures` matches the checkable
object, so merging two conditions collapses both test legs onto one predicate
and leaves either half untested — the same isolation obligation the module's
cross-variable validations carry.

#### Scenario: An inert input warns and still plans

- **WHEN** a metric-set input is set while the toggle that makes it effective
  is off
- **THEN** the plan succeeds and reports a warning naming that input and its
  missing prerequisite, rather than failing

#### Scenario: Each check is independently bound

- **WHEN** one such check block is removed
- **THEN** exactly one test leg reports a missing expected failure and every
  other leg stays green

### Requirement: Free-form values reaching the machine config are format-validated

A typed input whose value is rendered verbatim into a resource that becomes
part of the controlplane machine configuration SHALL constrain its accepted
character set by variable `validation`, and the module's test suite SHALL
carry a rejection leg per corruption vector plus a negative-space control
proving the documented form is still accepted.

The Cilium agent metric-delta list is such an input: the chart renders its
entries raw and unquoted into the `cilium-config` ConfigMap, which the module
bakes into a create-only `inlineManifest`. An entry containing a newline with
matching indentation escapes the surrounding scalar and injects arbitrary
ConfigMap keys; an entry containing a document separator splits the rendered
manifest and blanks the seed-marker output that parses it.

#### Scenario: A corrupting entry is rejected at plan time

- **WHEN** an entry contains an embedded newline, a document separator, or
  omits the required add/remove prefix
- **THEN** the plan fails at the variable, naming the offending value

#### Scenario: The documented form is not rejected

- **WHEN** every entry is a well-formed add or remove of a metric name
- **THEN** the plan succeeds and the list reaches the computed values layer
  intact

## MODIFIED Requirements

### Requirement: Seed and wiring audit outputs

The module SHALL expose secret-free audit outputs that bind the composed
patch lists to tests: the kubelet serving-cert rotation wiring per role
and the decoded rotation patch content, the cert-approver seed wiring,
namespace labels, RBAC approve scope and per-object recommended-label
gaps, the ArgoCD namespace labels, and a boolean asserting the
non-sensitive base patch list is a prefix of the final controlplane patch
list. For the cert-approver seed the module SHALL additionally expose,
parsed from the rendered manifest, `cert_approver_rbac_rules` (the decoded
ClusterRole rule set, for rule-set-closure assertions),
`cert_approver_pod_security_context` (the decoded container securityContext,
for the restricted-PSA guard), `cert_approver_container_args` and
`cert_approver_env` (the decoded arguments and `PROVIDER_*`/`BYPASS_DNS_RESOLUTION`
environment, for the config-injection and leader-election checks), and
`cert_approver_replicas` (the rendered replica count). For the Cilium seed
the module SHALL additionally expose `cilium_seed_observability_markers`
— booleans (`agent_metrics`, `agent_metric_overrides`, `operator_metrics`,
`hubble`, `hubble_metrics`, `hubble_open_metrics`) decoded from the frozen
seed render's `cilium-config` ConfigMap, `{}` when `deploy_cilium = false` —
for tests binding the seed render to the observability inputs without
re-rendering the chart.

Because a marker's value must discriminate the input it reports, a marker
SHALL test the rendered key's VALUE where the chart emits that key
unconditionally, and its presence only where the chart gates emission on the
input. The output's documentation SHALL name any marker that fails to
discriminate at the render layer.

The markers describe the SEED, not the running cluster. On a cluster that has
adopted the emitted self-management Application the frozen seed may lag what
is actually reconciled, so the output's documentation SHALL state that scope
rather than leaving it to be inferred.

#### Scenario: Audit outputs stay secret-free

- **WHEN** the seed and wiring audit outputs are read
- **THEN** they expose booleans, label maps, decoded RBAC rules,
  securityContext, container args, environment and replica count only —
  never the seed patch lists that embed Secret material

#### Scenario: Cilium observability markers reflect the seed render

- **WHEN** `deploy_cilium = true` and the Cilium observability inputs are
  set
- **THEN** `cilium_seed_observability_markers` decodes booleans from the
  frozen seed's `cilium-config` ConfigMap matching those inputs, without a
  second chart render

### Requirement: Grouped typed input surface

The module SHALL expose its inputs as typed variable groups: cluster
identity (`cluster_name`, `cluster_endpoint`); versions (`talos_version`
as the machine-config schema pin fixed at bootstrap,
`talos_install_version` as the installer pin defaulting to the schema
pin, `kubernetes_version`); topology (`nodes`, `images`,
`hardware_capabilities`); machine-config patches (all-nodes, per-role and
per-node lists); substrate delivery (the ArgoCD and Cilium toggles with
their chart-version, namespace, values-override and secret-material
knobs, plus a chart-repository knob for Cilium only — the ArgoCD chart
repository is hardcoded in `main.tf` — together with the always-on
cert-approver seed's three tuning knobs: `cert_approver_provider_regex`
(default `".*"`), `cert_approver_provider_ip_prefixes` (default
`["0.0.0.0/0", "::/0"]`, non-empty), and `cert_approver_replicas` (default
`1`); the seed itself has no disable toggle; and the Cilium observability +
self-management group: `cilium_agent_metrics`, `cilium_operator_metrics`
(independent Prometheus toggles, default `false`), `cilium_hubble_enabled`
(default `false`; forces the observer-API server TLS off in the computed
values — metrics-only scope), `cilium_hubble_metrics` (a string list,
default `[]`), `cilium_agent_metric_overrides` (a string list, default `[]`,
format-validated — the chart's add/remove delta against its default metric
set, not a replacement for it), `cilium_hubble_open_metrics` (default
`false`, the OpenMetrics exposition format), `cilium_self_management`
(default `false`, guarded by the cross-variable validations below), and
`cilium_self_management_project` (default `"default"`)); cluster network
(`pod_cidr`, `service_cidr`, `dual_stack`,
`allow_scheduling_on_controlplanes`); and the cluster health
timeout. Because `deploy_argocd` defaults to true and a plan-time
precondition requires `sops_age_key` to be a valid age private key
whenever ArgoCD is deployed, `sops_age_key` is de-facto required under the
default toggles.

The two metric-set inputs SHALL declare `nullable = false`: the shipped
example shim reads `cluster.yaml` through `try()`, which does not catch a
key written with an empty value, so a bare key would otherwise deliver
`null` into conditions that cannot accept it.

`cilium_gateway_api_crds_url` carries a cross-component version coupling the
module cannot validate at plan time: Cilium's Gateway API support requires a
minimum Gateway API CRD bundle version that changes across Cilium minors, and
the input is an opaque URL that Talos applies verbatim. Its documentation
SHALL therefore state the Gateway-API CRD floor required by the Cilium chart
version currently pinned by `cilium_chart_version`, together with the channel
(standard vs experimental) that satisfies the platform's Gateway-API-only
Hard Constraint — in every copy that documents it, the module README's Inputs
row included. No mechanical gate enforces this: `spec:check-staleness` proves
only that the owning spec was touched, `check-module-readme-parity.sh` checks
row presence and not prose, and no check compares the CRD version literal
against the chart pin. It is therefore a **reviewer-enforced** obligation on
every `cilium_chart_version` bump, and a mechanical coupling remains desirable
and unbuilt.

The two chart-version inputs (`cilium_chart_version`, `argocd_chart_version`)
SHALL declare `nullable = false` alongside their default, which makes the
module's declared default the SINGLE source of truth for the pinned chart
version: a caller MAY pass `null` to mean "take the base's pin", and OpenTofu
substitutes the default. This is a per-input contract, NOT a module-wide
convention — no other input promises null-means-default, and a `null` passed to
an input that does not declare `nullable = false` stays `null` rather than
falling back. The convention exists so a consumer who omits the corresponding
`cluster.yaml` key inherits a base chart bump instead of freezing whatever
literal their copied shim carried: the shipped example shim SHALL therefore pass
`try(local.<component>.chart_version, null)`, and the shipped `cluster.yaml`
examples SHALL leave the key commented out, with a setting explained as a
deliberate pin against the base rather than as the normal case. A consumer that
does set the key keeps full control; the value simply wins over the default as
any other input does.

#### Scenario: Optional groups fall back to documented defaults

- **WHEN** a caller supplies only the required inputs (identity,
  versions, nodes, images) together with either a valid `sops_age_key`
  or `deploy_argocd = false`
- **THEN** the plan succeeds with the documented defaults: any substrate
  toggle left unset defaults to enabled, the network CIDRs default to
  the Talos defaults, `talos_install_version` falls back to
  `talos_version`, the health timeout defaults to `"10m"`, and the
  Cilium observability + self-management group defaults to all-off /
  empty

#### Scenario: Gateway API CRD floor tracks the pinned Cilium chart

- **WHEN** the `cilium_gateway_api_crds_url` input documentation is read at
  any pinned `cilium_chart_version`
- **THEN** it names the minimum Gateway API bundle version that pinned Cilium
  version requires, and states which channel to seed — including when the
  experimental channel is required instead of standard
