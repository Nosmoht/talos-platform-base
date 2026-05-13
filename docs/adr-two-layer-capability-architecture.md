# ADR: Two-Layer Capability Architecture — Tool-Capability-Index (Layer A) Separate from PNI Network-Trust Registry (Layer B)

**Status:** proposed
**Date:** 2026-05-13
**Companion docs:** [Platform Capability Index](./platform-capability-index.yaml) · [PNI Capability Architecture](./capability-architecture.md) · [Capability Producer/Consumer Symmetry ADR](./adr-capability-producer-consumer-symmetry.md)

## Context and Problem Statement

The term *capability* in this base repo has been used for two structurally different concerns:

1. **Network-trust capability** — which cross-namespace L4/L7 traffic patterns are permitted, governed by Kyverno + Cilium. This is the established PNI v2 registry at `kubernetes/base/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml`.
2. **Tool capability** — what functional services the platform offers, with which tools today, and what swap classes exist between alternative implementations.

Both concerns are real and both need a single source of truth, but their shape, consumers, and lifecycle differ enough that bundling them into one artifact produced symptoms in earlier design rounds: entries that don't fit the network-trust shape were patched with `control_plane_only: true` flags; Acid-4 (tenant-visible network surface) was used as a pass/fail filter rather than as an architectural discriminator; schema fields that only make sense for one concern were duplicated.

The CNCF TAG App Delivery *Platforms White Paper* (2023) defines a platform's *capabilities* as the stable, tool-agnostic offerings, and notes capabilities may comprise several features. Backstage (CNCF Incubating) entity model and Crossplane (CNCF Graduated) Composite Resource Definitions both support this two-level shape (capability ↔ implementations) but neither directly addresses the network-trust concern.

The schema must also reserve room for a v1.X / v2.X design direction — Backstage adapter, Crossplane composition mapping, multi-cluster tenant-provisioning — without committing this base to any of it. The full forward-looking statements are collected in [`vision.md`](vision.md); this ADR addresses only the v0.x decision.

## Decision Drivers

- **D1.** Capability vocabulary must align with the CNCF Platforms White Paper definition (capability = stable, tool-agnostic; comprised of features).
- **D2.** Existing PNI v2 registry, Kyverno policies, and CCNPs must keep working without rewrite.
- **D3.** Schema must be ingestable by Backstage entity catalog (Component/API/Resource kinds) without remapping. (Forward-looking — see [`vision.md`](vision.md) §"Backstage Software Catalog adapter"; the adapter itself is not built in v0.x.)
- **D4.** Schema must accommodate a future Crossplane XRD/Composition migration (note: Crossplane v2 removed Claims; XRs are the namespaced consumer-facing handle). (Forward-looking — see [`vision.md`](vision.md) §"Multi-tenant cluster provisioning"; not in flight.)
- **D5.** Capability lifecycle vocabulary must match the Kubernetes host-stack convention (alpha/beta/GA/deprecated, per K8s feature-gate and API-deprecation policies).
- **D6.** Tool-swap reasoning must be explicit: implementations carry an explicit swap-class so an ADR proposing a swap can cite an enum value rather than improvise.
- **D7.** Control-plane-only tools (ArgoCD, Kyverno, Tetragon, external-secrets, cert-approver, vault-config-operator) must be inventoried for provenance but must NOT receive PNI capability labels.

## Considered Options

**Option 1 — Extend the PNI registry to cover all tools.** Add fields like `control_plane_only` and `swap_class` to the existing ConfigMap; Kyverno policies grow to ignore the extended fields.

**Option 2 — Two separate artifacts with shared identifier scheme.** Keep the PNI registry as a Kyverno-consumed ConfigMap focused on network trust. Add a separate `docs/platform-capability-index.yaml` as a human-and-tool catalog. Capability IDs match where the two concerns overlap.

**Option 3 — Deprecate the PNI registry in favor of a unified richer artifact.** Replace both with one large schema; rewrite Kyverno policies to consume the new shape.

