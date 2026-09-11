---
type: reference
title: Helm Value Surface — ArgoCD and Cilium
description: Which Helm values a consumer cluster can actually set for the two substrate charts, on which of the five delivery paths, in which lifecycle phase — and the three places where the surface closes.
tags: [argocd, cilium, helm, values, consumer-contract, delivery-paths]
generated: { by: human:nosmoht, at: "2026-09-06T00:00:00Z" }
sources:
  - resource: tofu/modules/talos-cluster/main.tf
  - resource: tofu/modules/talos-cluster/variables.tf
  - resource: tofu/modules/talos-cluster/outputs.tf
  - resource: tofu/modules/talos-cluster/cilium-values.tf
  - resource: tofu/modules/talos-cluster/helm/argocd-values.yaml
  - resource: tofu/modules/talos-cluster/helm/cilium-values.yaml
  - resource: tofu/modules/talos-cluster/examples/complete/main.tf
  - resource: tofu/modules/talos-cluster/README.md
  - resource: kubernetes/substrate/argocd/values.yaml
  - resource: kubernetes/substrate/argocd/README.md
  - resource: kubernetes/bootstrap/cilium/values.yaml
  - resource: schemas/cluster.schema.json
  - resource: scripts/render-component.sh
  - resource: scripts/check-argocd-substrate-invariants.sh
  - resource: scripts/check-cilium-reference-values.py
  - resource: scripts/check-shim-key-parity.sh
  - resource: .ci-oci-tarball-include.txt
  - resource: .ci-release-guard-pathspec.txt
  - resource: UPGRADING.md
  - resource: openspec/specs/argocd-module-seed/spec.md
  - resource: openspec/specs/argocd-substrate/spec.md
  - resource: openspec/specs/cilium-cni-delivery/spec.md
---

# Helm Value Surface — ArgoCD and Cilium

## Why this page exists

Consumers report that they cannot set all the Helm values they need for the two
substrate charts, `argo-cd` and `cilium`. This page is the map behind that
report. There is no single value surface in this base: each chart reaches a
cluster through more than one render, each render composes its values
differently, and each closes at a different point. A value that is freely
settable on one path is unreachable on the next, or is superseded once the
cluster moves from bootstrap into steady state.

This page describes the surface as shipped. It decides nothing — see §Not
decided here.

**Reading the citations.** Line numbers are as of this page's `generated.at` and
nothing gates them; each is paired with the symbol or heading it points at, so
a shifted line is still findable. Where a fact is normative, the owning spec is
named and is the authority — see §Where the normative statements live.

**Delivery caveat.** This page ships in no release artifact
(`AGENTS.md` §Project Structure), so nothing here reaches a consumer who
vendors the published tarball. The consumer-facing half of §Where the surface
closes and §What works today instead needs a home in `UPGRADING.md` or the
component READMEs; that is an open item, not something this page discharges.

## The five delivery paths

| # | Path | Values input | Consumer access |
|---|---|---|---|
| A | ArgoCD Day-0 seed — `data "helm_template" "argocd"`, `tofu/modules/talos-cluster/main.tf:51` | `helm/argocd-values.yaml`, then `var.argocd_values_override`, later wins (`main.tf:66-70`) | free-form, fresh bootstrap only |
| B | ArgoCD CRDs — `data "helm_template" "argocd_crds"`, `tofu/modules/talos-cluster/main.tf:869` | none — no `values` block at all, only `set crds.install=true` | none |
| C | ArgoCD steady state — `kubernetes/substrate/argocd/` | `values.yaml`, rendered at authoring time by `scripts/render-component.sh` into `_rendered/` | none in the published payload |
| D | Cilium seed — `data "helm_template" "cilium"`, `tofu/modules/talos-cluster/main.tf:359` | `helm/cilium-values.yaml`, then the module-computed layer, then `var.cilium_values_override` (`main.tf:374-378`) | free-form, fresh bootstrap only |
| E | Cilium self-management — `local.cilium_self_management_app`, `tofu/modules/talos-cluster/cilium-values.tf:269` | floor and computed layer only; no `values_override` term (`cilium-values.tf:201-203`, `:251-260`) | typed inputs only |

