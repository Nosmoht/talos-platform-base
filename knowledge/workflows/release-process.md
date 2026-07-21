---
type: workflow
title: Release Process
description: How a release moves from conventional commit through the automated semantic-release flow and the MAJOR-bump guard to a signed OCI artifact on ghcr.io.
tags: [release, semantic-release, oci, supply-chain]
timestamp: 2026-07-21
sources:
  - .github/workflows/release.yml
  - .github/workflows/commitlint.yml
  - .github/workflows/oci-publish.yml
  - .releaserc.json
  - package.json
  - CHANGELOG.md
  - CONTRIBUTING.md
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
individual commits. Rationale in the workflow header: squash-merge uses the PR
title as the resulting commit subject on `main`, and that subject is what
semantic-release parses.

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
`tagFormat: "v${version}"`, and three plugins: `@semantic-release/commit-analyzer`
and `@semantic-release/release-notes-generator` (both with the
`conventionalcommits` preset) plus `@semantic-release/github`
(`successComment` and `failComment` disabled). The toolchain is pinned in
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
  `needs: plan`). The surface set is `.ci-oci-tarball-{include,expected}.txt`,
  `schemas/**`, `platform-hardware-features.yaml`, `contracts/**`, and
  `kubernetes/base/**/values.yaml`. Gated on `will-release`, so a non-releasing
  push (docs/chore) never fails it. **Override:** a maintainer who has confirmed
  the change is genuinely non-breaking adds an `Allow-Non-Major: <reason>` git
  trailer to the tip (merge) commit, downgrading the block to a warning. The
  match is anchored to line-start (a prose mention or negation cannot trigger
  it); under squash-merge the merging maintainer must verify the trailer in the
  concatenated body. Additive, backward-compatible edits to a surface path (a
  new optional schema field, a new default value) are the expected override
  case — the guard flags any change to the path, not only breaking ones. The
  set is the
  high-signal subset a dropped `type!:` marker most often slips through — it is
  **not** exhaustive (tofu module interfaces and machine-config patches are out
  of the mechanical net; reviewer judgment covers those).
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
**not** commit anything back to `main` — it tags and creates the GitHub Release
only; `CHANGELOG.md` is cut by hand in the releasing PR (automating that cut is
tracked as a follow-up).

## CHANGELOG contract

`CHANGELOG.md` is **hand-maintained** (Keep a Changelog sections under
`## Unreleased`); semantic-release ships no changelog plugin here. Released
sections use the exact header form (illustrative example):

```markdown
## v2.0.0 — 2026-06-22
```

`oci-publish.yml` extracts release notes with an awk exact-prefix match on
`## <tag>` followed by a single space (the body runs until the next `##`
heading). If no matching section exists, the workflow **silently falls back**
to `gh release create --generate-notes` — a renamed or malformed header
degrades release notes without failing the release.

Note the interaction with `release.yml`: `@semantic-release/github` creates
the GitHub Release when it tags, so under the automated flow `oci-publish.yml`
usually finds the Release already existing and only uploads assets
(`--clobber`). The CHANGELOG-extraction and `gh release create` branch is
exercised when a tag is pushed manually (the fallback path).

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
8. **GitHub Release** — if the Release already exists (the normal case under
   the semantic-release flow), assets are re-uploaded with `--clobber`;
   otherwise it is created with notes from the matching CHANGELOG section (or
   auto-generated on mismatch) and `--prerelease` for hyphenated tags. Assets:
   the tarball, `checksums.txt`, and the CycloneDX SBOM. ghcr.io remains the
   authoritative, signed consumption path.

Consumer-side signature/provenance verification is covered in
[verify-release](verify-release.md).

## End-to-end summary

1. Author commits per conventional-commit rules; PR title linted by
   `lint-pr-title`. CHANGELOG `[Unreleased]` is cut by hand in the same PR.
2. Merge to `main` → `plan` computes the next version into the job summary and
   runs the blocking MAJOR-bump guard.
3. Guard passes → `release` runs unattended (no approval) → semantic-release
   tags `v<version>` and creates the Release object. semantic-release does not
   commit back to `main`.
4. Tag push (App token) → `oci-publish.yml` builds the allowlisted tarball,
   signs, attests (SLSA + SBOM), publishes to
   `ghcr.io/nosmoht/talos-platform-base:<tag>`, and attaches the tarball,
   checksums, and SBOM to the Release.
