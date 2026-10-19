---
sources:
  primary:
    - kubernetes/bootstrap/cilium/values.yaml
    - kubernetes/bootstrap/cilium/extras.yaml
    - tofu/modules/talos-cluster/helm/cilium-values.yaml
    - tofu/modules/talos-cluster/cilium-values.tf
    - tofu/modules/talos-cluster/cilium-seed.tf
references:
  - AGENTS.md §Repository Purpose (three pillars)
  - knowledge/decisions/0029-public-api-and-major-rule.md
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

#### Scenario: The API-server endpoint is configurable and gated on the toggle

- **WHEN** `cilium_kube_proxy_replacement` is true
- **THEN** the computed values layer carries `kubeProxyReplacement: true`
  plus the configured `k8sServiceHost`/`k8sServicePort`, defaulting to Talos
  KubePrism; and when the toggle is false it carries
  `kubeProxyReplacement: false` and NO endpoint keys, because Cilium then
  reaches the API server through the ClusterIP kube-proxy provides

#### Scenario: The configured endpoint is observed at the render layer

- **WHEN** `cilium_k8s_service_host` and `cilium_k8s_service_port` are set and
  the seed render is produced
- **THEN** both values appear in the rendered agent DaemonSet as the
  `KUBERNETES_SERVICE_HOST` / `KUBERNETES_SERVICE_PORT` container env vars,
  per the class rule above — the values-map assertion alone cannot distinguish
  a key the chart consumes from one it silently discards, and this endpoint is
  what Cilium reaches the API server through before the CNI is up

### Requirement: Cilium-side kube-proxy pairing emitted from the computed layer

The Cilium side of the kube-proxy replacement pairing is
`kubeProxyReplacement` plus the API-server endpoint host and port Cilium
reaches before the CNI is up. The module SHALL
emit all three from its computed values layer — never from the shipped floor
file — so both delivery paths carry the same values, and the endpoint's host
and port SHALL be typed inputs defaulting to Talos KubePrism rather than
hardcoded literals.

#### Scenario: The pairing keys never come from the floor file

- **WHEN** either delivery path carries `kubeProxyReplacement`,
  `k8sServiceHost` or `k8sServicePort`
- **THEN** the value comes from the module's computed values layer, and the
  shipped floor file carries none of the three

#### Scenario: A cluster whose API-server endpoint is not KubePrism says so

- **WHEN** the reachable API-server endpoint of a cluster is not Talos
  KubePrism — Cilium documents these values as derived from that endpoint
- **THEN** the consumer can set the typed host and port inputs instead of
  the KubePrism defaults, with no hardcoded literal to override

#### Scenario: The override joint-key rejection costs no capability

- **WHEN** `module-interface-contract`'s override joint-key rejection refuses
  these keys in `cilium_values_override`
- **THEN** the endpoint stays reachable through the typed inputs — just not
  through a layer that would set one half without the other

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

The repo SHALL pin the seed's rendered `cilium-config` surface at two levels:
its full KEY SET against a committed fixture, so a bump that adds or removes
any key fails until the fixture is refreshed deliberately; and the VALUES of a
curated set of datapath- and security-relevant keys. A refresh SHALL be a
deliberate act that answers the consumer-facing question in `UPGRADING.md`,
never a silent regeneration.

#### Scenario: A chart bump that changes the seed's config surface fails the suite

- **WHEN** the pinned chart renders a `cilium-config` whose key set differs from
  the committed fixture, or whose value for a curated key differs from its pin
- **THEN** the module's test target fails, naming the divergence, rather than
  freezing the new default into the machine configuration unnoticed

#### Scenario: A default changed under an unchanged key is caught by the value pins

- **WHEN** a chart bump changes the default of a curated key while the key set
  still matches the committed fixture
- **THEN** the curated value pin fails, because a key set alone cannot catch a
  default that changed under an unchanged key
- **AND** this suite is what catches it: the seed bypasses the
  kustomize/conftest render gate, so the create-only controlplane machine
  configuration would otherwise take the new default with nothing failing