Paths A and D are OpenTofu renders baked into the Talos machine config; path E
is an OpenTofu render emitted as a module output and never applied. Path C is
the Rendered Manifests Pattern described in
[Manifest Pipeline](manifest-pipeline.md): the chart is templated at authoring
time, not at sync time.

**Path B is neither.** Its render is frozen like the seeds
(`terraform_data.argocd_crds_render`), but it is written to disk by
`local_file.argocd_crds` and applied by `null_resource.argocd_crds`, which runs
`kubectl apply --server-side` after the cluster-health gate
(`tofu/modules/talos-cluster/main.tf:1007-1103`). Unlike the seeds it therefore
**re-fires** when its `manifest_sha` trigger moves — i.e. on a deliberate
`argocd_chart_version` bump. It still takes no values: the data source renders
with no `values` block at all, only `set crds.install=true`.

**Both seed renders are frozen, and freezing is not the reason they are
bootstrap-only.** `terraform_data.argocd_render`
(`tofu/modules/talos-cluster/main.tf:105-110`) and
`terraform_data.cilium_render` (`main.tf:409-415`) each carry
`ignore_changes = [input]`, which keeps an unstable Helm render from re-pushing
a machine config on every plan. The deeper property is that a Talos
`inlineManifest` is applied once at bootstrap: "re-capture on a live cluster is
inert for a create-only seed" (`main.tf:99-104`). So an override edited after
the first bootstrap reaches a **fresh bootstrap only**. `UPGRADING.md`, in the
`v10.0.0` section's step 2, states the same for the ArgoCD NetworkPolicy lever:
the seed values reach "a **fresh bootstrap only**".

`-replace` on the render resource is not the way around it, and this base does
not claim to know exactly what it does. `UPGRADING.md` §"Removed Helm values"
records that `-replace` is the only mechanism that re-captures the render, that
it rewrites the controlplane patch so machine config re-pushes to **every**
controlplane, and that two things are **unverified**: whether Talos' manifest
reconcile updates objects it already created or only creates missing ones, and
whether those objects are already owned by a self-management `Application`.
Treat it as a planned operation with a `tofu plan` dry-run, not as the Day-2
lever.

### Where the normative statements live

This page is a cross-cutting map, not a second contract. Each path's required
behaviour is owned by a spec, and the spec is the authority on disagreement:
`openspec/specs/argocd-module-seed/spec.md` for path A (including the
merge/later-wins semantics of `argocd_values_override`),
`openspec/specs/argocd-substrate/spec.md` for path C,
`openspec/specs/cilium-cni-delivery/spec.md` for paths D and E (the three value
layers, the frozen seed, and the emitted Application not inheriting
`cilium_values_override`), and
`openspec/specs/module-interface-contract/spec.md` for the typed variable
surface with its guard validations.

## Value reachability per lifecycle phase

| Component | Day-0 seed | Day-0 CRDs | Steady state / Day-2 |
|---|---|---|---|
| ArgoCD | free-form (`argocd_values_override`, path A) | none (path B) | none through the published component (path C) |
| Cilium | free-form (`cilium_values_override`, path D) | n/a — CRDs ride the seed render | typed inputs only through the base (path E) |

"Free-form" means an arbitrary YAML values document merged over the shipped
layers by Helm's own multi-file merge: later wins, lists replace, maps merge.
The escape hatch therefore **sets and extends**; it does not restore a chart
default the floor overrode.

Measured against the pinned `argo-cd` 10.6.0 chart, whose default is
`dex.enabled: true` while the seed floor sets it to `false`: a later layer
carrying `dex.enabled: null` leaves the floor's `false` effective — identical
render, under both helm 3.20.2 (the repo pin) and helm 4.2.4. Nulling the
**parent** map instead (`dex: null`) does drop the subtree, but it drops it
rather than reverting to the chart default. So a leaf the floor owns cannot be
handed back to the chart, and the coarse lever costs the whole map.
`tofu/modules/talos-cluster/variables.tf:650-657` (the `cilium_values_override`
description) states the leaf half of this.

"Typed inputs only" means the `cilium_*` module variables listed in the module
README's §Inputs — no free-form document.

## Where the surface closes

### 1. The published ArgoCD component exposes no Helm value surface

