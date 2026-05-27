---
status: accepted
date: 2026-05-27
date-history:
  - 2026-05-26 initial (proposed)
  - 2026-05-27 accepted
deciders:
  - Thomas Krahn
consulted: []
informed: []
supersedes:
  - docs/adr-multi-repo-platform-split.md §Component Classification — Consumer-in-Base / Backend-in-Overlay
  - docs/adr-multi-repo-platform-split.md §"Corollary on PNI itself"
related:
  - docs/adr-multi-repo-platform-split.md
  - docs/adr-capability-producer-consumer-symmetry.md
  - docs/adr-two-layer-capability-architecture.md
  - docs/adr-three-layer-capability-architecture.md
---

# ADR: Substrate-Only Base + Separate Apps Repository

## Context and Problem Statement

The repository name `talos-platform-base` semantically promises a
**substrate** — the minimal stack required to make a Talos cluster
runnable (Talos itself, a CNI, a GitOps engine). The current contents
do not match that promise: `kubernetes/base/infrastructure/` holds 22
components, of which only one (`argocd`) is GitOps-engine substrate
and one (`cert-approver`) is Talos-specific bootstrap glue. The
remaining 20 components — Observability stack (Loki, kube-prometheus-
stack, Alloy, Tetragon), Auth (Dex), Secrets (vault-operator, vault-
config-operator, external-secrets), Storage (piraeus-operator, local-
path-provisioner), Workloads (KubeVirt, CDI, NVIDIA, Multus), platform
contract (`platform-network-interface`) and Admission engine (Kyverno)
— are tenant-facing platform **offerings**, not substrate.

ADR `adr-multi-repo-platform-split.md` §Component Classification
(committed 2026-04-30) classified these offerings as "Platform
Consumer in Base" and explicitly fixed PNI as "platform architecture
[that] stays in base". That classification ties every Base-tag bump
to all 22 components in lock-step and forces Multi-Cluster consumers
to accept the full offering matrix regardless of which subset they
deploy. The OCI artifact already published by this repo
(`.ci-oci-tarball-include.txt`, 42 paths) contains **only** `talos/`
+ `docs/platform-hardware-features.yaml` — `infrastructure/` is
consumed exclusively via Git-source Multi-Source-App. The
Substrate-vs-offering split therefore already exists at the artifact
boundary; only the repository structure lags behind.

## Decision Drivers

- **Repo name vs. repo content** — the semantic mismatch between
  `talos-platform-base` and the 22-app payload is operationally
  expensive: every Base bump triggers re-validation of the full app
  matrix even when only Talos / Cilium / ArgoCD changed.
- **Existing artifact asymmetry** — the OCI artifact is already
  Talos-only. Aligning repo structure to the existing artifact
  boundary is cheaper than maintaining the current dual model.
- **Lifecycle decoupling** — Talos / Cilium / ArgoCD substrate bumps
  carry different risk profiles than app updates. Coupling them in
  one tag prevents independent cadence.
- **Multi-cluster divergence** — different clusters select different
  backends (Postgres-vs-managed-Postgres, MinIO-vs-S3, Loki-vs-
  Victoria-Logs). A shared base that ships all offerings constrains
  this choice.
- **Not-a-driver** — there is no security incident, no tool defect,
  and no co-maintainer onboarding driving this. It is purely
  architectural realignment.

## Considered Options

1. **Status quo** — keep the 2026-04-30 classification; all platform
   offerings remain in Base.
2. **Substrate-only Base + new `talos-platform-apps` repo** — Base
   carries only Talos + CNI + GitOps engine + Talos-specific
   bootstrap glue (cert-approver); all platform offerings move to a
   new repository.
3. **Intermediate split** — PNI vocabulary stays in Base as a
   shared contract; remaining platform offerings move to Apps.
4. **3-way split** — Substrate / PNI-vocabulary / Apps, each in its
   own repository.

## Decision Outcome

