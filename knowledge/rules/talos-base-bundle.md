---
type: Rule
rule_id: talos-base-bundle
title: Bundle Conventions
description: Repo-specific OKF bundle conventions layered on top of the built-in maintenance rules, rendered into the AGENTS.md managed block.
rule_summary: Repo-specific bundle conventions on top of the built-in maintenance rules.
tags: [okf, maintenance, conventions]
generated: { by: human:nosmoht, at: "2026-08-28T00:00:00Z" }
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

- Update the owning concept in the SAME task that changes behavior, an API, a command, a config or an example — the bundle records shipped behavior, and anything not yet shipped is labelled as planned.
- Record a meaningful technical decision as a `decision` concept carrying context, options, the chosen path and its tradeoffs, linked to the concepts, workflows and source files it affects. Decision history is append-only: supersede or append a clarification, never rewrite the old context away.
- Create or update a concept when an API, schema, table, config key or contract changes at its source, and point at the authoritative file instead of copying generated or code-derived truth into prose.
- Use the closed `type` vocabulary: `architecture`, `reference`, `workflow`, `decision`, `glossary`, `project`, `Rule`. Add a new type by editing this list and `knowledge/index.md` in the same change. `Rule` is capitalized because the CLI requires that spelling, not as a naming pattern to copy.
- Record provenance as `generated: { by, at }` on every concept that lists `sources`. `by` is REQUIRED inside `generated` and is an actor — `human:<id>`, `process:<id>`, or `<producer>/<version>`; this bundle uses `human:nosmoht`. The v0.1 `timestamp` key is retired: no frontmatter under `knowledge/` may carry it, though prose describing what was done on a past date is record and stays.
- Write every date as a quoted ISO 8601 datetime, `"2026-08-23T00:00:00Z"`. A date alone is rejected in both spellings; the midnight is padding for a record that has day precision, not an observed time.
- Set `generated.at` to the date the concept's content last meaningfully changed, and never omit it on a concept that lists `sources`.
- Add a `verified` entry for a reading of the concept against its `sources` that actually happened, dated the day it happened. `verified` is a history: append, never rewrite, and never invent. Authoring or editing a concept is `generated`, never `verified` — do not certify your own edit.
- Judge freshness by comparing the newest `verified[].at` against `generated.at` yourself: an OKF consumer reads any `human:<id>` entry as human-reviewed and flags nothing when the reading predates the content.
- Write every `sources` entry as a mapping whose `resource` key holds the repo-relative path the concept was derived from, one per line, as `- resource: Taskfile.yml`. A bare string is a v0.1 leftover and fails validation; the path itself is checked by `scripts/check-knowledge-frontmatter.sh`, not by `openknowledge`.
- Re-verify a concept when a change lands inside what the concept describes — not merely when a file listed in its `sources` was touched. A green validation run proves link and schema health, never freshness.
- Give `decision` concepts `decided` instead: no `sources`, so no `generated` and no `verified` either. `knowledge/decisions/template.md` deliberately carries no `decided` so a copy cannot ship a placeholder date; add it when you copy. Their full field contract lives in `knowledge/decisions/index.md`.
- Use the OKF lifecycle vocabulary in `status`: `stable`, `draft`, `deprecated`; an absent `status` means `stable`. See `knowledge/decisions/index.md` §Status vocabulary for the MADR mapping and why the record keeps the older words.
- Link relatively inside the bundle, and cite anything outside it as an inline code span rather than a markdown link: `knowledge/.openknowledge.toml` raises `link-target` to error, so an escaping link fails validation. Quote any rule key containing a dot in that file — `"okf-0.2-metadata"` unquoted is read as a TOML dotted key and drops every rule in the file.
- Validate with `task knowledge:validate`, which runs `openknowledge validate` plus the offline link gate. Run `task knowledge:rules-check` as well after touching `knowledge/rules/`.
- Invoke `openknowledge` through the `knowledge:*` task targets, never bare: the version pin and the telemetry opt-out both live in `Taskfile.yml`, and a bare run skips both silently. This supersedes the built-in instruction above to run `openknowledge validate "knowledge"` — `task knowledge:validate` performs that validation and satisfies it. Where a bare run is unavoidable, prefix it with `OPENKNOWLEDGE_TELEMETRY=off`.
- Record bundle changes in `knowledge/log.md`, one bullet per changed concept under today's date, stating WHAT changed. Why it changed belongs in the commit body and the issue, which is where git already keeps it — do not restate a rationale here. User-facing changes belong in the root `CHANGELOG.md`; the two files have separate audiences and do not mirror each other.
- Regenerate the `AGENTS.md` managed block with `task knowledge:rules-apply` after changing this file. Hand-editing the block fails `task knowledge:rules-check`.