Scope of this section: the `oras pull` payload, which is what
`AGENTS.md` §Repository Purpose describes as the consumption mechanism. See the
qualification at the end of the section for the git path.

The component's contract is `openspec/specs/argocd-substrate/spec.md`, whose
§"Requirement: Kustomize consumption surface" defines consumption as building
one kustomization over committed rendered artifacts. A Helm values input is
absent from it by construction, not by omission.

Of the files under `kubernetes/substrate/argocd/`, the payload carries exactly
four (`.ci-oci-tarball-include.txt:3-6`): `_rendered/crds.yaml`,
`_rendered/manifests.yaml`, `kustomization.yaml` and `namespace.yaml`. Its
`values.yaml`, `chart.lock.yaml` and `_rendered-overlay/` are not shipped, and
no chart is templated at sync time
([Manifest Pipeline](manifest-pipeline.md)) — so on this path there is no
values input to address. (The payload does ship the module's seed values file,
`tofu/modules/talos-cluster/helm/argocd-values.yaml` at
`.ci-oci-tarball-include.txt:10`; that one belongs to path A, and every key in
it is reachable through `argocd_values_override`.)

The base states the closure in its own words at
`kubernetes/substrate/argocd/values.yaml:9` — configuration is wired by
patching rendered ConfigMaps in the consumer's own kustomize overlay, "not
through these Helm values, which a consumer of the published component never
has". `kubernetes/substrate/argocd/README.md:41` repeats the sentence inside
invariant I1's rationale; it is one statement in two places, not two
independent confirmations.

The Multi-Source `helm.valueFiles` mechanism the repository README documents for
Helm-delivered components does not apply here: ArgoCD resolves `$ref` only
inside `helm.valueFiles` and `helm.fileParameters`, and a kustomization cannot
reference a sibling source — see
[ArgoCD SSO Wiring Contract](argocd-sso-contract.md) §"Why not a Multi-Source
Application".

**Consequence for a consumer on this path.** Anything expressible only as a
chart value, and not as a patch on an already-rendered object, is unreachable.
Patching reaches what was rendered; it cannot make the chart render something
else.

**Qualification — the git path is not closed the same way.** The kustomize
remote-base form the repository README documents fetches from git, not from the
tarball, and a git checkout does contain `values.yaml`, `chart.lock.yaml`,
`_rendered-overlay/` and `scripts/render-component.sh` — whose lock schema
accepts a `values:` path. A consumer on that path can fork the component and
re-render the chart with their own values. That is neither documented nor
gated as a supported consumer path, and it forfeits the base's own render
reproducibility, but it is not impossible, and §1 must not be read as saying it
is.

### 2. Cilium's long tail has no base-delivered Day-2 path

`var.cilium_values_override` reaches the render in exactly one place —
`tofu/modules/talos-cluster/main.tf:377`, the seed's values list. (It is read
once more, at `variables.tf:1050`, by the guard below, and it reaches
`output "cilium_seed_observability_markers"` transitively through the frozen
render — `tofu/modules/talos-cluster/outputs.tf` calls that coupling out by
name.)

The seed is bootstrap-only, per §The five delivery paths. And enabling
`cilium_self_management` while the override is non-empty is a hard plan-time
rejection (`tofu/modules/talos-cluster/variables.tf:1049-1052`). Both
properties are normative:
`openspec/specs/cilium-cni-delivery/spec.md` §"Requirement: Opt-in emitted
self-management Application for Day-2 delivery" requires that the emitted
`valuesObject` not inherit the override, and
`openspec/specs/module-interface-contract/spec.md` §"Requirement: Cilium
self-management guard validations" requires the rejection.

So the long tail the override exists to carry — Hubble beyond the typed inputs,
L2 and BGP announcements, bpf tuning, VLAN bypass, `secretsNamespaceLabels`
(`variables.tf:654-656`) — has no route into an already-bootstrapped cluster
that the base itself delivers.

