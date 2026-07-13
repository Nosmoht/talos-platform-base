---
type: decision
title: "ADR: OpenSpec as the behavioral-requirements surface"
description: "The base adopts OpenSpec with a directly-authored backfill of 14 substrate capability specs; openspec/specs/ is normative for behavioral requirements, scoped to consumer-facing platform behavior."
status: accepted
id: base:openspec-adoption
timestamp: 2026-07-13
deciders:
  - repo owner
consulted: []
informed: []
supersedes: []
superseded_by: []
related:
  - base:ship-ai-tool-artifacts
  - base:substrate-only-base
tags: [adr, spec-driven-development, governance]
---

# ADR: OpenSpec as the behavioral-requirements surface

## Context and Problem Statement

The repo documents architecture, decisions, and workflows in the
`knowledge/` OKF bundle, but has no artifact stating the platform's
behavioral requirements — what the substrate must observably do for a
consumer. OpenSpec (`@fission-ai/openspec`, MIT) provides a
directory-convention + CLI for exactly that: `openspec/specs/` as the
requirements source of truth and `openspec/changes/` for delta proposals
merged on archive. The owner additionally wants the already-implemented
platform covered, not only future changes.

## Decision Drivers

- Behavior changes should be reviewable as requirement deltas, not only as
  manifest/code diffs.
- The owner explicitly wants coverage of the existing implementation
  (backfill), overriding OpenSpec's official anti-backfill guidance.
- A young, fast-moving tool (breaking rebuild at its v1.0) must be pinned
  and supply-chain-controlled.
- The base/apps/consumer layering (`base:substrate-only-base`) must not
  blur: specs may cover only what the substrate itself delivers.

## Considered Options

1. Endorsed incremental path: initialize OpenSpec, let specs accumulate
   only via the change lifecycle.
2. Directly-authored backfill of every substrate behavioral capability,
   then the endorsed change lifecycle for everything afterwards.
3. No adoption; keep prose docs only.

## Decision Outcome

Chosen option: **backfill + change lifecycle (option 2)**, by explicit
owner decision. The staleness risk the official guidance warns about is
accepted and mitigated (see below), not ignored.

**Scope principle.** Spec'd is every externally observable contract the
platform delivers to consumers. Excluded is repo-internal QA whose only
consumer is this repo's CI — the demarcation is the consumer, not the
file type: `oci-publish.yml` produces a consumer-facing artifact contract
(spec'd, producer side only); gitleaks/scorecard/preflight/docs-lint/
REUSE/shellcheck/commitlint/release-automation, the render/validate
pipelines, and MCP wiring gate this repo (not spec'd; documented in
`knowledge/`). Consumer-side verification how-to stays in
[verify-release](../workflows/verify-release.md).

**Ownership model.** Spec frontmatter lists `sources:` (code/config paths
only) split into `primary` (exactly one owning spec per path) and
`secondary` (informative). ADRs and `AGENTS.md` never appear as sources —
they are `references:`. Normative statements stay in `AGENTS.md` §Hard
Constraints and the ADRs; specs cite them and describe observable
outcomes (pure reference, zero restatement).

**SoT map vs `knowledge/reference/`.** Specs are normative for
requirements; reference docs stay narrative:
[talos-cluster-module](../reference/talos-cluster-module.md) → interface
requirements in `module-interface-contract`, composition in
`hardware-capability-composition`, machine-config in
`machine-config-generation`, bootstrap flow in
`cluster-bootstrap-lifecycle`, installer surface in
`node-image-composition`; [cluster-yaml](../reference/cluster-yaml.md) →
`cluster-yaml-sot`. The module README's variable/output tables are
terraform-docs-generated (inject mode) and exempt from this map.

### Consequences

- Positive: 14 substrate capabilities carry testable requirements with
  scenario-level observability; future behavior changes travel as spec
  deltas through `openspec/changes/`.
- Negative: backfilled specs are descriptive of current code; nothing
  forces them to track reality except the convention below. This is the
  owner-accepted residual.
- Negative: a second validator (`openspec`) joins `openknowledge` — the
  near-identical names are a standing confusion hazard (disambiguated in
  Taskfile namespace comments and the workflow doc).
- Follow-up: staleness convention — a PR touching a spec's `primary`
  source updates the owning spec. Not CI-enforced yet; a CI mapping of
  source-diff → owning spec is the named follow-up candidate.
- Follow-up: `markdownlint` exempts the generated tool trees; the
  hand-authored specs stay lint-clean (no `openspec/` exemption was
  needed at adoption).
- Follow-up: the npm install is exact-version-pinned with lifecycle
  scripts disabled, but carries no artifact-integrity hash (unlike the
  checksum-verified curl-fetched sibling tools). A lockfile-based install
  (`npm ci --ignore-scripts` against a committed lockfile) is the named
  follow-up.

## Pros and Cons of the Options

### Option 1 — incremental only

- Pro: specs never claim more than a change verified.
- Con: the existing platform — the bulk of the behavior — stays unspec'd
  indefinitely; contradicts the owner's stated goal.

### Option 2 — backfill + lifecycle (chosen)

- Pro: full behavioral map from day one; delta reviews start immediately.
- Con: descriptive-oracle risk and staleness convention (see
  Consequences).

### Option 3 — no adoption

- Pro: no new tool, no new surface.
- Con: behavior changes stay reviewable only at the implementation level.

## Validation

`openspec validate --all --strict --no-interactive` is fail-closed for
directly-authored specs and runs in `docs-lint.yml` on every PR plus
locally via `task spec:validate`; the fail-closed property is continuously
re-proven by a committed malformed fixture that must fail validation
(bite-check), and the `sources:` ownership model is enforced by
`scripts/check-spec-partition.py` (exclusivity, plus completeness relative
to the script's enumerated substrate source universe — extending the
universe is part of adding a new source class; an unknown-module drift
guard catches the most likely omission). The pin lives in
`.tool-versions` (SoT) plus the Taskfile vars block, asserted by
`task dev:verify-pins`; `task spec:check-regen` keeps the committed tool
trees equal to the pinned generator's output (parity, not benignity —
instruction-body review stays mandatory). The `docs-lint.yml` CI job runs
exactly these Taskfile targets, so the local and remote validation chains
are the same commands by construction.
The decision is wrong if specs rot despite the staleness convention —
the trigger to revisit is a merged behavior change whose owning spec was
not updated.

## Links

- `base:ship-ai-tool-artifacts` (ADR-0014) — enables committing the
  generated tool integrations
- [spec-driven-development workflow](../workflows/spec-driven-development.md)
- OpenSpec upstream: `github.com/Fission-AI/OpenSpec`
