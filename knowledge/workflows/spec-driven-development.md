---
type: workflow
title: "Spec-Driven Development (OpenSpec)"
description: "How behavioral requirements are maintained in the OpenSpec surface — the change lifecycle, the scope demarcation against knowledge/, and the pinned-tool upgrade procedure."
tags: [workflow, openspec, spec-driven-development]
timestamp: 2026-07-13
sources:
  - openspec/config.yaml
  - Taskfile.yml
  - .github/workflows/docs-lint.yml
---

# Spec-Driven Development (OpenSpec)

The platform's behavioral requirements live in `openspec/specs/` — one
capability per directory, validated by the `openspec` CLI. Adoption
rationale, scope principle, and ownership model:
[ADR-0015](../decisions/0015-openspec-adoption.md); the committed tool
integrations: [ADR-0014](../decisions/0014-ship-ai-tool-artifacts.md).

> **Naming warning:** `openspec` (behavioral specs, this workflow) and
> `openknowledge` (validates this `knowledge/` bundle) are two unrelated
> tools with near-identical names. Task namespaces keep them apart:
> `spec:*` vs `knowledge:*`.

## What is spec'd — and what is not

Spec'd: externally observable contracts the platform delivers to
consumers (module surface, delivered manifests, the published OCI
artifact's supply-chain properties). Not spec'd: repo-internal QA whose
only consumer is this repo's CI (secret-scan, scorecard, lint pipelines,
release automation) — that stays documented here in `knowledge/`.
Normative constraints live in `AGENTS.md` §Hard Constraints and the ADRs;
specs cite them and describe observable outcomes only.

## Change lifecycle

Behavior changes travel as spec deltas, not direct spec edits:

1. `/opsx:propose` (or `openspec` CLI directly) — create a change under
   `openspec/changes/<name>/` with proposal + delta specs
   (ADDED/MODIFIED/REMOVED/RENAMED requirement sections).
2. `/opsx:apply` — implement against the delta.
3. `/opsx:archive` — merge the deltas into `openspec/specs/` and move the
   change to the dated archive.

The one-time backfill of the 14 substrate capabilities was directly
authored by explicit owner decision (ADR-0015); it is the exception, not
the pattern.

### Spec-gap backfill

A third lane, for when an existing capability's spec turns out to be silent
on behavior that already ships — the backfill closed, but a gap survived it.
The delta is `ADDED`-only and step 2 has nothing to implement, so proposing
and archiving land together. First use:
`openspec/changes/archive/2026-07-15-spec-bootstrap-identity-subset/`.

The hazard this lane exists to bound: *"the apply phase is empty because the
behavior already ships"* is a self-certifying claim, and a PR that ships code
and spec together could reach for it to narrate a review that never happened.
So the lane is only available under all four conditions:

- The delta is `ADDED`-only. A `MODIFIED` or `REMOVED` requirement means
  behavior is changing — that is lane 1, and its review happens before the
  code.
- The proposal names the shipped implementation (file + fragment) each added
  requirement describes, and carries the verification that proves the claim —
  a run, not a reading.
- Any code the change touches is a **fix for a defect the spec work
  uncovered**, described as such in the proposal, and not a behavior change
  the spec is being written around.
- The requirements are mechanically bound before merge, or the proposal states
  why they cannot be and what carries them instead. A spec-gap backfill whose
  requirements nothing executes has moved prose from an unwatched file to a
  watched one and called it a gate — see
  [ADR-0016](../decisions/0016-capability-profiles-predicate-only.md) for why
  that is not enough.

If any condition fails, it is lane 1: propose, get the delta reviewed, then
implement.

## Validation

- Locally: `task spec:validate` (strict validate, bite-check via the
  committed malformed fixture, source-ownership partition, offline link
  check) and `task spec:check-regen` (committed tool trees equal the
  pinned generator's output).
- CI: `docs-lint.yml` runs exactly these Taskfile targets on every PR —
  the local chain and the remote chain are the same commands by
  construction.
- Staleness gate (CI-enforced on PRs): a diff touching a spec's `primary`
  source must also touch the owning spec — `task spec:check-staleness`
  (`scripts/check-spec-staleness.py`, driven by the frontmatter
  `sources:` ownership map). Fragment-keyed sources
  (`Taskfile.yml#bootstrap:argocd`) fire at fragment granularity: only a
  diff inside the named YAML-key block counts (unresolvable fragments
  fail closed), so unrelated edits to a shared file never force a spec
  touch. For verified no-behavior-change diffs (comment-only edits,
  refactors) the `Spec-Impact: none` trailer — in the commit BODY, never
  the subject — downgrades the failure to a warning, scoped per commit:
  EVERY commit touching the violating file must carry it. The PR
  reviewer judges the no-behavior-change claim.

## Tool pin and upgrades

The CLI is npm-distributed and pinned (`.tool-versions` is the SoT; the
committed `package.json` + `package-lock.json` carry the installable
copy with integrity hashes — `task dev:verify-pins` asserts the pair,
locally and in CI). Install: `task spec:install-cli` (`npm ci
--ignore-scripts` against the lockfile, then a `~/.local/bin` symlink —
the lockfile's integrity hashes are the supply-chain control;
`--ignore-scripts` additionally disables lifecycle scripts). Upgrading:

1. Bump the pin in `.tool-versions` and `package.json` together, then
   refresh the lockfile via `npm install --package-lock-only
   --ignore-scripts` (`dev:verify-pins` fails on a partial bump).
2. `task spec:install-cli`, then `task spec:update` — regenerates the
   committed Claude/Codex integration trees and fails if the regeneration
   emitted paths the `.gitignore` negation list does not cover.
3. `task spec:validate`; review the regenerated trees as
   **security-relevant content** — they are instruction files Claude Code /
   Codex auto-load, so diff the instruction bodies, not just the paths
   (a compromised generator release would enter exactly here). Then commit.
   Never hand-edit the trees (ADR-0014); CI's regeneration-parity gate in
   `docs-lint.yml` rejects any divergence between the committed trees and
   what the pinned CLI generates.