### Requirement: Curated value pins grow as bumps reveal regressions

The curated value set SHALL start from the keys whose flip would break the
cluster silently or widen its exposure, and SHALL grow as chart bumps reveal
more. It is intentionally open: its purpose is to make the class of
regression visible, not exhaustive coverage.

#### Scenario: A bump reveals a datapath-relevant flip outside the curated set

- **WHEN** a chart bump flips the default of a key outside the curated set
  whose flip would break the cluster silently or widen its exposure — as the
  Cilium 1.20 bump moved `bpf-lb-algorithm-annotation` from `"false"` to
  `"true"`, turning a previously inert `service.cilium.io/lb-algorithm`
  Service annotation live while nothing in the suite noticed
- **THEN** that key joins the curated value set

### Requirement: Cluster-agnostic floor values with layered configuration

The module SHALL render the seed from three value layers, later layer
winning per Helm merge semantics: the shipped floor
`tofu/modules/talos-cluster/helm/cilium-values.yaml`, then module-computed
values derived from typed inputs, then the consumer's
`cilium_values_override`.

#### Scenario: Consumer override wins over the floor

- **WHEN** `cilium_values_override` sets a key also present in the shipped
  floor values
- **THEN** the rendered seed carries the override's value for that key, and on
  the multi-source emitted Application the override's file is ordered after the
  module-set layer so Helm resolves it the same way

#### Scenario: Floor keeps install-time-fixed values out

- **WHEN** the shipped floor values file is read
- **THEN** it contains no routing mode, encryption, native-routing CIDR,
  Gateway API, or kube-proxy-replacement keys — those are emitted only by
  the module's computed layer

#### Scenario: A ConfigMap-only change reaches the running agents

- **WHEN** the pinned chart renders with the shipped floor
- **THEN** the `cilium` DaemonSet pod template carries the
  `cilium.io/cilium-configmap-checksum` annotation, so a change that lands only
  in `cilium-config` rolls the agents instead of syncing green over agents that
  keep the previous configuration

#### Scenario: An override declines the agent roll

- **WHEN** `cilium_values_override` sets `rollOutCiliumPods: false`
- **THEN** the rendered `cilium` DaemonSet pod template carries no
  `cilium.io/cilium-configmap-checksum` annotation — which also keeps the
  scenario above discriminating, since a chart that emitted the annotation
  unconditionally would otherwise satisfy it with the floor key gone

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
  all carry — a typed input is the shape that reaches both paths in step,
  which is why one exists for a value the override would otherwise set on the
  seed alone

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

### Requirement: Floor values carry the Talos invariants

The shipped floor `tofu/modules/talos-cluster/helm/cilium-values.yaml` SHALL
carry the Talos invariants: cgroup auto-mount disabled, `SYS_MODULE` absent
from the agent capability set, `cni.exclusive: false`, Hubble disabled for a
deterministic render, a single operator replica as the single-node-correct
boundary condition, and `rollOutCiliumPods: true`.

#### Scenario: The floor file carries each invariant

- **WHEN** the shipped floor values file is read
- **THEN** it disables cgroup auto-mount, omits `SYS_MODULE` from the agent
  capability set, and sets `cni.exclusive: false`
- **AND** it disables Hubble, sets a single operator replica, and sets
  `rollOutCiliumPods: true`

### Requirement: Computed layer derived from typed inputs

The module-computed layer SHALL derive from typed inputs the routing mode,
kube-proxy replacement, native-routing CIDR, Gateway API, MTU, encryption,
the operator replica count — pinned by its own typed input, or derived from
the node set — and Cilium agent and operator Prometheus metrics, Hubble
enablement/metrics/observer-API-TLS, the agent metric-delta list and the
Hubble OpenMetrics exposition flag.

#### Scenario: Each computed value traces to a typed input

- **WHEN** the module plans with Cilium delivered
- **THEN** every key of the computed layer is derived from the module's typed
  inputs or, for the operator replica count, from its own typed input or the
  node set

### Requirement: Computed layer shared by both delivery paths

