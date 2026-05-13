# Vision

This document collects forward-looking statements that appear scattered across
the ADR set, the capability architecture, and the harness-plugin integration
spec. They are **not roadmap**, **not commitments**, and **not planned for any
specific tag**. They are anchors — the design choices made for the current
v0.x have one eye on the future shape described here, but the future shape is
not in flight.

## Honest status (today, 2026-05-14)

- **One maintainer** ([@nosmoht](https://github.com/nosmoht)).
- **Single planned consumer** (the maintainer's homelab); no public consumer
  cluster repo exists yet.
- **Repository age**: 13 days since initial commit (created 2026-04-30).
- **Two OCI tags** published (`v0.1.0`, `v0.2.0`).
- **External adopters**: none known.

Anything in this file beyond §"Honest status" is a design hypothesis the
v0.x schema was built to accommodate — not a deliverable on any timeline.

## v1.X horizons (months-to-year scale)

These are concrete extensions whose design fits the current schema but whose
implementation is out of scope for the current tag stream. None has an issue
in this repo's backlog yet; opening one is a prerequisite for treating any of
these as work.

### Backstage Software Catalog adapter

The Layer-A capability index ([`platform-capability-index.yaml`](platform-capability-index.yaml))
was designed with Backstage entity-model field alignment so that a future
adapter can ingest it without remapping. The adapter itself is **not built**.

Known open question: Backstage's `lifecycle` field exists for the `Component`
and `API` entity kinds, but not for `Resource` (Backstage open issue #25111).
Per-kind mapping will be non-uniform.

### Behavioral-equivalence test fixtures per implementation

The capability index allows multiple implementations per capability with a
`swap_class`. To strengthen the swap-class claim, each "swappable" capability
could carry a behavioral-equivalence test fixture. **No CNCF precedent exists
for this pattern**; it would be pioneering.

The trade-off — maintenance overhead vs. swap-confidence — is unresolved.
v0.x leaves the fixture as optional metadata only.

## v2.X horizons (year-plus scale, design only)

These statements describe a target architecture the v0.x vocabulary was built
to survive — they do **not** describe near-term work.

### Multi-tenant cluster provisioning via Backstage portal

A future v2.X path imagined for the platform: customers request a
fully-isolated tenant Kubernetes cluster via a Backstage portal. The cluster
is materialised by Crossplane (v2) + Cluster-API + KubeVirt. The tenant
cluster consumes host-cluster platform services across cluster boundaries via
Cilium ClusterMesh.

Realism check:

- Crossplane v2 removed Claims; XRs are the namespaced consumer-facing handle.
  Compatible with the current `implementations[].composition` schema, but
  XRD/Composition generation tooling does not exist here.
- Cluster-API + KubeVirt as a tenant-cluster provisioner is a research-grade
  pattern, not a mature product.
- ClusterMesh requires ≥ 2 reachable clusters with a tunneled service-discovery
  layer; today there is one cluster.

**This will not ship in v0.x.** It is included here only to explain why
schema fields like `deployment_topology ∈ {host-singleton, host-only,
tenant-instance, host-and-tenant}` and `cross_cluster_protocol` exist in the
capability index — they reserve namespace, they do not implement behaviour.

### Cross-cluster identity

Cross-cluster identity (SPIFFE? Vault auth? OIDC federation?) is **the
v2.X-blocking open question**. The Layer A index documents the protocol
bridge (`cilium-clustermesh`) but does not resolve identity.

### Customer parametric capability selection

If multi-tenant cluster provisioning materialises, the customer's choice of
capability implementation would happen at the Crossplane Composition layer,
not in this base. The base would supply the catalogue (Layer A); composition
selection would happen one layer above.

## CNCF-conformance is not a claim

The Two-Layer ADR aligns vocabulary with the [CNCF TAG App Delivery Platforms
White Paper](https://github.com/cncf/tag-app-delivery/blob/main/platforms-whitepaper/v1/paper.md),
draws on Backstage (CNCF Incubating) and Crossplane (CNCF Graduated) field
shapes, and uses ISO-8601 dates. None of this is **CNCF-conformant** in a
programmatic sense — there is no CNCF conformance programme for platform-base
repos. The alignment is design-rhetorical, not certificational.

## Harness plugin (separate repo)

[`docs/harness-plugin-integration.md`](harness-plugin-integration.md) specifies
what the `kube-agent-harness` Claude Code plugin should provide for v2. That
plugin repository does not yet exist publicly. Subagents and rules listed
there as "shipped" describe the maintainer's local workflow, not a public
artefact.

The harness-plugin-integration document is a **contract spec for a future
plugin**, not a status report on a running one. Reading it as the latter
overstates what is in flight.

## What this document is NOT

- **Not a roadmap.** There is no timeline, no quarter, no sprint allocation.
- **Not a commitment.** Any item here can be deprioritised or removed without
  notice; consumers should not plan against it.
- **Not a feature inventory.** Things in this file are *not built*; refer to
  the [CHANGELOG](../CHANGELOG.md) for what actually shipped.
- **Not user-facing.** External adopters considering this base for production
  should pretend this file does not exist and evaluate only `v0.2.0` as it
  stands today.

## How to use this file

- When a doc says something the current repo cannot do, that line probably
  belongs here. Move it; leave a one-line pointer in the source doc.
- When proposing new work, check whether the design assumes a v1.X / v2.X
  feature listed here. If yes, surface the dependency.
- When in doubt about whether a statement is current-truth or aspiration:
  search this file. If it lives here, it is aspiration.

## See also

- [`adr-two-layer-capability-architecture.md`](adr-two-layer-capability-architecture.md) — Layer A/B split (status: proposed)
- [`capability-architecture.md`](capability-architecture.md) — the v2 contract as implemented today
- [`harness-plugin-integration.md`](harness-plugin-integration.md) — spec for the not-yet-public plugin repo
- [`CHANGELOG.md`](../CHANGELOG.md) — what actually shipped per tag