**There is a route, and it is the consumer's own.** The rejection message names
it: migrate the override into your own Cilium Application first, then empty
`cilium_values_override` on the SoT (`variables.tf:1051`). The emitted
Application is a module output the consumer commits into their own app-of-apps
repo, where their GitOps is the single writer
(`tofu/modules/talos-cluster/outputs.tf`, the
`cilium_self_management_app` description), so its `valuesObject` is theirs to
extend. `kubernetes/bootstrap/cilium/values.yaml:6` is copy-ready input for
exactly that, and its key paths are validated against the pinned chart's
`values.schema.json` on every PR by `scripts/check-cilium-reference-values.py`.
`deploy_cilium = false` plus the consumer's own delivery is the other opt-out.

What is missing is therefore not a route but base support for one: the handoff
is manual, the base carries no mechanism that moves an override across it, and
the reference file diverges from the live floor (it enables Hubble and
WireGuard strict mode and sets two operator replicas, none of which the floor
does) so a copy is a starting point, not a migration.

### 3. Seed/steady-state collisions are documented case by case, never enumerated

`argocd_values_override` is seed-only, and whatever it sets that the
steady-state render also declares is overwritten at the first self-management
sync (`tofu/modules/talos-cluster/variables.tf:505-511`).

What exists today is per-case guidance, not the set. The same variable
description names the highest-value members ("SSO and RBAC do NOT belong here")
and `UPGRADING.md`'s `v10.0.0` step 2 names a third
(`global.networkPolicy.create`) with the seed and steady-state levers spelled
out side by side. On the base's
own side, `scripts/check-argocd-substrate-invariants.sh` renders **both**
values files fresh with the pinned chart and asserts six invariants across them
on every PR — so the two files are compared, and four of the invariants are
explicitly shared across the paths. Its own scope note excludes the consumer
override: "base CI cannot gate what a consumer boots".

What no artifact provides is the collision set itself — the intersection of the
keys a consumer's override sets with the keys path C declares. There is no
plan-time signal and no published list, and the consumer cannot compute it
either, because the steady-state values file is not in the payload they receive
(§1). Compounding it, the frozen render means an override edited after
bootstrap is a clean-plan no-op regardless.

Precedent for what a signal could look like: the module hard-rejects the
analogous Cilium hazard rather than letting it pass
(`variables.tf:1049-1052`), and ADR-0022 records why a warning was judged
insufficient there.

## What works today instead

- **ArgoCD:** a single-source Application over the consumer's own repository,
  with this base entering as a tag-pinned kustomize remote base (or a vendored
  local path), plus strategic-merge patches on the rendered ConfigMaps. The
  worked, CI-built example is `kubernetes/examples/argocd-consumer-sso/`; the
  full contract is [ArgoCD SSO Wiring Contract](argocd-sso-contract.md).
- **Cilium before self-management:** `substrate.cilium.values_override` in
  `cluster.yaml`, at a fresh bootstrap.
- **Cilium after self-management:** the consumer's own Cilium Application, which
  owns its values entirely — the migration is manual (§2).

Where this stops for ArgoCD: a chart value that produces no rendered object to
patch, and any change to the chart's own rendering. On the published path there
is no mechanism for those.

## Why the surface is shaped this way

The narrow typed surface is a recorded decision, not an oversight.

- [ADR-0007](../decisions/0007-cluster-yaml-sot.md) §4 sets the altitude:
  first-class fields for the common, irreversible and foot-gun-prone set;
  escape hatches for the long tail — explicitly "do not type every Talos/Cilium
  knob".
- [ADR-0022](../decisions/0022-cilium-observability-and-argocd-self-management.md)
  §(c) declines an unbounded override merge into the emitted `valuesObject`,
  because a seed escape hatch would then flow into a continuously reconciled
  resource with no plan-time visibility into its contents. The replacement it
  names is the bounded merge in §(f) plus the hard-reject guard — not a
  substitute route for the override's own contents.
- The same ADR's 2026-08-15 addendum records the typed-input answer for one
  narrower case, the operator replica count: `cilium_values_override` "cannot
  be that escape hatch, because it reaches only the seed", and "a typed input
  closes it on both paths at once". That reasoning was applied to a single
  value, not to the long tail.
- The same ADR §(l) records closing `substrate.cilium` to a typed key set.

## Open findings

