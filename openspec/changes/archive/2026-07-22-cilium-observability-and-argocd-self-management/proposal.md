## Why

Consumers who want Cilium/Hubble metrics today must hand-roll a
`cilium_values_override` YAML blob, and there is no supported way for an
already-bootstrapped, GitOps-reconciled consumer to change the Cilium config on
a running cluster: the module's own Cilium delivery is a frozen, create-only
`cluster.inlineManifests` seed (`cilium-cni-delivery`, "Seed render frozen
against non-deterministic re-renders") that does not reconcile. Issue #188
requests first-class observability inputs (agent/operator Prometheus metrics,
Hubble flow/metrics) plus a documented Day-2 delivery path.

The plan (`.work/issue-188/plan.md`, revision 4) implements both, but its
`§Verification` section omitted the OpenSpec spec-delta this repo's
`AGENTS.md §Spec-Driven Development` requires: the diff touches the `primary`
sources of THREE specs — `module-interface-contract` (`variables.tf`,
`outputs.tf`, `versions.tf`), `cluster-yaml-sot` (`schemas/cluster.schema.json`),
`cluster-bootstrap-lifecycle` (`main.tf`, locals relocated out of it) — and
introduces a fourth primary-source relationship: the relocated Cilium
value-computation locals now live in a NEW file,
`tofu/modules/talos-cluster/cilium-values.tf`, which the `check-spec-partition.py`
completeness gate requires an owning spec for. This change closes that gap,
authored during implementation per an orchestrator-confirmed binding addendum
(`.work/issue-188/builder-addenda.md` item 7) rather than before it — the code
is already written and independently verified; this proposal documents its
observable contract.

Full rationale, the Hubble-TLS-independent-of-metrics grounding, the
floor-preservation merge design, and the override-drop hazard:
`knowledge/decisions/0022-cilium-observability-and-argocd-self-management.md`.

## What Changes

- `module-interface-contract` gains six new `cilium_*` inputs (agent/operator
  Prometheus metrics, Hubble enablement + metrics list, opt-in self-management
  and its target AppProject), two new cross-variable guard validations on
  `cilium_self_management` (deploy-prereq gate; override-drop hard-reject), two
  new outputs (`cilium_self_management_app`, the emitted Application;
  `cilium_seed_observability_markers`, a secret-free audit output), and its
  OpenTofu floor bumps `>= 1.7.0` → `>= 1.9.0` (the two new validations'
  cross-variable `condition`s are an OpenTofu ≥ 1.9 feature, parsed at module
  load regardless of the toggles' values).
- `cluster-yaml-sot` widens the `substrate.cilium` schema from a loosely typed
  object to closed (`additionalProperties: false`) with a full typed
  `properties` list — the 11 pre-existing keys plus six new observability +
  self-management keys — so a typo'd key is caught at lint time.
- `cilium-cni-delivery` gains a new primary source
  (`tofu/modules/talos-cluster/cilium-values.tf`, the relocated value-computation
  locals), its module-computed-values layer now also carries agent/operator
  Prometheus metrics and Hubble enablement/metrics/TLS-off, and it gains a new
  opt-in delivery mechanism — a module-emitted (never applied) ArgoCD
  Application — alongside the pre-existing static reference-values file.
- `cluster-bootstrap-lifecycle`: `§Purpose` prose only, noting the relocated
  Cilium value-computation locals now live in `cilium-values.tf`; no
  Requirement changes (its bootstrap-sequencing behavior is unaffected).

## Capabilities

### New Capabilities

None. The behavior modifies four existing capabilities.

### Modified Capabilities

- `module-interface-contract`: two MODIFIED requirements (grouped typed input
  surface; version constraints — OpenTofu floor bump), one MODIFIED
  requirement (seed and wiring audit outputs — the new secret-free marker
  output), two ADDED requirements (the self-management guard validations; the
  opt-in self-management output).
- `cluster-yaml-sot`: one MODIFIED requirement (untyped escape hatches and
  structural secret exclusion — the `substrate.cilium` closure).
- `cilium-cni-delivery`: one MODIFIED requirement (cluster-agnostic floor
  values with layered configuration — the observability additions to the
  computed layer), one ADDED requirement (opt-in emitted self-management
  Application).
- `cluster-bootstrap-lifecycle`: `§Purpose` prose only; no requirement change.

## Impact

- Specs: `openspec/specs/module-interface-contract/spec.md`,
  `openspec/specs/cluster-yaml-sot/spec.md`,
  `openspec/specs/cilium-cni-delivery/spec.md` — merged in on archive (this
  change is archived in the same commit that ships the code, per
  `scripts/check-spec-staleness.py` globbing `openspec/specs/*/spec.md` only).
  `openspec/specs/cluster-bootstrap-lifecycle/spec.md` — `§Purpose` prose
  hand-edited directly (no Requirement delta to merge), matching the
  `2026-07-17-replace-cert-approver-postfinance` precedent for a
  no-requirement-change primary-source touch; `openspec/specs/cilium-cni-delivery/spec.md`
  frontmatter (`sources.primary`) is likewise hand-edited to add
  `cilium-values.tf` — frontmatter and `§Purpose` prose are outside the
  delta-tracked Requirements schema.
- Code: `tofu/modules/talos-cluster/{variables.tf,outputs.tf,versions.tf,main.tf}`
  (moved locals out of `main.tf`), `tofu/modules/talos-cluster/cilium-values.tf`
  (new — the relocated value-computation locals + the emitted Application
  local), `schemas/cluster.schema.json`, `cluster.yaml.example`,
  `tofu/modules/talos-cluster/examples/complete/{main.tf,cluster.yaml}`.
- Gates: `tofu/modules/talos-cluster/tests/input-validation.tftest.hcl` (10 new
  offline runs — default-off, all three AC#1 legs, hubble-metrics-list,
  hubble-TLS-off, floor-preservation, app-on shape, three guard-failure legs),
  `tofu/modules/talos-cluster/tests/composition.tftest.hcl` (one new network
  run binding the seed-render observability markers).
- Docs: `knowledge/decisions/0022-cilium-observability-and-argocd-self-management.md`
  (new ADR), `CHANGELOG.md` (`### Added` + `### Changed — BREAKING`),
  `UPGRADING.md` (OpenTofu floor, schema closure, new opt-in surface,
  override-drop hazard, bootstrap-window datapath gap, ArgoCD-adoption
  caveat), `tofu/modules/talos-cluster/README.md` (Inputs/Outputs rows + a new
  `## Cilium observability + self-management` section).
