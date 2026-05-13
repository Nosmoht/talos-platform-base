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

### Knowledge Map

For deep dives, read these in addition to AGENTS.md:

- **Capability-first architecture** → `docs/capability-architecture.md`
- **PNI cookbook (manifest recipes)** → `docs/pni-cookbook.md`
- **Per-capability catalogue (auto-generated)** → `docs/capability-reference.md`
- **Architecture overview (C4)** → `ARCHITECTURE.md`
- **Architecture decisions** → `docs/adr-*.md`
- **Issue lifecycle + state machine** → `docs/issue-workflow.md`
- **OCI verification** → `docs/oci-artifact-verification.md`
- **Harness-plugin integration (rules / subagents this base benefits from)** → `docs/harness-plugin-integration.md`
- **Security disclosure + supply chain** → `SECURITY.md`
- **Upgrade guide for vendored bases** → `UPGRADING.md`
