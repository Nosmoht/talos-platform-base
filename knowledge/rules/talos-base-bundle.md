---
type: Rule
rule_id: talos-base-bundle
title: Bundle Conventions
description: Repo-specific OKF bundle conventions layered on top of the built-in maintenance rules, rendered into the AGENTS.md managed block.
rule_summary: Repo-specific bundle conventions on top of the built-in maintenance rules.
tags: [okf, maintenance, conventions]
timestamp: 2026-08-23
sources:
  - resource: Taskfile.yml
  - resource: CONTRIBUTING.md
---

# Bundle Conventions

The conventions this bundle layers on top of OKF v0.1 and the built-in
`openknowledge` maintenance rules. This document is the source of truth for
them; `index.md` carries the rationale and points here.

Two authoring constraints for this file, both learned from the renderer:

1. **One physical line per bullet.** The renderer emits only a bullet's first
   line, so a wrapped bullet reaches `AGENTS.md` truncated mid-sentence.
   `MD013` is disabled repo-wide, so long lines are fine here.
2. **No markdown links, only inline code spans.** The bullets are rendered
   verbatim into `AGENTS.md` at the repository root. A bundle-relative link is
   correct inside the bundle and broken one directory up, and the offline link
   gate checks the root markdown files too.

## Instructions

- Use the closed `type` vocabulary: `architecture`, `reference`, `workflow`, `decision`, `glossary`, `project`, `Rule`. Add a new type by editing this list and `knowledge/index.md` in the same change. `Rule` is capitalized because the CLI requires that spelling, not as a naming pattern to copy.
- Set `timestamp` to the date of the last substantive verification, not the last typo fix, and keep `sources` pointing at the repo-relative paths the concept was derived from.
- Re-verify a concept when a change to one of its `sources` lands inside what the concept describes — not merely because a listed file was touched. A green validation run proves link and schema health, never freshness.
- Omit `sources` on `decision` concepts: an ADR records a decision rather than deriving from source files. Their field contract, including `status`, `id`, `deciders`, and `supersedes`, lives in `knowledge/decisions/index.md`.
- Link relatively inside the bundle, and cite anything outside it as an inline code span rather than a markdown link: `.openknowledge.toml` raises `link-target` to error, so an escaping link fails validation.
- Validate with `task knowledge:validate`, which runs `openknowledge validate` plus the offline link gate. Run `task knowledge:rules-check` as well after touching `knowledge/rules/`.
- Invoke `openknowledge` through the `knowledge:*` task targets, never bare: the version pin and the telemetry opt-out both live in `Taskfile.yml`, and a bare run skips both silently. Where a bare run is unavoidable, prefix it with `OPENKNOWLEDGE_TELEMETRY=off`.
- Record bundle changes in `knowledge/log.md`, one bullet per changed concept under today's date. User-facing changes belong in the root `CHANGELOG.md`. The two files have separate audiences and do not mirror each other.
- Regenerate the `AGENTS.md` managed block with `task knowledge:rules-apply` after changing this file. Hand-editing the block fails `task knowledge:rules-check`.
