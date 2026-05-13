# Glossary

Cross-domain vocabulary used throughout this repo. Cite this file when a
term first appears in a new doc or ADR; do not redefine in place. New terms
land here first; AGENTS.md §"Key Terms" carries a curated subset for
agent-context loading and links back here for the full definition.

## Capability-first networking (PNI v2)

- **PNI** — Platform Network Interface. Kyverno + Cilium contract for
  capability-mediated cross-namespace access. v2 is capability-first,
  namespace-anchored, instance-aware. See
  [`capability-architecture.md`](capability-architecture.md) and the
  [Producer/Consumer Symmetry ADR](adr-capability-producer-consumer-symmetry.md).

- **Capability** — stable, tool-agnostic identifier for a platform service
  (`monitoring-scrape`, `tls-issuance`, `cnpg-postgres`, …). Source of truth:
  `kubernetes/base/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml`.
  Capabilities are the *stable interface*; tools are *swappable implementations*.

- **Instanced capability** — capability whose data plane is partitioned per
  tenant (`cnpg-postgres.<cluster>`, `vault-secrets.<mount>`). Requires the
  `.<inst>` suffix on consumer and producer labels. Audit policy
  `pni-instanced-suffix-required-audit` flags missing suffixes via
  `PolicyReport` without blocking.

- **Producer / Consumer symmetry** — for every capability, five label /
  annotation sites carry the contract: producer namespace, producer pod,
  producer Service (annotations), consumer namespace, consumer pod. See
  [`AGENTS.md`](../AGENTS.md) §"PNI v2 Capability-First Contract" for the
  authoritative table.

- **Namespace-anchored trust** — a `platform.io/capability-provider.<cap>`
  label on a workload is valid only if the workload's namespace carries the
  matching `platform.io/provide.<cap>: "true"` label. There is no central
  tool-signature whitelist; trust derives from the namespace declaration.

- **Capability-selector** — CCNP `endpointSelector` expressed as
  `platform.io/capability-{provider,consumer}.<cap>` rather than
  `app.kubernetes.io/name: <tool>`. Capability-selectors make tool swaps
  (e.g. Prometheus → Victoria-Metrics) a label move on the pod template,
  not a CCNP edit.

- **Reserved label / reserved annotation** — keys in the `platform.io/`
  namespace that MUST NOT be set by tenant manifests. Settable only by base
  manifests or by RBAC-gated producer charts. Enforced by Kyverno policies
  `pni-reserved-labels-enforce` / `pni-reserved-annotations-enforce`.

- **CCNP / CNP** — `CiliumClusterwideNetworkPolicy` /
  `CiliumNetworkPolicy`. File naming: `ccnp-*.yaml` (cluster-scoped) /
  `cnp-*.yaml` (namespace-scoped).

- **PolicyReport** — Kyverno audit-mode output stream. Visible via
  `kubectl get policyreport -A`; used by audit-only policies such as
  `pni-instanced-suffix-required-audit`.

## GitOps & cluster lifecycle

- **AppProject** — ArgoCD RBAC boundary. Scopes the repos and namespaces an
  Application is allowed to deploy to. Bootstrap-time resources; see
  `kubernetes/bootstrap/argocd/root-project.yaml.tmpl`.

- **Multi-Source Application** — ArgoCD `Application` with `spec.sources[]`
  carrying two entries: the base repo (this repo, vendored via OCI) and the
  consumer cluster repo. ArgoCD reconciles the merged tree.

- **Sync-wave** — ArgoCD annotation `argocd.argoproj.io/sync-wave: <N>`
  controlling deploy order. Conventional bands in this base:
  `-2` PNI registry, `-1` AppProjects, `0` infrastructure, `1` apps.

- **OCI artifact** — immutable, signed tarball of this base. Published to
  `ghcr.io/nosmoht/talos-platform-base:<tag>` on every `v*` git-tag push,
  with cosign keyless signature and SLSA build provenance. Consumed via
  `oras pull`. See [`oci-artifact-verification.md`](oci-artifact-verification.md).

- **Rendered Manifests Pattern** — Akuity-named pattern (KubeCon EU 2024).
  Helm/Kustomize render output is committed to git and consumed as
  ArgoCD `directory`-source. Eliminates render-time drift between developer
  workstations and the cluster. See [`rendered-manifests.md`](rendered-manifests.md).

## Talos & node lifecycle

- **Schematic** — Talos Image Factory spec embedding system extensions
  into an installer image. Consumer-repo input lives in
  `talos/talos-factory-schematic*.yaml`; base-side schematic IDs are
  recorded in `talos/*.schematic-ids.mk`.

- **DRBD** — Distributed Replicated Block Device. LINSTOR's replication
  layer for persistent storage. Configured per-node via the `drbd.yaml`
  Talos patch.

## Two-layer capability vocabulary (proposed)

- **Layer A — Tool-Capability-Index** — static catalog of every functional
  capability the platform offers, with implementation alternatives and swap
  classes. Source: [`platform-capability-index.yaml`](platform-capability-index.yaml).
  Not consumed at runtime; read at build time by render and lint scripts.
  Status: proposed; tooling pending. See
  [`adr-two-layer-capability-architecture.md`](adr-two-layer-capability-architecture.md).

- **Layer B — PNI Capability Registry** — runtime registry consumed by
  Kyverno for admission decisions. Subset of Layer A by `id`. Lives at
  `kubernetes/base/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml`.

## Repo conventions

- **Hard constraint** — universal cluster invariant codified in
  [`AGENTS.md`](../AGENTS.md) §"Hard Constraints". Enforced server-side by
  the `hard-constraints-check` PR check.

- **Tool-agnostic safety invariant** — a non-cluster-invariant rule (e.g.
  "no secrets in committed files") enforced by gitleaks, pre-commit, or
  another scanning gate.

- **Right altitude** — the lightest-sufficient form for an automation
  artifact (description → declaration → CLI line → shell helper → code).
  See the [`right-altitude.md` rule](https://github.com/Nosmoht/claude-config/blob/main/rules/right-altitude.md)
  in the harness plugin for the test.

## See also

- [`AGENTS.md`](../AGENTS.md) — canonical SOT; this glossary is its dictionary
- [`capability-architecture.md`](capability-architecture.md) — the *why* behind PNI v2
- [`pni-cookbook.md`](pni-cookbook.md) — the *how* (manifest recipes)
- [`adr-capability-producer-consumer-symmetry.md`](adr-capability-producer-consumer-symmetry.md) — decision record
