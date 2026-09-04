---
type: workflow
title: Release Process
description: How a release moves from conventional commit through the automated semantic-release flow and the MAJOR-bump guard to a signed OCI artifact on ghcr.io.
tags: [release, semantic-release, oci, supply-chain]
generated: { by: human:nosmoht, at: "2026-09-04T00:00:00Z" }
sources:
  - resource: .github/workflows/release.yml
  - resource: scripts/release-major-bump-guard.sh
  - resource: scripts/release-guard-lib.sh
  - resource: .ci-release-guard-pathspec.txt
  - resource: .github/workflows/commitlint.yml
  - resource: .github/workflows/oci-publish.yml
  - resource: .releaserc.json
  - resource: package.json
  - resource: CHANGELOG.md
  - resource: CONTRIBUTING.md
---

# Release Process

Releases are conventional-commit-driven and fully automated — no human
approval step. The chain is: PR title lint → merge to `main` → `release.yml`
plan (dry-run) → hard MAJOR-bump guard → semantic-release cuts the tag → the
tag push triggers `oci-publish.yml`, which builds, signs, attests, and
publishes the OCI artifact plus the GitHub Release.

The former manual approval gate (an `environment: release` protection) was
removed so a merge to `main` releases without operator action. Its one
mechanical function — catching a breaking base-surface change that ships
without a MAJOR bump — is now a blocking CI check (the MAJOR-bump guard,
below). What the human gate additionally provided implicitly (an eyeball on
every release) is **not** replaced; automated releases are unattended.

## Commit gate — commitlint on the PR title

`.github/workflows/commitlint.yml` (job `lint-pr-title`, action
`amannn/action-semantic-pull-request` v5) lints the **PR title**, not the
individual commits. It **is** a required status check as of 2026-08-31,
together with the merge-method settings ADR-0020 §Amendment recorded as
outstanding.

The release type does *not* come from the title. `merge_commit_title` is
`PR_TITLE`, so the merge subject on `main` is the PR title — which is why the
title lint is required; semantic-release computes the bump from the
branch commits preserved in the range. What the title lint buys is narrower and
load-bearing: `merge_commit_message` is `PR_TITLE`, so the title becomes the
merge commit **body** — the line the MAJOR-bump guard reads. The closed type list
below is what keeps an `Allow-Non-Major:` line out of it.

- Allowed types: `feat`, `fix`, `perf`, `chore`, `docs`, `test`, `refactor`, `ci`.
- `requireScope: false` — a scope like `fix(cilium): …` is house style per
  `CONTRIBUTING.md`, not mandatory.
- The gate applies to PRs only; direct-`main` commits bypass it. With the
  manual release approval removed, there is **no** human backstop for a
  malformed direct-`main` commit subject; the MAJOR-bump guard below covers
  only the breaking-surface-without-MAJOR class, not commit-message hygiene in
  general. The mitigating factor is that `main` merges land as merge commits
  that preserve the PR-title-derived subject.

## Version computation — `.releaserc.json`

`.releaserc.json` configures semantic-release with `branches: ["main"]`,
`tagFormat: "v${version}"`, and two plugins: `@semantic-release/commit-analyzer`
and `@semantic-release/release-notes-generator`, both with the
`conventionalcommits` preset.

There is deliberately **no publish plugin**: `@semantic-release/github` was
removed because it published an asset-less GitHub Release the moment it tagged,
and release immutability then refused every asset upload `oci-publish.yml`
attempted (#251, and the [Amendment
(2026-09-04)](../decisions/0020-automated-release-no-approval-gate.md) to
ADR-0020). semantic-release core creates and pushes the git tag itself —
`publish` is an optional lifecycle step — so dropping the plugin costs the
GitHub Release object and nothing else. `release-notes-generator` stays: its
output no longer reaches a release, but the dry-run prints it into the `plan`
log, which is where a maintainer reads what the computed version contains.

The toolchain is pinned in
`package.json` (`semantic-release` 25.0.5,
`conventional-changelog-conventionalcommits` 9.3.1) — the repo is **not** a
Node project; the manifest exists only to pin npm-distributed tooling
(it also carries the `openspec`/`markdownlint-cli` gate pins, see the
spec-driven-development workflow) and is excluded from the OCI tarball.

No custom `releaseRules` are declared, so the commit-analyzer defaults apply:

- `feat` → MINOR.
- `fix` / `perf` → PATCH.
- `BREAKING CHANGE:` footer or `type!:` marker → MAJOR.
- `refactor`, `docs`, `chore`, `test`, `ci` → **no release** (no default
  release rule; a refactor-only history produces "no relevant changes").

