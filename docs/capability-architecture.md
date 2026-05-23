# Capability-First Architecture

**Status:** active (v2 contract)
**Audience:** consumer-cluster authors, platform operators, agentic tools.
**Companion docs:** [ADR — Capability Producer/Consumer Symmetry][adr] · [ADR — Three-Layer Capability Architecture][adr-three] · [Cookbook][cookbook] · [Capability Reference][ref] · [Layer-C Hardware Features Registry][hw]

[adr]: ./adr-capability-producer-consumer-symmetry.md
[adr-three]: ./adr-three-layer-capability-architecture.md
[cookbook]: ./pni-cookbook.md
[ref]: ./capability-reference.md
[hw]: ./platform-hardware-features.yaml

This document is the canonical **explanation** for the platform's
capability-first network architecture. It does not prescribe individual
manifests (see the [Cookbook][cookbook] for that) and does not enumerate
capabilities (see the [Capability Reference][ref]). It explains *why* the
shapes are what they are.

## Where this document sits in the three-layer model

Per [ADR — Three-Layer Capability Architecture][adr-three], the platform
governs **three** capability layers:

- **Layer A — Tool-Capability-Index** (`docs/platform-capability-index.yaml`):
  the static catalogue of every functional capability the base provides,
  with stable ids, swap classes, and `requires_hardware_features[]`
  cross-references into Layer C.
- **Layer B — PNI Network-Trust Registry** (Kyverno-consumed ConfigMap):
  the **runtime** subset of Layer A that mediates cross-namespace
  pod-to-pod / pod-to-service L4/L7 traffic. **This document is about
  Layer B.** Every recipe, contract, and admission rule below operates
  on Layer-B vocabulary.
- **Layer C — Hardware Features Registry** (`docs/platform-hardware-features.yaml`):
  the catalogue of atomic hardware predicates (`nvidia-gpu`,
  `vt-x-or-amd-v`, `drbd-kernel-module`, …) that Layer A entries declare
  via `requires_hardware_features[]` and that consumer-side composite
  capabilities (in `cluster.yaml`) declare via `requires_features[]`.

Layer A and Layer C are static catalogues; Layer B is the runtime
contract. Layer C is **disjoint** from Layer B — hardware predicates do
not mediate network trust. The Reserved-label namespace
`platform.io/hardware-feature.*` / `platform.io/hardware-capability.*`
is governed by the same Kyverno policy file as the Layer-B reservations
(`kyverno-clusterpolicy-pni-reserved-labels-enforce.yaml`) for
co-location, but the two rule sets are independently enforced.

## Layer A entries: tool-capability vs network-primitive

