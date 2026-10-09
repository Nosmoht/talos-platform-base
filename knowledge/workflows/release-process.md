---
type: workflow
title: Release Process
description: How a release moves from the PR title through the automated semantic-release flow to a signed OCI artifact on ghcr.io.
tags: [release, semantic-release, oci, supply-chain]
generated: { by: human:nosmoht, at: "2026-10-09T00:00:00Z" }
sources:
  - resource: .github/workflows/release.yml
  - resource: scripts/preflight-checks.sh
  - resource: .github/workflows/commitlint.yml
  - resource: .github/workflows/oci-publish.yml
  - resource: .releaserc.json
  - resource: package.json
  - resource: CHANGELOG.md
  - resource: CONTRIBUTING.md
---

# Release Process

Releases are conventional-commit-driven and fully automated — no human
approval step. The chain is: PR title lint → squash merge to `main` →
`release.yml` plan (dry-run) → semantic-release cuts the tag → the tag push
triggers `oci-publish.yml`, which builds, signs, attests, and publishes the OCI
artifact plus the GitHub Release.

The former manual approval gate (an `environment: release` protection) was
removed so a merge to `main` releases without operator action
([ADR-0020](../decisions/0020-automated-release-no-approval-gate.md)). Its
successor, a path-based MAJOR-bump guard with an `Allow-Non-Major:` override, was
removed in turn by the #292 cutover
([ADR-0029](../decisions/0029-public-api-and-major-rule.md) §Amendment
(2026-10-09)). Whether a change is MAJOR is judged once, by the reviewer, on the
PR title; nothing re-checks the content mechanically.

## Commit gate — commitlint on the PR title

`.github/workflows/commitlint.yml` (job `lint-pr-title`, action
`amannn/action-semantic-pull-request` v5) lints the **PR title**, not the
individual commits. It **is** a required status check as of 2026-08-31,
together with the merge-method settings ADR-0020 §Amendment recorded as
outstanding.

Pull requests are **squash-merged only**: `squash_merge_commit_title` is
`PR_TITLE` and `squash_merge_commit_message` is `BLANK`, and merge commits and
rebase merges are disabled. Each commit on `main` is therefore one PR whose
subject is its title plus a `(#N)` suffix and whose body is empty, and the title is the
**only** input to the version bump. Branch commits, their footers and the PR
description never reach `main`. `AGENTS.md §Issue-Interface` `state:close`
copies the linted title into `--subject` and passes `--body ""` explicitly, so
the subject is the linted title and the body stays empty whatever the settings
say.
`scripts/preflight-checks.sh` Check 4 asserts the settings with an admin
credential; the weekly `policy-audit.yml` run cannot read them and checks the
newest commit's shape instead (one parent, a `(#N)` suffix, an empty body).

- Allowed types: `feat`, `fix`, `perf`, `chore`, `docs`, `test`, `refactor`, `ci`.
- `requireScope: false` — a scope like `fix(cilium): …` is house style per
  `CONTRIBUTING.md`, not mandatory.
- The gate applies to PRs only; direct-`main` commits bypass it, and with the
  manual release approval removed there is **no** backstop for a malformed
  direct-`main` commit subject. `main` is protected, so such a commit needs an
  admin push.

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
`package.json` (`semantic-release` plus
`conventional-changelog-conventionalcommits`) — read the versions from there,
never from this page, which carried a stale one for three minor releases. The
repo is **not** a Node project; the manifest exists only to pin npm-distributed tooling
(it also carries the `openspec`/`markdownlint-cli` gate pins, see the
spec-driven-development workflow) and is excluded from the OCI tarball.

No custom `releaseRules` are declared, so the commit-analyzer defaults apply:

- `feat` → MINOR.
- `fix` / `perf` → PATCH.
- `BREAKING CHANGE:` footer or `type!:` marker → MAJOR.
- `refactor`, `docs`, `chore`, `test`, `ci` → **no release** (no default
  release rule; a refactor-only history produces "no relevant changes").

With a blank squash body, the `!` in the PR title is the only marker that
reaches the analyzer. The analyzer would also read a body line matching the
`conventional-commits-parser` note pattern (`BREAKING CHANGE` or
`BREAKING-CHANGE` in any letter case, followed by a colon or whitespace), which
is why the body must stay empty. Which changes are MAJOR is decided by
[ADR-0029](../decisions/0029-public-api-and-major-rule.md) §Classification.

## Plan and release — `.github/workflows/release.yml`

Triggered on every push to `main` (concurrency group `release-main`,
`cancel-in-progress: false` so a half-done release is never cancelled).

### Job `plan` (ungated dry-run)

- `npm ci --ignore-scripts`, then `npx semantic-release --dry-run`.
- Greps the log for "the next release version is X.Y.Z" and emits
  `will-release` / `next-version` outputs plus a `# Release plan` job summary
  showing the next version (or "No release").