The module-computed layer SHALL be computed once, in
`tofu/modules/talos-cluster/cilium-values.tf`, and SHALL feed BOTH the seed
render and the opt-in emitted self-management Application (see Requirement
"Opt-in emitted self-management Application for Day-2 delivery") — a single
observability data-flow, with no divergent computation between the two
delivery paths.

#### Scenario: Seed and emitted Application share one computation

- **WHEN** the module produces both the seed render and the emitted
  self-management Application
- **THEN** both take their module-computed values from the single computation
  in `tofu/modules/talos-cluster/cilium-values.tf`

### Requirement: Multi-input parent keys assembled as one merge term

Within the computed layer, a parent key written by more than one typed input
SHALL be assembled as a single merge term. This collision level and the
distinct floor-versus-computed one the emitted Application's bounded merge
resolves SHALL both carry an explicit sub-merge plus a preservation assertion
that fails when either contributor is lost.

#### Scenario: Two inputs writing one parent key both survive

- **WHEN** two typed inputs write the same top-level key of the computed
  layer, which is a shallow `merge()` over conditional maps
- **THEN** they are assembled as one merge term, so the later does not replace
  the earlier wholesale and silently drop the earlier input's effect
- **AND** a preservation assertion fails if either contributor is lost

### Requirement: rollOutCiliumPods is the floor's one non-invariant key

The floor SHALL carry `rollOutCiliumPods: true`, its one key that is not a
Talos or CNI invariant; it belongs to the floor rather than the computed
layer because no typed input derives it. The floor's own header SHALL state
this exception, so the membership rule the file declares matches the file.

#### Scenario: The floor header states the exception

- **WHEN** the header of `tofu/modules/talos-cluster/helm/cilium-values.yaml`
  is read
- **THEN** it names `rollOutCiliumPods: true` as the exception to the file's
  Talos-or-CNI-invariant membership rule

#### Scenario: The property the key fixes holds on every cluster

- **WHEN** a delivered values change renders only into the `cilium-config`
  ConfigMap, as most Cilium settings do
- **THEN** the chart's pod-template checksum rolls the agent DaemonSet, where
  without it the DaemonSet stays untouched and the running agents keep the
  previous configuration while the sync reports success

### Requirement: Superseding computed keys emitted only where they supersede

A computed key that supersedes a floor key SHALL be emitted only on the
shapes where it actually supersedes it.

#### Scenario: The floor stays a contributor where the computed key would not supersede it

- **WHEN** the cluster shape is one where a computed key would not supersede
  its floor key
- **THEN** the computed layer omits that key, so the floor stays a
  contributor for that parent and the preservation assertion protecting the
  parent's sub-merge can still fail
- **AND** emitting the key unconditionally would make the floor a
  non-contributor, the mutation that assertion exists to catch equivalent,
  and the gate pass silently

### Requirement: Computed values asserted at the render layer

A value the module computes into a Helm values layer SHALL additionally be
asserted at the RENDER layer wherever the rendered object exposes it.

#### Scenario: A key the chart does not recognise fails the render assertion

- **WHEN** a computed key is one the chart does not recognise — a typo, a
  wrong nesting level, a key the chart renamed in a later version
- **THEN** Helm, merging values without `--strict`, discards it without error
  and every assertion on the values map stays green while the rendered object
  silently keeps the chart's own default
- **AND** the render-layer assertion is what detects the divergence

### Requirement: Reference values for optional Day-2 self-management

The repo SHALL retain `kubernetes/bootstrap/cilium/values.yaml` as a
reference-only Helm values file for optional Day-2 Cilium self-management —
it is not consumed by the module's seed render — and SHALL ship
`kubernetes/bootstrap/cilium/extras.yaml` providing the `cilium`
GatewayClass that the Helm chart does not generate, consistent with the
platform's Gateway-API-only stance (normative: AGENTS.md §Hard Constraints —
Gateway API only).

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

### Requirement: Reference values reconciled on every chart bump

