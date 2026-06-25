# Harness Plugin Integration

**Audience:** maintainers of the Claude Code harness
plugin and contributors who want to know what this base expects from
the Claude Code primitives layer.

**Status:** **specification** for a plugin repository that does not yet
exist publicly. Everything in this file describes a *contract* the plugin
should satisfy; subagents and rules listed as "shipped" describe the
maintainer's local workflow, not a public artefact. See
[`vision.md`](vision.md) §"Harness plugin (separate repo)" for the honest
read on what is in flight today.

This base ships **no `.claude/`** by design; the harness plugin is the
runtime executor for Claude-Code primitives. This file states the contract
from the base's side.

## Why this exists

`CLAUDE.md` enforces: this base ships no `.claude/` directory. That
is deliberate — tool-namespaced directories belong to the runtime
that consumes them. Claude Code is *one* runtime; Codex CLI reads
`AGENTS.md` directly and needs no `.claude/`. Putting rules,
subagents, or hooks under `.claude/` here would couple repo SOT to
Claude Code, which is a Right-Altitude violation (see CLAUDE.md
operating rules in any consumer repo).

But the substrate workflow **does** benefit from Claude-Code
primitives — path-scoped rule loading, edit-time subagents, PreToolUse
hooks. Those primitives live in the harness plugin
(separate repo). Consumer cluster repos install the plugin, which then
provides edit-time intelligence for this base when working in a
consumer-cluster checkout.

## What the harness plugin SHOULD provide

### Path-scoped auto-loaded rules

Rule frontmatter `paths:` accepts glob patterns only (not content
predicates); content-trigger logic lives in the rule prose, which the
loaded LLM applies when it sees the matching token in-context.

Recommended rule files the plugin should ship — `paths:` is a glob:

| Rule | `paths:` glob | Purpose |
|---|---|---|
| `talos-hard-constraints.md` | `tofu/modules/talos-cluster/**/*.tf` | Reinforces "no `debugfs=off`", "no `secureboot` installer" |
| `gateway-api-only.md` | `kubernetes/**/*.yaml` | Catches `kind: Ingress` insertions before CI rejects them |
| `endpointslices-only.md` | `kubernetes/**/*.yaml` | Catches `kind: Endpoints` (deprecated since K8s 1.33.0) |

### Subagents

Existing in the harness plugin today (CLAUDE.md §Subagents lists them):

| Subagent | Purpose | When dispatched |
|---|---|---|
| `gitops-operator` | renders, validates, suggests minimal kustomize patches | edit-time on `kubernetes/**` |
| `talos-sre` | reviews Talos patches against hard constraints, knows boot-loop traps | edit-time on `tofu/modules/talos-cluster/**` |
| `platform-reliability-reviewer` | reviews PR diffs touching substrate manifests, Talos patches, ADRs | explicit on PR-prep |
| `researcher` | open-ended cross-repo research with web budgets | explicit |
| `builder-implementer` / `builder-evaluator` | issue-implementation pipeline (see issue-workflow.md) | `/implement-issue` skill |

### PreToolUse hooks

| Hook | Trigger | Action |
|---|---|---|
| `block-secret-paths` | any file Read/Edit/Write | reject paths matching common secret patterns (already provided by harness) |
| `block-sensitive-content` | Write/Edit content | reject literal home paths, RFC1918 IPs in committed docs |
| `forbidden-kinds-pre-check` | Edit/Write on `kubernetes/**` | warn on `kind: Ingress`, `kind: Endpoints` before kubectl-render time |

### Skills (user-invocable slash commands)

These are nice-to-have, not load-bearing:

| Skill | Purpose |
|---|---|
| `/render-component` | runs `kubectl kustomize --enable-helm` on a chosen component and pipes through `yq` for label inspection |

## What this base ships independent of the plugin

These primitives live in this base directly because they are tool-agnostic:

- `AGENTS.md` — canonical SOT readable by any agent.
- `CLAUDE.md` — minimal Claude Code addenda (imports AGENTS.md).
- `docs/` — full documentation tree (this is plain Markdown, runtime-agnostic).
- `scripts/` — cluster-agnostic validation and helper shell, callable from any harness or none.
- Validation pipeline: `Makefile` + `scripts/` + `.github/workflows/`.

Anything Claude-Code-specific (rules, subagents, hooks, skills) is the plugin's responsibility.

## Cross-tool neutrality of AGENTS.md

`AGENTS.md` in this repo is intentionally readable by:

- **Claude Code** — via `@AGENTS.md` import in `CLAUDE.md` and harness-plugin auto-load.
- **Codex CLI / OpenAI Codex** — native primary file per [agents.md spec](https://agents.md).
- **Cursor / Amp / Factory / Jules** — same agents.md convention.

Do not introduce Claude-Code-specific syntax (`<claude:tool>`, etc.)
into `AGENTS.md`. Tool-specific extensions go in `CLAUDE.md` and never
in `AGENTS.md`.

## Versioning the plugin against this base

When the plugin ships a new rule that depends on a specific base
contract version (e.g. a new substrate hard constraint or Layer-C
label rule), the plugin's rule frontmatter should pin
`requires-base-version: ">=v0.X.0"`. The plugin's loader can then skip
rules whose pin does not match the vendored base.

The pinning mechanism is forward-looking.

## See also

- [`AGENTS.md`](../AGENTS.md) — tool-agnostic SOT
- [`CLAUDE.md`](../CLAUDE.md) — Claude Code addenda
- [`docs/adr-0004-substrate-only-base.md`](./adr-0004-substrate-only-base.md) — the substrate-only base scope
- [`agents.md spec`](https://agents.md) — canonical agent-instruction file format
- The harness plugin — a separate Claude Code plugin repository (not part of this base)