Chosen option: **Substrate-only Base + new `talos-platform-apps`
repo (Option 2)**, because (a) it aligns the repo name with the
existing artifact-boundary fact, and (b) the `substrate` definition
("what makes the cluster runnable") cleanly excludes all 20 platform
offerings including PNI — generic egress patterns are not the same
as runnability prerequisites.

### Scope of supersession

This ADR supersedes **only** the named sections of
`adr-multi-repo-platform-split.md`:

- §Component Classification — Consumer-in-Base / Backend-in-Overlay
- §"Corollary on PNI itself"

All other sections of `adr-multi-repo-platform-split.md` remain in
force:

- The 3-Repo-Role model (base / harness / consumer)
- Per-cluster trust model (self-rooted peers)
- Day-0 OCI consumption + Day-2 Multi-Source-Application
- Pin-drift discipline between Day-0 and Day-2

The 3-Repo-Role model is extended in scope: Multi-Source-Application
now has three sources (`base`, `apps`, `cluster`) instead of two.

### Component Classification (Substrate vs Apps)

| Path | Destination |
|---|---|
| `talos/**` | Substrate |
| `kubernetes/bootstrap/argocd/**` | Substrate |
| `kubernetes/bootstrap/cilium/**` | Substrate |
| `kubernetes/base/infrastructure/argocd/**` | Substrate (GitOps engine self-upgrade path) |
| `kubernetes/base/infrastructure/cert-approver/**` | Substrate — Talos-specific bootstrap glue. Native Talos integration declined in siderolabs/talos#8523 as "not planned"; external approver remains the prescribed pattern as of Talos v1.12 (2025-12) |
| `policies/conftest/{k8s,argocd}.rego` | Substrate — generic K8s + ArgoCD hygiene, PNI-frei |
| `docs/platform-hardware-features.yaml` + schema | Substrate — Talos Layer-C vocabulary |
| Pre-commit hooks (gitleaks, mcp-config-portable, codex-config-placeholder-only) | Substrate |
| `kubernetes/base/infrastructure/platform-network-interface/**` | Apps |
| `kubernetes/base/infrastructure/{kyverno,multus-cni,node-feature-discovery}/**` | Apps |
| `kubernetes/base/infrastructure/{dex,external-secrets,vault-operator,vault-config-operator}/**` | Apps |
| `kubernetes/base/infrastructure/{kube-prometheus-stack,loki,alloy,tetragon,metrics-server,nvidia-dcgm-exporter,nvidia-device-plugin}/**` | Apps |
| `kubernetes/base/infrastructure/{cert-manager,local-path-provisioner,piraeus-operator,kubevirt,kubevirt-cdi}/**` | Apps |
| `scripts/{render-capability-*,lint-capability-index,check-capability-index-refs,capability-deprecation-scan}.sh` | Apps |
| `docs/{capability-architecture,pni-cookbook,capability-reference}.md` | Apps |
| `docs/adr-capability-producer-consumer-symmetry.md` | Apps |
| `docs/adr-two-layer-capability-architecture.md` | Apps |
| `docs/adr-three-layer-capability-architecture.md` | Apps |
| `Makefile` target `validate-kyverno-policies` | Apps |
| `.github/workflows/gitops-validate.yml` kyverno-smoke + capability-index-check jobs | Apps |
| `.github/workflows/docs-lint.yml` capability-reference-fresh job | Apps |

### Apps Repository Contract

- **Location**: `github.com/devobagmbh/talos-platform-apps` (public).
- **Consumption mechanism**: OCI artifact (symmetry with Base) AND
  Git-source for Day-2 Multi-Source-Application. Apps publishes its
  own OCI artifact at `ghcr.io/devobagmbh/talos-platform-apps:vA.B.C`
  on tag push.
- **Day-0 use** is optional. Apps are platform offerings, not
  cluster-bring-up dependencies; workstation `make day0` only needs
  Substrate.
- **Apps-side PNI ownership**: PNI registry, Kyverno policies,
  capability scripts, capability ADRs all live in Apps. Apps owns
  the `kubelet-serving` and `platform.io/*` vocabulary.

