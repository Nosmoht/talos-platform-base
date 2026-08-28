## MODIFIED Requirements

### Requirement: Cluster-agnostic floor values with layered configuration

The module SHALL render the seed from three value layers, later layer
winning per Helm merge semantics: the shipped floor
`tofu/modules/talos-cluster/helm/cilium-values.yaml` (Talos invariants:
cgroup auto-mount disabled, `SYS_MODULE` absent from the agent capability
set, `cni.exclusive: false`, Hubble disabled for a deterministic render,
a single operator replica as the single-node-correct boundary condition),
then module-computed values derived from typed inputs (routing mode,
kube-proxy replacement, native-routing CIDR, Gateway API, MTU, encryption,
the operator replica count derived from the node set, and — issue #188 —
Cilium agent and operator Prometheus metrics, Hubble
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

- **WHEN** the module plans against a node set of two or more nodes
- **THEN** both the seed's computed values layer and the emitted
  self-management Application carry `operator.replicas: 2` — the chart's own
  default, restoring the failover its `podAntiAffinity` is there to spread,
  because the operator's explicit `node.kubernetes.io/not-ready` toleration
  carries no `tolerationSeconds` and therefore suppresses the automatic
  300-second eviction that would otherwise reschedule a lone replica off a
  NotReady node

#### Scenario: A single-node cluster keeps the floor's replica count

- **WHEN** the module plans against a node set of exactly one node
- **THEN** the computed layer emits no `operator.replicas` key and the
  floor's value of 1 is the effective one — a second replica could never be
  placed against the chart's hostname anti-affinity, and the floor remaining
  the sole contributor under `operator` is what keeps that parent's
  sub-merge preservation assertion able to fail

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