A prose `**BREAKING**` line in the commit body is **not** recognized — only
the footer or the `!` marker bumps MAJOR (`CONTRIBUTING.md` §Conventional
commits). This carries the `AGENTS.md` rule that a breaking change to base
Helm values requires a MAJOR bump: without the footer, the change ships as a
non-breaking release.

## Plan and release — `.github/workflows/release.yml`

Triggered on every push to `main` (concurrency group `release-main`,
`cancel-in-progress: false` so a half-done release is never cancelled).

### Job `plan` (ungated dry-run)

- `npm ci --ignore-scripts`, then `npx semantic-release --dry-run`.
- Greps the log for "the next release version is X.Y.Z" and emits
  `will-release` / `next-version` outputs plus a `# Release plan` job summary
  showing the next version (or "No release").
- **MAJOR-bump guard** (blocking, `if: will-release == 'true'`): when a
  published base-surface path changed since the last tag but the computed bump
  is not MAJOR, the step **fails** — blocking `release` (which is
  `needs: plan`). The logic lives in `scripts/release-major-bump-guard.sh`; the
  guarded set and its membership rule live in `.ci-release-guard-pathspec.txt`,
  which is the single source — this document deliberately does not restate the
  list. Deliberate carve-outs are in `.ci-release-guard-exempt.txt`, one reason
  per entry. Gated on `will-release`, so a non-releasing push (docs/chore) never
  fails it; the job summary above is unconditional, so a surface change parked on
  `main` without a release is visible there.
  **Override:** a maintainer who has confirmed the change is genuinely
  non-breaking adds an `Allow-Non-Major: <reason>` trailer to the **body** of the
  merge commit. Four properties make it an attestation rather than a string: it
  is read from the body only; it is honoured only on a merge commit (≥2 parents,
  so a re-enabled squash or rebase merge makes the guard fail closed); it needs
  maintainer prose above it, so a body that is only the trailer — which is what
  a PR-title-derived merge body is — is refused; and a placeholder reason is
  refused. Additive, backward-compatible edits to a guarded
  path (a new optional schema field, a new default value) are the expected
  override case — the guard flags any change to the path, not only breaking ones.
  The set is the high-signal subset a dropped `type!:` marker most often slips
  through — it is **not** exhaustive (tofu module interfaces and machine-config
  patches are out of the mechanical net; reviewer judgment covers those).
  `task supply-chain:check-release-guard` is the binding: a required `docs-lint`
  step that fails if a published tarball member is neither guarded nor
  exempt-with-reason, or if the guard stops biting.
- The job runs with `GITHUB_TOKEN`, which cannot push to protected `main` nor
  trigger downstream workflows — so this ungated job cannot cut a real release.

### Job `release` (unattended)

Runs whenever `will-release == 'true'` and `plan` (incl. the guard) passed — no
approval step. It mints a GitHub App token (`vars.RELEASE_APP_ID` +
`secrets.RELEASE_APP_PRIVATE_KEY`), checks out with `persist-credentials:
false`, and runs the real `npx semantic-release` with the App token. The App
token matters: tags pushed with the default `GITHUB_TOKEN` do not trigger other
workflows, so the App token is what makes the `v*` tag push fire
`oci-publish.yml` while preserving its signing identity. semantic-release does
**not** commit anything back to `main`, and it no longer creates the GitHub
Release either — it tags, and `oci-publish.yml` owns the release object;
`CHANGELOG.md` is cut by hand in the releasing PR (automating that cut is
tracked as a follow-up).

## When the release is blocked

**This section is the authoritative copy of the recovery procedure.** The PR
template, the guard's own `::error::` output and the `release-guard-advisory` job
all point here.

Three facts make the recovery non-obvious:

1. **Re-running the failed workflow can never help.** The guard reads the
   attestation from `git log -1` — the tip commit. A re-run inspects the same
   tip.
2. **The trailer has to land on a NEW tip commit**, and `main` is protected, so
   that means another pull request — not a push.
3. **`gh pr merge --merge` with no `--body` cannot carry it.** With
   `merge_commit_message: PR_TITLE` the body is the PR title, and `Commit Lint`
   rejects a title shaped like a trailer. `AGENTS.md §Issue-Interface` declares
   the `--subject`/`--body` form for this reason.

The procedure:

```bash
# 1. read what is actually blocking — the run log lists it, or locally:
./scripts/release-major-bump-guard.sh --advisory

# 2. decide. If any listed change IS breaking, do not attest: land a commit
#    carrying a `BREAKING CHANGE:` footer or a `type!:` marker and let the
#    release go MAJOR.

# 3. if every listed change is genuinely non-breaking, merge the next PR with an
#    attestation in the BODY:
gh pr merge <N> --merge \
  --subject "fix(scope): what the PR does" \
  --body $'why this is not breaking\n\nAllow-Non-Major: the only guarded change since v9.1.0 is an additive optional key in schemas/cluster.schema.json; nothing that validated before stops validating'
```

