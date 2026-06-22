# Glossary

Cross-domain vocabulary used throughout this repo. Cite this file when a
term first appears in a new doc or ADR; do not redefine in place. New terms
land here first; AGENTS.md §"Key Terms" carries a curated subset for
agent-context loading and links back here for the full definition.

## GitOps & cluster lifecycle

- **AppProject** — ArgoCD RBAC boundary. Scopes the repos and namespaces an
  Application is allowed to deploy to. Bootstrap-time resources; see
  `kubernetes/bootstrap/argocd/root-project.yaml.tmpl`.

- **Multi-Source Application** — ArgoCD `Application` with `spec.sources[]`
  carrying two entries: the base repo (this repo, vendored via OCI) and the
  consumer cluster repo. ArgoCD reconciles the merged tree.

- **Sync-wave** — ArgoCD annotation `argocd.argoproj.io/sync-wave: <N>`
  controlling deploy order. Conventional bands in this base:
  `-1` AppProjects, `0` infrastructure, `1` apps.

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
  (and an optional SBC board overlay) into an installer image. Derived per
  node by the `tofu/modules/talos-cluster` module from the node's `image`
  (baseline `extensions` + `overlay` + `architecture`) unioned with the
  `extensions` + `extraKernelArgs` of the provisioning profiles its
  `hardware_capabilities` resolve to; identical nodes are content-hash-deduped
  to one schematic, and resolved schematic IDs are exposed via the module's
  `schematic_ids` output.

- **DRBD** — Distributed Replicated Block Device. LINSTOR's replication
  layer for persistent storage. Provisioned as a Talos system extension via
  the base `drbd` provisioning profile, selected by a node's
  `storage-replicated` hardware capability (the profile contributes
  `siderolabs/drbd` to the node's schematic extensions).

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
- [`adr-substrate-only-base.md`](adr-substrate-only-base.md) — why the base ships substrate only (Talos + Cilium + ArgoCD + cert-approver)
- [`adr-three-layer-capability-architecture.md`](adr-three-layer-capability-architecture.md) — the Layer C hardware-features registry that survives in the substrate
