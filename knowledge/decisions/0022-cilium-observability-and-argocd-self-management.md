---
type: decision
title: "ADR: Cilium observability inputs + opt-in ArgoCD self-management delivery mode"
description: "Adds first-class default-off Cilium observability inputs (agent/operator Prometheus metrics, Hubble metrics-only) and an opt-in emitted-Application self-management delivery mode; closes the substrate.cilium schema and bumps the module's OpenTofu floor to >= 1.9."
status: accepted
id: base:cilium-observability-and-argocd-self-management
timestamp: 2026-07-22
deciders:
  - platform-maintainer
related:
  - base:cluster-yaml-sot
  - base:opentofu-cluster-lifecycle
  - base:namespace-ownership-rendered-manifests
  - base:substrate-only-base
tags: [adr, cilium, observability, argocd]
---

# ADR: Cilium observability inputs + opt-in ArgoCD self-management delivery mode

## Context and Problem Statement

The `tofu/modules/talos-cluster` module delivers Cilium as a frozen,
create-only controlplane `inlineManifest` seed
(`data.helm_template.cilium` → `terraform_data.cilium_render`,
`ignore_changes=[input]` — main.tf). That seed has no first-class way to turn
on Cilium's own observability surface (agent/operator Prometheus metrics,
Hubble flow/metrics) short of the free-form `cilium_values_override` long
tail, and no Day-2 path for a consumer's ArgoCD to take over steady-state
Cilium management once bootstrapped — matching the model ArgoCD delivery
already has (module seeds it once; the consumer's own ArgoCD self-manages it
Day-2, per the module README's "ArgoCD delivery + health gate" section).
Issue #188 asks for both: first-class observability inputs, and an opt-in
delivery mode that lets a consumer's ArgoCD adopt Cilium the same way.

## Decision Drivers

- Observability inputs should be first-class, typed, and default-off — not
  buried in the untyped `cilium_values_override` long tail.
- A single Cilium ArgoCD self-management story for the platform's three
  co-equal pillars (Talos + Cilium + ArgoCD) — Cilium should be able to follow
  the same seed-once/self-manage-after pattern ArgoCD itself uses.
- AGENTS.md §Hard Constraints forbids the module directly applying
  ArgoCD-managed resources ("NEVER `kubectl apply` ArgoCD-managed resources —
  commit to git, push, let ArgoCD sync"). Any self-management delivery mode
  must be emit-only.
- No divergent observability data-flow: the frozen seed and the emitted
  self-management `Application` must derive their Cilium values from the same
  computation, not two independently-evolving layers.
- Capability claims about Hubble's TLS/metrics coupling must be grounded
  before being encoded in a default (`rules/verification-discipline.md
  §Capability-claim grounding`), not assumed.

## Considered Options

1. **Free-form values only** — extend `cilium_values_override` documentation
   to cover observability and self-management, add no typed inputs.
2. **First-class typed observability inputs + a module-side `kubectl apply`
   of the self-management `Application`** — the module both renders and
   applies the steady-state resource.
3. **First-class typed observability inputs + an emitted-Application output
   (module renders, never applies) with an unbounded consumer-override merge**
   feeding the emitted `valuesObject` (the override folded in wholesale).
4. **First-class typed observability inputs + an emitted-Application output
   with a bounded, module-controlled merge** (floor ⊕ computed-including-
   observability only — no `cilium_values_override` term), gated by a
   hard-reject `validation` guard when an override is set. (Chosen.)

## Decision Outcome

Chosen option: **4 — first-class default-off observability inputs, plus an
opt-in emitted (never applied) self-management `Application` fed by a
bounded, module-controlled merge**, because it keeps the module's single
observability data-flow intact, respects the Hard Constraint against
module-side `kubectl apply` of ArgoCD-managed resources (ruling out Option
2), and avoids silently laundering an unbounded free-form override into a
Day-2-reconciled resource (ruling out Option 3 — see §Declined alternatives).

### Consequences

- Positive: a single computed-values map (`local.cilium_computed_values` in
  `cilium-values.tf`) feeds both the frozen bootstrap seed and the emitted
  self-management `Application` — no divergent observability layers.
- Positive: the emitted `Application` is a module OUTPUT only; the module
  never applies an ArgoCD-managed resource, satisfying the Hard Constraint by
  construction.
- Negative: two consumer-visible compatibility breaks — the OpenTofu floor
  bump (`>= 1.9`, required for cross-variable `validation` blocks) and the
  now-CLOSED `substrate.cilium` schema (`additionalProperties: false`). Both
  documented in CHANGELOG + README + UPGRADING.
- Negative: a bootstrap-window datapath gap on BGP/L2 clusters that migrate
  their override into self-management (see §Bootstrap-window datapath gap).
- Follow-up: any future computed-or-floor key added under a parent already
  shared between the floor and the computed layer must add its own explicit
  sub-merge (see §Bounded merge + two-engine-drift below) — recorded as a
  standing invariant, not code today (no second collision exists yet).

## Design detail

### (a) First-class observability inputs (default off)

`cilium_agent_metrics`, `cilium_operator_metrics`, `cilium_hubble_enabled`,
`cilium_hubble_metrics` — all default off/empty. Layered into
`local.cilium_computed_values` (`cilium-values.tf`) alongside the existing
routing/encryption/gateway-API computed keys, so they flow through the exact
same `compact([floor, computed_yaml, override])` Helm-deep-merge the frozen
seed has always used.

### (b) Opt-in emitted self-management delivery mode, emit-not-apply

`cilium_self_management` (default off) emits `cilium_self_management_app` — a
rendered ArgoCD `Application` manifest string, `""` when off. The module
renders it locally (`yamlencode`) and does nothing else with it: no
`kubectl`, no live-apply resource type, no CRD-ordering dependency. This is
the direct consequence of AGENTS.md §Hard Constraints ("NEVER `kubectl apply`
ArgoCD-managed resources — commit to git, push, let ArgoCD sync; only
exception: one-time bootstrap AppProjects") — the module's deliverable is the
manifest; the consumer's own GitOps is the single writer. Consumer pattern: a
one-line `local_file` resource in the consumer's own root against the output,
committed to their GitOps repo.

### (c) Declined alternatives

- **Module-side `kubectl apply` of the self-management `Application`**
  (Option 2) — directly violates the Hard Constraint above; declined outright.
- **Reconcile-safe re-seed trigger** — considered and declined: re-triggering
  the frozen seed's render on every apply would defeat the deliberate
  create-only/`ignore_changes=[input]` design that makes the bootstrap seed
  byte-identical and idempotent; the self-management `Application` output is
  the correct place for anything that needs to track live drift, not the
  seed.
- **Unbounded consumer-override merge into the emitted `valuesObject`**
  (Option 3, the original design) — declined because it would let
  `cilium_values_override` (an arbitrary Helm-values escape hatch intended for
  the seed) flow silently into a resource ArgoCD reconciles continuously,
  with no plan-time visibility into what that override actually contains.
  Replaced by the bounded merge in (f) plus the hard-reject guard.

### (d) Single observability data-flow + coupling

Both consumers of Cilium values — the frozen seed
(`cilium_computed_values_yaml`, consumed by `data.helm_template.cilium`) and
the emitted `Application` (`cilium_effective_values`) — read from the SAME
`local.cilium_computed_values` map. `cilium_self_management` itself is
coupled to delivery state: it requires `deploy_argocd=true` AND
`deploy_cilium=true` (there is nothing to hand off to ArgoCD otherwise, and no
Cilium seed to be handing off from).

### (e) OpenTofu >= 1.9 floor bump

Cross-variable `validation` blocks (the deploy-prereq guard and the
override-drop guard in (f)) are an OpenTofu >= 1.9 feature. This is a **real,
consumer-visible compatibility break**: every consumer of this module —
not only those opting into `cilium_self_management` — now needs OpenTofu
>= 1.9 to `plan`/`apply` at all. The blast radius is permanent (the floor
does not lower again) for the sake of one opt-in feature; accepted because
the input-validation safety the guards provide (§f, §Bootstrap-window
datapath gap) is judged to outweigh the floor-bump cost, and because OpenTofu
1.9 has been generally available long enough that the floor is not
practically restrictive. Documented in CHANGELOG + README + UPGRADING.

### (f) Bounded merge, override-drop hazard, and the hard-reject guard

`cilium_effective_values` (`cilium-values.tf`) is a deliberately **bounded**,
module-controlled merge — floor ⊕ computed-values-including-observability
ONLY, with no `cilium_values_override` term. It is NOT an arbitrary-depth
recursive merge: today's floor∩computed key set has exactly one lossy
collision under a plain top-level `merge()` — the `operator` parent (the
floor sets `operator.replicas`; the computed observability layer adds
`operator.prometheus` when `cilium_operator_metrics` is on). A plain
`merge(floor, computed)` would let the computed `operator` map replace the
floor `operator` map wholesale, dropping `operator.replicas`. The merge
therefore does a top-level `merge()` PLUS one explicit re-merge of the
`operator` sub-map. `hubble` also collides (the floor sets
`hubble.enabled=false`) but its sole floor key is intentionally superseded,
so the plain top-level merge already handles it correctly with no sub-merge
needed. `cgroup` and `securityContext.capabilities.ciliumAgent` are untouched
by the computed layer and pass through the top-level merge verbatim.

**Two-engine-drift invariant** (recorded, not code today — no second
collision exists to bind): this shallow `merge()` + explicit `operator`
sub-merge reproduces Helm's recursive deep-merge only because today's
floor∩computed key set has exactly this one lossy collision. Any future
computed-or-floor key added under a shared parent MUST add (i) an explicit
sub-merge for that parent in `cilium-values.tf` AND (ii) a floor-preservation
collision assert in `tests/input-validation.tftest.hcl` mirroring the
`operator.replicas` pair — otherwise a future change silently drops the
colliding sibling with no test catching it.

**Override-drop hazard.** The emitted `valuesObject` does NOT inherit
`cilium_values_override` by design (see §Declined alternatives, Option 3). A
consumer with a seed-active override (BGP control-plane, L2 announcements,
bpf tuning) who enables `cilium_self_management` would have that
datapath-critical config silently **DROPPED** the moment ArgoCD adopts
Cilium — the emitted `Application` simply never carries it. To prevent this
happening silently, the module **hard-rejects** `cilium_self_management=true`
while `cilium_values_override` is non-empty via a `variable` `validation`
block in `variables.tf` (kept as a SEPARATE block from the deploy-prereq
guard — see §Guard isolation below): the consumer must migrate the override
into their own Cilium `Application` first, then empty
`cilium_values_override` in the SoT.

**Guard isolation.** The deploy-prereq guard (`deploy_argocd` +
`deploy_cilium`) and the override-drop guard live in two SEPARATE
`validation` blocks in `variables.tf`, each with a code comment warning
against merging them: `expect_failures` in `tofu test` matches the variable
(the checkable object), not a specific validation block, so leg isolation in
`tests/input-validation.tftest.hcl` (deploy-prereq legs vs. the override-drop
leg) holds only because each leg's inputs are crafted to fire exactly one
block. Merging the two blocks into one condition would silently collapse all
three legs onto a single untested predicate.

### (g) Hubble TLS-off is metrics-only, not a metrics-disabling change

`cilium_hubble_enabled=true` forces `hubble.tls.enabled=false` — this is a
deliberate metrics-only scope (no Relay/UI in this issue's scope), not an
accidental weakening of Hubble's observability output. Grounded via T1
official Cilium docs (docs.cilium.io/en/stable/observability/hubble/configuration/tls/
and docs.cilium.io/en/stable/observability/metrics/): the Hubble **metrics**
Prometheus scrape endpoint (the `hubble-metrics` headless Service, port
`9965`, `prometheus.io/scrape: "true"`) is gated exclusively by
`hubble.enabled=true` plus a non-empty `hubble.metrics.enabled` — it is
architecturally independent of `hubble.tls.enabled`, which governs only the
separate Hubble observer gRPC API consumed by Relay/UI. Since Cilium 1.16 the
metrics API carries its own TLS knob (`hubble.metrics.tls.enabled`, distinct
from the observer-API `hubble.tls.enabled`), so setting the observer API's
TLS off does not disable or break metrics export; the scrape endpoint stays a
plaintext HTTP surface unless a consumer explicitly opts into
`hubble.metrics.tls.enabled=true` via `cilium_values_override`. This
independence is additionally confirmed by rendering the actual pinned chart
(1.19.4): the `hubble-metrics` Service / `:9965` endpoint appears in the
render regardless of `hubble.tls.enabled`, and is asserted in
`tests/composition.tftest.hcl`.

Should observer-API TLS ever need enabling in a future change, the
recommended method is `hubble.tls.auto.method: cronJob`, not `method: helm` —
grounded via T1 official docs
(docs.cilium.io/en/stable/observability/hubble/configuration/tls/): the
`helm` method invokes Sprig `genCA`/`genSignedCert` inline during Helm
templating, embedding fresh CA/cert material in the rendered YAML on every
render — which would break the frozen bootstrap seed's render-determinism
guarantee (`scripts/check-render-determinism.sh`). The `cronJob` method
instead schedules a one-shot `Job` + a recurring `CronJob` (running
`cilium/certgen`) that generate/store certs as Kubernetes Secrets at
apply/runtime, not at template time — a stable, deterministic `helm template`
output, matching `certmanager` method's stability. `tls.enabled=false` (the
choice made here) is strictly stronger than either non-regenerating method:
zero cert material generated at render OR runtime, satisfying the
render-determinism half of AC #2 outright.

### (h) `spec.project` posture + supply-chain note

`cilium_self_management_project` defaults to `"default"` (the always-present
permissive AppProject) so the feature works out of the box. Scoping to a
dedicated project is **strongly recommended hardening**: the project must
grant destination namespace `kube-system` at
`https://kubernetes.default.svc`, plus Cilium's cluster-scoped resources (its
CRDs, ClusterRoles, ClusterRoleBindings) in `clusterResourceWhitelist` — a
scoped project without that whitelist leaves the adopted `Application`
inert/degraded. Separately: the emitted `targetRevision` is
`var.cilium_chart_version`, a mutable tag with no digest/cosign pin; unlike
the frozen, render-once seed, the self-managed `Application` re-pulls the
chart on every ArgoCD reconcile — a broader, repeated-fetch supply-chain
surface than the seed. `cilium_chart_repository` should point only at a
trusted source.

### (i) ArgoCD-adoption runtime caveat

The first ArgoCD sync that adopts the seed-created Cilium resources into the
emitted `Application` may trigger managed-fields reconciliation and an agent
restart — inherent to seed-to-GitOps takeover, not a code defect, and not
avoidable in this module. Documented as a known runtime caveat in the README
and UPGRADING.

### (j) ADR-0002 cross-reference

A dedicated per-component Cilium `Application` (consumer-GitOps-owned) that
manages workloads inside the pre-existing built-in `kube-system` namespace
and carries no `Namespace` resource — [ADR-0002](./0002-namespace-ownership-rendered-manifests.md)'s
single-owner invariant is not engaged.

### (k) Chart-version-skew, empty-metrics, re-bootstrapped-node interactions

- **Chart-version-skew**: `cilium_chart_version` is a seed-only knob for the
  bootstrap render; once self-management is adopted, bumping it re-renders
  the emitted `Application`'s `targetRevision` and ArgoCD performs the
  upgrade — the module itself never upgrades a running Cilium.
- **Empty `hubble_metrics`**: `cilium_hubble_enabled=true` with an empty
  `cilium_hubble_metrics` is a valid, accepted half-on state — the Hubble
  server runs but exports no metrics.
- **Re-bootstrapped-node interaction**: a node that re-runs the frozen seed
  (fresh bootstrap or `-replace`) re-applies whatever `cilium_values_override`
  is set in the SoT at that time — including a stale override a consumer
  believed was already migrated to self-management. See the following section
  for the mirror-image case.

### Bootstrap-window datapath gap (accepted trade-off, no code fix)

The override-drop guard (§f) and the seed's create-only design interact in
two ways that are in tension and must both be understood, not just the one
convenient to state:

- (a) While `cilium_values_override` stays set in the SoT, the guard blocks
  `cilium_self_management` outright — a consumer cannot self-manage with a
  seed-active override still declared.
- (b) Once a consumer empties `cilium_values_override` to enable
  self-management, a **future** fresh bootstrap or a `-replace` re-seed of
  the frozen render brings that node up with plain-floor Cilium only (no
  BGP/L2/bpf) until ArgoCD's first sync adopts and re-applies the override
  via the self-managed `Application` — a bootstrap-window datapath gap on
  BGP/L2-dependent clusters.

This is the mirror image of the re-bootstrapped-node interaction in (k): one
state has the gap on the seed side (b), the other has it on the
already-migrated-but-seed-still-stale side (k's bullet). There is no code fix
for either; a consumer on a BGP/L2-dependent cluster should plan around the
window (e.g. hold node reboots/replacements until ArgoCD's adoption sync is
confirmed).

### (l) Schema/contract parity — closing `substrate.cilium`

Closing the `substrate.cilium` object in `schemas/cluster.schema.json`
(`additionalProperties: false` + the full 17-property enumeration) is itself
a new schema decision and is bound by `rules/schema-contract-parity.md`'s
five parity dimensions:

1. **Closed-vs-open field set**: CLOSED. A typo'd or unknown key under
   `substrate.cilium` now fails `check-jsonschema` at lint time instead of
   being silently dropped by the `try()`-based shim in
   `examples/complete/main.tf`. This is itself the SECOND consumer-visible
   compatibility break introduced by this change (alongside the OpenTofu
   floor bump in §e) — a consumer with an existing extra/misspelled key under
   `substrate.cilium` must fix it on upgrade.
2. **Duplicate-key behavior**: standard YAML parsing applies; a duplicate
   top-level key under `substrate.cilium` in a consumer's `cluster.yaml` is
   file corruption, not a supported merge — consistent with every other
   block in this schema.
3. **Version-skew behavior**: `cluster.schema.json` carries no schema-level
   `version` field; the migration path for a closed-field addition is the
   CHANGELOG/UPGRADING entry accompanying this ADR, exactly as prior schema
   changes in this repo have done.
4. **In-file untrusted-data marker policy**: not applicable — `cluster.yaml`
   is a trusted, consumer-authored config file, not LLM-agent-read untrusted
   data.
5. **Per-field mutability**: every field under `substrate.cilium` is
   mutable-in-place (a consumer edits and re-applies); none are append-only.
   The two new self-management inputs are not secrets and carry no
   confidentiality requirement.

## Validation

- `tofu validate` + `tofu fmt -check` over the module and
  `examples/complete/` (module-internal consistency).
- `tofu test -filter=tests/input-validation.tftest.hcl` (offline, provider-less
  fixture): default-off byte-identical render, the AC#1 positive-oracle
  legs, the floor-preservation `operator.replicas`-equality assert, the
  guard's three legs (deploy-prereq A/B, override-drop C) each isolated to
  fire exactly one `validation` block, and the required negative-space
  positive control (override set + self-management off must plan-succeed).
- `tofu test -filter=tests/composition.tftest.hcl` (network): the frozen
  seed-render observability markers, plus the render-level `hubble-metrics`
  Service / `:9965` check confirming Hubble TLS-off does not disable metrics
  at the pinned chart version.
- `uvx --from check-jsonschema check-jsonschema --schemafile
  schemas/cluster.schema.json` against `cluster.yaml.example` and
  `examples/complete/cluster.yaml` — confirms the closed schema still accepts
  every documented key and the invalid fixture still fails.
- `scripts/check-module-readme-parity.sh` — every new variable/output has a
  README row.
- Revisit if a future Cilium chart major version changes the
  `operator.prometheus.enabled` default away from `true`, which would let
  `cilium_seed_observability_markers.operator_metrics` become a genuinely
  discriminating marker — the audit-only caveat on that output should be
  re-checked against the pinned chart version at any future
  `cilium_chart_version` bump.

## Addendum 2026-08-12 — re-verified at the Cilium 1.20.0 bump

The §Validation claims above were established against chart 1.19.4. The
`cilium_chart_version` bump to 1.20.0 re-ran them against the new chart. All
hold unchanged; nothing in this ADR is superseded.

- **§(g) `hubble-metrics` / `:9965`** — still rendered by chart 1.20.0
  independently of `hubble.tls.enabled`. The `tests/composition.tftest.hcl`
  assertion continues to bind it at the new pin.
- **The §Validation revisit trigger did NOT fire** — `operator.prometheus.enabled`
  still defaults to `true` in 1.20.0, so
  `cilium_seed_observability_markers.operator_metrics` remains audit-only and its
  caveat in `outputs.tf` stands as written.
- **All four marker keys survive** — `prometheus-serve-addr`,
  `operator-prometheus-serve-addr`, `enable-hubble`, and
  `hubble-metrics-server` are all still emitted by the 1.20.0
  `cilium-configmap.yaml` template, so the `try(..., {})`-wrapped output did not
  silently degrade.
- **Seed determinism holds** — two successive renders of the floor ⊕ computed
  layers at 1.20.0 are byte-identical, so the `hubble.enabled: false` floor still
  suppresses the chart's default template-time `genCA` path.
- **Seed size grew ~4.9 %** (57 458 → 60 268 bytes for the default seed). Still
  within the budget noted at `main.tf:368-369`, but the trend is worth watching:
  nothing gates the Talos machine-config size limit, and an overflow surfaces at
  Talos apply time rather than plan time. Two caveats on that figure: it is the
  **Cilium term only**, whereas Talos sees the SUM of the Cilium, ArgoCD and
  cert-approver inlineManifests; and the `~66 KB` budget in the `main.tf`
  comment is prose with no cited Talos-side ceiling and no mechanical check.
  **Closed after this bump (issue #213).** The sourced ceiling is Talos'
  `GRPCMaxMessageSize = 32 * 1024 * 1024` (`pkg/machinery/constants/constants.go`
  at tag `v1.11.0`), wired into machined's gRPC server via
  `grpc.MaxRecvMsgSize` and into the client in `pkg/machinery/client/connection.go`;
  `ApplyConfiguration` carries the document in one such message. The unsourced
  `~66 KB` figure is three orders of magnitude off and was removed rather than
  kept. The bound is a **precondition over the summed patch locals** on
  `data.talos_machine_configuration.controlplane`, not a postcondition over its
  `machine_configuration`: that attribute depends on `talos_machine_secrets`, so on
  a first plan it is unknown and a postcondition over it defers to apply — the very
  failure the gate exists to move earlier. Measured, not assumed: the postcondition
  form did not fire even with the ceiling lowered to 1000 bytes, while the
  precondition form fails at plan with the summed byte count.

  Two residuals stay open, stated rather than hidden. First, 32 MiB is the bound
  that could be SOURCED, not proof that nothing tighter binds first — whether the
  STATE partition, etcd, or maintenance mode imposes a smaller practical limit is
  not established. Second, the gate has no permanent test: binding it would need a
  synthetic ~32 MiB seed, so the red-green is a re-runnable procedure (lower
  `local.controlplane_payload_ceiling_bytes`, run `task tofu:test`) rather than a
  committed assertion. An output exposing the summed bytes for trend-watching was
  considered and left out to keep the module's output surface stable; the gate's
  failure message carries the numbers instead.

### New default-on 1.20 surface in the seed (measured, not inferred)

The seed bypasses the kustomize/conftest render gate, and
`cilium_seed_observability_markers` decodes only four booleans — so a chart bump
can move a default into the create-only controlplane machine config with nothing
asserting it. The `cilium-config` keys chart 1.20.0 adds over 1.19.4, with their
rendered values in the DEFAULT seed (floor ⊕ computed, no override):

| New `cilium-config` key | Rendered value | Note |
|---|---|---|
| `gateway-api-use-remote-address` | `"true"` | Backing Helm value `gatewayAPI.useRemoteAddress` is NEW in 1.20 and defaults true, but the default is behavior-PRESERVING, not a new default-on behavior: Cilium 1.19 hardcoded the same Envoy field (`operator/pkg/model/translation/envoy_http_connection_manager.go` at `v1.19.4`, `UseRemoteAddress: true` with `SkipXffAppend: false`), and 1.20 keeps that literal while adding the `withUseRemoteAddress` mutator (`envoy_listener.go`) so config can override it. New knob, unchanged posture; see `UPGRADING.md` §2. |
| `bpf-lb-sock-hostns-only` | `"true"` | NOT a marker of the 1.20 NodePort change: the 1.20 template forces this key `"true"` whenever `gatewayAPI.enabled` (for Maglev per-backend weights), and the key exists in the 1.19.4 template too. It does mean the base satisfies the second trigger condition of the upstream NodePort note (`UPGRADING.md` §4), whose basis is the release notes, not this key. |
| `envoy-node-locality-enabled` | `"false"` | Off. Backing `envoy.nodeLocality.enabled`; the key has no 1.19.4 counterpart. |
| `envoy-access-log-enabled` | `"true"` | Newly EMITTED key; the backing `envoy.accessLog` value is unset (null) in BOTH 1.19.4 and 1.20.0, so this records the emitted default — it is NOT established that the underlying behavior changed. |
| `envoy-xds-mode` | `"ads"` | Same caveat: `envoy.xdsMode` is null in both charts. |
| `enable-host-firewall` | `"false"` | Off. |
| `enable-datapath-plugins` | `"false"` | Off — the new plugin-loading surface is not opened. |
| `devices`, `datapath-plugins-state-dir`, `clustermesh-default-global-namespace`, `enable-dynamic-source-lookup-nodeport`, `proxy-cluster-max-pending-requests` | — | No security-relevant default change observed. |

Added keys are not the whole delta. Diffing the FULL rendered `cilium-config` map
in both directions (158 keys at 1.19.4, 170 at 1.20.0 — 12 added, 0 removed)
turns up exactly one **changed value on a key that exists in both**:

| Changed `cilium-config` key | 1.19.4 | 1.20.0 | Note |
|---|---|---|---|
| `bpf-lb-algorithm-annotation` | `"false"` | `"true"` | 1.20's ConfigMap template forces it `"true"` whenever `gatewayAPI.enabled`, which is the base default. Turns a previously inert `service.cilium.io/lb-algorithm` Service annotation live. Consumer-facing; documented in `UPGRADING.md` §2. |

Method note for the next bump: diff the full rendered map in both directions,
added / removed / changed. Scanning only for keys the new chart ADDS misses a
changed default on an existing key, which is exactly what
`bpf-lb-algorithm-annotation` is — and it is the only such key here.

Object inventory is unchanged between the two charts (same kinds, same counts;
the two DaemonSets are `cilium` and `cilium-envoy` in both), so 1.20 adds no new
default-on workload to the seed.

Not fixed here and tracked separately: there is no `cilium_seed_missing_labels`
output mirroring `cert_approver_seed_missing_labels`, and no assert pinning any
of the keys above — so the next bump can flip one silently. The agent capability
lists in `helm/cilium-values.yaml` are likewise hard forks of the chart defaults
with no test binding them; measured at this bump, the divergence is IDENTICAL in
1.19.4 and 1.20.0 (the floor withholds `SYS_MODULE` and `SYSLOG` and adds
`NET_BIND_SERVICE`), so the bump introduces no new drift — but the
`NET_BIND_SERVICE` grant's stated justification ("Gateway API / envoy listeners
on privileged ports") is questionable in both versions, since `cilium-envoy`
renders as a standalone DaemonSet rather than running in the agent.

### §k gains a second dimension: chart-version seed skew

§k and §"Bootstrap-window datapath gap" record stale-seed skew for the
`cilium_values_override` dimension. The chart version is a second dimension of
the same gap, and a minor bump is the first time it is material.

`ignore_changes = [input]` freezes the render for the life of the state, and
`local.cilium_controlplane_patch` feeds that one frozen value into EVERY
controlplane machine config — including one generated for a controlplane added
or replaced later. So a cluster bootstrapped at 1.19.4 and since moved to
1.20.0 via the emitted self-management Application will re-seed 1.19.4 Cilium
objects on a controlplane join, against a running 1.20.0 datapath. Cilium
supports skew only between consecutive minors, so the gap is tolerable at one
minor and is not a general licence.

Same shape of mitigation as §"Bootstrap-window datapath gap", and no code fix:
re-freeze deliberately (`tofu apply -replace=terraform_data.cilium_render[0]`)
so the seed and the running version agree BEFORE touching controlplane
membership, or hold membership changes until that is done. Note the freeze is
symmetric — it blocks re-capture on the way back too, so a rollback that was
adopted via `-replace` needs a second `-replace` to revert the seed.
Operator-facing form: `UPGRADING.md` §1 and its Back-out paragraph.

## Links

- Issue #188.
- [ADR-0007: Module-delivered Cilium + `cluster.yaml` as the declarative
  cluster SoT](./0007-cluster-yaml-sot.md) — the bootstrap-seed pattern this
  ADR extends.
- [ADR-0002: Namespace Ownership in the Rendered Manifests
  Pattern](./0002-namespace-ownership-rendered-manifests.md) — the
  single-owner invariant confirmed not engaged (§j).

## Addendum 2026-08-14 — two further typed metric-set inputs

`cilium_agent_metric_overrides` (`prometheus.metrics`) and
`cilium_hubble_open_metrics` (`hubble.metrics.enableOpenMetrics`) join the
observability group. Nothing in this ADR is superseded: both reach BOTH engines
through `local.cilium_computed_values`, so §(d)'s single-data-flow property
holds, and §(f)'s bounded floor ⊕ computed merge is untouched — `prometheus` is
absent from the floor and `hubble` remains intentionally superseded, so the
floor∩computed collision count is still exactly one (`operator`).

**§(f) gains a second collision LEVEL, not a second collision.** The invariant
was written for floor-versus-computed collisions. The same lossy-replace
mechanic exists one layer earlier, INSIDE `local.cilium_computed_values`: it is
a shallow `merge()` over conditional maps, so two terms writing the same
top-level key do not combine — the later replaces the earlier wholesale, and
there is no floor to preserve because the loss is computed-versus-computed. Both
new inputs land on parents an existing term already writes (`prometheus`,
`hubble.metrics`), so each is folded into a single hoisted sub-map
(`local.cilium_prometheus_values`, `local.cilium_hubble_metrics_values`) rather
than added as a sibling term. The clause-(i)/(ii) obligation now reads: an
explicit sub-merge at the level where the collision occurs, plus a preservation
assert. Level B is the cheaper mistake — a sibling term reads as an independent
feature toggle right up until it eats its neighbour, and for `hubble` it would
take `tls.enabled = false` with it, re-arming the template-time `genCA` path
§(g) exists to keep out of the seed.

**Guard tier: `check`, not `validation`.** An input that is merely inert gets a
plan-time warning. A hard reject would refuse a working configuration, because
the prerequisite can be satisfied through `cilium_values_override` — an opaque
string the module cannot introspect, by the same argument §(f) uses to justify
hard-rejecting the override under self-management. The two tiers are consistent:
this module hard-rejects silent BREAKAGE and warns about no-ops. `tofu test`
promotes a failing check to a run failure and a check block is a checkable
object, so `expect_failures = [check.<name>]` binds each block directly; the
one-block-per-predicate rule from §Guard isolation carries over unchanged.

**Format validation is not optional here.** Measured against the pinned chart:
`prometheus.metrics` entries render RAW and UNQUOTED into `cilium-config` as a
multi-line plain scalar, so an entry carrying a newline with matching
indentation escapes it and writes standalone ConfigMap keys into the create-only
machine config. An entry containing `---` additionally splits the rendered
document and silently blanks `cilium_seed_observability_markers`, which parses
on that literal. The accepted class is deliberately conservative
(`^[+-][a-zA-Z_][a-zA-Z0-9_]*$`).

**`enableOpenMetrics` does not roll the agents** — measured, and the reason it
needs an operator-facing note rather than a footnote. The `cilium` DaemonSet pod
template is byte-identical with the flag on and off and the chart emits no
config-checksum annotation, so ArgoCD reports Synced/Healthy while running
agents keep the previous exposition format until some unrelated restart. A
composition-suite assert pins the no-checksum fact, so a future chart that adds
one turns the docs red rather than leaving them quietly wrong.

**Grafana dashboards were considered and declined.** The chart's three
`dashboards.enabled` toggles were in an earlier draft of this change. They emit
six Grafana-JSON ConfigMaps, growing the seed render from 60 268 to 587 208
bytes — well under the payload ceiling, so no gate would have caught it. They
were dropped on the routing rule in `AGENTS.md §Repository Purpose`: their only
consumer is a Grafana from the apps catalog, and the `namespace` / sidecar
`label` that decide whether anything reads them are values a cluster-agnostic
base cannot know. Typing them would also have forced the first deliberate
divergence between the two engines. They belong in the consumer's Grafana
Application.

**Residual.** The chart-key spelling of both Helm paths is bound only by
`tests/composition.tftest.hcl`, which is network-dependent and advisory in CI.
Helm ignores an unknown value key silently, so an offline suite cannot tell a
correct path from a typo — it only ever sees the module's own map.
