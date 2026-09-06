---
type: decision
title: "ADR: The consumer's Helm value surface is free-form and reaches every lifecycle phase"
description: "Decides the guarded-vs-tunable question in favour of a tunable value surface: the consumer's free-form values layer becomes the last layer on every ArgoCD and Cilium workload-values path, joint keys whose Talos half the module owns are rejected at plan time instead, and per-value typed inputs stop being the answer for the long tail."
status: stable
id: base:consumer-free-helm-value-surface
decided: "2026-09-06T00:00:00Z"
deciders:
  - platform-maintainer
consulted: []
informed: []
supersedes:
  - "/decisions/0022-cilium-observability-and-argocd-self-management.md §(c) third bullet (the declined unbounded consumer-override merge into the emitted valuesObject), §(f) Override-drop hazard (the hard-reject guard it justifies), and the typed-input substitution claim in §Addendum 2026-08-15"
superseded_by: []
related:
  - base:cilium-observability-and-argocd-self-management
  - base:cluster-yaml-sot
  - base:argocd-substrate-relocation
  - base:substrate-only-base
  - base:argocd-crd-apply-scope
tags: [adr, cilium, argocd, helm, consumer-interface]
---

# ADR: The consumer's Helm value surface is free-form and reaches every lifecycle phase

## Context and Problem Statement

Consumers report that they cannot set all the Helm values they need for the two
substrate charts, `argo-cd` and `cilium`.
[The ArgoCD/Cilium Helm value surface](../reference/helm-values-surface.md) maps
why, in five delivery paths and three points where the surface closes. That map
is the evidence for everything below and is not restated here.

The open question, unresolved since before the substrate-only ablation: is the
value surface **substrate-guarded** — the base enumerates what a consumer may
set — or **substrate-tunable**, the consumer sets what they need and owns the
consequence? This ADR decides it. The deciding input is a product
constraint, not a code observation: consumers have materially different
requirements, and a base that cannot meet a consumer requirement is not adopted.
A closed value surface is an adoption blocker, not a design virtue.

## Decision Drivers

- **Adoption.** Every requirement the base structurally cannot express is a
  reason to write one's own Talos + Cilium + ArgoCD wiring instead of pinning it.
- **Release-cadence coupling.** A per-value typed input closes exactly one key
  and costs a base release the consumer must wait for and re-pin. The long tail
  is not enumerable, so the cost recurs indefinitely — the typed-input requests
  still outstanding are one per consumer requirement. Free-form pass-through is
  paid once.
- **No new silent overwriting.** The complaint's third cause is a consumer value
  superseded without notice. A widened surface must not re-create that by having
  the module re-assert its own values over a consumer's.
- **Unbootable states are not freedom.** A value the substrate's own wiring
  contradicts yields a cluster that never converges, baked into a create-only
  seed. Rejecting that combination removes no capability, only an outcome.
- **ADR-0007 §4 already assigns the long tail to escape hatches.** What is
  missing is that the escape hatch does not reach every lifecycle phase — a
  reach problem, not a policy problem.

## Considered Options

1. **Status quo plus typed inputs on demand** — ADR-0022's answer, and the
   shape of the typed-input requests still outstanding.
2. **Bounded tunable subset** — enumerate a guarded key set, declare the rest
   tunable, enforce in the schema.
3. **Free-form pass-through on every workload-values path** — the consumer's
   layer is last wherever workload values are composed, Day-0 and Day-2, with a
   plan-time rejection limited to keys whose other half the module owns.
4. **Sync-time Helm templating for the ArgoCD component** — replace the
   committed render with an ArgoCD Helm source.

## Decision Outcome

Chosen option: **3**, because it is the only option whose per-value cost to the
base is zero, and the requirement is that a consumer with an unanticipated need
is not blocked waiting for a base release. Option 2 fails like option 1 once the
enumeration proves incomplete, and an enumeration over a third-party chart's
value surface is incomplete by construction. Option 4 is rejected in §(c).

Option 3 is chosen with the boundary §(d) draws, not without one — and that
boundary is not a list of what a consumer may set. It is the far smaller set of
keys whose counterpart the module writes into the Talos machine config, where a
disagreement is not a choice but a cluster that does not come up.

