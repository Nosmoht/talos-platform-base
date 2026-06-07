# docs/

Reference documentation for `talos-platform-base`. The repo root carries
the orientation files (README, ARCHITECTURE, CONTRIBUTING, SECURITY,
UPGRADING, AGENTS.md, CLAUDE.md); this directory carries the deeper
material.

Organised loosely along [Diátaxis](https://diataxis.fr/) quadrants —
tutorial / how-to / reference / explanation.

## Tutorial — "learn by doing"

- [`tutorial-first-consumer-cluster.md`](tutorial-first-consumer-cluster.md) — minimal 30-minute walk-through of vendoring, verifying, and rendering a base release.

## How-to — task-oriented recipes

- [`pni-cookbook.md`](pni-cookbook.md) — concrete consumer + producer manifest patterns.
- [`oci-artifact-verification.md`](oci-artifact-verification.md) — cosign + SLSA verification recipe.
- [`mcp-setup.md`](mcp-setup.md) — install + verify MCP server binaries.
- [`issue-workflow.md`](issue-workflow.md) — GitHub issue lifecycle, state-machine, and `bin/issue-state.sh` adapter.

## Reference — look-up material (factual, dry)

- [`capability-reference.md`](capability-reference.md) — per-capability catalogue (**auto-generated**, do not hand-edit).
- [`platform-capability-index.md`](platform-capability-index.md) — Layer A: Tool-Capability-Index, generated from `platform-capability-index.yaml`.
- [`platform-hardware-features.md`](platform-hardware-features.md) — Layer C: atomic hardware features registry, generated from `platform-hardware-features.yaml`.
- [`primitive-contract.md`](primitive-contract.md) — Diagnostics primitive output schema (harness-plugin contract).
- [`rendered-manifests.md`](rendered-manifests.md) — render-pipeline factual description (stages, chart.lock.yaml schema, workflow commands).
- [`glossary.md`](glossary.md) — cross-domain vocabulary (PNI, capability terms, GitOps, Talos, repo conventions). Cite this when a term first appears in a new doc.
- [`openssf-best-practices.md`](openssf-best-practices.md) — self-assessment against the [OpenSSF Best Practices](https://www.bestpractices.dev/) Passing-level criteria; source of truth for the external enrolment form.

## Explanation — discussion-level material

- [`capability-architecture.md`](capability-architecture.md) — canonical explanation of the capability-first contract (why namespace-anchored trust, why instance scoping, why no central tool-signature whitelist).
- [`day-zero-pattern.md`](day-zero-pattern.md) — the three layers (Talos + bundled K8s + CNI / ArgoCD self-bootstrap / ArgoCD-reconciled day-two), the five documented `kubectl apply` exceptions, and the end-to-end command sequence.
- [`adr-multi-repo-platform-split.md`](adr-multi-repo-platform-split.md) — why base + consumer is a two-repo split.
- [`adr-substrate-only-base.md`](adr-substrate-only-base.md) — why the base ships substrate only (Talos + Cilium + ArgoCD + cert-approver) and the remaining components move to a separate `talos-platform-apps` repo at v1.0.0. Carries the four-cluster realisability validation of the substrate thesis. **Status: accepted.** Supersedes parts of the Multi-Repo ADR.
- [`adr-opentofu-cluster-lifecycle.md`](adr-opentofu-cluster-lifecycle.md) — why the OpenTofu module `tofu/modules/talos-cluster` is the sole Talos cluster-lifecycle path, replacing the removed `Makefile.lib`/argv-print/5-axis generator. Per-class architecture (incl. arm64/SBC overlay) + per-class/per-node patches. **Status: accepted.** Supersedes the Shared Render Artifact ADR.
- [`adr-task-runner-consolidation.md`](adr-task-runner-consolidation.md) — why the developer workflow consolidates on `go-task` + `devbox` and retires the `Makefile` (the OpenTofu cutover only migrated the `tofu/` subtree; the kustomize/Kyverno/bootstrap/MCP targets and the devbox-without-make seam remain). Fixes the ArgoCD bootstrap double-install in-flight. **Status: accepted.** Completes the OpenTofu-cluster-lifecycle migration.
- [`adr-shared-render-artifact.md`](adr-shared-render-artifact.md) — why a single shared render artifact (`argv-print.sh` `EMIT=content`) was the cross-frontend source of truth for per-node Talos config. **Status: superseded** by the OpenTofu cluster-lifecycle ADR (the `make`/argv-print frontend is removed; the OpenTofu provider renders config directly).
- [`adr-capability-producer-consumer-symmetry.md`](adr-capability-producer-consumer-symmetry.md) — why capability-first, namespace-anchored trust, instance scoping.
- [`adr-three-layer-capability-architecture.md`](adr-three-layer-capability-architecture.md) — adds Layer C (Hardware Features Registry) alongside Layer A (Tool-Capability-Index) and Layer B (PNI network-trust). Documents the Composite Capability Convention, NFD placement, and the Workload-class out-of-scope deferral. **Status: accepted.** Supersedes the Two-Layer ADR.
- [`adr-two-layer-capability-architecture.md`](adr-two-layer-capability-architecture.md) — separating Tool-Capability-Index (Layer A) from PNI network-trust registry (Layer B). **Status: superseded** by the Three-Layer ADR; body preserved for decision history.
- [`adr-namespace-ownership-rendered-manifests.md`](adr-namespace-ownership-rendered-manifests.md) — which ArgoCD Application owns `Namespace` resources under the rendered-manifests pattern (choreography amended after a second ownership-conflict incident). **Status: accepted.**
- [`harness-plugin-integration.md`](harness-plugin-integration.md) — what the `kube-agent-harness` Claude Code plugin should provide for this base.
- [`vision.md`](vision.md) — forward-looking statements (v1.X / v2.X). Aspiration, **not roadmap and not commitments**. Cite this file when extracting hypothetical-future statements from operative docs.

## Authoring conventions

- New ADRs: copy [`adr-template.md`](adr-template.md), rename to `adr-<short-kebab-id>.md`, fill in every [MADR 3.0](https://adr.github.io/madr/) frontmatter field. The frontmatter is canonical; do not duplicate `Status:` / `Date:` lines in the body.
- New how-to docs: `<topic>-<recipe>.md`, lead with audience + companion-doc table.
- Auto-generated files carry the comment block `<!-- GENERATED FILE — DO NOT EDIT BY HAND. -->` at the top.
- Diagrams: Mermaid in fenced ` ```mermaid ` blocks (renders natively in GitHub).
- Linting: `markdownlint` config at repo root (`.markdownlint.yaml`); CI gate in `.github/workflows/docs-lint.yml`.

## See also

- [`../README.md`](../README.md) — orientation
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — C4 L1/L2 view
- [`../AGENTS.md`](../AGENTS.md) — tool-agnostic SOT
