---
sources:
  primary:
    - kubernetes/bootstrap/cilium/values.yaml
    - kubernetes/bootstrap/cilium/extras.yaml
    - tofu/modules/talos-cluster/helm/cilium-values.yaml
    - tofu/modules/talos-cluster/cilium-values.tf
  secondary:
    - tofu/modules/talos-cluster/main.tf
references:
  - AGENTS.md §Repository Purpose (three pillars)
---

# cilium-cni-delivery

## Purpose

Cilium is a co-equal substrate pillar delivered by the
`tofu/modules/talos-cluster` module as a controlplane Talos
`cluster.inlineManifests` seed (`deploy_cilium`); the repo additionally ships
reference Helm values and a GatewayClass extra for optional Day-2 Cilium
self-management.

## Requirements

### Requirement: Cilium seeded as a controlplane inlineManifest

The module SHALL, when `deploy_cilium` is true, render the Cilium chart
locally via `data.helm_template.cilium` (CRDs included) and bake the frozen
render into the controlplane machine configuration as a
`cluster.inlineManifests` entry named `cilium`, so the CNI comes up with the
cluster bootstrap without any Helm release or in-cluster apply step.

#### Scenario: Controlplane config carries the Cilium seed

- **WHEN** the module plans with `deploy_cilium = true`
- **THEN** the controlplane config patches include a
  `cluster.inlineManifests` entry named `cilium` whose contents are the
  frozen chart render

#### Scenario: Empty render is rejected at plan time

- **WHEN** the Cilium chart render produces an empty manifest
- **THEN** the plan fails with an error naming the empty Cilium seed instead
  of freezing it

### Requirement: Default CNI and kube-proxy disabled with Cilium delivery

The module SHALL, when `deploy_cilium` is true, apply an authoritative
all-nodes patch that sets the Talos cluster CNI to `none` — placed last so a
caller `config_patches` entry cannot re-enable the default CNI — and SHALL
set `cluster.proxy.disabled` in the same patch when
`cilium_kube_proxy_replacement` is enabled, keeping the Talos side and the
Cilium-side kube-proxy replacement in sync.

#### Scenario: Default CNI cannot resurface via caller patches

- **WHEN** `deploy_cilium = true` and a caller patch carries a `cni` stanza
- **THEN** the rendered machine configuration still sets
  `cluster.network.cni.name: none`, because the module's CNI patch is
  ordered after all caller patches

### Requirement: Seed render frozen against non-deterministic re-renders

The module SHALL consume the Cilium render through a state-frozen resource
(`terraform_data.cilium_render` with `ignore_changes` on its input) so that
render drift at identical inputs never re-pushes machine configuration; a
deliberate re-seed requires an explicit resource replacement.

#### Scenario: Render drift does not churn machine config

- **WHEN** a later plan re-evaluates the chart render and produces different
  bytes at unchanged inputs
- **THEN** the frozen render output — and therefore the machine
  configuration — is unchanged

### Requirement: Seed configuration surface is pinned

The seed bypasses the kustomize/conftest render gate, so a chart bump can move a
datapath- or security-relevant default into the create-only controlplane machine
configuration with nothing failing. The repo SHALL therefore pin the seed's
rendered `cilium-config` surface at two levels: its full KEY SET against a
committed fixture, so a bump that adds or removes any key fails until the fixture
is refreshed deliberately; and the VALUES of a curated set of datapath- and
security-relevant keys, because a key set alone cannot catch a default that
changed under an unchanged key. A refresh SHALL be a deliberate act that answers
the consumer-facing question in `UPGRADING.md`, never a silent regeneration.

The curated value set is intentionally open: it starts from the keys whose flip
would break the cluster silently or widen its exposure, and grows as bumps reveal
more. Its purpose is not exhaustive coverage but to make the class of regression
visible — the Cilium 1.20 bump moved `bpf-lb-algorithm-annotation` from `"false"`
to `"true"`, turning a previously inert `service.cilium.io/lb-algorithm` Service
annotation live, and nothing in the suite noticed.

#### Scenario: A chart bump that changes the seed's config surface fails the suite

- **WHEN** the pinned chart renders a `cilium-config` whose key set differs from
  the committed fixture, or whose value for a curated key differs from its pin
