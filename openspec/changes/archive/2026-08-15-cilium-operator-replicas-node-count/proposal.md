# Cilium operator replicas follow the cluster's node count

## Why

The shipped floor pins `operator.replicas: 1`. That value is correct for
exactly one cluster shape — a single node — because the chart's operator
`podAntiAffinity` is `requiredDuringSchedulingIgnoredDuringExecution` on
`kubernetes.io/hostname`: a second replica has nowhere to land and stays
Pending. On every other shape the floor is a downgrade from the chart's own
default of 2, and it removes the only mitigation for a failure mode the chart
carries by design.

The chart tolerates `node.kubernetes.io/not-ready` on the operator with no
`tolerationSeconds`. Kubernetes adds a 300-second eviction toleration for that
taint only when the pod does not set one explicitly, so the explicit toleration
suppresses it: a NotReady node keeps a single-replica operator bound to it with
no failover. The operator is what clears `node.cilium.io/agent-not-ready` from
newly joined nodes (`operator.removeNodeTaints`, on by default), so a stuck
operator also stops new nodes from becoming schedulable.

Two replicas plus the chart's anti-affinity restore the failover. The module
already knows the node set, so the value can be derived instead of pinned.

## What Changes

- `cilium-cni-delivery`: the computed layer emits `operator.replicas = 2` when
  the cluster has two or more nodes; at one node it emits no `operator.replicas`
  key and the floor keeps owning the value. The floor file is unchanged — it
  stays the single-node-correct boundary condition.
- The `operator` parent gains a second contributor and therefore folds through
  one hoisted sub-map (`local.cilium_operator_values`), per the existing
  single-merge-term rule for multi-contributor parents. The conditional emission
  is load-bearing beyond correctness: it keeps the floor the sole contributor of
  a key under `operator` at one node, which is what keeps the explicit `operator`
  sub-merge in `cilium_effective_values` detectable by its preservation assert.
  An unconditional emission would turn that assert's mutant into an equivalent
  one and silently retire a live gate.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `cilium-cni-delivery`

## Impact

- Specs: `cilium-cni-delivery`.
- Code: `tofu/modules/talos-cluster/cilium-values.tf`.
- Gates: `tofu/modules/talos-cluster/tests/input-validation.tftest.hcl` — two new
  runs (the multi-node arm asserting both engines; the level-B pair asserting the
  two `operator` contributors coexist) plus one new assert on the existing
  default-off run pinning the single-node absence of the computed `operator` key.
- Docs: `CHANGELOG.md`, `knowledge/decisions/0022-cilium-observability-and-argocd-self-management.md`
  (addendum), `knowledge/log.md`.
- Consumer-visible behaviour change: a multi-node cluster that adopts this tag
  gets a second `cilium-operator` replica. Consumers pinning their own value via
  `cilium_values_override` are unaffected — the override layer still wins.
