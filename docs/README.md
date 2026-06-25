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
- [`adr-0001-multi-repo-platform-split.md`](adr-0001-multi-repo-platform-split.md) — why base + consumer is a two-repo split.
- [`adr-0004-substrate-only-base.md`](adr-0004-substrate-only-base.md) — why the base ships substrate only (Talos + Cilium + ArgoCD + cert-approver) and the remaining components move to a separate `talos-platform-apps` repo at v2.0.0 (the substrate-only ablation; v1.0.0 shipped earlier without it). Carries the four-cluster realisability validation of the substrate thesis. **Status: accepted.** Supersedes parts of the Multi-Repo ADR.
- [`adr-0006-opentofu-cluster-lifecycle.md`](adr-0006-opentofu-cluster-lifecycle.md) — why the OpenTofu module `tofu/modules/talos-cluster` is the sole Talos cluster-lifecycle path, replacing the removed `Makefile.lib`/argv-print/5-axis generator. Per-class architecture (incl. arm64/SBC overlay) + per-class/per-node patches; the per-class node model is since amended by [`adr-0009-node-capability-composition.md`](adr-0009-node-capability-composition.md) (per-node `image` + composed `hardware_capabilities`). **Status: accepted.** Supersedes the Shared Render Artifact ADR.
- [`adr-0012-makefile-retirement.md`](adr-0012-makefile-retirement.md) — why the `Makefile` is retired and **go-task is the single runner**: Phase-3 ablation (#140) landed, firing the prior ADR's own convergence trigger, so the survivor targets fold into `Taskfile.yml` under a namespaced scheme (`tofu:*` / `gitops:*` / `bootstrap:*` / `cluster:*` / `supply-chain:*` / `mcp:*` / `dev:*`), `chart-pull` + `grafana-dashboards-check` are dropped, and `devbox.json` gains `yq-go` + `gettext` (not `gnumake`). Corrects the prior ADR's per-target table (`validate-gitops`/`render-*` in fact survive) and retires its `gnumake`-bridge predicate. **Status: accepted.** Supersedes the Task-Runner-Consolidation ADR.
- [`adr-0008-task-runner-consolidation.md`](adr-0008-task-runner-consolidation.md) — why there was **no** wholesale Make→go-task migration *at the time*: most Makefile targets served components that exit under `base:substrate-only-base` (18→catalog, 2→dissolve), so the Makefile would dissolve *with* the substrate split, survivors folding into the Taskfile at Phase-3 ablation. **Status: superseded** by the Makefile-Retirement ADR (Phase-3 has now landed; the fold + retirement executed there, and two premises — the per-target table and the `gnumake` bridge — were corrected).
- [`adr-0005-shared-render-artifact.md`](adr-0005-shared-render-artifact.md) — why a single shared render artifact (`argv-print.sh` `EMIT=content`) was the cross-frontend source of truth for per-node Talos config. **Status: superseded** by the OpenTofu cluster-lifecycle ADR (the `make`/argv-print frontend is removed; the OpenTofu provider renders config directly).
- [`adr-0003-three-layer-capability-architecture.md`](adr-0003-three-layer-capability-architecture.md) — the Layer C Hardware Features Registry (the substrate-resident capability layer). Documents the Composite Capability Convention, NFD placement, and the Workload-class out-of-scope deferral. **Status: accepted.**
- [`adr-0009-node-capability-composition.md`](adr-0009-node-capability-composition.md) — the γ' model: replaces the monolithic per-node `class` with composable capabilities → atomic features carrying a `provisions:` bundle, so a node can hold any *set* of capabilities (storage + compute + GPU) without 2^N hand-authored classes. Moves boot kernel args into the Image Factory schematic (the v1.10+ UKI correctness fix) and auto-emits the Layer-C labels. **Status: accepted.** Implements the γ' model the Three-Layer ADR / issue #61 anticipated.
- [`adr-0010-composition-logic-placement.md`](adr-0010-composition-logic-placement.md) — open question scoping *where* the capability-composition resolution logic should execute: bespoke HCL `locals` in `composition.tf` (status quo) vs a portable pre-processing layer vs a hybrid. Records the tofu-executor lock-in + #99-anti-pattern tension surfaced reviewing PR #135; decision deferred with a hybrid recommendation + a concrete revisit trigger. **Status: proposed.**
- [`adr-0002-namespace-ownership-rendered-manifests.md`](adr-0002-namespace-ownership-rendered-manifests.md) — which ArgoCD Application owns `Namespace` resources under the rendered-manifests pattern (choreography amended after a second ownership-conflict incident). **Status: accepted.**
- [`harness-plugin-integration.md`](harness-plugin-integration.md) — what the Claude Code harness plugin should provide for this base.
- [`vision.md`](vision.md) — forward-looking statements (v1.X / v2.X). Aspiration, **not roadmap and not commitments**. Cite this file when extracting hypothetical-future statements from operative docs.

## Authoring conventions

- New ADRs: copy [`adr-template.md`](adr-template.md), rename to `adr-NNNN-<short-kebab-id>.md` (take the next free number), fill in every [MADR 3.0](https://adr.github.io/madr/) frontmatter field. The frontmatter is canonical; do not duplicate `Status:` / `Date:` lines in the body.
- New how-to docs: `<topic>-<recipe>.md`, lead with audience + companion-doc table.
- Auto-generated files carry the comment block `<!-- GENERATED FILE — DO NOT EDIT BY HAND. -->` at the top.
- Diagrams: Mermaid in fenced ` ```mermaid ` blocks (renders natively in GitHub).
- Linting: `markdownlint` config at repo root (`.markdownlint.yaml`); CI gate in `.github/workflows/docs-lint.yml`.

## ADR Index (numeric)

All 12 ADRs in chronological decision order (`0001..0012`):

- [`adr-0001-multi-repo-platform-split.md`](adr-0001-multi-repo-platform-split.md)
- [`adr-0002-namespace-ownership-rendered-manifests.md`](adr-0002-namespace-ownership-rendered-manifests.md)
- [`adr-0003-three-layer-capability-architecture.md`](adr-0003-three-layer-capability-architecture.md)
- [`adr-0004-substrate-only-base.md`](adr-0004-substrate-only-base.md)
- [`adr-0005-shared-render-artifact.md`](adr-0005-shared-render-artifact.md)
- [`adr-0006-opentofu-cluster-lifecycle.md`](adr-0006-opentofu-cluster-lifecycle.md)
- [`adr-0007-cluster-yaml-sot.md`](adr-0007-cluster-yaml-sot.md)
- [`adr-0008-task-runner-consolidation.md`](adr-0008-task-runner-consolidation.md)
- [`adr-0009-node-capability-composition.md`](adr-0009-node-capability-composition.md)
- [`adr-0010-composition-logic-placement.md`](adr-0010-composition-logic-placement.md)
- [`adr-0011-substrate-hard-constraints.md`](adr-0011-substrate-hard-constraints.md)
- [`adr-0012-makefile-retirement.md`](adr-0012-makefile-retirement.md)

## See also

- [`../README.md`](../README.md) — orientation
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — C4 L1/L2 view
- [`../AGENTS.md`](../AGENTS.md) — tool-agnostic SOT