The reason is not decoration. A placeholder (`<reason>`, `TODO`, `FIXME`, a bare
`reason`, or anything under 12 characters) is refused, because the example above
is published in three places and a copy-paste must not attest anything.

**The attestation covers every guarded path changed since the last tag**, not
only the ones the merged PR touched. The guard prints that full set before its
verdict, in the run log and the job summary, precisely so the scope is visible at
the moment it is used.

**An attestation does not survive a later push.** It is read from the tip commit
only, so an ordinary merge after an attested one re-arms the block for the same,
already-attested change. The guard notices a prior attestation in the range and
says so, but does not honour it — re-attest on the new tip.

**Recovery latency is bounded by the required checks**, not by the guard: the
recovery PR clears `validate`, `Secret Scan (gitleaks)`, `docs-lint`,
`Hard Constraints` and `lint-pr-title` like any other.

If the block is not what you expected — a path you believe should not be guarded
at all — the supported route is to **move** it into
`.ci-release-guard-exempt.txt` with a reason, not to delete it from the pathspec.
`scripts/check-release-guard-coverage.sh` prints the exact five-file edit
sequence when it refuses.

### When the guard errors (exit 2)

A `guard error` verdict is a different situation from `guard blocked`, and the
attestation route above **cannot** clear it — the guard exits before the trailer
is read. The causes are enumerated in
[ADR-0020 §Amendment](../decisions/0020-automated-release-no-approval-gate.md);
each is an environment fault, not a judgement call: tags not fetched, a shallow
checkout, an unresolvable tag, a `NEXT` that is missing or below the highest
stable tag, a pathspec entry that matches nothing at the base (a guarded
directory renamed in an earlier release), or a malformed data file. Fix the
cause; there is nothing to attest.

### Break glass — the guard itself is broken

If the guard errors on every push and the cause cannot be fixed quickly, note
that removing it is deliberately not a one-file edit:
`scripts/check-release-guard-coverage.sh` fails when `release.yml` stops
invoking the guard, and it runs in the **required** `docs-lint` context — so a
naive revert PR is un-mergeable. The supported emergency revert touches, in one
PR: the guard step in `.github/workflows/release.yml`, the invocation assertion
in `scripts/check-release-guard-coverage.sh`, the
`supply-chain:check-release-guard` step in `.github/workflows/docs-lint.yml`, and
its Taskfile target. That PR still clears the required checks. The alternative,
for a repo admin, is an admin merge of the minimal revert; prefer the four-file
PR, because the admin path leaves no record of what was disabled.

## CHANGELOG contract

`CHANGELOG.md` is **hand-maintained** (Keep a Changelog sections under
`## Unreleased`); semantic-release ships no changelog plugin here.

