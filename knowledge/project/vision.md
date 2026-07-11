---
type: project
title: Vision
description: Forward-looking design anchors the schema was built to accommodate — explicitly not roadmap, commitments, or shipped features.
tags: [project, vision]
timestamp: 2026-07-11
migrated_from: docs/vision.md (deleted in the OKF migration; see git history)
sources:
  - CHANGELOG.md
  - MAINTAINERS.md
  - .github/workflows/oci-publish.yml
---

# Vision

This document collects forward-looking statements that appear scattered across
the ADR set, the capability architecture, and the harness-plugin contract
spec. They are **not roadmap**, **not commitments**, and **not planned for any
specific tag**. They are anchors — the design choices made for the v0.x era
have one eye on the future shape described here, but the future shape is
not in flight.

*Statements about the external ecosystem (Backstage, Crossplane,
Cluster-API, CNCF landscape) are as-of-writing observations, not
re-verified claims — check upstream before relying on them.*

> [2026-07-11 verification] The version labels in this document (v0.x,
> "v1.X horizons", "v2.X horizons") predate the current tag stream. The git
> history was squashed in June 2026 and the pre-v2.0.0 tags were removed
> (their entries survive in `CHANGELOG.md`); the current tags are `v2.0.0`
> and `v3.0.0`. Read "v1.X / v2.X horizons" as medium-/long-term design
> horizons, not as the shipped v2.x/v3.x releases — v2.0.0 (substrate-only
> ablation) and v3.0.0 (Makefile retirement, kubelet serving-cert rotation)
> shipped none of the features below.

## Honest status (verified 2026-07-11)

- **One maintainer** ([@nosmoht](https://github.com/nosmoht)) — the single
  active maintainer listed in `MAINTAINERS.md`.
- **No public consumer cluster repo exists yet.**
- **Repository age**: created 2026-04-30; roughly ten weeks at verification
  time. The current git history root dates 2026-06-25 (history squash,
  June 2026).
- **Two git tags** published (`v2.0.0`, `v3.0.0`), each with a GitHub Release
  and an OCI artifact produced by `.github/workflows/oci-publish.yml`; the
  earlier v0.x/v1.x tags were removed with the history squash (their release
  notes remain in `CHANGELOG.md`).
- **External adopters**: none known.

> [2026-07-11 verification] Updated from the 2026-05-14 snapshot (then:
> 13 days old; two tags `v0.1.0`, `v0.2.0`).

Anything in this file beyond §"Honest status" is a design hypothesis the
v0.x schema was built to accommodate — not a deliverable on any timeline.

## v1.X horizons (months-to-year scale)

These are concrete extensions whose design fits the current schema but whose
implementation is out of scope for the current tag stream. None has an issue
in this repo's backlog yet; opening one is a prerequisite for treating any of
these as work.

### Backstage Software Catalog adapter

The capability catalogue — now owned by the `talos-platform-apps` repo
rather than this base — was designed with Backstage entity-model field
alignment so that a future adapter can ingest it without remapping. The
adapter itself is **not built**.

> [2026-07-11 verification] `talos-platform-apps` is not publicly visible on
> GitHub as of this date.

Known open question: Backstage's `lifecycle` field exists for the `Component`
and `API` entity kinds, but not for `Resource` (Backstage issue #25111 —
closed as of 2026-07-11; whether the lifecycle gap itself persists upstream
was not re-verified). Per-kind mapping will be non-uniform.

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
  layer; a single-cluster deployment has none.

**This will not ship in v0.x.** It is included here only to explain why
schema fields like `deployment_topology` (host-singleton | host-only |
tenant-instance | host-and-tenant) and `cross_cluster_protocol` exist in the
capability catalogue (now in `talos-platform-apps`) — they reserve
namespace, they do not implement behaviour.

### Cross-cluster identity

Cross-cluster identity (SPIFFE? Vault auth? OIDC federation?) is **the
v2.X-blocking open question**. The capability catalogue documents the
protocol bridge (`cilium-clustermesh`) but does not resolve identity.

### Customer parametric capability selection

If multi-tenant cluster provisioning materialises, the customer's choice of
capability implementation would happen at the Crossplane Composition layer,
not in this base. The `talos-platform-apps` catalogue would supply the
options; composition selection would happen one layer above.

## CNCF-conformance is not a claim

The capability vocabulary aligns with the [CNCF TAG App Delivery Platforms
White Paper](https://github.com/cncf/tag-app-delivery/blob/main/platforms-whitepaper/v1/paper.md),
draws on Backstage (CNCF Incubating) and Crossplane (CNCF Graduated) field
shapes, and uses ISO-8601 dates. None of this is **CNCF-conformant** in a
programmatic sense — there is no CNCF conformance programme for platform-base
repos. The alignment is design-rhetorical, not certificational.

## Harness plugin (separate repo)

The [harness plugin contract](harness-plugin-contract.md) specifies
what the Claude Code harness plugin should provide for this base.
That plugin repository does not yet exist publicly. Subagents and rules listed
there as "shipped" describe the maintainer's local workflow, not a public
artefact.

The harness-plugin contract document is a **contract spec for a future
plugin**, not a status report on a running one. Reading it as the latter
overstates what is in flight.

## What this document is NOT

- **Not a roadmap.** There is no timeline, no quarter, no sprint allocation.
- **Not a commitment.** Any item here can be deprioritised or removed without
  notice; consumers should not plan against it.
- **Not a feature inventory.** Things in this file are *not built*; refer to
  `CHANGELOG.md` for what actually shipped.
- **Not user-facing.** External adopters considering this base for production
  should pretend this file does not exist and evaluate only the latest tagged
  release (`v3.0.0` at verification time) as it stands.

## How to use this file

- When a doc says something the current repo cannot do, that line probably
  belongs here. Move it; leave a one-line pointer in the source doc.
- When proposing new work, check whether the design assumes a v1.X / v2.X
  feature listed here. If yes, surface the dependency.
- When in doubt about whether a statement is current-truth or aspiration:
  search this file. If it lives here, it is aspiration.

## See also

- [Substrate-only base](../decisions/0004-substrate-only-base.md) — why the base ships substrate only
- [Harness plugin contract](harness-plugin-contract.md) — spec for the not-yet-public plugin repo
- `CHANGELOG.md` — what actually shipped per tag