Because `kubernetes/bootstrap/cilium/values.yaml` is offered to consumers as
copy-ready input for a self-managed Application, a `cilium_chart_version`
bump SHALL reconcile it against the newly pinned chart for its **datapath-
and security-critical** values, covering both failure modes in the scenarios
below, and SHALL either fix the file or document the consequence in
`UPGRADING.md`.

#### Scenario: The chart removed a value spelling the file uses

- **WHEN** the newly pinned chart has **removed** a value spelling the file
  uses
- **THEN** Helm, merging without `--strict`, drops it silently rather than
  rejecting it, so the consumer's cluster is misconfigured or newly failing
  with no error at render or apply time
- **AND** the bump fixes the file or documents the consequence in
  `UPGRADING.md`

#### Scenario: The chart changed a default under a spelling that still parses

- **WHEN** the newly pinned chart has changed the **default or enforcement
  behavior** of a value under a spelling that still parses
- **THEN** the consumer's cluster is misconfigured or newly failing with no
  error at render or apply time
- **AND** the bump fixes the file or documents the consequence in
  `UPGRADING.md`

### Requirement: Removed reference-value spellings fail a schema-path check

The removed-spelling failure mode SHALL be enforced mechanically rather than
by review: a check SHALL validate every value path in
`kubernetes/bootstrap/cilium/values.yaml` against the pinned chart's own
`values.schema.json` and fail on a path the chart does not declare, running
from the same script locally and in CI so a local pass means what a CI pass
means.

#### Scenario: The chart registry is unreachable

- **WHEN** the check cannot reach the chart registry it needs
- **THEN** it SHALL skip loudly rather than fail, so an outage does not block
  unrelated merges
- **AND** this leaves one stated hole: during an outage a removed spelling
  can merge

#### Scenario: A changed default is outside the check's reach

- **WHEN** a chart bump changes a default under a spelling that still parses
- **THEN** the schema-path check does not report it — no schema can express
  it — and that failure mode stays reviewer-enforced

### Requirement: Unrecognized reference values are removed

A value in `kubernetes/bootstrap/cilium/values.yaml` found to be
unrecognized by the pinned chart SHALL be removed. Known exception: a full
audit of every value in the file against the pinned chart is out of scope
for a version bump, so the file MAY still carry a value the chart does not
recognize.

#### Scenario: An unrecognized value is found

- **WHEN** a value in the file is found to be unrecognized by the pinned chart
- **THEN** it is removed — it is inert rather than harmful, since Helm drops
  it and removing it leaves the rendered output byte-identical, but it
  misleads a consumer copying the file

### Requirement: Reference values carry rollOutCiliumPods

`kubernetes/bootstrap/cilium/values.yaml` SHALL carry
`rollOutCiliumPods: true` alongside the floor.

#### Scenario: A consumer copies the reference values

- **WHEN** a consumer follows the documented copy path into a self-managed
  Application — the very delivery path the key exists for
- **THEN** the copied values carry `rollOutCiliumPods: true`, so the consumer
  is not handed the defect the floor closes
- **AND** this is a file-content obligation, because the schema-path check
  validates spellings present, never a key absent, and so cannot report its
  omission

### Requirement: Opt-in emitted self-management Application for Day-2 delivery

The module SHALL, when `cilium_self_management = true` (guarded by the
`module-interface-contract` cross-variable validations), expose an
`argoproj.io/v1alpha1` `Application` manifest — via the
`cilium_self_management_app` output, never applied by the module — as the
Day-2 delivery path for a Cilium config change (including the observability
inputs) on an already-bootstrapped cluster.

#### Scenario: Emitted Application carries the module-set values only

- **WHEN** `cilium_self_management = true` and
  `cilium_self_management_values_source` is unset
- **THEN** the emitted Application carries `spec.source` (not `spec.sources`),
  its `valuesObject` equals the floor ⊕ computed-values merge, the manifest
  carries no `syncPolicy` and no values-digest annotation, and
  `cilium_self_management_values` is the empty string

#### Scenario: The consumer override reaches Day-2 as the last values layer

- **WHEN** `cilium_self_management = true`, `cilium_values_override` is
  non-empty, and `cilium_self_management_values_source` is set