Within Layer A itself, the `kind:` discriminator distinguishes two
structurally different entry types (per issue #62):

- **`tool-capability`** — entries with a real, swappable implementation.
  Each implementation points at one or more infrastructure components
  under `kubernetes/base/infrastructure/<x>/` via `composition[]`, and
  the `swap_class` enum records the cost of moving between alternatives.
  Examples: `metrics-scrape`, `block-storage-replicated`, `vault-secrets`.
- **`network-primitive`** — entries whose dataplane IS the Cilium/Kyverno
  rule itself (CIDR-based CCNP egress, Gateway-API HTTPRoute backend
  permission, cluster-singleton plumbing). There is no swappable tool
  implementation; `composition[]` is legitimately empty. Examples:
  `internet-egress` (CIDR egress to public IPs), `controlplane-egress`
  (egress to kube-apiserver), `gateway-backend` (Gateway-API selector
  permission), `external-gateway-routes` (Gateway listener attachment).

Both kinds remain Layer-A entries — they share the schema, the
identifier discipline, and the cross-reference to Layer B. The
validation script `scripts/check-capability-index-refs.sh` skips the
"non-external active impl but composition is empty" rule for
`kind: network-primitive` entries; the rule stays enforced for
`kind: tool-capability` entries to keep the swap-class semantics honest.

Hybrid entries — those whose implementations include both a real tool
AND an external-network attachment (current example: `s3-object` with
`minio-operator` plus `external-s3`) — keep `kind: tool-capability` at
the entry level and mark the network-attachment implementation with the
per-implementation flag `external_network_attachment: true`.

## TL;DR

Capabilities are stable; tools are swappable in the design — see the
"Tool-swap mechanics" section below for the contract, and
[issue #34](https://github.com/Nosmoht/talos-platform-base/issues/34) for
the status of the first end-to-end verified swap. Trust is namespace-anchored.
The design supports instance-scoped multi-tenant data services; the current
operating reality is single-tenant. There is no central tool whitelist.

## Core invariant — capabilities are the stable interface

Every cross-namespace connection in the platform is mediated by a
**capability**: a stable, tool-agnostic identifier (`monitoring-scrape`,
`tls-issuance`, `cnpg-postgres.<inst>`, …) declared in the
[capability registry](../kubernetes/base/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml).

- **Consumers** declare which capabilities they consume. They never name
  a tool.
- **Producers** declare which capabilities they provide. They keep their
  tool identity as an implementation detail.
- **Network policies (CCNPs)** select on the capability label, never on
  the tool name. Replacing Prometheus with Victoria-Metrics, Loki with
  Victoria-Logs, or CNPG with StackGres is a producer-side label move,
  not a CCNP rewrite.

The single documented exception is plumbing without a capability fit
(e.g. `kube-dns` in `ccnp-pni-monitoring-dns-visibility.yaml`); the file
header names the exception explicitly.

## Five-site contract

For each capability `<cap>` (with optional instance `<inst>`), five
sites carry the contract:

```text
                  Producer side                   |        Consumer side
──────────────────────────────────────────────────┼──────────────────────────────────────
  Namespace   provide.<cap>[.<inst>]: "true"      |   consume.<cap>[.<inst>]: "true"
  Pod         capability-provider.<cap>[.<inst>]  |   capability-consumer.<cap>[.<inst>]
  Service     capability-endpoint.<cap>           |   (no consumer-side service contract)
              capability-protocol.<cap>
              (Service annotations, discovery only)
```

All keys are prefixed `platform.io/`. Reserved (producer-side) keys are
admission-controlled; consumer-side keys are free-form opt-in.

| Site | Key | Reserved | Function |
|---|---|---|---|
| Producer Namespace | `provide.<cap>[.<inst>]: "true"` | yes | trust anchor (RBAC + Kyverno) |
| Producer Pod | `capability-provider.<cap>[.<inst>]: "true"` | yes | CCNP `endpointSelector` target |
| Producer Service | annotation `capability-endpoint.<cap>: <port-name>` + `capability-protocol.<cap>: <wire>` | yes | discovery only |
| Consumer Namespace | `consume.<cap>[.<inst>]: "true"` | no | opt-in declaration |
| Consumer Pod | `capability-consumer.<cap>[.<inst>]: "true"` | no | CCNP source selector |

CCNPs match Pod labels, not Service labels — that is a Cilium constraint.
Service annotations exist for discovery tooling and dashboards.

## Namespace-anchored trust

A workload's `capability-provider.<cap>` claim is valid **iff** its
namespace carries `platform.io/provide.<cap>: "true"`. This invariant
is parametric and ships in one Kyverno rule
(`kyverno-clusterpolicy-pni-reserved-labels-enforce.yaml` →
`capability-provider-requires-namespace-provide`).

The architecture explicitly **rejects** two alternative trust models:

1. **Central tool-signature whitelist.** A Kyverno policy enumerating
   `app.kubernetes.io/component`, `redis_setup_type`,
   `app.kubernetes.io/managed-by`, etc. grows linearly with every
   producer integration and contradicts tool-swappability.
2. **Kube-system exemptions.** A producer in a shared system namespace
   cannot self-anchor its trust. The fix is **relocation to a
   dedicated namespace**, not an exemption. `metrics-server` was
   relocated `kube-system → metrics-server` for exactly this reason.

Consequence: every capability-provider component ships its own
`namespace.yaml` in this base, even when the namespace name is shared
(both `loki` and `kube-prometheus-stack` co-own the `monitoring`
namespace, each declaring its capabilities).

## Per-instance scoping

Capabilities whose data plane could be partitioned per tenant carry an
instance suffix. In v0.x this is a contract the base enforces (via the
audit-mode policy `pni-instanced-suffix-required-audit`) — the single
existing operator runs a single tenant. The mechanism is in place for
multi-tenant use cases that may emerge; see [`vision.md`](vision.md) for
where multi-tenant operation fits in possible future tag streams.

```yaml
# Consumer namespace
labels:
  platform.io/consume.cnpg-postgres.team-foo: "true"
# Producer pod
labels:
  platform.io/capability-provider.cnpg-postgres.team-foo: "true"
```

Registry declares which capabilities are instanced:

```yaml
- id: cnpg-postgres
  instanced: true
  instance_source: { apiVersion: postgresql.cnpg.io/v1, kind: Cluster }
```

The instance unit is registry-declared (Vault uses the KV mount path;
CNPG uses the `Cluster` CR name). Per-instance L4 isolation prevents a
compromised tenant pod with `consume.cnpg-postgres.team-foo` from
reaching `team-bar`'s database at L4.

### Instance enforcement is consumer-overlay scope

The base does **not** ship per-instance Kyverno `generate` + `mutate`
machinery. The base ships only the *operators* for instanced
capabilities; the data-plane instances (CNPG `Cluster`,
`RabbitmqCluster`, `RedisFailover`, `Kafka`, Vault `server`,
`LinstorCluster`) are all consumer-overlay-deployed. Per-instance
binding lives where the instances live: in the overlay.

Base ships instead:

1. The **vocabulary** — schema, reserved keys, namespace-anchored rule.
2. The **discipline advisory** — audit-mode policy
   `pni-instanced-suffix-required-audit` emits a PolicyReport entry on
   bare `consume.<instanced-cap>` (no block).

## Vocabulary discipline (advisory)

Two audit-mode advisories carry vocabulary discipline without blocking:

- `pni-instanced-suffix-required-audit` — flags missing instance
  suffixes on instanced capabilities.
- Sunset checker — `policies/conftest/capability_sunset.rego` fails the
  build when `now > sunset` on a deprecated registry entry. PR F (alias
  removal) ships automatically once a sunset date passes; there is no
  user-go-ahead gate.

## Enforcement summary

| Concern | Mechanism | Mode |
|---|---|---|
| Reserved labels on tenant resources | Kyverno `pni-reserved-labels-enforce` | enforce |
| Namespace-anchored producer trust | Kyverno `capability-provider-requires-namespace-provide` (parametric rule, namespace lookup via `apiCall`) | enforce |
| Reserved annotations on Services | Kyverno `pni-reserved-annotations-enforce` | enforce |
| Capability registry well-formedness | Kyverno `pni-capability-validation-enforce` (cap on namespace must exist in registry) | enforce |
| Network-profile + interface-version on tenant namespaces | Kyverno `pni-contract-enforce` | enforce |
| Missing instance suffix on instanced capability | Kyverno `pni-instanced-suffix-required` | audit |
| Sunset on deprecated capability | conftest `capability_sunset.rego` | enforce (CI build fails) |
| L4 reachability per capability | Cilium CCNP `endpointSelector` matches `capability-provider/-consumer` labels | enforce |

L4 only — application-layer authorisation (Vault tokens, Postgres roles,
OIDC scopes, Argo RBAC, Kafka ACLs) is unchanged and not in PNI scope.

## Tool-swap mechanics

A producer-tool swap (Loki → Victoria-Logs, Piraeus → Rook, Prometheus →
Victoria-Metrics, Vault → OpenBao) follows the same five steps:

1. New producer chart deploys to its own namespace.
2. New `namespace.yaml` declares the same `provide.<cap>` labels.
3. New Helm values set `podLabels.platform.io/capability-provider.<cap>: "true"`.
4. New Helm values set `service.annotations.platform.io/capability-endpoint.<cap>` / `capability-protocol.<cap>`.
5. Old chart is retired; CCNPs do not change.

Consumer manifests do not change at all.

## Backwards compatibility — deprecation + sunset

Deprecated registry entries carry `deprecated: true`, `sunset: "<date>"`,
and (for splits) `split_into: [<new-ids>]`. During the grace window,
CCNPs match both old and new selectors in parallel; conftest fails the
build on `now > sunset`.

Consumers verify their own usage with:

```bash
scripts/capability-deprecation-scan.sh kubernetes/
```

## Out of scope

- L7 authorisation (Vault tokens, Postgres roles, Kafka ACLs, OIDC
  scopes) — remains app-layer.
- Identity-aware policy (SPIFFE / Cilium L7 identity) — deferred to a
  future ADR.
- HTTP-path-level distinctions in CCNPs — Cilium does not enforce L4 at
  path granularity; documentation splits are decorative at the network
  layer and must be enforced at the application layer.
- Per-instance Kyverno generate+mutate machinery for tools the base
  does not deploy — consumer-overlay scope.

## References

- [ADR — Capability Producer/Consumer Symmetry][adr]
- [PNI Cookbook][cookbook] — concrete consumer/producer recipes
- [Capability Reference][ref] — per-capability catalogue (auto-generated)
- [Harness Plugin Integration](./harness-plugin-integration.md) — Claude Code primitives wiring for v2
- `AGENTS.md` §"Platform Network Interface (PNI) — v2 Capability-First Contract" — tool-agnostic summary