1. `tofu/modules/talos-cluster/helm/argocd-values.yaml:12` says a consumer "can
   replace this wholesale via var.argocd_values_override". It is a merge —
   `main.tf:66-70`, `variables.tf:501-503` and
   `tofu/modules/talos-cluster/README.md:571` all say so. The identical claim
   stood in that README's §Inputs row and was corrected when this page was
   written; the values-file comment is a spec `primary` source and was left for
   its own change.
2. The same file at `:32` carries the mirrored sentence about "these Helm
   values, which a consumer of the published component never has". That file
   **is** in the payload (`.ci-oci-tarball-include.txt:10`), so the sentence is
   false where it sits — it is true of the steady-state values file it mirrors,
   and the mirror crossed a delivery boundary that changes its truth value.
3. `AGENTS.md` §Repository Purpose describes live reconciliation as a
   Multi-Source Application over base and cluster repo. For the ArgoCD
   component that form is ruled out — see §1.
4. `schemas/cluster.schema.json:305-307` leaves `substrate.argocd` an open
   `{"type": "object"}` with no `properties`, no `additionalProperties: false`
   and no `description`, while `substrate.cilium` and `substrate.cert_approver`
   are closed. `scripts/check-shim-key-parity.sh:19-24` skips it for that
   reason, so the four keys the shipped shim reads
   (`tofu/modules/talos-cluster/examples/complete/main.tf:103-106`) are bound in
   neither direction: a typo under `substrate.argocd` passes lint and vanishes.
5. Neither `values_override`'s content is validated against the chart, and how
   much slips through differs by chart. Malformed YAML fails the render, and the
   data source has a postcondition against an empty one. Beyond that, a key the
   chart does not **declare** — a typo, a wrong nesting level, or a key a later
   chart version removed — is dropped silently, because Helm merges without
   `--strict`. **Type** validity is only checked where the chart ships a
   `values.schema.json`: `cilium` does, `argo-cd` 10.6.0 does not, and
   `server.replicas: definitely-not-an-integer` was measured to template
   cleanly into the argocd-server Deployment (exit 0, helm 3.20.2) — deferring
   the failure to bootstrap. Stated in
   `openspec/specs/cilium-cni-delivery/spec.md` §"Requirement: Cluster-agnostic
   floor values with layered configuration",
   `scripts/check-cilium-reference-values.py` (its header, the #211 defect
   class) and `UPGRADING.md` §"Removed Helm values — audit your `cilium_values_override`",
   whose audit note records that a clean plan is not evidence the override
   survived a chart bump. That the module cannot introspect
   the opaque string, and why its prerequisite checks therefore warn instead of
   reject, is at `tofu/modules/talos-cluster/cilium-values.tf:302-323`. The
   reference file has a schema gate; the two overrides have none.
6. The `substrate.argocd` asymmetry in finding 4 is documented as deliberate in
   `openspec/specs/cluster-yaml-sot/spec.md` §"Requirement: Untyped escape
   hatches and structural secret exclusion",
   `scripts/check-shim-key-parity.sh:19-24` and
   [cluster.yaml — Declarative Cluster SoT](cluster-yaml.md) §"How CI binds the
   schema to the shim". The schema itself is silent, not documenting. No
   decision record says why ArgoCD is the exempt one; ADR-0022 §(l) covers only
   the closing of `substrate.cilium`.

## Tracker state

Issue states below were read on 2026-09-06 and are a snapshot, not a durable
claim — confirm with `gh issue view` before relying on one. Nothing gates a
tracker assertion in a committed file.

| Gap | Tracked as |
|---|---|
| Umbrella: which values may a consumer set (guarded vs. tunable) | issue 86 — open, `status: triage`; its deliverables are absent from the tree and its target render path is retired |
| 1 — published ArgoCD component exposes no value surface | issue 261 — open, `status: triage` |
| 2 — Cilium long tail has no base-delivered Day-2 path | issues 227 and 188 track single values, not the surface |
| 3 — collision set never enumerated | issue 262 — open, `status: triage` |
| Finding 5 (silent drop of undeclared keys) | issue 211, closed, for the reference-values case only |

## Not decided here

This page fixes nothing and chooses no remedy. The two candidate shapes — open
a real value surface on the steady-state paths, or widen the module's escape
hatches — are the open question, and issue 86 is where it belongs.
