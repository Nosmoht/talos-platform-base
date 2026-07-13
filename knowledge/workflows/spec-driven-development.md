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

## Validation

- Locally: `task spec:validate` (strict validate + offline link check).
- CI: `docs-lint.yml` runs `openspec validate --all --strict
  --no-interactive` on every PR — fail-closed, verified empirically
  (malformed spec → exit 1).
- Staleness convention: a PR touching a spec's `primary` source file
  updates the owning spec (frontmatter `sources:`; not yet CI-enforced).

## Tool pin and upgrades

The CLI is npm-distributed and pinned (`.tool-versions` is the SoT;
Taskfile vars and the docs-lint env block are drift-asserted copies).
Install: `task spec:install-cli` (always `--ignore-scripts`). Upgrading:

1. Bump the pin in `.tool-versions`, `Taskfile.yml`, and
   `.github/workflows/docs-lint.yml` together (the drift assert fails CI
   on a partial bump).
2. `task spec:install-cli`, then `task spec:update` — regenerates the
   committed Claude/Codex integration trees and fails if the regeneration
   emitted paths the `.gitignore` negation list does not cover.
3. `task spec:validate`; review and commit the regenerated trees. Never
   hand-edit them (ADR-0014).
