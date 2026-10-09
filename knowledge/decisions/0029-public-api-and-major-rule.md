---
type: decision
title: "ADR: The base's public API and the MAJOR rule"
description: "Declares the base's public API and defines a MAJOR release as one after which configuration a consumer wrote fails, or silently changes its effect; an upstream version number is never MAJOR by itself. Decides the provider-constraint form and a squash-only release mechanism whose PR title is the only bump source; the content-based breaking-change check it first planned is withdrawn."
status: stable
id: base:public-api-and-major-rule
decided: "2026-10-09T00:00:00Z"
deciders:
  - platform-maintainer
consulted: []
informed: []
supersedes:
  - "/decisions/0020-automated-release-no-approval-gate.md §Context MAJOR-vs-MINOR framing and §Consequences surface-set carve-out (now); §Decision 2, §Decision 3 and the merge-commit-only premise of §Amendment (2026-08-25), §Amendment (2026-08-31) and §Amendment (2026-08-31, second) (when the planned cutover ships)"
  - "/decisions/0027-talos-provider-prerelease-pin.md §Follow-up 2026-10-03 (exact stable pin), in force until the planned provider range ships"
superseded_by: []
related:
  - /decisions/0020-automated-release-no-approval-gate.md
  - /decisions/0022-cilium-observability-and-argocd-self-management.md
  - /decisions/0026-machine-config-apply-mode.md
  - /decisions/0027-talos-provider-prerelease-pin.md
  - /decisions/0028-consumer-free-helm-value-surface.md
tags: [adr, release, versioning, public-api]
---

# ADR: The base's public API and the MAJOR rule

## Context and Problem Statement

Nothing stated in one place which changes to the base are MAJOR. The module's
types and the OpenSpec specs declare individual contracts, and the written
triggers disagreed. `AGENTS.md` §Commit & Pull Request Guidelines required a
MAJOR for a breaking change to the base's Helm values. `README.md` required one
for a breaking change to the Helm values or to the `cluster.yaml` /
`talos-cluster` module interface. The release-plan prompt in
`.github/workflows/release.yml` asks for a MAJOR when a published contract,
layout or Helm-value default moved. Classification was inconsistent as a
result: `UPGRADING.md` records v8.2.0 (Cilium 1.20) as MINOR with action
required for every consumer, and v10.0.0 as MAJOR for a NetworkPolicy default.