- **THEN** the emitted Application carries `spec.sources` and no
  `spec.source`; `sources[0]` is the `ref` source named `values` at the
  configured repository and revision; and `sources[1].helm.valueFiles` is
  exactly the module-set layer's path followed by the override's path, so
  Helm applies the override last

#### Scenario: The joint keys survive a missing or stale values file

- **WHEN** the emitted Application is multi-source
- **THEN** `sources[1].helm.valuesObject` carries `kubeProxyReplacement` and,
  with the kube-proxy replacement on, `k8sServiceHost` and `k8sServicePort` —
  applied after both `valueFiles`, so the kube-proxy-replacement pairing with
  Talos' `cluster.proxy.disabled` holds even when the committed values file is
  absent or stale, and `ignoreMissingValueFiles` is `false` so a wrong path is
  a loud sync error rather than a silent render against chart defaults

#### Scenario: The override entry is absent when there is no override

- **WHEN** `cilium_self_management_values_source` is set and
  `cilium_values_override` is empty
- **THEN** `sources[1].helm.valueFiles` carries the module-set layer alone,
  never a `$values/` path to a file the consumer never wrote

#### Scenario: Emitted Application targets the default AppProject unless scoped

- **WHEN** `cilium_self_management_project` is left at its default
- **THEN** the emitted Application's `spec.project` is `"default"` — the
  base's only pre-existing AppProject — functional out-of-the-box, with a
  dedicated scoped project as documented, recommended hardening

#### Scenario: A values source on the permissive project warns

- **WHEN** `cilium_self_management_values_source` is set while
  `cilium_self_management_project` is still `"default"`
- **THEN** the plan warns, because that project's `sourceRepos: ['*']` accepts
  any repo the manifest names and the multi-source arm is the first shape whose
  manifest names a values repo of its own — so the state where an edit to one
  string decides where a privileged DaemonSet's Helm values come from is not the
  silent one

#### Scenario: The joint keys are a precedence the override file cannot beat

- **WHEN** the file committed at `override_path` names `kubeProxyReplacement`,
  `k8sServiceHost` or `k8sServicePort`
- **THEN** the emitted Application's `valuesObject` still decides those three,
  because it is applied after every `valueFiles` entry — the module's key
  rejection covers the `cilium_values_override` INPUT and cannot cover a file
  the module never reads, so the generated values document's own header SHALL
  disclose the precedence and name the typed inputs that set both halves

#### Scenario: The Day-2 path complements the seed and the reference file

- **WHEN** a Cilium config change targets an already-bootstrapped cluster
- **THEN** the emitted Application is its delivery path, complementing the
  frozen create-only bootstrap seed and the pre-existing static
  `kubernetes/bootstrap/cilium/values.yaml` reference file

### Requirement: Emitted Application shape selected by the values source

The emitted Application SHALL take one of two shapes, selected by
`cilium_self_management_values_source`: single-source when it is unset (the
default), multi-source when it is set.

#### Scenario: The values source selects the shape

- **WHEN** `cilium_self_management_values_source` is unset
- **THEN** the emitted Application is single-source; and when it is set, the
  emitted Application is multi-source

### Requirement: Single-source Application carries the bounded merge only

On the single-source shape, `spec.source.helm.valuesObject` SHALL be the
bounded, module-controlled merge of the floor and computed-values layers
only, and `cilium_values_override` SHALL NOT reach it. Configuring or not
configuring a values source SHALL NOT move this document AT ONE BASE
REVISION.

#### Scenario: The override does not reach the single-source document

- **WHEN** `cilium_values_override` is non-empty and the values source is
  unset
- **THEN** the emitted `spec.source.helm.valuesObject` is the floor ⊕
  computed-values merge alone

### Requirement: Single-source document changes across base revisions are announced

The single-source document's stability is not a promise across revisions: a
floor or computed-layer change moves it for every consumer on this arm,
deliberately. Such a change is consumer-visible on this arm and SHALL carry
an `UPGRADING.md` note and a deliberate golden refresh.

#### Scenario: A base revision moves the single-source document