- **THEN** the module's test target fails, naming the divergence, rather than
  freezing the new default into the machine configuration unnoticed

### Requirement: Cluster-agnostic floor values with layered configuration

The module SHALL render the seed from three value layers, later layer
winning per Helm merge semantics: the shipped floor
`tofu/modules/talos-cluster/helm/cilium-values.yaml` (Talos invariants:
cgroup auto-mount disabled, `SYS_MODULE` absent from the agent capability
set, `cni.exclusive: false`, Hubble disabled for a deterministic render,
a single operator replica as the single-node-correct boundary condition),
then module-computed values derived from typed inputs (routing mode,
kube-proxy replacement, native-routing CIDR, Gateway API, MTU, encryption,
the operator replica count — pinned by its own typed input, or derived from
the node set — and Cilium agent and operator Prometheus metrics, Hubble
enablement/metrics/observer-API-TLS, the agent metric-delta list and the
Hubble OpenMetrics exposition flag), then the consumer's
`cilium_values_override`. The module-computed layer is computed once, in
`tofu/modules/talos-cluster/cilium-values.tf`, and feeds BOTH this seed
render and the opt-in emitted self-management Application (see the ADDED
requirement below) — a single observability data-flow, no divergent
computation between the two delivery paths.

Within that computed layer, a parent key written by more than one typed
input SHALL be assembled as a single merge term. The computed layer is a
shallow `merge()` over conditional maps, so two terms writing the same
top-level key do not combine — the later replaces the earlier wholesale,
silently dropping the earlier input's effect. This is a distinct collision
level from the floor-versus-computed one the emitted Application's bounded
merge resolves, and both SHALL carry an explicit sub-merge plus a
preservation assertion that fails when either contributor is lost.

A computed key that supersedes a floor key SHALL be emitted only on the
shapes where it actually supersedes it. Emitting it unconditionally makes
the floor a non-contributor for that parent, which retires the preservation
assertion protecting the parent's sub-merge: the mutation it exists to catch
becomes equivalent and the gate passes silently.

A value the module computes into a Helm values layer SHALL additionally be
asserted at the RENDER layer wherever the rendered object exposes it. Helm
merges values without `--strict`, so a key the chart does not recognise —
a typo, a wrong nesting level, a key the chart renamed in a later version —
is discarded without error: every assertion on the values map stays green
while the rendered object silently keeps the chart's own default.

#### Scenario: Consumer override wins over the floor

- **WHEN** `cilium_values_override` sets a key also present in the shipped
  floor values
- **THEN** the rendered seed carries the override's value for that key

#### Scenario: Floor keeps install-time-fixed values out

- **WHEN** the shipped floor values file is read
- **THEN** it contains no routing mode, encryption, native-routing CIDR,
  Gateway API, or kube-proxy-replacement keys — those are emitted only by
  the module's computed layer

#### Scenario: Operator replicas follow the cluster's node count

- **WHEN** the module plans against a node set of two or more nodes with no
  explicit replica count pinned
- **THEN** the computed values layer, the rendered seed's `cilium-operator`
  Deployment, and the emitted self-management Application all carry
  `operator.replicas: 2` — the chart's own default, which the floor's single
  replica had diverged from on every cluster shape rather than only the one
  where a single replica is correct

#### Scenario: A single-node cluster keeps the floor's replica count

- **WHEN** the module plans against a node set of exactly one node with no
  explicit replica count pinned
- **THEN** the computed layer emits no `operator.replicas` key and the
  floor's value of 1 is the effective one — a second replica could never be
  placed against the chart's hostname anti-affinity, and the floor remaining
  the sole contributor under `operator` is what keeps that parent's
  sub-merge preservation assertion able to fail

#### Scenario: An explicit operator replica count overrides the derivation on both paths

- **WHEN** the module plans with `cilium_operator_replicas` set to a value
  the node count would not have derived
- **THEN** that value is what the computed layer, the rendered seed's
  `cilium-operator` Deployment, and the emitted self-management Application
  all carry — the typed input is the only per-cluster pin the emitted
  Application accepts, because its `valuesObject` carries no
  `cilium_values_override` term and the module rejects that override
  alongside `cilium_self_management`

#### Scenario: A replica count above the node count is rejected