`## [Unreleased]` carries two blocks with different lifetimes. `### Pending
release` holds entries awaiting the next tag: the by-hand cut moves **that block
only** under the new `## vX.Y.Z — DATE` heading. The historical-backfill block
below it documents entries that shipped in `v7.0.0`–`v9.0.0` without a CHANGELOG
section (tracked in #233) and stays where it is across every cut until that
backfill lands. Released
sections use the exact header form (illustrative example):

```markdown
## v2.0.0 — 2026-06-22
```

`oci-publish.yml` extracts release notes with an awk exact-prefix match on
`## <tag>` followed by a single space (the body runs until the next `##`
heading). If no matching section exists, the workflow **silently falls back**
to `gh release create --generate-notes` — a renamed or malformed header
degrades release notes without failing the release.

Note the interaction with `release.yml`: nothing there creates a GitHub
Release, so the CHANGELOG-extraction path runs on **every** release, automated
or manually tagged. A renamed or malformed version header therefore
degrades the notes of a normal release, not just a hand-pushed one.

## Publish — `.github/workflows/oci-publish.yml`

Triggered on `push` of tags `v*` (job `publish`):

1. **Build tarball** from the `.ci-oci-tarball-include.txt` allowlist
   (fail-closed: any path not listed is excluded by default).
2. **Verify tarball contents** against the committed
   `.ci-oci-tarball-expected.txt` fixture — divergence fails the job. Run
   `task supply-chain:oci-allowlist` locally before tagging to pre-check
   (see [tasks reference](../reference/tasks.md)).
3. **Checksums** (`sha256sum`), then **`oras push`** to
   `ghcr.io/<owner>/talos-platform-base:<tag>` with artifact type
   `application/vnd.talos-platform-base.v1+tar`.
4. **cosign sign** (keyless OIDC, `--yes`) against the pushed digest —
   anchors the signature to the workflow's GitHub OIDC identity.
5. **SLSA build provenance** via `actions/attest-build-provenance`
   (pushed to the registry).
6. **SBOM**: CycloneDX 1.6 JSON generated by `anchore/sbom-action`, attached
   via `cosign attest --type cyclonedx`.
7. **`:latest` tag** — skipped for any hyphenated tag (SemVer pre-release
   identifiers must not become the default consumers pin).
8. **GitHub Release** — created as a **draft** with notes from the matching
   CHANGELOG section (or auto-generated on mismatch) and `--prerelease` for
   hyphenated tags, the three assets attached to that draft (the tarball,
   `checksums.txt`, and the CycloneDX SBOM), and only then flipped to
   published. The order is not stylistic: release immutability freezes a
   release when it is **published**, and a published release rejects every
   asset upload with HTTP 422, so the draft window is the only place assets can
   be attached. ghcr.io remains the authoritative, signed consumption path.
9. **Asset assertion** — the published release is read back and its asset names
   compared against the three expected ones. A publish that loses an asset
   fails the job, and the `notify` job below turns that into a tracking issue.

A failure anywhere in `publish` opens or updates one tracking issue titled
"release: the OCI publish did not complete" (job `notify`, mirroring
`release.yml`). Before this existed, a failed publish was visible only in the
Actions tab of a tag nobody was watching.

Consumer-side signature/provenance verification is covered in
[verify-release](verify-release.md).

## A release that shipped without assets

**This section is the authoritative copy of the asset-recovery procedure.** The
publish job's `::error::` output and the `notify` issue body both point here.

A published GitHub Release is immutable: its assets cannot be added, replaced,
or deleted, and no API call or workflow re-run changes that. So a release that
shipped without its assets stays that way — recovery is forward-only:

1. Confirm what is actually missing. The OCI artifact and the release assets
   fail independently:
   `oras manifest fetch ghcr.io/nosmoht/talos-platform-base:<tag> --descriptor`
   against `gh release view <tag> --json assets`. When the artifact is present,
   consumers on the `oras pull` path documented in
   [verify-release](verify-release.md) are unaffected and only the
   release-asset path is broken.
2. Do not re-run the publish workflow for that tag expecting a repair. The job
   refuses to touch an already-published release and exits non-zero, by design
   — the alternative was three HTTP 422s and a green-looking failure.
3. Record the tag as asset-less in [verify-release](verify-release.md)
   §Releases without assets, so a consumer is not sent after files that do not
   exist.
4. If the assets are genuinely needed, cut a **new** tag. Under the automated
   flow that means landing a releasing commit; there is no un-publish and no
   in-place amendment.

The five tags that shipped asset-less this way (`v9.2.2`, `v9.2.3`, `v10.0.0`,
`v11.0.0`, `v11.0.1`) plus the two earlier ones whose publish failed for an
unrelated reason (`v9.1.2`, `v9.2.0`) are listed in
[verify-release](verify-release.md).

## End-to-end summary

1. Author commits per conventional-commit rules; PR title linted by
   `lint-pr-title`. CHANGELOG `[Unreleased]` is cut by hand in the same PR.
2. Merge to `main` → `plan` computes the next version into the job summary and
   runs the blocking MAJOR-bump guard.
3. Guard passes → `release` runs unattended (no approval) → semantic-release
   tags `v<version>`. It creates no Release object and does not commit back to
   `main`.
4. Tag push (App token) → `oci-publish.yml` builds the allowlisted tarball,
   signs, attests (SLSA + SBOM), publishes to
   `ghcr.io/nosmoht/talos-platform-base:<tag>`, then creates the GitHub Release
   as a draft carrying the tarball, checksums, and SBOM and publishes it.

## Rollback — a defective tag

There is no un-publish and no automatic interception (ADR-0020 removed the
manual gate). The model is **forward-fix plus new tag**:

1. Fix the defect on `main` (revert commit or corrective commit); the merge
   releases the corrected version unattended.
2. Move `:latest` off the bad digest if consumers resolve it — the pipeline
   never does this by itself:
   `oras tag ghcr.io/nosmoht/talos-platform-base:v<fixed> latest`.
3. Leave the bad tag in place (immutable history; consumers pin exact tags
   and verify cosign identity), but note it in `CHANGELOG.md` and, when a
   consumer action is needed, in `UPGRADING.md`.
4. Consumers that already adopted the bad tag roll their pin forward to the
   fixed tag — never backward past a MAJOR/layout boundary without applying
   the paired consumer-side reverts documented in the relevant `UPGRADING.md`
   section (e.g. the ADR-0024 relocation's pin+paths pairing).