### Consumer-side adapter

- Pin files: `.base-version` (existing) + new `.apps-version`.
  Independent bumps, two drift-checks.
- Multi-Source-Application gains a third source named `apps`:
  - `base` → `talos-platform-base`, path `kubernetes/base/<comp>/`
  - `apps` → `talos-platform-apps`, path `kubernetes/base/<comp>/`
  - `cluster` → consumer repo, path `kubernetes/overlays/<tenant>/<comp>/`
- AppProject `sourceRepos` lists all three repo URLs.
- `scripts/check-base-pin-drift.sh` extended (or new
  `check-apps-pin-drift.sh` added) to verify Day-0 / Day-2 pin
  parity for both Base and Apps.

### Release sequencing

The currently-planned v0.6.0 release bundles: Talos 5-axis path as
default, PNI policy name/behaviour mismatch cleanup, kebab-case
hardware-feature migration, and CycloneDX 1.6 SBOM start. v0.6.0 is
gated on Talos Phase-3 completion plus ≥2-week soak per
`talos/RELEASE-NOTES-v0.5.2.md`.

The Substrate split lands **after** v0.6.0:

1. **v0.6.0** — coordinated breaking release as already planned.
   PNI-cleanup work done in this repo (will then migrate to Apps as
   part of the split).
2. **v1.0.0** — Substrate split. Major bump signals breaking change
   to consumers. Apps repository starts at v0.1.0.

This sequencing is more expensive than bundling (PNI-cleanup gets
touched twice — once here in v0.6.0, once during the migration to
Apps) but preserves the v0.6.0 release stage that consumer cluster
repos have already begun preparing for.

### Migration plan

Six phases, ordered:

1. **Phase 0** — this ADR merges as `accepted`.
2. **Phase 1** — `devobagmbh/talos-platform-apps` initialized with
   LICENSE, README, AGENTS.md skeleton, `.github/workflows/` skeleton.
   OCI-publish workflow mirrors Base's.
3. **Phase 2** — `git filter-repo` on a clone of this repo extracts
   `kubernetes/base/infrastructure/**` (excluding `argocd` and
   `cert-approver`), `policies/conftest/` exclusions, capability
   scripts, capability docs and ADRs, Kyverno CI jobs.
   Filtered tree pushed as initial commit history to Apps repo.
4. **Phase 3** — in Base: PR removes the same paths, strips PNI
   labels from `kubernetes/bootstrap/cilium/values.yaml`, ablates
   AGENTS.md §PNI sections plus PNI-related Hard Constraints,
   removes `make validate-kyverno-policies`, prunes
   `gitops-validate.yml` jobs. Bumps Base to v1.0.0.
5. **Phase 4** — consumer cluster repos update Multi-Source-App
   configurations to three sources, add `.apps-version`, extend
   drift-check tooling. Documented in consumer-side upgrade guide
   (not in this repo).
6. **Phase 5** — open GitHub issues triaged with labels
   `migrate-to-apps` or `stays-in-base` **before** the cut; after
   v1.0.0 lands, issues labeled `migrate-to-apps` are moved via
   `gh issue transfer` to the Apps repo.

### Out-of-scope for this ADR

- The Apps repository's internal architecture (component grouping,
  AppProject layout, OCI tarball contents).
- Consumer cluster repo migration tooling.
- Whether `node-feature-discovery` should later be re-promoted to
  Substrate if a future Talos release deprecates the dual-namespace
  convention.
- Whether Cilium itself should later split into Substrate
  (CNI core) + Apps (Cilium Tetragon-equivalent enterprise features).

### Consequences

- **Positive**:
  - Repository name matches contents — `talos-platform-base` carries
    only substrate.
  - Independent lifecycle for Talos/Cilium/ArgoCD bumps vs. app
    updates; Base-tag frequency drops markedly.
  - Validation surface in Base shrinks to bootstrap + Talos checks.
  - Multi-Cluster offering choice is no longer constrained by Base
    coupling.
  - OCI artifact contents stay unchanged — what is published today
    is exactly what Base ships post-split.

