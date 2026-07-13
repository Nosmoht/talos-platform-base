---
type: workflow
title: Release Process
description: How a release moves from conventional commit through the semantic-release approval gate to a signed OCI artifact on ghcr.io.
tags: [release, semantic-release, oci, supply-chain]
timestamp: 2026-07-11
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

Releases are conventional-commit-driven with a human approval gate. The chain
is: PR title lint → merge to `main` → `release.yml` plan (dry-run) → manual
approval in the `release` GitHub Environment → semantic-release cuts the tag →
the tag push triggers `oci-publish.yml`, which builds, signs, attests, and
publishes the OCI artifact plus the GitHub Release.

## Commit gate — commitlint on the PR title

`.github/workflows/commitlint.yml` (job `lint-pr-title`, action
`amannn/action-semantic-pull-request` v5) lints the **PR title**, not the
individual commits. Rationale in the workflow header: squash-merge uses the PR
title as the resulting commit subject on `main`, and that subject is what
semantic-release parses.

- Allowed types: `feat`, `fix`, `perf`, `chore`, `docs`, `test`, `refactor`, `ci`.
- `requireScope: false` — a scope like `fix(cilium): …` is house style per
  `CONTRIBUTING.md`, not mandatory.
- The gate applies to PRs only; direct-`main` commits bypass it. The manual
  release approval is the backstop.

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

## Plan and approval — `.github/workflows/release.yml`

Triggered on every push to `main` (concurrency group `release-main`,
`cancel-in-progress: false` so a half-done release is never cancelled).

### Job `plan` (ungated dry-run)

- `npm ci --ignore-scripts`, then `npx semantic-release --dry-run`.
- Greps the log for "the next release version is X.Y.Z" and emits
  `will-release` / `next-version` outputs plus a `# Release plan` job summary
  showing the next version (or "No release").
- **MAJOR prompt**: if any `kubernetes/base/**/values.yaml` changed since the
  last tag, the summary appends a warning to confirm MAJOR-vs-MINOR before
  approving, reminding that only a `BREAKING CHANGE:` footer bumps MAJOR.
- The job runs with `GITHUB_TOKEN`, which cannot push to protected `main` nor
  trigger downstream workflows — so this ungated job cannot cut a real release.

### Job `release` (approval-gated)

Runs only when `will-release == 'true'` and waits for manual approval in the
`release` GitHub Environment. It mints a GitHub App token
(`vars.RELEASE_APP_ID` + `secrets.RELEASE_APP_PRIVATE_KEY`), checks out with
`persist-credentials: false`, and runs the real `npx semantic-release` with
the App token. The App token matters: tags pushed with the default
`GITHUB_TOKEN` do not trigger other workflows, so the App token is what makes
the `v*` tag push fire `oci-publish.yml` while preserving its signing
identity.

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
   `lint-pr-title`.
2. Squash-merge to `main` → `plan` computes the next version into the job
   summary (with the MAJOR prompt when base Helm values changed).
3. Human approves the `release` environment → semantic-release tags
   `v<version>` and creates the Release object.
4. Tag push (App token) → `oci-publish.yml` builds the allowlisted tarball,
   signs, attests (SLSA + SBOM), publishes to
   `ghcr.io/nosmoht/talos-platform-base:<tag>`, and attaches the tarball,
   checksums, and SBOM to the Release.
