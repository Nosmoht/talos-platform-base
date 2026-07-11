---
type: workflow
title: Issue Lifecycle
description: The GitHub issue state machine — status labels, guarded transitions via the issue-state script, and the session-start ritual that gates agent work.
tags: [issues, workflow, labels, agents]
timestamp: 2026-07-11
sources:
  - scripts/issue-state.sh
  - AGENTS.md
  - .github/ISSUE_TEMPLATE/spec.yml
  - .github/ISSUE_TEMPLATE/bug.yml
---

# Issue Lifecycle

GitHub Issues are the primary work entry point. The lifecycle is a label-driven
state machine; `scripts/issue-state.sh` implements the transitions
deterministically over the `gh` CLI, and only the `status: ready` label
authorizes an agent (or human) to begin work.

## States (labels)

Both issue templates (`.github/ISSUE_TEMPLATE/spec.yml` and
`.github/ISSUE_TEMPLATE/bug.yml`) apply `status: triage` at creation; the bug
template additionally applies `type: bug`. The script-managed states are:

| Label | Meaning |
| --- | --- |
| `status: triage` | New issue, being assessed; not authorized for work. |
| `status: ready` | Spec complete — **authorizes** pickup. |
| `status: in-progress` | Claimed; the assignee identifies the working session. |
| `status: needs-review` | Implementation done, awaiting review. |
| `status: blocked` | Halted with a reason comment; needs human untangling. |
| closed (no `status:` label) | Done — `close` strips all `status:` labels. |

The spec template also carries a triage-time risk dropdown with the values
`risk: low`, `risk: medium`, `risk: high`.

## Readiness gate

Promotion from `status: triage` to `status: ready` is a human triage act, not
a script transition. The spec template carries seven sections (Intent,
Context, Acceptance Criteria, Non-Goals, Boundaries, Verification,
Dependencies) — the first six are mandatory form fields, Dependencies is
optional — and states that issues with empty or vague Acceptance Criteria
"will be returned to the author" — Acceptance Criteria must be
machine-checkable predicates (file exists, command exits 0, regex matches),
and the Verification section lists the concrete commands an evaluator runs.

## Transitions — `scripts/issue-state.sh`

Each subcommand checks guards before writing; a failed guard exits `1` with a
diagnostic. Common flags: `--dry-run` (print `gh` commands without executing)
and `--repo OWNER/REPO` (override auto-detection). Exit codes: `0` success,
`1` precondition not met, `2` `gh`/network failure, `3` usage error.

| Subcommand | Transition | Guards |
| --- | --- | --- |
| `claim <N>` | `status: ready` → `status: in-progress` + assign caller | issue OPEN, has `status: ready`, zero assignees |
| `handoff <N>` | `status: in-progress` → `status: needs-review` | has `status: in-progress`, caller is the assignee |
| `release <N>` | `status: in-progress` → `status: ready`, clear assignee | has `status: in-progress`, caller is the assignee |
| `block <N> "<reason>"` | any → `status: blocked` + reason comment | issue exists (idempotent) |
| `close <N> --pr <ref>` | `status: needs-review` → closed, all `status:` labels removed, comment with PR reference | has `status: needs-review` |

`claim` is race-aware: after writing, it re-reads the issue. If more than
one assignee landed, it rolls the claim back (`status: ready` restored,
assignee removed, `status: in-progress` removed) and exits `1` — the loser
releases and retries. If the caller is missing from the final assignees
entirely, it exits `1` as a verification failure WITHOUT rollback (any
label flip already written stays in place).

```bash
# Typical agent flow
scripts/issue-state.sh claim 138
# ... implement, verify, push ...
scripts/issue-state.sh handoff 138
scripts/issue-state.sh close 138 --pr "https://github.com/Nosmoht/talos-platform-base/pull/142"
```

## Session-start ritual

Per `AGENTS.md` §Session-Start Ritual, every session begins by scanning the
backlog via the `github` MCP server:

1. `mcp__github__list_issues(state="open", labels=["status: ready"])`
2. `mcp__github__list_issues(state="open", labels=["status: in-progress"])`
3. **Status gate**: only the `status: ready` label authorizes work to begin.

An issue that is merely open, or still `status: triage`, is not authorization —
the gate is the label.

## Script vs MCP

- **Reads** (backlog listing, issue bodies) go through the `github` MCP
  server — see [mcp-setup](mcp-setup.md) for the server configuration.
- **State transitions** go through `scripts/issue-state.sh` — it encodes the
  guards, race handling, and label hygiene that ad-hoc `gh issue edit` or MCP
  writes would skip. The script is harness-agnostic (Claude Code, Codex CLI,
  or manual invocation) and backend-swappable at the subcommand interface:
  only the `gh` calls inside each subcommand would change for another tracker.

## Related

- Release flow after an issue closes: [release-process](release-process.md).
- Runner targets used in issue verification: [tasks reference](../reference/tasks.md).