The release mechanism added two more problems. semantic-release analyzes every
commit in the tag range — the branch commits and the merge commit whose subject
is the PR title — while `lint-pr-title` checks only the title, so a stray
`BREAKING CHANGE:` line in a branch commit cuts a MAJOR nobody reviewed. And the
path guard of [ADR-0020](0020-automated-release-no-approval-gate.md) §Decision 2
blocks every non-MAJOR release that touches a guarded path, chart lock files and
rendered output included, while it exempts the module interface that consumer
configuration binds to. Its only way out is an `Allow-Non-Major:` attestation
the merge button cannot write: shipping v15.0.2, a security fix, took three
pull requests (#287, #289, #291). Exact provider pins add a fourth: a consumer
root whose own constraint excludes a moved pin fails `tofu init` until it is
edited.

Issue #292 records the measurements behind these points — a replay of the
commit analyzer over every tag range since v2.0.0, and synthetic pull requests
run through today's guard and through a squash-only regime. This record cites
them from the issue; it does not re-measure them.

## Decision Drivers

- SemVer 2.0.0 reserves MAJOR for incompatible changes to the declared public
  API, so the base has to declare one.
- The base releases the tooling around Talos, Cilium and Argo CD, not the
  software that tooling manages. An upstream version number says nothing by
  itself about what a consumer's configuration does after an upgrade.
- One reviewed source decides the bump. No label, trailer or attestation file
  decides or overrides it.
- Release automation stays unattended, as ADR-0020 decided: a failed check
  blocks and notifies, and there is no manual approval gate.
- A compatible security fix ships as a PATCH without extra pull requests.

## Considered Options

1. Status quo: the path guard plus the `Allow-Non-Major:` attestation, with the
   bump computed from every commit in the range.
2. A declared public API and a consumer-effect MAJOR rule, with the PR title as
   the only bump source under squash-only merges and a content-based check
   backing the title.
3. The same rule, with a label, trailer or attestation file that decides or
   overrides the bump.
4. CalVer or a 0.x version line.

## Decision Outcome

Chosen option: **option 2, a declared public API and a consumer-effect MAJOR
rule, decided by the PR title and checked against the content of the change**,
because it ties the version to what a consumer's configuration experiences, it
leaves one reviewed source for the bump, and it replaces blocks on paths with a
check on what the change does.

§Public API, §Classification and §Provider constraints are in force from this
record's adoption. The mechanism in the three §Planned sections is decided and
not yet shipped; §Interim state says what holds until it ships.

### Consequences

- Positive: MAJOR has one definition, owned here. Other documents point at it.
- Positive: the module interface, which the path guard exempts, is part of the
  public API.
- Positive: once the planned mechanism ships, a compatible upgrade or security
  fix ships as MINOR or PATCH without an attestation.
- Negative: until the planned cutover ships, the path guard still blocks a
  non-MAJOR release that touches a guarded path, even where §Classification
  calls the change MINOR or PATCH.
- Negative: a title-only bump source lets a mis-titled break through unless the
  content check detects it. The classes it cannot detect stay with the reviewer.
- Negative: squash merges drop the branch commits' SHAs and per-commit
  authorship from `main`.
- Follow-up: the cutover change ships the merge settings, the title-only bump
  source, the content check and the guard removal; the provider-range change
  applies §Provider constraints to the `talos` constraint and its spec
  requirement. Issue #292 tracks both.

## Public API

1. The `tofu/modules/talos-cluster` module's input variables — name, type,
   optionality, nullability and whether a default exists — its outputs, and its
   validation rules.
2. The documents under `schemas/` and `contracts/`, and
   `platform-hardware-features.yaml`.
3. The OCI tarball layout: which paths the published artifact carries.
4. The identity of rendered resources a consumer patches or selects: kind,
   namespace, name and selector labels.
5. Shipped CRDs and the versions they serve.
6. The consumer setups that `UPGRADING.md` and this knowledge bundle document
   as supported.

Helm-value **defaults** are behavior, not API surfaces: rows 11, 12 and 15 of
§Classification classify a change to one. Consumer override keys reach the API
through item 1, the module inputs that carry them, and through row 10. Hard
constraints (`AGENTS.md` §Hard Constraints) are base invariants, not API
surfaces; tightening one so that consumer configuration is rejected is MAJOR
through row 3.

## Classification

A release is MAJOR when, after upgrading the base, configuration a consumer wrote
fails, or silently changes its effect. An upstream version number is
never MAJOR by itself: shipping or supporting a new Talos, Kubernetes, Cilium,
Argo CD or provider version is a feature or a fix, and becomes MAJOR only
through what it does to consumer configuration. What the base releases is the
tooling around Talos, Cilium and Argo CD, not the software that tooling manages.

These examples fix how each kind of change is classified; the Title form column
gives the Conventional Commit form a PR title takes for that class:

| # | Change | Class | Title form |
|---|---|---|---|
| 1 | A module input or output is removed or renamed | MAJOR | `type!:` |
| 2 | An input type narrows, an `optional()` attribute becomes required, or an input loses its default or its null acceptance | MAJOR | `type!:` |
| 3 | Validation or a schema newly rejects input it accepted, such as the closed `substrate.cilium` in v7.0.0 or the override keys v13.0.0 rejects | MAJOR | `type!:` |
| 4 | A schema, contract or vocabulary entry is removed | MAJOR | `type!:` |
| 5 | A tarball path moves | MAJOR | `type!:` |
| 6 | A rendered resource identity is renamed or a CRD version is removed | MAJOR | `type!:` |
| 7 | Support ends for a Talos schema version existing clusters may hold; `talos_version` must not change after bootstrap | MAJOR | `type!:` |
| 8 | A provider or OpenTofu constraint excludes a version a consumer root may legitimately pin (§Provider constraints) | MAJOR | `type!:` |
| 9 | A shipped change breaks a documented supported setup, such as the NetworkPolicies v10.0.0 ships by default | MAJOR | `type!:` |
| 10 | A shipped chart change silently drops a consumer override key without any action by the consumer | MAJOR | `type!:` |
| 11 | A new upstream release or a new default version whose effect stays compatible | MINOR | `feat:` |
| 12 | A default changes behind an existing input, with an `UPGRADING.md` note, such as `rollOutCiliumPods: true` in v14.0.0; this covers the single-source Cilium self-management arm, where no opt-out exists, unless row 9 applies | MINOR | `feat:` |
| 13 | A change reaches a consumer only when they move a pin in their own files, with an `UPGRADING.md` note, such as Cilium 1.20 in v8.2.0, gated by the consumer's own `chart_version` | MINOR | `feat:` |
| 14 | A new optional input, output or schema field | MINOR | `feat:` |
| 15 | An upstream patch or security fix whose effect stays compatible, such as Argo CD v3.5.4 in v15.0.2; the routine apply it triggers does not make it MAJOR (Routine apply, below) | PATCH | `fix:` |
| 16 | A packaging repair, such as the module files v11.0.0 added to the tarball | PATCH | `fix:` |
| 17 | `tofu init -upgrade` against a lock file alone | not MAJOR | no `!` |

**Routine apply.** A release that triggers a routine machine-configuration apply
is not MAJOR by itself. How an apply-mode input (`controlplane_apply_mode`,
`worker_apply_mode`; [ADR-0026](0026-machine-config-apply-mode.md)) handles any
apply is that setting's documented effect, not an effect of the release. Such a
release requires an `UPGRADING.md` note.

**From adoption on.** This classification governs changes from this record's
adoption on. It does not reclassify, renumber or retract any tag, including
where a row's example shipped with a different class: v14.0.0 and v11.0.0
shipped as MAJOR, and `UPGRADING.md` records the `rollOutCiliumPods` default
change as MAJOR, although rows 12 and 16 now classify those changes as MINOR and
PATCH.

## Provider constraints

This section governs every constraint in the module's `versions.tf`:
`required_version` and every `required_providers` entry.

- **Floor (required).** Each constraint has a floor: the oldest version the base
  supports, which is the oldest version the module's code needs. It rises only
  when the module needs a newer feature, and that rise is MAJOR (row 8), because
  it excludes a published version the previous release admitted.
- **Upper bound (recommended).** An upper bound sits below the dependency's next
  breaking line: the next MAJOR for a dependency at 1.0 or later, the next MINOR
  for a 0.x dependency.
- **When a constraint change is MAJOR.** A constraint change is MAJOR if and
  only if it excludes a published version the previous release admitted, by
  raising a floor or by moving an exact pin. Widening a constraint is not MAJOR.
  An upper bound that excludes only unpublished versions is not MAJOR.
- **Exact pins.** An exact pin is allowed only when the machinery the module
  needs exists only in a prerelease, because an OpenTofu constraint matches a
  prerelease only through an exact `=` on that version — the case of
  [ADR-0027](0027-talos-provider-prerelease-pin.md). Moving such a pin is MAJOR.
- **Conformance today.** `required_version = ">= 1.9.0"` and the `helm`, `local`
  and `null` constraints conform. The exact stable `talos` pin (`"0.12.0"`) does
  not, since no prerelease-only machinery requires it, and neither does the
  requirement "Version constraints and backend agnosticism" in
  `openspec/specs/module-interface-contract/spec.md`, which mandates that pin.
  Moving both to a conforming range is planned for the provider-range change.
  - **Update 2026-10-09 (#296).** The `talos` constraint is
    `">= 0.12.0, < 0.13.0-0"` and conforms, and the requirement states that
    range. The `-0` upper bound also excludes 0.13 prereleases: a root that
    pins a prerelease exactly makes OpenTofu order it against the other
    constraints, and `< 0.13.0` would admit it. The gate keeps the module's
    committed lock at the floor, so base CI verifies the `talos` floor; a later
    0.12.x is admitted without a behavioral base CI run.
- **Known limitation.** CI runs OpenTofu `1.12.1` only
  (`.github/workflows/tofu-validate.yml`) and does not resolve the `helm`,
  `local` or `null` floors, so CI verifies no floor. A floor states what the
  module's code needs; CI coverage does not define it.

## Interim state

**Ended 2026-10-09 in #298: the path guard, the `Allow-Non-Major:` attestation and
the merge-commit-only settings are removed; merges are squash-only.**

**Ended 2026-10-09 in #298: the release-plan prompt and the release-guard files
that row 12 superseded are deleted.**

**Ended 2026-10-09 in #298: [Release Process](../workflows/release-process.md)
describes the squash-only mechanism.**

**Ended 2026-10-09 in #296: the requirement "Version constraints and backend
agnosticism" no longer mandates an exact `talos` pin; it states the range
§Provider constraints sets.**

These facts hold until the named planned change ships:

- §Public API, §Classification and §Provider constraints apply from the merge
  that adopted this record.
- The path guard, the `Allow-Non-Major:` attestation and the merge settings that
  ADR-0020 decided stay in force until the planned cutover ships.
- Until the planned provider range ships, the requirement "Version constraints
  and backend agnosticism" in `openspec/specs/module-interface-contract/spec.md`
  governs the shipped module's `talos` constraint.
- Until the planned cutover ships, §Classification row 12 supersedes the
  release-plan prompt in `.github/workflows/release.yml` and the release-guard
  files where they call a Helm-value default change MAJOR.
- Issue #292 tracks the remaining work and stays open until it ships.

The current release mechanism — where the bump comes from, the guard and the
attestation procedure — is described in
[Release Process](../workflows/release-process.md), which stays accurate until
the cutover.

Two append-only rules keep this record current. The change that ships a planned
mechanism inserts a dated line, `**Shipped YYYY-MM-DD in #N.**`, directly above
that section's planned label. The change that ends an interim fact inserts a
dated line, `**Ended YYYY-MM-DD in #N: <fact>.**`, at the top of this section.
Neither removes the text below it: the planned labels and the interim facts keep
the state at decision time.

## Planned: merge method and bump source

**Shipped 2026-10-09 in #298, without the pre-tag check of the third bullet, which
§Amendment (2026-10-09) withdraws.**

**Planned — not yet shipped.**

- The repository allows squash merges only. The squash subject defaults to the
  PR title and the default body is blank; merge commits and rebase merges are
  disabled. `lint-pr-title` stays a required check.
- The PR title is the only source of the bump. Branch commits no longer reach
  `main`, so a footer in one no longer counts.
- Before tagging, `release.yml` verifies that every first-parent commit in the
  range is the squash of a merged pull request and that its subject equals that
  pull request's final title. A commit that fails — an admin push, an edited
  merge message — blocks the release and opens the tracking issue.
- `scripts/preflight-checks.sh` Check 4 reads the merge settings with an admin
  credential. Its parent-count fallback is reported as limited evidence, not as
  a pass.

## Planned: content-based breaking-change check

**Withdrawn 2026-10-09 in #298: not built; see §Amendment (2026-10-09).**

**Planned — not yet shipped.**

A content-based breaking-change check replaces the path guard and the
`Allow-Non-Major:` attestation. Its logic lives in a Taskfile target that the
workflows call.

- It runs as a required pull-request check on `opened`, `edited`, `reopened`
  and `synchronize`, comparing the merge base with the head, and again in
  `release.yml` over the tag range before tagging.
- It fails when it detects a MAJOR class of §Classification and the governing
  title carries no `!`.
- It detects every mechanically detectable MAJOR class:
  - module inputs and outputs, through an HCL parser: removal, rename, type
    narrowing, an `optional()` attribute becoming required, a lost default, lost
    null acceptance, and a new required input;
  - schemas, with `$ref`, `allOf` and `oneOf` resolved: a removed property, a
    new required property, `additionalProperties` closed, and a narrowed `type`
    or `enum`;
  - removed entries in `contracts/` or `platform-hardware-features.yaml`;
  - removed tarball paths;
  - removed or renamed rendered resource identities;
  - removed CRD versions;
  - narrowed provider or OpenTofu constraints, meaning a constraint that
    excludes a published version the previous release admitted (§Provider
    constraints).
- It fails closed on any git, parse or missing-input error.
- The classes it cannot detect stay with the reviewer: behavior effects such as
  the NetworkPolicies of v10.0.0, and upstream keys a chart drops. When it sees a
  public-API path change, the check lists these classes as a hint.
- `!` in the title is the only way past it. No label, trailer or attestation
  file overrides it.
- With the check in place, these are removed: `scripts/release-major-bump-guard.sh`
  and its bite-check; the `release.yml` guard step and the `notify` conditions
  that depend on its verdict; the release-guard advisory and lock check in
  `docs-lint.yml`; and `.ci-release-guard-pathspec.txt`,
  `.ci-release-guard-exempt.txt` and `.ci-release-guard.lock`, unless the new
  check reuses them. The OCI-membership and module-extraction checks under
  `task supply-chain:*` stay.

## Planned: cutover and reverts

**Shipped 2026-10-09 in #298; the pre-tag range check the first bullet cites is
withdrawn (§Amendment (2026-10-09)).**

**Planned — not yet shipped.**

- The classification governs PR titles from this record's adoption on. The
  mechanism above applies from the first tag whose range starts at or after the
  cutover merge commit. The pre-tag range check never inspects commits before
  that commit, which are two-parent merge commits.
- A pull request in flight at the cutover is retitled before merge so that its
  title carries the intended bump; a footer in one of its branch commits stops
  counting.
- No `revert` type is added; the types `.github/workflows/commitlint.yml` allows
  stay. A revert pull request is titled by its effect on the last released
  state:
  - reverting an unreleased change:
    `chore(<scope>): revert "<subject>"`, or the type of the net effect where
    that differs;
  - reverting a released interface addition:
    `<type>(<scope>)!: revert "<subject>"`, a MAJOR, because configuration that
    uses the addition fails;
  - reverting a released fix or behavior change:
    `fix(<scope>): revert "<subject>"`, unless §Classification makes it MAJOR.

## Pros and Cons of the Options

### Option 1 — status quo: path guard plus attestation

- Pro: shipped and enforced today; no migration.
- Con: blocks compatible releases on path alone, and its only way out is an
  attestation the merge button cannot write.
- Con: exempts the module interface, rewards an unnecessary `!`, and leaves the
  branch-commit bump source unreviewed.

### Option 2 — declared API, consumer-effect rule, title-only bump, content check

- Pro: one reviewed bump source, and a check that looks at what the change does
  rather than which path it touches.
- Pro: a compatible upgrade or security fix ships without ceremony.
- Con: needs a parser-based check that fails closed, and behavior effects stay
  with the reviewer.
- Con: squash merges drop branch-commit SHAs and per-commit authorship.

### Option 3 — a label, trailer or attestation side channel

- Con: a second bump source beside the title, which is the defect this decision
  removes. Rejected.

### Option 4 — CalVer or a 0.x version line

- Con: gives up the compatibility signal consumers pin by. Not adopted.

## Validation

- Until the cutover ships: a reviewer checks each PR title against
  §Classification. A release whose class disagrees with the table for a change
  it contains shows the rule is not being applied.
- The planned check is measured in both directions before it ships: it fails on
  a mutant of each detectable MAJOR class under a title without `!`, and passes
  on the same mutants with `!` and on compatible changes. Issue #292 lists the
  mutants and the history replays it must reproduce.
- The decision is wrong if a consumer's configuration fails or changes its
  effect after a non-MAJOR upgrade that followed this table, or if a MAJOR
  release forces no consumer edit and changes no consumer-visible effect.

## Amendment (2026-10-09)

**The content-based breaking-change check and the pre-tag landed-commit check
are not built; the rest of the planned mechanism shipped in #298.**

- No maintained tool detects the §Classification classes across module inputs,
  schemas, rendered identities and constraints. A purpose-built detector would
  have been larger than the problem it covers: the history replay in issue #292
  finds one mis-titled break (v7.0.0, #189). It would also only compensate for
  the title-only bump source rather than remove a cause. The reviewer judges each
  PR title against §Classification; nothing re-checks the content.
- The pre-tag check that every first-parent commit is the squash of a merged PR
  with its title as subject is not built. `AGENTS.md §Issue-Interface` merges
  with `--subject` copied from the linted PR title and an empty `--body`. `scripts/preflight-checks.sh` Check 4 asserts the merge
  settings with an admin credential and, where the settings are unreadable,
  the newest commit's shape (one parent, a `(#N)` suffix, an empty body). That
  fallback reports a pass, not the limited evidence the fourth bullet of
  §Planned: merge method and bump source planned: a re-enabled merge method shows
  only after a merge uses it. An admin push or a hand-edited squash message
  remains possible and is the maintainer's own act.
- release-please was considered and not adopted. Under squash merges it derives
  the bump from the same subjects; its release PR is either merged automatically,
  with no review, or is the manual gate ADR-0020 removed; and it creates the
  GitHub Release itself, which the draft-release flow in `oci-publish.yml` owns.
- §Validation's measurement of the planned check no longer applies. The decision
  is still wrong under its last bullet.

## Links

- [issue #292](https://github.com/Nosmoht/talos-platform-base/issues/292) — the
  problem record, its measurements and the remaining work
- [ADR-0020](0020-automated-release-no-approval-gate.md) — the unattended
  release, the path guard and the attestation this record supersedes in part
- [ADR-0027](0027-talos-provider-prerelease-pin.md) — the exact provider pin
  §Provider constraints supersedes in part
- [ADR-0022](0022-cilium-observability-and-argocd-self-management.md) — the
  single-source Cilium self-management arm that row 12 covers
- [Release Process](../workflows/release-process.md) — the current mechanism
- [SemVer 2.0.0](https://semver.org/) — MAJOR is for incompatible changes to
  the declared public API
