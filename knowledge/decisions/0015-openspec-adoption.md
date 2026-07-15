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
- Negative: backfilled specs are descriptive of current code; the
  CI staleness gate (below) forces a *touch* of the owning spec, not the
  *correctness* of the update. This is the owner-accepted residual.
- Negative: a second validator (`openspec`) joins `openknowledge` — the
  near-identical names are a standing confusion hazard (disambiguated in
  Taskfile namespace comments and the workflow doc).
- Follow-up (closed 2026-07-13): staleness convention — a PR touching a
  spec's `primary` source must also touch the owning spec. CI-enforced
  via `task spec:check-staleness` (`scripts/check-spec-staleness.py`) in
  `docs-lint.yml`; fragment-keyed sources fire at fragment granularity
  (fail-closed on unresolvable fragments) so shared files like
  `Taskfile.yml` do not produce chronic false positives; escape for
  verified no-behavior-change diffs is the `Spec-Impact: none` trailer
  in the body of every commit touching the file (per-commit scope),
  judged by the PR reviewer. Scope: PR events — a direct push to a
  protected `main` bypasses the gate by construction; the PR path is the
  enforced contribution path. The gate forces a *touch* of the owning
  spec, not the *correctness* of the update.
- Follow-up: `markdownlint` exempts the generated tool trees; the
  hand-authored specs stay lint-clean (no `openspec/` exemption was
  needed at adoption).
- Follow-up (closed 2026-07-13): npm artifact integrity — `openspec` and
  `markdownlint-cli` are pinned in the committed `package.json` +
  `package-lock.json` and installed via `npm ci --ignore-scripts`. Scope:
  the integrity hashes pin the fetch to the reviewed lockfile
  (registry/MITM tampering) and `dev:verify-pins` asserts
  registry.npmjs.org provenance of every resolved URL; unlike the
  checksum-verified curl-fetched sibling tools the hash set is authored
  in-PR, so lockfile diffs remain human review surface.

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
`.tool-versions` (SoT) plus the committed `package.json` +
`package-lock.json` (the installable, integrity-hashed copy), asserted by
`task dev:verify-pins`; `task spec:check-regen` keeps the committed tool
trees equal to the pinned generator's output (parity, not benignity —
instruction-body review stays mandatory); `task spec:check-staleness`
fails a PR whose diff touches a spec's `primary` source without touching
the owning spec. The `docs-lint.yml` CI job runs exactly these Taskfile
targets, so the local and remote validation chains are the same commands
by construction.
The decision is wrong if specs rot despite the staleness gate — the
trigger to revisit is a merged behavior change whose owning spec carries
a stale description (the gate forces a touch, not a correct one).

## Links

- `base:ship-ai-tool-artifacts` (ADR-0014) — enables committing the
  generated tool integrations
- [spec-driven-development workflow](../workflows/spec-driven-development.md)
- OpenSpec upstream: `github.com/Fission-AI/OpenSpec`
