# talos-platform-base — Claude Code Memory

@AGENTS.md

## Claude-Code-Specific Additions

This base ships no `.claude/` directory. The `kube-agent-harness` plugin
provides Claude-Code-specific rules, hooks, subagents, and skills. Consumer
cluster repos either install the plugin or vendor a subset of its primitives
into their own `.claude/` tree.

### Path-Scoped Auto-Loaded Rules

Domain rules with `paths:` frontmatter live in the harness plugin. When
present in a consumer repo (via plugin install), Claude Code auto-loads them
at edit time matching the path glob.

### Hooks

PreToolUse / PostToolUse hooks are plugin-shipped; they activate when the
plugin is installed in a consumer repo. The base itself enforces nothing at
edit time.

### Subagents

Subagents (`gitops-operator`, `talos-sre`, `platform-reliability-reviewer`,
`researcher`, `builder-implementer`, `builder-evaluator`) are plugin-shipped.
This base ships none.

### Context Architecture

- All shared operational knowledge lives in `AGENTS.md`.
- This file kept minimal — adds only Claude-Code-specific notes.
- After incidents in a consumer cluster: update `AGENTS.md` §Hard Constraints
  here only if the lesson is universal across clusters; environment-specific
  postmortems stay in the consumer repo.

### Documentation entry-points

For the full Diátaxis-organised index, read [`docs/README.md`](docs/README.md).
The root-level orientation files ([`README.md`](README.md),
[`ARCHITECTURE.md`](ARCHITECTURE.md), [`AGENTS.md`](AGENTS.md),
[`CONTRIBUTING.md`](CONTRIBUTING.md), [`SECURITY.md`](SECURITY.md),
[`UPGRADING.md`](UPGRADING.md), [`MAINTAINERS.md`](MAINTAINERS.md)) cover
governance and scope; everything else lives under `docs/` and is indexed there.

Claude-Code-specific: read this file plus AGENTS.md before editing; the
harness plugin (when installed in a consumer repo) supplies the rest of the
runtime context (path-scoped rules, hooks, subagents).
