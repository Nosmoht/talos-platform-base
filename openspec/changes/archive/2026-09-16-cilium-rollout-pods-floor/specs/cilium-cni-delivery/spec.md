## MODIFIED Requirements

### Requirement: Cluster-agnostic floor values with layered configuration

The module SHALL render the seed from three value layers, later layer
winning per Helm merge semantics: the shipped floor
`tofu/modules/talos-cluster/helm/cilium-values.yaml` (Talos invariants:
cgroup auto-mount disabled, `SYS_MODULE` absent from the agent capability
set, `cni.exclusive: false`, Hubble disabled for a deterministic render,
a single operator replica as the single-node-correct boundary condition,
and `rollOutCiliumPods: true`),
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

The floor SHALL carry `rollOutCiliumPods: true`. It is the one floor key that
is not a Talos or CNI invariant, and it is admitted because the property it
fixes holds on every cluster: most Cilium settings render only into the
`cilium-config` ConfigMap, so without the chart's pod-template checksum a
delivered values change leaves the agent DaemonSet untouched and the running
agents on the previous configuration while the sync reports success. It belongs
to the floor rather than the computed layer because no typed input derives it.
The floor's own header SHALL state this exception, so the membership rule the
file declares matches the file.

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

The file SHALL carry `rollOutCiliumPods: true` alongside the floor. It is
offered as copy-ready input for a self-managed Application — the very delivery
path the key exists for — so omitting it would hand a consumer following the
documented copy path the defect the floor closes, with the schema-path check
unable to report it (it validates spellings present, never a key absent).

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
`kubernetes/bootstrap/cilium/values.yaml` reference file.

The emitted Application SHALL take one of two shapes, selected by
`cilium_self_management_values_source`:

**Single-source (values source unset, the default).**
`spec.source.helm.valuesObject` SHALL be the bounded, module-controlled merge
of the floor and computed-values layers only, and `cilium_values_override` SHALL
NOT reach it. Configuring or not configuring a values source SHALL NOT move this
document AT ONE BASE REVISION. It is not a promise across revisions: a floor or
computed-layer change moves it for every consumer on this arm, deliberately and
as a MAJOR release.

**Multi-source (values source set).** `spec.sources` SHALL carry exactly two
entries: a `ref`-only source for the consumer's values repository (no `path`,
no `chart` — it generates no manifests and exists so `$values/<path>`
resolves at all), and the Cilium chart source whose
`helm.valueFiles` SHALL be the module-set layer FIRST and
`cilium_values_override` SECOND, with `helm.ignoreMissingValueFiles`
explicitly `false`. The ORDER of that list is the precedence mechanism: Helm
merges later files over earlier ones at arbitrary depth, which is why the
merge belongs to Helm and not to the module — the override is an opaque YAML
document and HCL has no generic recursive merge. The override entry SHALL be
absent when the override is empty. The module SHALL NOT place the override in
`valuesObject`: that slot is applied after every `valueFiles` entry, and it
is where the module re-asserts its own keys.

`helm.valuesObject` on the multi-source shape SHALL carry the joint keys of
`module-interface-contract`'s override joint-key guard — `kubeProxyReplacement`
always, plus `k8sServiceHost` and `k8sServicePort` when
`cilium_kube_proxy_replacement` is true — and nothing else. Those keys are
produced by the computed layer alone, never by the floor file, so on this
shape they live only in a file the consumer commits; any state in which that
file resolves empty would otherwise render a Cilium that does not replace
kube-proxy while Talos already carries `cluster.proxy.disabled`, leaving a
running cluster with no ClusterIP datapath and no cluster DNS that the
create-only seed cannot repair. Re-asserting them as the last layer SHALL NOT
constitute the module overwriting a consumer value, because the override is
forbidden to name them.

The module SHALL additionally expose the module-set layer as
`cilium_self_management_values`, a YAML document for the consumer to commit at
the values source's `values_path`, empty on the single-source shape. The
emitted Application SHALL carry a
`talos-platform-base.io/values-digest` annotation over that layer, matching a
digest recorded in the document's own header, so a stale committed values file
is detectable — the two artifacts are committed independently and ArgoCD
compares neither. The annotation SHALL be absent on the single-source shape,
which has no such file.

The Application SHALL carry `spec.project = var.cilium_self_management_project`
(default `"default"`, the base's sole permissive AppProject; a scoped
consumer-created project is recommended hardening and, on the multi-source
shape, MUST list both the values repository and the chart repository in
`sourceRepos`) and SHALL carry no `syncPolicy`, so the consumer controls sync
timing for the graceful-restart-gated DaemonSet roll that enabling Hubble
triggers.

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
