---
type: decision
title: "ADR: Remove the manual release approval gate; replace its MAJOR backstop with a blocking CI guard"
description: "Drops the environment:release manual-approval protection so a merge to main releases unattended, and replaces the gate's one mechanical function — catching a breaking base-surface change shipped without a MAJOR bump — with a blocking MAJOR-bump guard in the plan job."
status: stable
id: base:automated-release-no-approval-gate
decided: "2026-07-21T00:00:00Z"
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
- Add a `failure()`-conditioned notification on `release.yml` so an unattended
  release failure surfaces without polling.
