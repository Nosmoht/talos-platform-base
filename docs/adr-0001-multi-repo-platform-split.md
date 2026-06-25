---
status: accepted
id: base:multi-repo-platform-split
date: 2026-05-18
date-history:
  - 2026-04-27 initial
  - 2026-04-29 amended (consumption mechanism)
  - 2026-05-18 amended (de-named consumer repos for cluster-agnostic phrasing)
deciders:
  - platform-maintainer
consulted:
  - gitops-operator (consumption-mechanism design)
informed: []
supersedes:
  - implicit single-repo assumption that pre-dated this base
---

# ADR: Multi-Repo Platform Split for Multi-Cluster Reuse

## Context

The platform began as a single-cluster GitOps tree. Adding a second cluster
(different IPs, FQDNs, OIDC issuers, SOPS keys) exposed three problems with
the single-overlay / single-repo model:

1. Cluster identity (IPs, FQDNs, OIDC issuers, SOPS keys) was hardcoded in
   dozens of files under `kubernetes/overlays/<cluster>/**`, making
   add-cluster a copy-paste exercise that drifts over time.
2. Claude Code tooling (skills, agents, hooks, scripts) lived in `.claude/**`
   of the same monolith and could not be reused across clusters without
   manual sync.
3. Cross-cluster trust and multi-cluster service-consumption required an
   explicit federation model before any further architectural commitment.

## Decision

Split the platform into **three logically distinct repository roles**:

| Role | Visibility | Contents |
|---|---|---|
| **Platform base** (this repo, `talos-platform-base`) | public | Talos templates, substrate infrastructure Helm bases (Talos + Cilium + ArgoCD + cert-approver), ArgoCD bootstrap (parameterised), `AGENTS.md` core constraints. **NO cluster identity.** Published as an OCI artifact at `ghcr.io/<owner>/talos-platform-base:vX.Y.Z` on tag push. (The capability-network contract has since dissolved out of the base — see [`adr-0004-substrate-only-base.md`](adr-0004-substrate-only-base.md).) |
| **Claude-Code harness** | private | `.claude/{skills,agents,rules,references,hooks}`. Acts as a Claude-Code plugin for every consumer cluster repo. |
| **Consumer cluster repo** (one per cluster) | per-cluster choice | `kubernetes/overlays/<cluster>/**`, `talos/nodes/`, `cluster.yaml` (cluster-identity SOT at repo root), cluster-specific ADRs. Consumes base via OCI artifact + harness via `claude plugin install`. |

**Per-cluster trust model**: each cluster is a self-rooted peer. No shared
CA, no shared SOPS key, no shared Vault. Per-cluster break-glass kubeconfig.

**Per-cluster service consumption**: all capabilities are cluster-local. The
"shared platform service" class is intentionally empty. The
capability-network labels (the contract has since dissolved out of the base
per [`adr-0004-substrate-only-base.md`](adr-0004-substrate-only-base.md)) remain
cluster-scoped.

**Tooling distribution**: Claude Code's plugin mechanism (project-level
`claude plugin install` + global `~/.claude/plugins/`) is the canonical
path. Codex CLI is no longer a primary support target for skills; Codex
users must clone the harness repo separately and symlink — manual fallback
only.

## Component Classification — Consumer-in-Base / Backend-in-Overlay

> **Superseded** by [`adr-0004-substrate-only-base.md`](adr-0004-substrate-only-base.md):
> the base is now substrate-only (Talos + Cilium + ArgoCD + cert-approver), the
> Platform-Consumer/Backend-Provider split below moved into the
> `talos-platform-apps` catalog, and the capability-network contract dissolved
> out of the base into apps-CI Conftest + consumer-side Kyverno. The section is
> preserved for decision history; it does not describe the current base.

Phase 1 of the original migration classified components by directory
location (`kubernetes/base/` = base, `kubernetes/overlays/` = consumer).
That criterion left six backend providers parked in `base/` and three
platform-generic components parked in overlay-only. The corrected
classification, adopted as a binding architectural principle:

> Authentication and Observability are platform concerns and belong in base.
> Their backend storage is a tenant choice and belongs in overlay.

| Layer | Lives in | Examples |
|---|---|---|
| **Platform Consumer** (the *what*) | this base | Dex (auth), Loki / Grafana / kube-prometheus-stack / Tetragon / Alloy (observability) |
| **Backend Provider** (the *how*) | per-cluster repo overlay | cloudnative-pg → Postgres for Dex; minio → S3 for Loki; redis-operator / strimzi-kafka-operator → tenant workloads |