### Consequences

- Positive: a requirement the base never anticipated is satisfiable without a
  base change, on Day-0 and Day-2. The shipped typed inputs keep working.
- Negative: the silent-drop class widens in proportion — an override is not
  validated against its chart, Helm merges without `--strict`, and on the seed
  path a dropped key is baked into a create-only manifest. Accepted, not
  mitigated: the module cannot introspect an opaque string. Evidence in
  [the surface map](../reference/helm-values-surface.md) §Open findings.
- Negative: the ArgoCD values-level security floor becomes consumer-owned, with
  no base-side gate reaching it — §(e). The largest cost, and assigned rather
  than mitigated.
- Negative: the Cilium seed and the reconciled `Application` may hold different
  override content indefinitely, over a live behaviour the repository records as
  unverified — §(b).
- Negative: `openspec/specs/oci-supply-chain/spec.md` forbids what §(c) decides,
  in a SHALL-scoped requirement with a closing negative scenario.
- Follow-up: the two halves need separate implementing changes, each with its
  own OpenSpec delta; the release classification is settled there.

## Design detail

### (a) The principle

Wherever the base composes Helm values for a **workload** of `argo-cd` or
`cilium`, the consumer's free-form layer is present and applied **last**, subject
only to §(d). One path is deliberately outside it: the Day-0 ArgoCD CRD render
takes no values at all and is the one render the module applies itself. A values
layer there would re-open what ADR-0025 closed when it scoped that apply to
CustomResourceDefinitions; CRDs carry no consumer-tunable configuration.

### (b) Cilium Day-2 — the emitted Application inherits the override

`cilium_effective_values` (`tofu/modules/talos-cluster/cilium-values.tf`) is a
bounded floor ⊕ computed merge with no `cilium_values_override` term, and the
module hard-rejects `cilium_self_management = true` while the override is
non-empty (`tofu/modules/talos-cluster/variables.tf`). Both are superseded: the
emitted `Application`'s values must include the override.

**The merge belongs to Helm, not to the module.** The override is an opaque YAML
string of arbitrary depth and HCL has no generic recursive merge — ADR-0022 §(f)'s
two-engine-drift invariant is that problem at depth one, where the module owns
both layers and still enumerates the collision set by hand. So the override is
composed as a later Helm values layer, never deep-merged in HCL.

The shape that satisfies that: emit floor ⊕ computed as a values file the
consumer commits alongside the `Application`, reference it from
`spec.source.helm.valueFiles`, and carry the decoded override in
`spec.source.helm.valuesObject`. **One precondition is unverified** — that
ArgoCD applies `valuesObject` after `valueFiles`, so the override wins. The
Application CRD shipped in this repository establishes only that `valuesObject`
takes precedence over `values`, and says nothing about the ordering against
`valueFiles`; verify it against ArgoCD before building. If it does not hold, the
fallback is both layers as ordered `valueFiles` entries, which puts the ordering
in the list and needs no precedence assumption.

The two paths then compose differently, and that is accepted: on the seed path
floor, computed and override are three separate Helm layers; on the Application
path floor and computed are pre-flattened by the module's own shallow merge
before meeting the override. The difference is invisible at plan time, and
ADR-0022 §(f)'s standing obligation continues to bind every new key added under
a shared parent.

Two consequences are the decision's own:

- **The guard did two things and only one was the silent-drop hazard.** Its
  second effect forced `cilium_values_override = ""` before self-management,
  which kept the frozen seed and the reconciled `Application` from ever holding
  different override content. With it gone, divergence becomes the normal state
  — over a live re-capture behaviour
  [the surface map](../reference/helm-values-surface.md) records as unverified.
  ADR-0022's residual promoted that create-only assumption to load-bearing for
  one integer; this promotes it to an arbitrary-depth datapath document.
  Accepted as a known unverified risk, not as a safe property, and resolvable
  only by observation: replace a controlplane, or the render resource
  explicitly, on a self-managing cluster with a non-empty override, and record
  whether the seed rewrites objects the `Application` owns.
