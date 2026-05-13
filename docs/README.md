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
- [`primitive-contract.md`](primitive-contract.md) — Diagnostics primitive output schema (harness-plugin contract).
- [`rendered-manifests.md`](rendered-manifests.md) — render-pipeline factual description (stages, chart.lock.yaml schema, workflow commands).

## Explanation — discussion-level material

- [`capability-architecture.md`](capability-architecture.md) — canonical explanation of the capability-first contract (why namespace-anchored trust, why instance scoping, why no central tool-signature whitelist).
- [`adr-multi-repo-platform-split.md`](adr-multi-repo-platform-split.md) — why base + consumer is a two-repo split.
- [`adr-capability-producer-consumer-symmetry.md`](adr-capability-producer-consumer-symmetry.md) — why capability-first, namespace-anchored trust, instance scoping.
- [`adr-two-layer-capability-architecture.md`](adr-two-layer-capability-architecture.md) — separating Tool-Capability-Index (Layer A) from PNI network-trust registry (Layer B). **Status: proposed.**
- [`harness-plugin-integration.md`](harness-plugin-integration.md) — what the `kube-agent-harness` Claude Code plugin should provide for this base.

## Authoring conventions

- New ADRs: `adr-<short-kebab-id>.md` with MADR-style frontmatter.
- New how-to docs: `<topic>-<recipe>.md`, lead with audience + companion-doc table.
- Auto-generated files carry the comment block `<!-- GENERATED FILE — DO NOT EDIT BY HAND. -->` at the top.
- Diagrams: Mermaid in fenced ` ```mermaid ` blocks (renders natively in GitHub).
- Linting: `markdownlint` config at repo root (`.markdownlint.yaml`); CI gate in `.github/workflows/docs-lint.yml`.

## See also

- [`../README.md`](../README.md) — orientation
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md) — C4 L1/L2 view
- [`../AGENTS.md`](../AGENTS.md) — tool-agnostic SOT
