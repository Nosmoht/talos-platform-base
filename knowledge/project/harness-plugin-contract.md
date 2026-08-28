---
type: project
title: Harness Plugin Contract
description: The contract this base expects a Claude Code harness plugin to satisfy, stated from the base's side.
tags: [project, harness]
generated: { by: human:nosmoht, at: "2026-08-28T00:00:00Z" }
migrated_from: docs/harness-plugin-integration.md (deleted in the OKF migration; see git history)
sources:
  - resource: CLAUDE.md
  - resource: AGENTS.md
  - resource: contracts/primitive-contract.md
---

# Harness Plugin Contract

**Audience:** maintainers of the Claude Code harness
plugin and contributors who want to know what this base expects from
the Claude Code primitives layer.

**Status:** **specification** for a plugin repository that does not yet
exist publicly. Everything in this file describes a *contract* the plugin
should satisfy; subagents and rules listed as "shipped" describe the
maintainer's local workflow, not a public artefact. See
[vision](vision.md) §"Harness plugin (separate repo)" for the honest
read on what is in flight today.

This base ships **no hand-authored `.claude/` primitives** by design; the
harness plugin is the runtime executor for Claude-Code primitives. Since
[ADR-0014](../decisions/0014-ship-ai-tool-artifacts.md) the base DOES commit
the tool-GENERATED OpenSpec integration trees (`.claude/commands/opsx/`,
`.claude/skills/openspec-*/` and the Codex counterpart, regenerable via
`task spec:update`) — that reversal does not change this contract, which
concerns hand-authored rules, subagents, and hooks. This file states the
contract from the base's side.

## Why this exists

`AGENTS.md` §Tool Notes enforces (the statement moved out of `CLAUDE.md`
on 2026-08-28): this base ships no hand-authored Claude-Code
primitives (the committed OpenSpec-generated trees per ADR-0014 are the
sole, regenerable exception). That is deliberate — tool-namespaced
runtime content belongs to the runtime that consumes it. Claude Code is
*one* runtime; Codex CLI reads `AGENTS.md` directly. Putting hand-authored
rules, subagents, or hooks under `.claude/` here would couple repo SOT to
Claude Code, which is a Right-Altitude violation (see CLAUDE.md
operating rules in any consumer repo).

But the substrate workflow **does** benefit from Claude-Code
primitives — path-scoped rule loading, edit-time subagents, PreToolUse
hooks. Those primitives live in the harness plugin
(separate repo). Consumer cluster repos install the plugin, which then
provides edit-time intelligence for this base when working in a
consumer-cluster checkout.

## Machine-read primitive contract — path change (breaking for the harness)

The Phase-1a primitive output contract — the machine-read file that
`area: claude-harness` skills resolve at runtime to obtain
`schema_version` — lives at `contracts/primitive-contract.md`.

> [2026-07-11 verification] **Breaking coordination point for the harness
> maintainer.** The contract file moved out of the docs tree to
> `contracts/primitive-contract.md` (commit `ce82014`,
> "refactor(schemas)!: relocate machine-consumed contracts out of docs/").
> The harness skills resolve the contract via a hardcoded repo-relative
> path. The in-repo lookup snippet (contract §B1) was repointed to
> `contracts/primitive-contract.md` in this migration; the EXTERNAL
> harness's own `CONTRACT_PATH` still needs the same repoint. Because the
> lookup is fail-closed, an unrepointed harness resolves no contract and
> its Phase-1a primitives return `PRECONDITION_NOT_MET`
> ("contract not readable") until it is updated.

## What the harness plugin SHOULD provide

### Path-scoped auto-loaded rules

Rule frontmatter `paths:` accepts glob patterns only (not content
predicates); content-trigger logic lives in the rule prose, which the
loaded LLM applies when it sees the matching token in-context.

Recommended rule files the plugin should ship — `paths:` is a glob:

| Rule | `paths:` glob | Purpose |
| --- | --- | --- |
| `talos-hard-constraints.md` | `tofu/modules/talos-cluster/**/*.tf` | Reinforces "no `debugfs=off`", "no `secureboot` installer" |
| `gateway-api-only.md` | `kubernetes/**/*.yaml` | Catches `kind: Ingress` insertions before CI rejects them |
| `endpointslices-only.md` | `kubernetes/**/*.yaml` | Catches `kind: Endpoints` (deprecated since K8s 1.33.0) |

### Subagents

Subagents the plugin should provide (contract items — none ship with this
base, and availability in any given harness varies):

| Subagent | Purpose | When dispatched |
| --- | --- | --- |
| `gitops-operator` | renders, validates, suggests minimal kustomize patches | edit-time on `kubernetes/**` |
| `talos-sre` | reviews Talos patches against hard constraints, knows boot-loop traps | edit-time on `tofu/modules/talos-cluster/**` |
| `platform-reliability-reviewer` | reviews PR diffs touching substrate manifests, Talos patches, ADRs | explicit on PR-prep |
| `researcher` | open-ended cross-repo research with web budgets | explicit |
| `builder-implementer` / `builder-evaluator` | issue-implementation pipeline via the `/implement-issue` skill | `/implement-issue` skill |

> [2026-07-11 verification] The original claim "CLAUDE.md §Subagents lists
> them" is stale — `CLAUDE.md` no longer contains a §Subagents section; it
> states the base ships no hand-authored Claude-Code primitives (since
> ADR-0014 the OpenSpec-generated trees are committed). Of the table
> above, `researcher`, `builder-implementer` and `builder-evaluator` are
> observable in the maintainer's harness at verification time;
> `gitops-operator`, `talos-sre` and `platform-reliability-reviewer` were
> not observed and should be read as contract items, not shipped ones.

### PreToolUse hooks

| Hook | Trigger | Action |
| --- | --- | --- |
| `block-secret-paths` | any file Read/Edit/Write | reject paths matching common secret patterns (already provided by harness) |
| `block-sensitive-content` | Write/Edit content | reject literal home paths, RFC1918 IPs in committed docs |
| `forbidden-kinds-pre-check` | Edit/Write on `kubernetes/**` | warn on `kind: Ingress`, `kind: Endpoints` before kubectl-render time |

### Skills (user-invocable slash commands)

These are nice-to-have, not load-bearing:

| Skill | Purpose |
| --- | --- |
| `/render-component` | runs `kubectl kustomize --enable-helm` on a chosen component and pipes through `yq` for label inspection |

## What this base ships independent of the plugin

These primitives live in this base directly because they are tool-agnostic:

- `AGENTS.md` — canonical SOT readable by any agent.
- `CLAUDE.md` — minimal Claude Code addenda (imports AGENTS.md).
- `knowledge/` — the knowledge bundle (plain Markdown, runtime-agnostic).
- `contracts/` — machine-consumed contracts (see the path-change section above).
- `scripts/` — cluster-agnostic validation and helper shell, callable from any harness or none.
- Validation pipeline: `Taskfile.yml` + `scripts/` + `.github/workflows/`.

> [2026-07-11 verification] The original list named the `Makefile` and the
> docs tree. The `Makefile` was retired at v3.0.0 in favour of go-task
> (see [Makefile retirement](../decisions/0012-makefile-retirement.md)); a
> deprecation stub remains for one release cycle. The docs tree is replaced
> by the `knowledge/` bundle.

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

- `AGENTS.md` — tool-agnostic SOT
- `CLAUDE.md` — Claude Code addenda
- [Substrate-only base](../decisions/0004-substrate-only-base.md) — the substrate-only base scope
- `contracts/primitive-contract.md` — the machine-read primitive output contract
- [agents.md spec](https://agents.md) — canonical agent-instruction file format
- The harness plugin — a separate Claude Code plugin repository (not part of this base)