## Decision Outcome

**Chosen: Option 2.**

The two artifacts are:

- **Layer A — Tool-Capability-Index.** SOT at `docs/platform-capability-index.yaml`. Static catalog, no in-cluster consumer at runtime. Read at build time by render and lint scripts, at PR time by validation, at design time by humans and agentic tools. Schema is the full bespoke schema documented in the Index header.
- **Layer B — PNI Capability Registry.** Unchanged location and Kyverno-consumed wire format. Subset of Layer A by ID: every Layer B entry must have a Layer A counterpart (same `id`); the reverse is not required.

Per-entry validation:

- A Layer A entry is admissible if Acid tests #1–#3 pass (≥2 plausible implementations exist; contract is stable; lifecycle is independent of sibling capabilities).
- A Layer B entry is admissible only if it additionally satisfies Acid #4 (tenant-visible network surface): there is real cross-namespace pod-to-pod or pod-to-service L4/L7 traffic for the capability.

The discriminator between Layer A and Layer A ∩ B is Acid #4 — not a `control_plane_only` flag.

### Schema essentials (Layer A)

Full schema lives in the YAML file header. Key fields and their sourcing:

| Field | Source / inspiration |
|---|---|
| `id`, `name`, `description`, `domain.{layer,category}` | bespoke, aligned with CNCF Platforms White Paper definition |
| `owner`, `tags[]` | Backstage descriptor format (for future ingestion compatibility) |
| `stability ∈ {alpha, beta, ga, deprecated}` | Kubernetes feature-gate and API-deprecation policy |
| `contract` (prose) | bespoke |
| `derived_from` (optional) | OASIS TOSCA `capability_type derived_from` (TOSCA is OASIS, not ISO) |
| `independence_test.{alt_impls_exist, contract_stable, independent_lifecycle, notes}` | bespoke; encodes Acid #1–#3 outcomes |
| `implementations[].{name, status, composition, swap_class}` | analogue of Crossplane XRD ↔ Composition pattern |
| `swap_class ∈ {drop-in, label-move, data-migration, consumer-change, rewrite-required}` | bespoke five-value enum; `rewrite-required` added to honestly reflect Kyverno↔Gatekeeper-class swaps |
| `instanced` + `instance_source` | unchanged from PNI v2 |
| `deployment_topology ∈ {host-singleton, host-only, tenant-instance, host-and-tenant}` | bespoke; reserved for a possible multi-cluster tenant-provisioning model (see [`vision.md`](vision.md); not implemented in v0.x) |
| `cross_cluster_protocol` | bespoke; documents the cross-cluster bridge for `host-singleton` / `host-and-tenant` capabilities. Default: `cilium-clustermesh`. Field is declarative only in v0.x — no cross-cluster reachability is implemented. |
| `pni_capability_id` | optional cross-reference to Layer B |
| `deprecated`, `replaced_by`, `split_into`, `sunset.{date,tag}` | Kubernetes API-deprecation policy (9 months / 3 releases grace) |

### Lifecycle commitments per stability

- **alpha** — may be removed without notice; `notes` field mandatory explaining why an entry exists at this stage.
- **beta** — production-deployed in base, contract may evolve with deprecation notices.
- **ga** — id and contract fixed; implementation swaps documented via `swap_class`. Breaking-change requires major OCI-tag bump.
- **deprecated** — terminal state; entry has `replaced_by` or `split_into`, and `sunset` ≥ 9 months OR 3 OCI tags from the deprecation announcement.

### Validation (CI required checks)

Three scripts, one CI job (`capability-index-check` in `gitops-validate.yml`):

- `lint-capability-index.sh` — schema lint (required fields, kebab-case, ISO-8601 dates, enum validity).
- `check-capability-index-refs.sh` — cross-reference check (`composition` entries exist as base infra directories or are marked external; `replaced_by`/`split_into` resolve; `pni_capability_id` resolves to a Layer B entry or is null).
- `render-capability-index.sh` — produces `docs/platform-capability-index.md`; CI verifies committed `.md` matches YAML source.