- **WHEN** `cilium_operator_replicas` exceeds the number of declared nodes
- **THEN** the plan is rejected — the chart's operator `podAntiAffinity` is
  `requiredDuringScheduling` on `kubernetes.io/hostname`, so at most one
  operator pod places per node and every surplus replica stays Pending
  indefinitely, and the value is baked into a create-only `inlineManifest`
  that no later apply can walk back

#### Scenario: A pin that cannot reach a running operator warns

- **WHEN** `cilium_operator_replicas` is set with `deploy_cilium = false`
- **THEN** the plan reports a warning and proceeds — the count is inert
  rather than wrong, which is a lower tier than rejection

#### Scenario: The resolved count reports which mechanism produced it

- **WHEN** the module plans with Cilium delivered
- **THEN** it reports the resolved operator replica count together with its
  origin — the pin, the node-count derivation, or the floor — so an operator
  debugging a Pending replica can tell a module derivation from a chart
  default without reading module internals

#### Scenario: Observability inputs surface in the seed render

- **WHEN** the module plans with `cilium_agent_metrics = true`,
  `cilium_operator_metrics = true`, and `cilium_hubble_enabled = true`
  (with a non-empty `cilium_hubble_metrics`)
- **THEN** the rendered seed's `cilium-config` ConfigMap carries the agent
  and operator Prometheus scrape keys and the Hubble enablement + metrics
  keys, and the Hubble observer-API server TLS is off
  (`hubble.tls.enabled = false`) — metrics-only scope, independent of the
  separate Hubble metrics-endpoint TLS knob

#### Scenario: Metric-set inputs reach the render without displacing their siblings

- **WHEN** the module plans with a non-empty agent metric-delta list, or
  with the Hubble OpenMetrics flag set, alongside the enabling toggle each
  one depends on
- **THEN** the rendered `cilium-config` carries the delta list and the
  OpenMetrics setting, AND the enabling toggle's own keys — the agent
  scrape address, Hubble enablement, and the forced-off observer-API TLS —
  are all still present

#### Scenario: An unset metric-set input adds no key at all

- **WHEN** the module plans with the enabling toggle on but the
  metric-delta list empty, or the OpenMetrics flag left at its default
- **THEN** the computed layer emits no corresponding key, so the emitted
  self-management Application's values are unchanged for a consumer who
  set neither

#### Scenario: The operator's two contributors coexist

- **WHEN** the module plans against two or more nodes with
  `cilium_operator_metrics = true`
- **THEN** the computed layer carries both `operator.replicas` and
  `operator.prometheus.enabled` — neither contributor displaces the other

### Requirement: Reference values for optional Day-2 self-management

The repo SHALL retain `kubernetes/bootstrap/cilium/values.yaml` as a
reference-only Helm values file for optional Day-2 Cilium self-management —
it is not consumed by the module's seed render — and SHALL ship
`kubernetes/bootstrap/cilium/extras.yaml` providing the `cilium`
GatewayClass that the Helm chart does not generate, consistent with the
platform's Gateway-API-only stance (normative: AGENTS.md §Hard Constraints —
Gateway API only). Because the file is offered to consumers as copy-ready
input for a self-managed Application, a `cilium_chart_version` bump SHALL
reconcile this file against the newly pinned chart for its **datapath- and
security-critical** values, covering both failure modes: a value spelling the
chart has **removed** (Helm merges without `--strict`, so it is dropped
silently rather than rejected), and a value whose **default or enforcement
behavior the chart has changed** under a spelling that still parses. In either
case the consumer's cluster is misconfigured or newly failing with no error at
render or apply time, so the bump SHALL either fix the file or document the
consequence in `UPGRADING.md`. The removed-spelling half SHALL be enforced
mechanically rather than by review: a check SHALL validate every value path in the
file against the pinned chart's own `values.schema.json` and fail on a path the
chart does not declare, running from the same script locally and in CI so a local
pass means what a CI pass means. Because it needs the chart registry, the check
SHALL skip loudly rather than fail when the registry is unreachable — an outage
must not block unrelated merges — which leaves one stated hole: during an outage a
removed spelling can merge. The changed-default half stays reviewer-enforced, since
no schema can express it. Known exception: a full audit of every value in
the file against the pinned chart is out of scope for a version bump, so the
file MAY still carry a value the chart does not recognize. Such a value is inert
rather than harmful — Helm drops it, and removing it leaves the rendered output
byte-identical — but it misleads a consumer copying the file, so a value found to
be unrecognized by the pinned chart SHALL be removed.

