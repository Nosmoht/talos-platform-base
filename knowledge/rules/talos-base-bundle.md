---
type: Rule
rule_id: talos-base-bundle
title: Bundle Conventions
description: Repo-specific OKF bundle conventions layered on top of the built-in maintenance rules, rendered into the AGENTS.md managed block.
rule_summary: Repo-specific bundle conventions on top of the built-in maintenance rules.
tags: [okf, maintenance, conventions]
generated: { by: human:nosmoht, at: "2026-08-23T00:00:00Z" }
verified:
  - { by: human:nosmoht, at: "2026-08-23T00:00:00Z" }
sources:
  - resource: Taskfile.yml
  - resource: CONTRIBUTING.md
---

# Bundle Conventions

The conventions this bundle layers on top of OKF v0.2 and the built-in
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
- Record provenance as `generated: { by, at }` on every concept that derives from `sources`. `by` is REQUIRED inside `generated` and is an actor — `human:<id>`, `process:<id>`, or `<producer>/<version>`; this bundle uses `human:nosmoht`. The v0.1 `timestamp` key is retired and nothing under `knowledge/` may carry it.
- Write every date as a quoted ISO 8601 datetime, `"2026-08-23T00:00:00Z"`. A date alone is rejected in both spellings, bare and quoted; the midnight is padding for a record that has day precision, not an observed time, and the quotes keep the value a string for parsers that would otherwise type it.
- Set `generated.at` to the date the concept's content last meaningfully changed, and add a `verified` entry for the date someone read the concept against its `sources` and confirmed it. They are separate on purpose: content changes without re-confirmation, and facts are re-confirmed without an edit. Omit either rather than guess a date.
- Add a `verified` entry only for a confirmation that actually happened, and never one older than `generated.at`. Any `human:<id>` entry makes the concept human-reviewed to an OKF consumer and nothing flags a stale one, so an invented or carried-over entry is a false claim in machine-readable form. Authoring a concept is `generated`, never `verified`.
- Write every `sources` entry as a mapping whose `resource` key holds the repo-relative path the concept was derived from, one per line, as `- resource: Taskfile.yml`. A bare string is a v0.1 leftover; `okf-0.2-metadata` is at error, so one bare entry fails validation. Nothing validates the path itself, so check a new one by hand.
- Re-verify a concept when a change lands inside what the concept describes — not merely when a file listed in its `sources` was touched. A green validation run proves link and schema health, never freshness.
- Give `decision` concepts `decided` instead: no `sources`, so no `generated` and no `verified` either — an ADR records a decision rather than deriving from source files. Their field contract, including `status`, `decided`, `id`, `deciders`, and `supersedes`, lives in `knowledge/decisions/index.md`.
- Use the OKF lifecycle vocabulary in `status`: `stable`, `draft`, `deprecated`; an absent `status` means `stable`. The MADR words stay in ADR bodies, in `history:` entries and in the `decisions/index.md` group headings, which are record.
- Link relatively inside the bundle, and cite anything outside it as an inline code span rather than a markdown link: `.openknowledge.toml` raises `link-target` to error, so an escaping link fails validation. Its rule keys are quoted, because an unquoted `okf-0.2-metadata` is read as a dotted key and kills the whole config.
- Validate with `task knowledge:validate`, which runs `openknowledge validate` plus the offline link gate. Run `task knowledge:rules-check` as well after touching `knowledge/rules/`.
- Invoke `openknowledge` through the `knowledge:*` task targets, never bare: the version pin and the telemetry opt-out both live in `Taskfile.yml`, and a bare run skips both silently. Where a bare run is unavoidable, prefix it with `OPENKNOWLEDGE_TELEMETRY=off`.
- Record bundle changes in `knowledge/log.md`, one bullet per changed concept under today's date. User-facing changes belong in the root `CHANGELOG.md`. The two files have separate audiences and do not mirror each other.
- Regenerate the `AGENTS.md` managed block with `task knowledge:rules-apply` after changing this file. Hand-editing the block fails `task knowledge:rules-check`.