- **Negative**:
  - One-time migration cost: filter-repo, 3-source Multi-Source-App
    rewrite per consumer repo, two pin-drift checks instead of one.
  - PNI cleanup work in v0.6.0 must be redone (re-applied) when PNI
    migrates to Apps in v1.0.0.
  - Two repositories to release-manage instead of one.

- **Follow-up**:
  - Author Apps-side `AGENTS.md` covering PNI Hard Constraints,
    capability vocabulary, and Kyverno-validation workflow.
  - Author consumer-side upgrade guide for the v1.0.0 cut.
  - Build the `talos-platform-apps` OCI-publish pipeline.

## Pros and Cons of the Options

### Option 1 — Status quo

- Pro: zero migration work; existing tooling and ADRs unchanged.
- Con: repo-name-vs-content mismatch persists; lock-step bumps
  continue to inflate Base release frequency; multi-cluster
  offering divergence stays blocked.

### Option 2 — Substrate-only Base + Apps repo (chosen)

- Pro: aligns repo structure with existing artifact boundary;
  cleanest Substrate definition; independent lifecycles; smallest
  Base maintenance surface long-term.
- Con: one-time migration cost; doubles release-management surface;
  3-source Multi-Source-App configuration per consumer.

### Option 3 — Intermediate (PNI in Base, other offerings in Apps)

- Pro: keeps shared label-vocabulary contract in Base; Apps repos
  consume vocabulary without forking it.
- Con: violates Substrate definition (PNI is not a runnability
  prerequisite); PNI Kyverno enforcement engine must follow PNI →
  Kyverno also in Base → unclear what else "shared contract" means.

### Option 4 — 3-way split (Substrate / PNI / Apps)

- Pro: maximally clean conceptual separation.
- Con: over-engineered for one solo maintainer + two consumer
  clusters; triple release-management surface; consumer
  Multi-Source-App grows to four sources.

## Validation

The decision is **wrong** if any of the following surface within
12 months of v1.0.0:

- Consumer cluster repos consistently need to vendor PNI vocabulary
  into Base instead of consuming it from Apps → indicates the
  Substrate cut was too aggressive and PNI was load-bearing for
  cluster-bring-up after all.
- Substrate-tag bumps frequency does not measurably drop versus the
  pre-split baseline → indicates the lifecycle-decoupling driver
  was wrong.
- Pin-drift incidents between Base and Apps versions cause more
  than two production-impacting failures → indicates the two-pin
  model needs replacement (e.g., Apps-pins-Base compatibility range).

The mechanical check that confirms it stays correct: after v1.0.0
lands, `find kubernetes/base/infrastructure -maxdepth 1 -mindepth 1
-type d | wc -l` returns ≤2 (only `argocd` and `cert-approver`).
If any other directory appears, this ADR was violated by a later
PR.

Re-review date: **2027-05-26** (12 months post-decision) or upon
the next Talos major-version release, whichever is sooner.

## Links

- `docs/adr-multi-repo-platform-split.md` — the partially-superseded
  predecessor. Sections retained: 3-Repo-Role model, OCI consumption,
  Day-0 / Day-2 distinction, pin-drift discipline.
- `.ci-oci-tarball-include.txt` — the existing artifact-boundary
  allowlist that motivates this ADR.
- `talos/RELEASE-NOTES-v0.5.2.md` — Talos Phase-3 soak requirement
  that gates v0.6.0 and therefore this split's v1.0.0.
- `UPGRADING.md` §`v0.6.0` (forthcoming) — the planned coordinated
  release that precedes this split.
- siderolabs/talos#8523 — Sidero Labs declined native kubelet-serving
  CSR auto-approval ("not planned"), grounding cert-approver's
  Substrate placement.
- `docs/adr-template.md` — MADR 3.0 template followed here.