PNI is the contract layer between the two. Base consumers declare a
capability via PNI labels (`platform.io/consume.cnpg-postgres`,
`platform.io/consume.s3-object`); the consumer overlay binds the capability
to a concrete backend (cnpg cluster + secret, MinIO tenant + credentials).

**Corollary on PNI itself**: PNI is platform architecture and stays in
base. The RFC1918 except-lists in PNI egress CCNPs are the standard "don't
reach private networks" guard, generic across all clusters. The default
Kubernetes ServiceCIDR API IP allowed in
`ccnp-pni-controlplane-egress-consumer-egress.yaml` is generic across
Talos-default clusters.

**Corollary on hardcoded backend coordinates**: no file under
`kubernetes/base/` may contain a concrete backend coordinate (Service DNS,
endpoint URL, credential secret name). The historical violation in
`kubernetes/base/infrastructure/loki/values.yaml` (hardcoded S3 endpoint)
was fixed by moving the endpoint into the consumer overlay's Helm-values
patch.

This principle governs all future component-classification decisions: the
question is never "where does the directory live today?" but "is this the
platform's *what* or the tenant's *how*?"

## Consumption Mechanism — Day-0 Bootstrap vs. Day-2 Reconciliation

Consumer cluster repos must consume this base at two distinct phases with
fundamentally different runtime contexts:

- **Day-0 (bootstrap)** — workstation-only, no in-cluster ArgoCD yet.
  Local `make` / `talosctl` / `kubectl` / `helm` calls read base files
  directly from the local filesystem (e.g. `talos/patches/common.yaml`,
  `kubernetes/bootstrap/argocd/root-application.yaml.tmpl`,
  `kubernetes/base/infrastructure/argocd/values.yaml`). Any consumption
  mechanism that requires a running ArgoCD is by definition unusable here.
- **Day-2 (reconciliation)** — ArgoCD is alive in the target cluster and
  reconciles app manifests against base + cluster overrides.

**Day-0 mechanism**: OCI artifact published to `ghcr.io`, fetched by the
consumer repo's `make day0` into a gitignored `vendor/base/` directory.

- On every tag push (`vX.Y.Z`) on this base, the GitHub Action
  `.github/workflows/oci-publish.yml` packages the repo and pushes it as an
  OCI artifact to `ghcr.io/<owner>/talos-platform-base:vX.Y.Z` (and
  `:latest`).
- Each consumer cluster repo carries a single-line `.base-version` file —
  the SOT for the base pin in that consumer repo.
- The consumer's `scripts/bootstrap-base.sh` reads `.base-version`, runs
  `oras pull` into `vendor/base/`, records the resolved version in
  `vendor/base/.version`, and marks the tree read-only. Idempotent.
- The consumer repo's top-level `Makefile` is a thin delegator that invokes
  `make -C vendor/base/talos gen-configs ENV=$(PWD)/cluster.yaml ...`. A
  `make day0` meta-target chains `bootstrap-base → gen-configs → apply →
  argocd-install → argocd-bootstrap` for new-cluster setup.
  > **Superseded (2026-06-02):** the `make -C vendor/base/talos gen-configs`
  > Day-0 mechanism described here was removed. Talos provisioning is now the
  > OpenTofu module `tofu/modules/talos-cluster` — see
  > [`adr-0006-opentofu-cluster-lifecycle.md`](adr-0006-opentofu-cluster-lifecycle.md).
  > The OCI-vendor + `.base-version` pin mechanism above is unchanged.
- `oras` CLI is a hard prerequisite on the workstation.

**Day-2 mechanism**: ArgoCD Multi-Source Application. Each component
Application carries `spec.sources[]` with two entries:

- Source `base`: `repoURL: github.com/<owner>/talos-platform-base.git`,
  `targetRevision: vX.Y.Z`, with a named `ref: base` and a path into
  `kubernetes/base/infrastructure/<comp>/`.
- Source `cluster`: `repoURL` of the consumer cluster repo,
  `targetRevision: main`, path into `kubernetes/overlays/<tenant>/<comp>/`,
  with `helm.valueFiles` referencing `$base/values.yaml` plus
  `values-<tenant>.yaml` from the consumer repo.

The component's AppProject lists **both** repo URLs in `sourceRepos`.

Pin-drift between Day-0 (`.base-version`) and Day-2
(`spec.sources[base].targetRevision`) is checked in the consumer repo's CI
via `scripts/check-base-pin-drift.sh`. The check fails the build when the
two pins diverge.

