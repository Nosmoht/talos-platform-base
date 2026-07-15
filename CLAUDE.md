# talos-platform-base — Claude Code Memory

@AGENTS.md

## Claude-Code-Specific Additions

This base commits exactly the OpenSpec-GENERATED tool artifacts — the
`.claude/` skill/command trees and their Codex counterpart, regenerable via
`task spec:update` (decision:
[`knowledge/decisions/0014-ship-ai-tool-artifacts.md`](knowledge/decisions/0014-ship-ai-tool-artifacts.md)).
The `/opsx:*` slash commands they provide drive the spec-driven workflow
(`AGENTS.md §Spec-Driven Development`). Never hand-edit those trees.

Everything else is unchanged: treat `AGENTS.md` as the canonical, tool-agnostic
source of operational knowledge (`openspec/config.yaml` carries only a pointer
to it, never parallel truth), and assume no hand-authored rule, hook, subagent,
or other skill is available unless you have verified it in the working repo.
Such primitives come from an external harness that an individual operator or a
consumer cluster repo chooses to install; they live and are versioned outside
this base.

### Context Architecture

- All shared operational knowledge lives in `AGENTS.md`.
- This file kept minimal — adds only Claude-Code-specific notes.
- After incidents in a consumer cluster: update `AGENTS.md` §Hard Constraints
  here only if the lesson is universal across clusters; environment-specific
  postmortems stay in the consumer repo.

### Documentation entry-points

For the deep reference, read [`knowledge/index.md`](knowledge/index.md) —
the OKF v0.1 knowledge bundle (architecture, reference, workflows,
decisions, glossary). The root-level orientation files
([`README.md`](README.md), [`ARCHITECTURE.md`](ARCHITECTURE.md),
[`AGENTS.md`](AGENTS.md), [`CONTRIBUTING.md`](CONTRIBUTING.md),
[`SECURITY.md`](SECURITY.md), [`UPGRADING.md`](UPGRADING.md),
[`MAINTAINERS.md`](MAINTAINERS.md)) cover governance and scope; everything
else lives under `knowledge/` and is indexed there.

Claude-Code-specific: read this file plus AGENTS.md before editing. Any
additional runtime context (path-scoped rules, hooks, subagents) comes from an
externally installed harness, not from this base — verify it is present in the
working repo before relying on it.