- **WHEN** a floor or computed-layer change moves the single-source document
- **THEN** the change carries an `UPGRADING.md` note and a deliberate golden
  refresh
- **AND** its release class follows ADR-0029 — row 12, MINOR with that note
  although this arm has no opt-out, and the higher class only if row 9
  applies

### Requirement: Multi-source Application carries ordered values files

On the multi-source shape, `spec.sources` SHALL carry exactly two entries: a
`ref`-only source for the consumer's values repository (no `path`, no
`chart`), and the Cilium chart source whose `helm.valueFiles` SHALL be the
module-set layer FIRST and `cilium_values_override` SECOND, with
`helm.ignoreMissingValueFiles` explicitly `false`. The override entry SHALL
be absent when the override is empty.

#### Scenario: The ref-only source exists for value resolution

- **WHEN** the emitted Application is multi-source
- **THEN** its `ref`-only source generates no manifests and exists so
  `$values/<path>` resolves at all

#### Scenario: The list order is the precedence mechanism

- **WHEN** Helm renders the chart source's `helm.valueFiles`
- **THEN** it merges later files over earlier ones at arbitrary depth, so the
  override wins over the module-set layer
- **AND** the merge belongs to Helm and not to the module, because the
  override is an opaque YAML document and HCL has no generic recursive merge

### Requirement: Multi-source valuesObject carries only the joint keys

The module SHALL NOT place the override in `helm.valuesObject`, which is
applied after every `valueFiles` entry and is where the module re-asserts its
own keys. On the multi-source shape `helm.valuesObject` SHALL carry the joint
keys of `module-interface-contract`'s override joint-key guard —
`kubeProxyReplacement` always, plus `k8sServiceHost` and `k8sServicePort`
when `cilium_kube_proxy_replacement` is true — and nothing else.

#### Scenario: The joint keys guard against an empty values file

- **WHEN** the committed module-set values file resolves empty on the
  multi-source shape — the joint keys are produced by the computed layer
  alone, never by the floor file, so on this shape they otherwise live only
  in a file the consumer commits
- **THEN** `valuesObject` still carries them, so the render is not a Cilium
  that does not replace kube-proxy while Talos already carries
  `cluster.proxy.disabled`
- **AND** the running cluster is not left with no ClusterIP datapath and no
  cluster DNS, a state the create-only seed cannot repair

#### Scenario: Re-asserting the joint keys overwrites no consumer value

- **WHEN** the module re-asserts the joint keys as the last layer
- **THEN** this SHALL NOT constitute the module overwriting a consumer value,
  because the override is forbidden to name them

### Requirement: Module-set values document and digest annotation

The module SHALL expose the module-set layer as
`cilium_self_management_values`, a YAML document for the consumer to commit
at the values source's `values_path`, empty on the single-source shape. The
emitted Application SHALL carry a `talos-platform-base.io/values-digest`
annotation over that layer, matching a digest recorded in the document's own
header; the annotation SHALL be absent on the single-source shape.

#### Scenario: A stale committed values file is detectable

- **WHEN** the committed values file was produced from an earlier
  module-set layer than the one the Application was emitted from
- **THEN** the Application's `talos-platform-base.io/values-digest`
  annotation differs from the digest in the file's header — the two
  artifacts are committed independently and ArgoCD compares neither

#### Scenario: No digest annotation without a values file

- **WHEN** the emitted Application is single-source, which has no such file
- **THEN** it carries no `talos-platform-base.io/values-digest` annotation

### Requirement: Emitted Application project and sync policy

The Application SHALL carry
`spec.project = var.cilium_self_management_project` (default `"default"`,
the base's sole permissive AppProject) and SHALL carry no `syncPolicy`, so
the consumer controls sync timing for the graceful-restart-gated DaemonSet
roll that enabling Hubble triggers.

#### Scenario: A scoped project lists both repositories

- **WHEN** a consumer creates a scoped project — the recommended
  hardening — for the multi-source shape
- **THEN** that project MUST list both the values repository and the chart
  repository in `sourceRepos`