### Alternatives considered (consumption mechanism)

| Alternative | Why rejected |
|---|---|
| **Git submodule** in consumer repo pointing at base | Solves Day-0 + Day-2 with one mechanism, but operational drag (`git submodule update --init` discipline, version bumps in two commits, ArgoCD `submoduleEnabled` global toggle). Not automatable cleanly. |
| **Kustomize remote URL** (`resources: [https://.../base.git/...?ref=vX]`) | Solves Day-2 cleanly but **fails Day-0**: `make`, `helm`, `yq` all read filesystem paths, not HTTP. Talos `make gen-configs` cannot consume a remote URL. |
| **Convention: parallel local clones** (`BASE_REPO_PATH ?= ../talos-platform-base`) | Solves Day-0 via convention but the consumer repo is no longer self-containing — `git clone` alone is insufficient, the user must clone two repos in correct relative paths. Documentation burden, no enforcement. |
| **Git subtree** | Base files committed into consumer repo. Self-containing, but version bumps are merge-conflict-prone, repo size grows linearly with each bump, and `git log` mixes consumer + base history. |
| **Tarball download via curl + checksum** (no OCI) | Functionally identical to OCI but without the registry's content-addressable storage and signing primitives. Weaker integrity guarantees, no built-in version listing (`oras repo tags`). |

## Consequences

### Positive

- Cluster identity isolation matches per-cluster security boundary
  (per-repo SOPS, per-repo CI access, per-repo PR review).
- Skills / agents / hooks update once in the harness repo → every consumer
  cluster benefits.
- Adding cluster N+1 = scaffold from a consumer-repo template + per-cluster
  identity; no base-repo edits.
- Aligns with industry GitOps-fleet patterns (Flux fleet-infra, ArgoCD
  ApplicationSet-of-cluster-repos).
- Decoupling resolves the long-standing cross-cluster trust and
  multi-cluster service-consumption questions with a concrete trust +
  consumption decision (cluster-local only; no shared platform services).

### Negative

- Up to three repo roles for two-plus clusters = coordination overhead.
  Bumping a base component requires: (1) tag-push on this base (CI
  auto-publishes OCI artifact), (2) `.base-version` bump + Argo
  `targetRevision` bump in each consumer repo. A CI drift check in each
  consumer enforces both pins move together.
- AGENTS.md / CLAUDE.md split requires careful import structure (host
  repo `@`-imports plugin docs).
- Codex CLI user experience for skills degrades to "manual symlink".
- `oras` CLI is a new prerequisite on every consumer-repo developer
  workstation. `make` validates its presence at bootstrap-base time with a
  clear install hint (`brew install oras`).

### Neutral / Out of scope

- ArgoCD ApplicationSet-of-clusters not adopted — each cluster runs its
  own ArgoCD pointing at its own repo. Manageable for ≤5 clusters.
- Service mesh federation explicitly NOT planned.
- Cross-cluster Vault / Dex / SSO explicitly NOT planned.
- Cluster-specific edge-ingress topologies stay in the consumer repo that
  needs them. No "shared edge ingress" capability across clusters.

## Alternatives Considered (high-level)

| Alternative | Why rejected |
|---|---|
| Multiple overlays in one repo (`overlays/<cluster-a>/`, `overlays/<cluster-b>/`) | Too many cluster-specific concerns leak through the cluster boundary; access control is per-repo on GitHub. |
| ArgoCD ApplicationSet-of-clusters in one repo | Same coupling concerns. ApplicationSet pattern works well at scale (≥10 clusters); for 2 clusters it's overkill and bundles unrelated trust domains. |
| Helm values branching per cluster | Doesn't address Talos node-config separation, SOPS-key per-cluster, or PR-review boundary. |
| Keep monolith, defer multi-cluster | Postpones the problem; the second-cluster bringup blocks on this anyway. |

## References

- ArgoCD ApplicationSet patterns —
  https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/
- Flux fleet-infra reference architecture —
  https://github.com/fluxcd/flux2-multi-tenancy

## Migration history

The initial migration from the pre-split monolith to this 3-role layout
completed in 2026-04 (Phases 1, 1.5, 2, 3A, 3B). Phase-by-phase migration
details lived in the original 2026-04-29 revision of this ADR. They have
been removed here because every reference to a specific consumer cluster
repo name belongs in that consumer repo, not in the cluster-agnostic base.
The decision itself, its rationale, and its consequences remain.
