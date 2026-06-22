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

- [`oci-artifact-verification.md`](oci-artifact-verification.md) — cosign + SLSA verification recipe.
- [`mcp-setup.md`](mcp-setup.md) — install + verify MCP server binaries.
- [`issue-workflow.md`](issue-workflow.md) — GitHub issue lifecycle, state-machine, and `bin/issue-state.sh` adapter.
- [`release-automation.md`](release-automation.md) — conventional-commit-driven releases (semantic-release + approval gate), one-time GitHub App + Environment setup.

## Reference — look-up material (factual, dry)

- [`platform-hardware-features.yaml`](platform-hardware-features.yaml) — Layer C: atomic hardware-features registry; the SoT consumed by the talos-cluster composition model and the `check-provisioning-catalog-refs.sh` / `lint-hardware-features.sh` gates.
- [`primitive-contract.md`](primitive-contract.md) — Diagnostics primitive output schema (harness-plugin contract).
- [`rendered-manifests.md`](rendered-manifests.md) — render-pipeline factual description (stages, chart.lock.yaml schema, workflow commands).
- [`glossary.md`](glossary.md) — cross-domain vocabulary (GitOps, Talos, hardware-capability terms, repo conventions). Cite this when a term first appears in a new doc.
- [`openssf-best-practices.md`](openssf-best-practices.md) — self-assessment against the [OpenSSF Best Practices](https://www.bestpractices.dev/) Passing-level criteria; source of truth for the external enrolment form.

## Explanation — discussion-level material

- [`day-zero-pattern.md`](day-zero-pattern.md) — the three layers (Talos + bundled K8s + CNI / ArgoCD self-bootstrap / ArgoCD-reconciled day-two), the five documented `kubectl apply` exceptions, and the end-to-end command sequence.
- [`adr-multi-repo-platform-split.md`](adr-multi-repo-platform-split.md) — why base + consumer is a two-repo split.
- [`adr-substrate-only-base.md`](adr-substrate-only-base.md) — why the base ships substrate only (Talos + Cilium + ArgoCD + cert-approver) and the remaining components move to a separate `talos-platform-apps` repo at v2.0.0 (the substrate-only ablation; v1.0.0 shipped earlier without it). Carries the four-cluster realisability validation of the substrate thesis. **Status: accepted.** Supersedes parts of the Multi-Repo ADR.
- [`adr-opentofu-cluster-lifecycle.md`](adr-opentofu-cluster-lifecycle.md) — why the OpenTofu module `tofu/modules/talos-cluster` is the sole Talos cluster-lifecycle path, replacing the removed `Makefile.lib`/argv-print/5-axis generator. Per-class architecture (incl. arm64/SBC overlay) + per-class/per-node patches; the per-class node model is since amended by [`adr-node-capability-composition.md`](adr-node-capability-composition.md) (per-node `image` + composed `hardware_capabilities`). **Status: accepted.** Supersedes the Shared Render Artifact ADR.
- [`adr-task-runner-consolidation.md`](adr-task-runner-consolidation.md) — why there is **no** wholesale Make→go-task migration: most Makefile targets serve components that exit under `base:substrate-only-base` (18→catalog, 2→dissolve), so the Makefile dissolves *with* the substrate split. Standalone work is only the ArgoCD bootstrap double-install fix + a one-package `gnumake`-in-devbox seam bridge; survivors fold into the Taskfile at Phase-3 ablation. **Status: accepted.**
- [`adr-shared-render-artifact.md`](adr-shared-render-artifact.md) — why a single shared render artifact (`argv-print.sh` `EMIT=content`) was the cross-frontend source of truth for per-node Talos config. **Status: superseded** by the OpenTofu cluster-lifecycle ADR (the `make`/argv-print frontend is removed; the OpenTofu provider renders config directly).
- [`adr-three-layer-capability-architecture.md`](adr-three-layer-capability-architecture.md) — the Layer C Hardware Features Registry (the substrate-resident capability layer). Documents the Composite Capability Convention, NFD placement, and the Workload-class out-of-scope deferral. **Status: accepted.**
- [`adr-node-capability-composition.md`](adr-node-capability-composition.md) — the γ' model: replaces the monolithic per-node `class` with composable capabilities → atomic features carrying a `provisions:` bundle, so a node can hold any *set* of capabilities (storage + compute + GPU) without 2^N hand-authored classes. Moves boot kernel args into the Image Factory schematic (the v1.10+ UKI correctness fix) and auto-emits the Layer-C labels. **Status: accepted.** Implements the γ' model the Three-Layer ADR / issue #61 anticipated.
- [`adr-composition-logic-placement.md`](adr-composition-logic-placement.md) — open question scoping *where* the capability-composition resolution logic should execute: bespoke HCL `locals` in `composition.tf` (status quo) vs a portable pre-processing layer vs a hybrid. Records the tofu-executor lock-in + #99-anti-pattern tension surfaced reviewing PR #135; decision deferred with a hybrid recommendation + a concrete revisit trigger. **Status: proposed.**
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