### Out of scope for v0.X

The following are deliberately left for a hypothetical future tag stream and
are described in [`vision.md`](vision.md) (which is explicit that none of
these is roadmap or commitment):

- Crossplane v2 XRD/Composition generation.
- Backstage Software Catalog adapter.
- Behavioral-equivalence test fixtures per implementation (no CNCF precedent).
- Customer parametric capability selection (would happen at the Composition
  layer one level above this base, not in the base).

## Consequences

### Positive

- **C+1.** Single answer for "what does this base provide?" — one YAML file, schema-validated, machine-readable, human-readable via generated MD.
- **C+2.** Tool-swap ADRs cite stable capability IDs and explicit `swap_class` enum values.
- **C+3.** Layer B PNI registry stays focused, retains existing Kyverno integration, no rewrite required.
- **C+4.** Capability vocabulary leaves room for a possible future Backstage + Crossplane + CAPI+KubeVirt direction without forcing it. Whether that direction is taken is a separate decision (see [`vision.md`](vision.md)).
- **C+5.** Control-plane-only tools have provenance without being smuggled into the network-trust model.

### Negative

- **C–1.** Two artifacts must stay in sync where IDs overlap. Mitigated by the validation script and by IDs being the only required link.
- **C–2.** The behavioral-equivalence pattern referenced in `verification:` is pioneering — no CNCF precedent. Risk: maintenance overhead exceeds value. Optional in v0.x; whether to make it mandatory at any future stability level is open (see [`vision.md`](vision.md) §"Behavioral-equivalence test fixtures").
- **C–3.** Cross-cluster identity (SPIFFE? Vault auth? OIDC federation?) is unresolved. The Layer A index documents the protocol bridge (`cilium-clustermesh`) but identity is left open and would block any multi-cluster direction; see [`vision.md`](vision.md) §"Cross-cluster identity".

### Neutral

- **C±1.** TOSCA influences `derived_from` semantics but is not adopted as a file format. TOSCA 2.0 is an OASIS standard with an ISO/IEC liaison; it is not itself an ISO standard.
- **C±2.** Backstage `lifecycle` field exists for the Component and API entity kinds, not for Resource (Backstage open issue #25111). If a Backstage adapter is ever built, per-kind mapping will not be uniform. (Not in flight; see [`vision.md`](vision.md).)
- **C±3.** "CNCF-conformant" is not a recognized programme for platform-base repos. This ADR claims vocabulary-alignment with the CNCF Platforms White Paper, compatibility with the Backstage entity model (CNCF Incubating), and design-compatibility with Crossplane v2 (CNCF Graduated). It does not claim CNCF conformance. (Made explicit in [`vision.md`](vision.md) §"CNCF-conformance is not a claim".)

## References

- CNCF TAG App Delivery — *Platforms White Paper* (2023): https://tag-app-delivery.cncf.io/whitepapers/platforms/
- Kubernetes API Deprecation Policy: https://kubernetes.io/docs/reference/using-api/deprecation-policy/
- Kubernetes Feature Gates: https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/
- Backstage Descriptor Format: https://backstage.io/docs/features/software-catalog/descriptor-format/
- Backstage System Model: https://backstage.io/docs/features/software-catalog/system-model/
- OASIS TOSCA Simple Profile YAML v1.3: https://docs.oasis-open.org/tosca/TOSCA-Simple-Profile-YAML/v1.3/TOSCA-Simple-Profile-YAML-v1.3.html
- Crossplane Composition Functions: https://docs.crossplane.io/latest/learn/feature-lifecycle/
- Companion ADR: [Capability Producer/Consumer Symmetry](./adr-capability-producer-consumer-symmetry.md)
- Companion doc: [PNI Capability Architecture](./capability-architecture.md)
