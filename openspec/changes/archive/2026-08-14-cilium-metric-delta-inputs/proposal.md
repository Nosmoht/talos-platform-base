# Typed Cilium metric-delta and OpenMetrics inputs

## Why

The four observability inputs from issue #188 cover enabling the agent,
operator and Hubble metric endpoints, but not what those endpoints export.
Everything beyond them — the chart's `prometheus.metrics` delta list, the
OpenMetrics exposition format — is reachable only through
`cilium_values_override`, and the override-drop guard hard-rejects
`cilium_self_management` while that override is non-empty. A consumer therefore
has to choose between tuning the metric set and using the module's Day-2
self-management path.

Two knobs move into the typed surface so they flow through the bounded
floor ⊕ computed merge that feeds both engines. The chart's Grafana dashboard
toggles are deliberately NOT typed: they emit ConfigMaps whose `namespace` and
sidecar `label` decide whether anything reads them — values a cluster-agnostic
base cannot know — so they are apps-catalog territory per the routing rule in
`AGENTS.md §Repository Purpose`.

## What Changes

- `cilium-cni-delivery`: the computed layer gains the agent metric-delta list
  and the Hubble OpenMetrics flag, and the seed render surfaces both. The
  single-data-flow property is unchanged — both inputs reach both engines.
- `module-interface-contract`: two new inputs on the Cilium observability
  group, one carrying a format validation, both carrying a plan-time `check`
  rather than a hard rejection; two new keys on the seed-marker output.
- `cluster-yaml-sot`: two new properties on the closed `substrate.cilium`
  object.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `cilium-cni-delivery`
- `module-interface-contract`
- `cluster-yaml-sot`

## Impact

- Specs: `cilium-cni-delivery`, `module-interface-contract`, `cluster-yaml-sot`.
- Code: `tofu/modules/talos-cluster/{cilium-values.tf,variables.tf,outputs.tf}`,
  `schemas/cluster.schema.json`,
  `tofu/modules/talos-cluster/examples/complete/{main.tf,cluster.yaml}`,
  `cluster.yaml.example`.
- Gates: `tofu/modules/talos-cluster/tests/input-validation.tftest.hcl` (nine
  new runs: both engines per input, conditional emission per input, both inputs
  together, the blessed Hubble half-on state, three format-rejection legs with a
  negative-space control, and two `expect_failures` legs binding the check
  blocks); `tests/composition.tftest.hcl` (the chart-key spelling oracle for
  both Helm paths, plus an assert pinning the no-DaemonSet-roll claim).
- Docs: `tofu/modules/talos-cluster/README.md`, `CHANGELOG.md`, `UPGRADING.md`,
  `knowledge/decisions/0022-…` addendum, `knowledge/reference/cluster-yaml.md`,
  `knowledge/log.md`.
