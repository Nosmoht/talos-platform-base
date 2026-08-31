---
type: decision
title: "ADR: Remove the manual release approval gate; replace its MAJOR backstop with a blocking CI guard"
description: "Drops the environment:release manual-approval protection so a merge to main releases unattended, and replaces the gate's one mechanical function — catching a breaking base-surface change shipped without a MAJOR bump — with a blocking MAJOR-bump guard in the plan job."
status: stable
id: base:automated-release-no-approval-gate
decided: "2026-07-21T00:00:00Z"
history:
  - 2026-07-21 accepted
  - 2026-08-25 amended (surface set corrected and moved to committed data; merge-commit-only premise made mechanical; fail-opens closed; notification shipped)
deciders:
  - platform-maintainer
related:
  - base:makefile-retirement
tags: [adr, release, ci, supply-chain]
---

# ADR: Remove the manual release approval gate; replace its MAJOR backstop with a blocking CI guard

## Context

`release.yml` gated its `release` job behind an `environment: release` manual
approval (required reviewer = the maintainer). A merge to `main` computed the
next version but then **waited** for a human to approve before tagging. In
practice this stalled releases: v6.0.0 (the #182 cert-approver swap) sat
computed-but-unreleased because nobody approved the run. The gate served one
mechanical purpose the automation could not: a last look at MAJOR-vs-MINOR,
since `commitlint` lints only the PR **title** and a dropped `type!:` marker
would ship a breaking base as a non-MAJOR release.

The goal: a merge to `main` releases with **no** operator action, without
losing that MAJOR backstop.

## Decision

1. **Remove `environment: release`.** The `release` job runs whenever `plan`
   reports `will-release == 'true'` and passes. No approval step.
2. **Add a blocking MAJOR-bump guard** to the `plan` job. When a published
   base-surface path changed since the last tag but the computed bump is not
   MAJOR, the step fails, blocking `release` (`needs: plan`). Surface set:
   `.ci-oci-tarball-{include,expected}.txt`, `schemas/**`,
   `platform-hardware-features.yaml`, `contracts/**`,
   `kubernetes/base/**/values.yaml`. Gated on `will-release`, so a non-releasing
   push never fails it.
3. **Maintainer override.** An `Allow-Non-Major: <reason>` git trailer on the
   tip (merge) commit downgrades the block to a warning — the escape hatch for a
   genuinely non-breaking edit to a surface path (an additive, backward-
   compatible schema field or a comment-only change; these are the *expected*
   override case, since the guard flags any change to a surface path, not only
   breaking ones). The match is anchored to line-start, so a prose mention or a
   negation cannot trigger it. It is a maintainer attestation: on a merge-commit
   workflow the merging maintainer owns the tip commit body; **under squash-merge
   (enabled on this repo) the maintainer must verify the trailer in the
   concatenated body**, since a PR author's branch-commit bodies flow into it. A
   label-gated override checked via the API is a candidate hardening for the
   follow-up.
4. **No commit-back.** semantic-release tags and creates the GitHub Release
   only; it does **not** push to `main`. `CHANGELOG.md` is cut by hand in the
   releasing PR. The App token, `persist-credentials: false`, and the signing
   identity in `oci-publish.yml` are unchanged. `RELEASE_APP_PRIVATE_KEY` /
   `RELEASE_APP_ID` are **repository**-scoped (not `release`-environment-scoped),
   so removing `environment: release` neither breaks authentication nor narrows
   a credential-access boundary — verified before the change.

## Consequences

### Positive

- Releases are unattended — a merge to `main` ships without waiting on the
  maintainer.
- The MAJOR misclassification the gate guarded against is now a deterministic,
  reviewable CI check rather than a human memory task.
- The signing / supply-chain surface is untouched: no new branch-protection
  bypass, no App write access to `main`, no change to the OIDC identity or
  attestation flow.

### Negative / accepted trade-offs

- **No human eyeball on releases.** A failed automated release (guard block,
  transient error) is silent unless someone watches the Actions tab. A failure
  notification is a candidate follow-up.
- **The guard replaces only the MAJOR half of what the gate caught.** General
  commit-message hygiene on direct-`main` commits (which bypass `commitlint`)
  has no human backstop now. Mitigating factor: `main` merges land as merge
  commits preserving the PR-title-derived subject.
- **The surface set is not exhaustive.** `tofu/modules/talos-cluster` interface
  changes and machine-config patches are breaking classes outside the
  mechanical net; reviewer judgment, not this guard, covers them.

## Alternatives considered

- **Keep the gate.** Rejected — it is exactly the manual wait the change removes,
  and it stalled v6.0.0.
- **Fully automate the CHANGELOG cut via commit-back to `main`.** Rejected for
  this change: on the repo's classic branch protection with strict required
  checks, a direct App push to `main` is blocked (GH006) and would require
  migrating to a ruleset with an App `always`-bypass — a permanent unreviewed
  write primitive inside the signed-artifact pipeline. Deferred to a follow-up
  that promotes the CHANGELOG via a bot PR + auto-merge (passes the required
  checks, needs no bypass).

## Follow-up

- Automate the `[Unreleased]` → `## vX.Y.Z — DATE` cut via a post-release bot PR
  with auto-merge (no direct-to-`main` push, no branch-protection bypass).
- ~~Add a `failure()`-conditioned notification on `release.yml` so an unattended
  release failure surfaces without polling.~~ Shipped, see §Amendment.

## Amendment (2026-08-25)

Issue #234. The Decision above stands; what follows corrects it where the
implementation and the record had drifted, and records the departures.

**The surface set named in §Decision 2 was wrong and is now data, not prose.**
It named `kubernetes/base/**/values.yaml`; that tree was retired by ADR-0024 and
the workflow guarded `kubernetes/substrate/` plus three globs this ADR never
mentioned. The set now lives in `.ci-release-guard-pathspec.txt` with its
membership rule in that file's header — this record does not restate it, so the
two cannot drift again. Five paths consumers actually receive were outside the
old net and are now inside it, including
`tofu/modules/talos-cluster/helm/{argocd,cilium}-values.yaml`, which `main.tf`
loads as the shipped base Helm values, i.e. the class `AGENTS.md` makes a MAJOR.
`schemas/fixtures/**` is excluded: negative lint fixtures reach no consumer
through the tarball or the pinned checkout, and blocking on them cost ten days.

`kubernetes/substrate/*/_rendered-overlay/kustomization.yaml` is deliberately
outside the set. It is a render input, so the membership rule's clause (d) would
reach it — but `scripts/verify-rendered.sh` fails on render drift inside the
**required** `validate` job, so an overlay change that affects the published
output cannot land without the matching `_rendered/` change, which clause (a)
already guards. Two depth-limited `:(glob)` entries keep it out; `:(glob)` stops
`*` crossing `/` where a plain `**` does not.

**§Decision 3's squash-merge sentence is superseded, and its premise is now
mechanical.** All three merge methods were enabled and `Commit Lint` was not a
required context, so the attestation was forgeable under every method, not only
squash. The repository is **to be** restricted to merge-commit-only, with
`merge_commit_message: BLANK` so the default merge body carries no
contributor-authored text at all, and the title lint made required. Those are
repo settings, not files: at the time this record was written they were **not
yet applied**, and `scripts/preflight-checks.sh` Check 4 is red against an admin
token until they are.
The carriers that keep the dependency from being another claim about a mutable
setting are **both in the guard**, because — measured on the first CI run — the
default `GITHUB_TOKEN` reads `allow_squash_merge`, `allow_rebase_merge`,
`merge_commit_message` and `merge_commit_title` back as `null`: those fields need
admin or push scope. `scripts/preflight-checks.sh` Check 4 is therefore a
local-admin gate like Check 1, not a CI gate, and it reports an unreadable field
as unreadable rather than as wrong.

The two carriers that hold with no API access at all:

1. an attestation is honoured only on a **merge commit** (≥2 parents), so a
   re-enabled squash or rebase merge makes the tip single-parent and the guard
   refuses;
2. an attestation is honoured only when **maintainer prose sits above the
   trailer**. With `merge_commit_message: PR_TITLE` the merge commit body is
   exactly the PR title — one contributor-authored line on a two-parent commit,
   where carrier 1 cannot discriminate. A body that is only the trailer is
   refused, and the PR-title channel structurally cannot produce anything else.

**Departures from the guard's original logic**, each measured before it was
changed: the trailer is read from the commit BODY (`%b`) because `%B` matched an
author-controlled subject line; a placeholder reason (`<reason>`, `TODO`) is
refused because both matched the line-anchored regex and the recovery command is
documented in several places; an empty `NEXT` made the guard print "guard
satisfied" and exit 0 on a changed surface; a `git diff` error was swallowed by
`|| true` and read as "no surface"; and a syntactically valid pathspec that
matches nothing is not an error to git, so a directory renamed in an earlier
release would silently guard nothing. All five now exit 2 rather than passing.

**Disclosure before decision.** The guard prints the surface list before its
verdict on every exit path, to the run log and the job summary, and the override
path states that the attestation clears every guarded file changed since the tag
— not only the merger's own. The escape hatch itself is unchanged (#234
Non-Goal); its scope is now visible at the moment it is used.