#### Scenario: Reference values are marked as non-live

- **WHEN** `kubernetes/bootstrap/cilium/values.yaml` is read
- **THEN** its header states it is reference-only and names
  `tofu/modules/talos-cluster/helm/cilium-values.yaml` as the live seed
  floor

#### Scenario: GatewayClass extra, no Ingress

- **WHEN** `kubernetes/bootstrap/cilium/extras.yaml` is applied
- **THEN** it creates exactly one resource — a GatewayClass named `cilium`
  with the Cilium gateway controller name — and no `kind: Ingress` resource

#### Scenario: A value the pinned chart removed fails the check

- **WHEN** `kubernetes/bootstrap/cilium/values.yaml` sets a value path the pinned
  chart's `values.schema.json` does not declare — for example the flat
  `encryption.strictMode.enabled` spelling that Cilium 1.20 removed
- **THEN** the check fails and names the offending path, instead of Helm dropping
  the value silently at render time

#### Scenario: Encryption strict mode survives the pinned chart

- **WHEN** `kubernetes/bootstrap/cilium/values.yaml` is rendered with
  `helm template` against the chart version pinned by
  `cilium_chart_version`
- **THEN** the file's encryption strict-mode settings reach the rendered
  `cilium-config` ConfigMap as `enable-encryption-strict-mode-egress`,
  `encryption-strict-egress-cidr` and
  `encryption-strict-egress-allow-remote-node-identities` — they are not
  silently dropped as unknown keys

### Requirement: Opt-in emitted self-management Application for Day-2 delivery

The module SHALL, when `cilium_self_management = true` (guarded by the
`module-interface-contract` cross-variable validations), expose an
`argoproj.io/v1alpha1` `Application` manifest — via the
`cilium_self_management_app` output, never applied by the module — as the
Day-2 delivery path for a Cilium config change (including the observability
inputs) on an already-bootstrapped cluster, complementing the frozen
create-only bootstrap seed above and the pre-existing static
`kubernetes/bootstrap/cilium/values.yaml` reference file. The emitted
Application's `spec.source.helm.valuesObject` SHALL be the bounded,
module-controlled merge of the floor and computed-values layers ONLY — it
SHALL NOT inherit `cilium_values_override` — because the override is an
opaque free-form string the module cannot introspect for datapath-critical
content (BGP control-plane, L2 announcements, bpf tuning); silently
carrying it forward on ArgoCD adoption could drop it, so
`module-interface-contract`'s guard hard-rejects enabling self-management
while an override is active instead. The Application SHALL carry
`spec.project = var.cilium_self_management_project` (default `"default"`,
the base's sole permissive AppProject; a scoped consumer-created project is
recommended hardening) and SHALL carry no `syncPolicy`, so the consumer
controls sync timing for the graceful-restart-gated DaemonSet roll that
enabling Hubble triggers.

#### Scenario: Emitted Application carries the module-set values only

- **WHEN** `cilium_self_management = true` and `cilium_values_override` is
  empty (the only state the guard permits)
- **THEN** the emitted Application's `valuesObject` equals the floor ⊕
  computed-values merge, and the manifest carries no `syncPolicy` key

#### Scenario: Emitted Application targets the default AppProject unless scoped

- **WHEN** `cilium_self_management_project` is left at its default
- **THEN** the emitted Application's `spec.project` is `"default"` — the
  base's only pre-existing AppProject — functional out-of-the-box, with a
  dedicated scoped project as documented, recommended hardening

### Requirement: Verified public chart archive

Before the Cilium Day-0 render, the module SHALL download the chart archive into
the consumer root's `.terraform` cache, verify its SHA-256 against the digest
declared by the base, and pass only that verified local file to the Helm data
source. A mismatched download or altered cached file SHALL fail the plan/apply
before any manifest enters the Talos machine configuration.

A consumer MAY select an HTTP mirror through `cilium_chart_repository`, but the
mirror SHALL serve bytes matching the same base-owned digest.

#### Scenario: Repository serves different bytes

- **WHEN** the selected Cilium repository returns an archive whose SHA-256 does
  not match the base pin
- **THEN** the plan/apply fails before the Cilium seed is rendered