- **The same string gains a second sink.** ADR-0007 §5 scopes its mitigation to
  the machine config — operator discipline behind `gitleaks`, not a structural
  guarantee. The emitted `Application` is committed to git as an ordinary
  manifest, and Cilium values legitimately carry secret material (IPsec keys,
  Hubble and clustermesh TLS, BGP passwords) that neither the consumer-side SOPS
  gate nor `gitleaks` recognises. No structural guarantee is claimed.

### (c) ArgoCD steady state — ship the chart inputs, do not template at sync time

The published component carries a render, not a chart, so chart-level values
(controller replicas, `redis-ha`, resources, `extraObjects`) are unreachable. The
decision is to **ship the component's chart inputs** — `values.yaml`,
`chart.lock.yaml`, `_rendered-overlay/`, `scripts/render-component.sh` and
`.tool-versions`, where the render's determinism pins live — so the consumer
re-renders the full chart surface in their own repository.

**This retracts a normative spec assertion.**
`openspec/specs/oci-supply-chain/spec.md` §"Steady-state ArgoCD consumables ship
in the payload" holds those authoring inputs outside the payload and closes its
scenario with "no **other** `kubernetes/substrate/` path is". That sentence is
the spec's own scoping, borrowing the requirement's `Per ADR-0024` attribution:
ADR-0024 decided which files to add to the allowlist, never that no others could
join. ADR-0024 is therefore extended, not contradicted, and the negative
assertion plus its borrowed attribution are what an OpenSpec change proposal has
to retract — mandatory per `AGENTS.md` §Spec-Driven Development.

**Additive in behaviour, not in contract.** The committed `_rendered/` tree stays
the default, so a consumer who does not re-render sees byte-identical behaviour.
The payload boundary, the release-guard surface and the consumability gate change
regardless, and four preconditions of the repository as it stands block the work
until cleared — the render script's root resolution, `_rendered-overlay/`'s
gitignored reference, chart-pin parity against the un-forced Day-0 CRD apply, and
a digest check that verifies only when a digest is already pinned. All four are
implementation state, not part of this decision.

Option 4 is rejected rather than merely not chosen: it would abandon the Rendered
Manifests Pattern for the component that manages the GitOps engine itself, moving
templating to sync time where there is no plan-time diff, and resolve the chart
at sync time instead of from a pinned, digest-checked pull. A consumer wanting
that trade may build their own Helm-source Application; the base does not ship it.

### (d) What stays closed, and why it is not an enumeration

**1. Keys whose counterpart the module writes into the Talos machine config.**
`cilium_kube_proxy_replacement` is one typed input feeding two sinks: the chart's
`kubeProxyReplacement` plus `k8sServiceHost`/`k8sServicePort`, and Talos'
`cluster.proxy.disabled` in an all-nodes patch placed last so it wins over any
caller patch. The chart half is reachable from the override; the Talos half is
not. So `kubeProxyReplacement: false` in the override against the typed default
yields no kube-proxy DaemonSet **and** a Cilium that does not replace it: no
ClusterIP datapath, no cluster DNS, no convergence — baked into a create-only
seed and unrecoverable without a re-bootstrap. An override pointing
`k8sServiceHost` at an endpoint that does not exist until the CNI is up deadlocks
the bootstrap identically.

An override naming one of these joint keys is therefore **rejected at plan
time**, naming the typed input that sets both halves together. This costs no
capability — a consumer wanting kube-proxy sets
`cilium_kube_proxy_replacement = false` and gets both halves in sync — and the
module can actually perform it, needing to recognise only key names it owns, never
to understand the chart. `cluster.network.cni.name: none` needs no rule: machine
config with no chart counterpart, opt-out stays `deploy_cilium = false`.

**2. What is not a chart value at all.** The `AGENTS.md` §Hard Constraints boot
guards, the forbidden-kind bans, and ADR-0007 §5's two structurally
secret-excluded fields.

Everything else is open, and the module does not re-assert its own value over a
consumer's — that would re-create the silent-overwrite complaint this decision
exists to answer.

### (e) The ArgoCD security floor becomes consumer-owned