**Notification scope.** The `notify` job covers a guard verdict, any `plan`
failure, and a `release` failure — not merely the guard-block half. `release` is
*skipped* rather than failed when `plan` dies, so the `plan`-result disjunct is
what actually carries the infrastructure classes ADR §Consequences named.

**Residuals, recorded rather than closed.** `NEXT` is scraped from
semantic-release's human-readable dry-run log, which also contains contributor
commit subjects; the scrape now takes the first match (the version line precedes
the generated notes) and the `release` job refuses to publish a version that
differs from the one the guard judged, but the input remains a log parse. A tag
pushed at `HEAD` empties the compared range, so the guard reports `guard n/a` —
inherent to a range-based check, not closed here. The trailer is read from the tip
only, so an ordinary push after an attested one re-arms the block for the same
attested change — the guard reports a prior attestation it finds in the range and
names the re-attest command, but does not honour it. `Commit Lint`'s presence in
the required-context list is asserted only by Check 1, which degrades to a
warning in CI because the default token cannot read branch protection.

## Amendment (2026-08-31)

**The settings §Amendment (2026-08-25) recorded as outstanding are applied.**
`allow_squash_merge` and `allow_rebase_merge` are off, `merge_commit_message` is
`BLANK`, and `lint-pr-title` is a required context. `scripts/preflight-checks.sh`
Check 4 passes against an admin token.

