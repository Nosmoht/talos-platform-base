# An explicit operator replica count, and an honest reason for the derived one

## Why

Two things, both surfaced by review of the node-count derivation that landed
immediately before this change.

**1. The derivation has no per-cluster opt-out on the self-management path.**
`cilium_values_override` pins the count on the seed path only: the emitted
Application's `valuesObject` carries no override term, and the module
hard-rejects that override while `cilium_self_management` is on. A self-managing
consumer whose second node is a dedicated storage or GPU node — tainted beyond
the operator's five tolerated keys, so the second replica can never place — had
no way to say so. That asymmetry was recorded as a known residual rather than
defended; this change closes it, and follows the convention
`cert_approver_replicas` already sets.

**2. The reason published for the derived value overstated what was measured.**
The original justification claimed a `NotReady` node keeps a single-replica
operator bound with no failover, and that a stuck operator stops new nodes from
becoming schedulable. Re-measured against the pinned chart, three links in that
chain do not hold as written:

- The operator tolerates `node.kubernetes.io/not-ready` but **not**
  `node.kubernetes.io/unreachable`. A hard node failure reports `Ready=Unknown`,
  which is the `unreachable` taint, so the standard 300-second eviction still
  applies. The honest delta is failover *latency*, not failover *existence*.
- With two replicas the operator runs **leader-elected** (its ClusterRole carries
  `coordination.k8s.io/leases` for exactly that, per the chart's own comment).
  A node marked `NotReady` whose operator pod is alive and still reaching the API
  keeps that pod as the leader; the standby stays passive. A second replica helps
  when the incumbent stops renewing its lease — not because a node was marked
  unhealthy.
- The operator is the taint **setter** as well as its remover:
  `set-cilium-node-taints` and `remove-cilium-node-taints` are both rendered from
  `.Values.operator.*` and both default on. A wedged operator therefore never
  *applies* `node.cilium.io/agent-not-ready` either, so new nodes become
  schedulable immediately and unsafely — the opposite of the published claim.

What survives measurement is narrower and still sufficient: 2 is the chart's own
default, which the floor's 1 diverged from without that ever being a multi-node
decision; the operator's rolling-update strategy is `maxUnavailable: 100%` at one
replica and `50%` at two, so at one replica every operator upgrade takes the only
instance down; and on a hard node failure a running standby takes over on lease
expiry instead of waiting out the 300-second eviction plus a reschedule and a
cold start.

## What Changes

- `cilium-cni-delivery`: a new typed input pins the operator replica count. When
  set it wins over the node-count derivation on **both** delivery paths — the
  frozen seed render and the emitted self-management Application. Unset (the
  default) leaves the derivation in place unchanged.
- A resolved count exceeding the declared node count **warns** at plan time and
  proceeds. The operator's `podAntiAffinity` is `requiredDuringScheduling` on
  hostname, so the surplus pods stay Pending; the module deliberately models node
  count rather than schedulability, and a rejection would refuse a configuration
  the consumer may have reason to want.
- The scenarios' rationale prose is cut back to what was measured. The full
  reasoning — including what a second replica does *not* buy — moves to the ADR,
  where a reader looking for justification will find it; the spec keeps
  observable outcomes.
- The rendered `cilium-operator` Deployment gains a render-layer assertion for
  its replica count. Helm merges values without `--strict`, so a values key the
  chart does not recognise is dropped silently: every values-map assertion stays
  green while the delivered Deployment keeps the chart default. This mirrors the
  binding `cert_approver_replicas` already has.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `cilium-cni-delivery`

## Impact

- Specs: `cilium-cni-delivery`.
- Code: `tofu/modules/talos-cluster/variables.tf` (new input + validation),
  `tofu/modules/talos-cluster/cilium-values.tf` (resolution local, two new
  plan-time `check` blocks).
- Contracts: `schemas/cluster.schema.json` (the `substrate.cilium` object is
  closed, so the key must be declared), `cluster.yaml.example`,
  `tofu/modules/talos-cluster/examples/complete/main.tf`.
- Gates: `tofu/modules/talos-cluster/tests/input-validation.tftest.hcl` (pin
  precedence on both paths, the two warning legs, the two rejected shapes) and
  `tofu/modules/talos-cluster/tests/composition.tftest.hcl` (the render-layer
  replica assertions, derived and pinned).
- Docs: `CHANGELOG.md`, `UPGRADING.md`,
  `tofu/modules/talos-cluster/README.md`,
  `knowledge/decisions/0022-cilium-observability-and-argocd-self-management.md`,
  `knowledge/log.md`.
- Consumer-visible: additive. Omitting the key preserves the behaviour of the
  preceding change exactly.
