---
status: superseded
id: base:shared-render-artifact
superseded_by:
  - base:opentofu-cluster-lifecycle
date: 2026-05-29
date-history:
  - 2026-05-29 initial (accepted; base-side renderer merged in PR #87)
  - 2026-06-02 superseded (OpenTofu cutover removed the make/argv-print frontend)
deciders:
  - Thomas Krahn
consulted: []
informed: []
supersedes: []
related:
  - base:substrate-only-base
  - base:multi-repo-platform-split
  - base:opentofu-cluster-lifecycle
---

> **Superseded (2026-06-02).** This ADR's premise was *two* per-node config
> frontends (`make`/`argv-print.sh` and the OpenTofu provider) needing a shared
> render artifact. The OpenTofu cutover
> ([`adr-0006-opentofu-cluster-lifecycle.md`](adr-0006-opentofu-cluster-lifecycle.md))
> removed the `make`/argv-print frontend entirely, so only one renderer (the
> provider) remains and no cross-frontend bridge is needed. Retained for
> historical context.

# ADR: Shared Render Artifact as the Cross-Frontend Source of Truth for Per-Node Talos Config

## Context and Problem Statement

The base renders per-node Talos machine config from the five-axis
`cluster.yaml` (roles, architectures, infrastructure-platforms,
hardware-platforms, hardware-capabilities). Two provisioning
frontends consume that composition:

- the `make` / `talos/scripts/argv-print.sh` path, which emits
  `talosctl gen config` argv for bare-metal nodes (homelab, in
  production today);
- a `tofu/modules/talos-cluster` HCL path (Crossplane / seeder) that
  drives the Terraform `talos` provider with a divergent `role`+`class`
  node schema and takes its `config_patches` from the caller.

A four-cluster realisability stress-test (homelab, DHQ office,
seeder, and a vSphere-VM cluster) found the `cluster.yaml`
**config-axis holds** across all four archetypes: zero unavoidable
non-parametrisable base changes surfaced. The control model that
held is three-category — substrate-invariant settings the base
fixes, universal mechanisms the base enables for the consumer to
select at Day-2, and cluster-topology the base deliberately does not
know and passes through generically (see
[`adr-0004-substrate-only-base.md` §Validation](adr-0004-substrate-only-base.md#validation)
for the full verdict).

The erosion was not in the config-axis but in the **implementation
layer**: the two frontends re-derive per-node patch composition
independently. A heterogeneous bare-metal cluster provisioned via
Crossplane (DHQ = heterogeneous hardware × tofu provisioning) would
therefore have to duplicate the homelab path's accumulated patch
substance in HCL. That duplication defeats the repository's core
promise — that a consumer profits from the base without redoing the
ground setup.

## Decision Drivers

- One source of truth for per-node patch composition; a single
  resolver, not two parallel implementations that drift.
- Provisioning-agnostic output: a CLI frontend (talosctl argv) and a
  non-CLI frontend (Terraform data source) must consume identical
  composition.
- No regression to the existing `make` / argv path, which renders a
  production cluster.
- Per-node heterogeneity must survive. Nodes of the same
  `machine_type` carry different patch sets — verified on the
  fixtures (`worker-test` 5 patches, `gpu-01` 4, `pi-01` 3, all role
  `worker`). A per-role-only tofu input is therefore insufficient.

## Considered Options

1. Keep two independent renderers (status quo) — each frontend
   re-derives composition from `cluster.yaml`.
2. Port the five-axis composition into HCL — make the tofu module a
   second full implementation of the renderer.
3. Shared render artifact — `argv-print.sh` emits the resolved
   per-node composition as a provisioning-agnostic JSON artifact that
   both the CLI path and the Terraform data source consume.

## Decision Outcome

Chosen option: **Option 3 — shared render artifact**, because it
keeps the five-axis resolution in one place while serving both a CLI
and a non-CLI frontend, and it carries no regression to the argv
path.

Concretely, `argv-print.sh` gained an `EMIT` mode. `EMIT=argv`
remains the default and is bit-identical to the prior behaviour.
`EMIT=content` emits a JSON object
`{node, machine_type, config_patches:[yaml,...]}` of the resolved
per-node patch contents in merge order. The `config_patches` array
maps directly onto the Terraform `talos` provider's
`data.talos_machine_configuration.config_patches` input (a
`list(string)`). One source of truth, two frontends. The base-side
renderer shipped in PR #87.

### Consequences

- Positive: a Crossplane / tofu-provisioned cluster receives the same
  patch substance as a `make`-provisioned one; capability and
  placeholder resolution (for example `${NIC_NAME}` to `eth0`)
  happens once in the shared resolver, not twice.
- Negative: the content artifact is a new contract surface the tofu
  module must consume. Until the module is wired, the source of truth
  is available but not yet consumed by the HCL frontend.
- Follow-up: (a) extend the `tofu/modules/talos-cluster` apply
  resource with a per-node `config_patches` input that consumes this
  artifact; (b) add a render-equivalence CI gate that confirms
  `data.talos_machine_configuration` produces a byte-identical machine
  config to the `talosctl gen config` path.

## Pros and Cons of the Options

### Option 1 — two independent renderers

- Pro: no new work; each frontend already exists.
- Con: divergence is structural, not incidental. The
  `cluster.bgp.*` schema pollution observed on an in-flight branch (a
  typed field added to the base `cluster.yaml` schema that base logic
  never consumes — its only consumer is the seeder's own Taskfile)
  is the same failure shape. Substance drift between the two
  frontends is guaranteed over time.

### Option 2 — port the composition into HCL

- Pro: native to Terraform consumers; no shell dependency at apply
  time.
- Con: two full implementations of the same composition doubles
  maintenance. The divergent `role`+`class` node schema in the tofu
  module is the precise erosion this ADR exists to stop, and porting
  the rest of the composition would entrench it.

### Option 3 — shared render artifact (chosen)

- Pro: one resolver; provisioning-agnostic; no argv-path regression;
  per-node heterogeneity preserved.
- Con: adds a JSON contract surface; the consumer-side wiring is
  deferred to a follow-up.

## Validation

The decision is **wrong** if either of the following surfaces:

- The content artifact and the argv path diverge in composition.
  Guarded mechanically by `make -f talos/Makefile.lib
  test-content-mode`, which asserts patch-count parity between the
  two modes for the same node, a non-empty `list(string)`, and
  per-node placeholder resolution.
- The Terraform data source produces a machine config that differs
  from the `talosctl gen config` path. This is the deferred
  **render-equivalence gate** — until it lands, equivalence is
  asserted only at the composition level (patch-count parity), not as
  byte-identity at the assembled-machine-config level.

Re-review when the tofu-module consumer side lands; that is the point
at which composition parity must be upgraded to assembled-config
byte-identity.

## Links

- PR #87 — base-side `EMIT=content` renderer (merged 2026-05-29).
- `talos/scripts/argv-print.sh` — the shared resolver.
- `talos/scripts/test-content-mode.sh` — the composition-parity gate.
- `docs/adr-0004-substrate-only-base.md` — the substrate model whose
  realisability this four-cluster investigation validated.
- `docs/adr-0001-multi-repo-platform-split.md` — OCI consumption and
  Day-0 / Day-2 distinction that frame the consumer relationship.
- `docs/adr-template.md` — MADR 3.0 template followed here.