- The job runs with `GITHUB_TOKEN`, which cannot push to protected `main` nor
  trigger downstream workflows — so this ungated job cannot cut a real release.

### Job `release` (unattended)

Runs whenever `will-release == 'true'` and `plan` passed — no approval step. It mints a GitHub App token (`vars.RELEASE_APP_ID` +
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

**This section is the authoritative copy of the recovery procedure.** The
tracking issue `notify` opens points here.

The release no longer blocks on content. It fails only when `plan` or
`release` fails: the dry-run errors (npm, registry, a missing tag), or the
`release` job computes a different version than `plan` did — it refuses to ship
a version nobody saw planned. Read the run log, fix the cause, and re-run the
workflow or push the next merge.

### When a release carries the wrong class

A mis-titled PR ships at once, and a published release is immutable. Do not
edit the merged PR's title: the subject on `main` is what counted.

- **A break shipped as MINOR or PATCH:** restore compatibility with a revert PR,
  titled by its own effect on the released state as ADR-0029 §Planned: cutover
  and reverts says — reverting a released rename or removal can itself be MAJOR.
  Then re-land the change under a `!` title with an `UPGRADING.md` note.
- **A MAJOR that breaks nothing, or a missed MINOR or PATCH:** nothing to undo;
  record the misclassification in the next release's `CHANGELOG.md` entry.

## CHANGELOG contract

`CHANGELOG.md` is **hand-maintained** (Keep a Changelog sections under
`## Unreleased`); semantic-release ships no changelog plugin here.

The same by-hand pass renames any `## Unreleased (next <CLASS>)` heading in
`UPGRADING.md` to the tag being cut. `<CLASS>` is MAJOR, MINOR or PATCH: the
unreleased heading names the class the section is expected to ship in, and the
renamed heading carries the class of the tag actually cut. That file's own §How
to use this file tells consumers to locate sections by their tag heading, so a
section authored before the version is known carries the unreleased form until
the cut and is renamed here — nothing automates it.

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
or manually tagged. A renamed or malformed version header therefore degrades
the notes of a normal release, not just a hand-pushed one — and the degrade is
the current norm rather than an edge case: the newest cut section is
`## v9.1.0`, so every tag since has taken the `--generate-notes` fallback
(#233 tracks the backlog).

Where the new `## vX.Y.Z — DATE` heading goes matters for the same reason. The
extractor prints everything from that heading to the next second-level
heading, and third-level sub-headings do not stop it. Put the heading **below** the historical-backfill
block that stays inside `[Unreleased]`, so the section it opens contains only
the moved `### Pending release` entries; placed above the backfill it would
swallow all of it into one patch release's notes, and the awk cannot tell.

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
   `checksums.txt`, and the CycloneDX SBOM), **the draft's assets verified**,
   and only then flipped to published with `make_latest=legacy`. The order is
   not stylistic: release immutability freezes a release when it is
   **published**, and a published release rejects every asset upload with HTTP
   422, so the draft window is the only place assets can be attached — and the
   only place a missing one can still be caught and discarded. An
   already-published release for the tag is refused outright; two drafts are
   refused rather than one being orphaned. ghcr.io remains the authoritative,
   signed consumption path.
9. **End-state assertion** — the published release is read back through the
   tag endpoint consumers use, and its asset set compared against the three
   expected files (`state == "uploaded"` and non-zero size, so a truncated
   upload does not pass on its filename alone).

Both steps are exercised on every PR by `task supply-chain:check-release-step`,
which extracts them from the workflow and drives them against a stub `gh`
through each release state — they never run on a PR themselves, and a tag
cannot be re-released.

A `publish` job that does not succeed — failed, cancelled, or timed out —
opens or updates one tracking issue titled "release: the OCI publish did not
complete" (job `notify`), and a successful one closes it (`notify-resolved`),
mirroring `release.yml`'s pair. Before this existed, a failed publish was
visible only in the Actions tab of a tag nobody was watching. The workflow also
serializes on a single `oci-publish` concurrency group, because it now moves
both `:latest` and the release's Latest flag.

Consumer-side signature/provenance verification is covered in
[verify-release](verify-release.md).

## When the publish job fails

**This section is the authoritative copy of the publish-recovery procedure.**
The `notify` issue body points here. Read the state the run left behind first;
most of these are repaired by re-running the workflow for the same tag, and
only the last one costs a version.

| What the run left | How to tell | Recovery |
|---|---|---|
| No GitHub Release at all | `gh release view <tag>` fails | Re-run the workflow for the tag |
| An unpublished draft, complete | the release shows as Draft AND carries all three assets, and every step before `Create GitHub Release` succeeded | Publish that draft — see §Publishing the draft the job built |
| An unpublished draft, incomplete | the release shows as Draft with assets missing, or an earlier step failed | Re-run: it discards the draft and rebuilds a complete one |
| Two drafts for the tag | the job says so and refuses | Delete them by hand, then re-run |
| `:latest` on a tag with no release | `oras manifest fetch …:latest --descriptor` against the tag's digest | Re-run; if the tag is defective instead, move `:latest` per §Rollback |
| A published release with no assets | see the section below | Forward-only — a new tag |

A re-run recovers the RELEASE OBJECT for every row above the last, because it
is created as a draft and published only after its assets are verified:
nothing immutable exists yet. Re-run from the Actions tab (`Publish OCI
artifact` → the run for the tag → Re-run all jobs).

**A re-run is not free, and it is not idempotent.** It re-executes the whole
job from the tarball build, and the tarball is not byte-reproducible — it
carries the mtimes of a fresh checkout. So a re-run:

- pushes a **new digest** to `ghcr.io/<owner>/talos-platform-base:<tag>`, i.e.
  the tag is remapped;
- mints a **second** cosign signature and a **second** SLSA provenance for the
  same version, both individually valid;
- moves `:latest` again for a non-hyphenated tag.

Consumers who pinned the digest (which
[verify-release](./verify-release.md) tells them to do, for exactly this
reason) keep resolving the first artifact and must re-pin deliberately; anyone
resolving the tag silently moves. Say so in the release notes or `UPGRADING.md`
when a re-run happens after consumers could already have vendored the tag.

## Publishing the draft the job built

When every step before `Create GitHub Release` succeeded and the draft carries
all three assets, the work is done and only the final `draft=false` never ran.
Publish that draft instead of re-running:

```sh
id="$(gh api --paginate repos/<repo>/releases \
  --jq '.[] | select(.tag_name=="<tag>" and .draft) | .id')"
gh api --method PATCH "repos/<repo>/releases/${id}" \
  -F draft=false -f make_latest=legacy --jq .html_url
```

That is the call the failed step would have made last, `make_latest=legacy`
included. Then verify what a consumer sees: `shasum -a 256 -c checksums.txt`
against the attached tarball, and `oras pull` of the same tag compared byte-wise
against it.

**Prefer this over a re-run when it applies**, because a re-run remaps the tag
to a new digest and mints a second signature and provenance — see the
non-idempotence warning above. It does NOT apply to a draft with missing assets:
the job's own guard refuses to publish one, and so should a human.

`v14.0.0` was recovered this way. The run failed because the publish step
looked the release up in a listing that had not yet caught up with the creation
— under 0.6s after creating it — while the artifact, signature, attestations
and `:latest` were all already in place. That lookup now addresses the release
by the url the create returned and retries while the listing is behind (#276),
so this section applies to a run that fails for some other reason at the same
point.

## A release that shipped without assets

**This section is the authoritative copy of the asset-recovery procedure.** The
publish job's `::error::` output points here for the already-published case.

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
`v11.0.0`, `v11.0.1`) keep their artifacts. Two earlier tags, `v9.1.2` and
`v9.2.0`, failed upstream of the push and have no artifact either — a
different, worse state. Both groups, and what a consumer should do with each,
are in [verify-release](verify-release.md) §Releases without assets.

## Which endpoint can see a draft release

Three lookups behave differently on a DRAFT, and the difference is not
documented by GitHub. Measured against this repository's own API on
2026-09-17, by creating a draft and deleting it again:

| Lookup | On a draft |
|---|---|
| `GET /repos/{repo}/releases/tags/{tag}` | **404** — the tags endpoint does not return drafts |
| `GET /repos/{repo}/releases` (the list) | returns it, but **not immediately**: a draft read back by id straight after creation was still absent from the list |
| `gh release view {tag} --json ...` | returns it, via GraphQL — so the id is a `node_id` (`RE_kwD…`), not the REST `databaseId` |

Two consequences for anyone editing `oci-publish.yml`:

**The list endpoint is not a mistake to be cleaned up.** It is there precisely
because the tags endpoint cannot see the state the publish flow lives in. An
edit that "simplifies" it to `GET /releases/tags/{tag}` fails every run, on a
tag push, where the cost is a version.

**A tag is not an identity.** Every tag-keyed lookup — the list filtered on
`tag_name`, `gh release view {tag}` — resolves to a SET, and more than one
draft can exist for one tag. Combined with the list's lag, a lookup by tag can
return somebody else's draft while this run's own has not landed, which is why
the step addresses its release by the `html_url` that `gh release create`
printed. See §Publishing the draft the job built and issue #276.

GitHub states no read-after-write guarantee for the list endpoint either way —
the entry above is measurement, not a documented contract, so treat the window
as unbounded rather than as the sub-second one that happened to be observed.

## End-to-end summary

1. The PR title carries the release class (ADR-0029 §Classification) and is
   linted by `lint-pr-title`; the reviewer checks the class. CHANGELOG
   `[Unreleased]` is cut by hand in the same PR.
2. Squash merge to `main` → `plan` computes the next version from the PR
   titles in the range into the job summary.
3. `release` runs unattended (no approval) → semantic-release
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