`scripts/check-argocd-substrate-invariants.sh` asserts six invariants that are
properties of the component's Helm values, three of them security controls (no
shipped `policy.csv`, no blanket `policy.default`, an exact five-policy
NetworkPolicy posture), and it reads the base's copy only. §(c) hands that file
to the consumer: a re-render with `global.networkPolicy.create: false`, or with a
`configs.rbac` block, voids the corresponding floor on that fork silently while
the render still passes schema validation, and no revisit trigger fires — nothing
breaks, the posture stops existing.

This is **assigned, not mitigated**. The implementing change ships the invariant
gate with the payload and names running it in the documented re-render procedure;
whether the consumer runs it is theirs, exactly as the consumer-cluster Kyverno
boundary already works for the seed-side override. What this ADR refuses is to
present the re-render path as consequence-free.

### (f) Typed inputs: the shipped ones stay, the substitution claim retires

Every shipped typed input stays — removing one breaks consumers for no gain, and
for a value feeding more than one sink (`pod_cidr`, `service_cidr`, the §(d)
case) a typed field is the only shape that keeps the halves in sync. The policy
for **new** ones returns to ADR-0007 §4 unchanged.

What retires is the *substitution* claim in ADR-0022's 2026-08-15 addendum — that
"a typed input closes it on both paths at once" and thereby discharges the
missing Day-2 reach. It closes one key per base release; the long tail is not
enumerable, so a per-key remedy does not answer a surface problem.

### (g) Schema parity — `substrate.cilium` stays closed

ADR-0022 §(l) is untouched. A closed typed-key set and a free value surface are
not in tension: the free-form content rides **inside** the `values_override`
string, so the schema still rejects a typo'd typed key at lint time. Four of the
five parity dimensions are unchanged; the fifth does change — §(l) recorded no
confidentiality requirement, which held while the override reached only the
machine config, and §(b) gives it a git-committed sink, so that question is
re-opened there rather than inherited silently here.

The open `substrate.argocd` object is a separate finding in the surface map and
is **not** decided here.

## Validation

Two gates bind the implementing changes. Two revisit triggers are labelled as not
mechanically armed, because this repo has no live cluster
(`AGENTS.md` §Testing Guidelines) and both depend on a consumer report.

- **The Cilium half is bound by two test legs, not one.**
  `tests/input-validation.tftest.hcl` carries the removed guard's isolated leg.
  Its replacement must assert both that the emitted `Application` carries an
  override key and that an override naming a §(d) joint key is rejected — the
  first alone would let the unbootable combination through.
- **The ArgoCD half is bound by a consumer-shaped render**, run from a
  tarball-only checkout in the vendored layout `AGENTS.md` §Repository Purpose
  describes: a modified `values.yaml` yields a changed render while the base's own
  tree stays byte-identical under `task gitops:validate`. Run from the base
  repository it proves nothing.
- **Revisit trigger — §(d)'s joint-key set is incomplete.** An override that
  breaks a bootstrap through a pair §(d) did not name means the set is wrong.
- **Revisit trigger — the silent-drop class becomes the dominant complaint.** If
  reports of unsettable values are replaced by reports of overrides that did
  nothing, the surface needs a validating gate rather than a narrower one. The
  symptom is attributed upstream as readily as here, so the trigger is weak.

## Links

- [The ArgoCD/Cilium Helm value surface](../reference/helm-values-surface.md) —
  the evidence map this decision rests on.
- [ADR-0022](0022-cilium-observability-and-argocd-self-management.md) — partially
  superseded here.
- [ADR-0007](0007-cluster-yaml-sot.md) §1 (the machine-config injection §(d)
  rests on), §4 (the right-altitude rule re-affirmed), §5 (the escape-hatch
  secret discipline §(b) extends).
- [ADR-0024](0024-argocd-substrate-relocation.md) — the allowlist decision §(c)
  extends, and [ADR-0025](0025-argocd-crd-apply-scope.md) — the Day-0 apply scope
  §(a) leaves closed.

Tracker provenance, for the discussion and not for the decision: the
guarded-vs-tunable question was raised as issue #86; the Cilium and ArgoCD
halves are tracked as #265 and #261, the collision set as #262, and the
typed-input requests §(f) reframes as #188 and #227.
