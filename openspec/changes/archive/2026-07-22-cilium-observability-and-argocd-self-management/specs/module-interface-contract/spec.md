## MODIFIED Requirements

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
default `[]`), `cilium_self_management` (default `false`, guarded by the
cross-variable validations below), and `cilium_self_management_project`
(default `"default"`)); cluster network (`pod_cidr`, `service_cidr`,
`dual_stack`, `allow_scheduling_on_controlplanes`); and the cluster health
timeout. Because `deploy_argocd` defaults to true and a plan-time
precondition requires `sops_age_key` to be a valid age private key
whenever ArgoCD is deployed, `sops_age_key` is de-facto required under the
default toggles.

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
— booleans (`agent_metrics`, `operator_metrics`, `hubble`, `hubble_metrics`)
decoded from the frozen seed render's `cilium-config` ConfigMap, `{}` when
`deploy_cilium = false` — for tests binding the seed render to the
observability inputs without re-rendering the chart.

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

### Requirement: Version constraints and backend agnosticism

The module SHALL require OpenTofu/Terraform `>= 1.9.0` and constrain its
providers to `siderolabs/talos` `>= 0.7.0, < 1.0.0`, `hashicorp/helm`
`>= 2.12, < 3.0.0` (local template rendering only — no Helm release or
apply), and `hashicorp/local` `>= 2.4` plus `hashicorp/null` `>= 3.2`
(used only for the ArgoCD CRD apply path). The `>= 1.9.0` floor (raised
from `>= 1.7.0`) is required because the `cilium_self_management` guard
validations below reference OTHER variables in their `condition` — a
cross-variable `validation` feature OpenTofu introduced at 1.9 — and is
parsed at module load regardless of any toggle's value, so it is a
permanent, consumer-visible compatibility floor for one opt-in,
default-off feature. The module SHALL declare no state backend — the
backend is the caller's concern and must be encrypted, because the
machine secrets land in state.

#### Scenario: No backend is imposed on the caller

- **WHEN** the module is initialized from any caller root
- **THEN** it declares no backend block and enforces only the version
  constraints above

#### Scenario: A pre-1.9 caller cannot load the module

- **WHEN** a caller initializes the module with OpenTofu/Terraform
  `< 1.9.0`
- **THEN** module load fails on the `required_version` constraint,
  regardless of whether `cilium_self_management` is set

## ADDED Requirements

### Requirement: Cilium self-management guard validations

The module SHALL reject at plan time, via two separate cross-variable
`validation` blocks on `cilium_self_management`: (1) enabling it while
`deploy_argocd` is false or `deploy_cilium` is false — self-management
hands the Day-2 config off from the module-delivered Cilium seed to the
consumer's ArgoCD, so both must be present; and (2) enabling it while
`cilium_values_override` is non-empty — the emitted Application's
`valuesObject` does not inherit `cilium_values_override` (see
`cilium-cni-delivery`), so a seed-active datapath override would be
silently dropped on ArgoCD adoption. The two guards SHALL remain separate
`validation` blocks (not combined into one `condition`) so each is
independently exercisable by a dedicated `expect_failures` test leg.

#### Scenario: Self-management without ArgoCD or Cilium is rejected

- **WHEN** `cilium_self_management = true` and either `deploy_argocd` or
  `deploy_cilium` is `false`
- **THEN** variable validation fails with an error naming the missing
  prerequisite

#### Scenario: Self-management with an active override is rejected

- **WHEN** `cilium_self_management = true` and `cilium_values_override`
  is non-empty
- **THEN** variable validation fails with an error directing the caller
  to migrate the override into their own Cilium Application and empty
  `cilium_values_override` before enabling self-management

### Requirement: Opt-in Cilium self-management output

The module SHALL expose `cilium_self_management_app` — a YAML-encoded
`argoproj.io/v1alpha1` `Application` manifest string — as `""` when
`cilium_self_management = false` (the default), and as the rendered
Application when `true`, with a `precondition` rejecting an unexpectedly
empty render while the toggle is on. The module SHALL NOT apply this
manifest itself — it is an output only, for the consumer's own GitOps to
commit and reconcile.

#### Scenario: Output is empty by default

- **WHEN** `cilium_self_management` is left at its default (`false`)
- **THEN** `cilium_self_management_app` is the empty string

#### Scenario: Output never renders empty while the toggle is on

- **WHEN** `cilium_self_management = true`
- **THEN** `cilium_self_management_app` is non-empty, or the plan fails on
  the output's precondition rather than emitting a hollow Application