Two corrections to that record. `merge_commit_title` is `PR_TITLE`, not
`MERGE_MESSAGE`: GitHub accepts only `PR_TITLE`+`PR_BODY`, `PR_TITLE`+`BLANK`
and `MERGE_MESSAGE`+`PR_TITLE`, so the combination the check demanded does not
exist, and `PR_TITLE`+`BLANK` is the only accepted pair that empties the body.
The merge subject is therefore contributor-supplied, which is why the title lint
is required rather than merely advisory.

And Check 4 is no longer "a local-admin gate, not a CI gate". It runs weekly in
`policy-audit.yml` under a GitHub App token with `Administration:read`. The
PR-attached `preflight` workflow that could not read any of these fields is
deleted: it reported success without looking, which is worse than no check. An
unreadable setting is now a failure rather than a warning, so a green run means
the setting was read.

## Amendment (2026-08-31, second)

**Correction to the amendment above: the merge settings are not readable from
CI at all.** That entry said Check 4 now runs in CI under an App token with
`Administration:read`. Measured on two `policy-audit.yml` runs, it does not:
`allow_squash_merge`, `allow_rebase_merge`, `merge_commit_message` and
`merge_commit_title` come back `null` under `Administration:read`, and adding
`Contents:read` changed nothing. Only an admin-scoped credential fills them in.
Checks 1 to 3 do work under that App token.

Rather than give a read-only audit token write permission on repository
administration, Check 4 falls back to the **effect** when the settings are
unreadable: the newest commit on `main` must have two parents. Squash and
rebase both leave a single-parent tip, so a one-parent newest commit means one
of them is enabled again — which is the half of the setting the attack needs,
since squash is what concatenates a contributor's commit body into the tip the
guard parses. The body itself is deliberately not checked: a maintainer-typed
body is legitimate, it is where `Allow-Non-Major:` goes.

Cost, stated rather than hidden: the effect check trails by one merge. It
notices a reverted setting only after a merge has happened under it. The direct
reading stays the primary path on a local admin run.
