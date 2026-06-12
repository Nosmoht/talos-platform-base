# Release automation

**Audience:** maintainers cutting releases of `talos-platform-base`, and
contributors who want to understand why a merge did (or did not) ship a release.

| Companion doc | Why |
|---|---|
| [`oci-artifact-verification.md`](oci-artifact-verification.md) | how the signed OCI artifact a release publishes is verified |
| [`../CONTRIBUTING.md`](../CONTRIBUTING.md) | conventional-commit subject rules (the release input) |
| [`../CHANGELOG.md`](../CHANGELOG.md) | human-curated narrative log (see "CHANGELOG ownership" below) |
| [`../MAINTAINERS.md`](../MAINTAINERS.md) | who approves a release |

## How a release happens

Releases are driven from the conventional-commit history by
[semantic-release](https://semantic-release.gitbook.io/), gated by one manual
approval. The pipeline is **semi-automatic**: version, notes, and tag are
computed automatically; a human approves once before anything is signed or
published.

1. A PR merges to `main` (squash-merge; the PR title becomes the commit
   subject — see "Commit discipline").
2. `.github/workflows/release.yml` runs the `plan` job: `semantic-release
   --dry-run` computes the next version and writes it to the run **summary**. If
   no commit since the last tag is release-worthy, the pipeline stops here — no
   approval is requested.
3. If a release is due, the `release` job pauses in the `release` GitHub
   **Environment** and waits for a maintainer to approve it. The summary from
   step 2 shows the computed version (and flags base Helm-value changes — see
   "Commit discipline").
4. On approval, the `release` job runs the real semantic-release using a
   short-lived **GitHub App token**. semantic-release creates the git tag and
   the GitHub Release (with generated notes).
5. Because the tag is pushed with the **App token** (not the default
   `GITHUB_TOKEN`, whose events do not trigger other workflows), the existing
   [`oci-publish.yml`](../.github/workflows/oci-publish.yml) fires on the tag
   push. It builds, cosign-signs, and attests the OCI artifact, advances
   `:latest`, and attaches the signed assets to the Release semantic-release
   already created.

`oci-publish.yml` is **unchanged** by this automation, so the cosign keyless
signing identity and the consumer verification regex in
[`oci-artifact-verification.md`](oci-artifact-verification.md) are preserved.

## Version bump rules

semantic-release uses the `conventionalcommits` preset. The bump is decided by
commit **type** and breaking markers:

| Commit | Bump |
|---|---|
| `feat: …` | MINOR |
| `fix: …` / `perf: …` | PATCH |
| `BREAKING CHANGE:` footer, or `type!: …` | MAJOR |
| `docs` / `chore` / `ci` / `test` / `refactor` | no release |

## Commit discipline (read this before relying on the automation)

- **A MAJOR bump requires a real `BREAKING CHANGE:` footer (or `type!:`).** Prose
  such as a bold `**BREAKING**` line in the commit body is **ignored** by the
  release tool. Historically this repo marked breaking changes with prose in the
  CHANGELOG (e.g. `v1.2.0`); under automation that no longer drives the version.
  This matters for the AGENTS.md Hard Constraint *"a breaking change to base
  Helm values requires bumping the next OCI tag's MAJOR version"*: the author
  must add the footer, or the change silently ships as MINOR/PATCH.
- The `plan` job flags when the release range touches
  `kubernetes/base/**/values.yaml` so the approver can catch a missing
  breaking-change footer at the gate.
- The commit-lint check (`.github/workflows/commitlint.yml`) validates the PR
  **title** type, but it cannot detect a missing breaking footer — that is a
  human review responsibility. It also gates PRs only; direct-`main` commits
  bypass it, so the repo convention is PR-merged changes.

## CHANGELOG ownership

The automation **never writes `CHANGELOG.md`**. The auto-generated **GitHub
Release notes are the canonical per-release record**. `CHANGELOG.md` stays a
human-curated narrative: keep the `## Unreleased` section as a rolling log and
promote it to a `## vX.Y.Z — DATE` heading at your discretion — this is
non-blocking and the automated release does not wait on it.

Consequence for `oci-publish.yml`: its CHANGELOG-section extraction (the `awk`
block) and its `gh release create` branch are normally **not exercised** under
this flow, because semantic-release has already created the Release, so
oci-publish takes its `gh release view … || upload --clobber` path. Those
branches remain as the fallback for a **manual** tag push (the rollback path
below) and are intentionally left in place.

## Race note

semantic-release pushes the tag before it creates the Release. The tag push
fires `oci-publish.yml`, which spends a few minutes building/signing before its
`gh release view` step — by then semantic-release has created the Release, so
oci-publish attaches assets to it. In the rare case oci-publish wins (a
semantic-release publish hiccup after tagging), oci-publish creates the Release
itself with `--generate-notes`; this is self-healing, not an error, but the
notes author is then GitHub rather than semantic-release.

## One-time setup (maintainer, GitHub UI)

1. **Create a GitHub App** (your account → Settings → Developer settings →
   GitHub Apps → New): no webhook; **Repository permission `Contents: Read &
   write`** only; "Only on this account". Note the **App ID**; generate and
   download a **private key** (`.pem`).
2. **Install** the App on `talos-platform-base` only.
3. **Create the `release` Environment** (repo → Settings → Environments → New,
   name `release`): add **Required reviewers** = the maintainer. This is the
   approval gate.
4. **Add credentials** (repo → Settings → Secrets and variables → Actions):
   Variable `RELEASE_APP_ID` = the App ID; Secret `RELEASE_APP_PRIVATE_KEY` =
   the full `.pem`.
5. **Make commit-lint required** (repo → Settings → Branches → `main` →
   require status checks): add the commit-lint check; keep `validate` and
   `Secret Scan (gitleaks)`.

No branch-protection bypass or ruleset migration is needed — the App never
pushes to `main`, only tags.

## Rollback

Disable or revert `.github/workflows/release.yml` to stop future automated
releases; the App and Environment can stay dormant. `oci-publish.yml` is
untouched, so the manual path (hand-write the `CHANGELOG.md` section, create an
annotated `vX.Y.Z` tag, `git push` it) still works as the fallback.

**Asymmetry to know:** a release already published cannot be cleanly undone —
the git tag and the cosign-signed OCI digest are immutable (GHCR tag
immutability), and `:latest` would need a manual re-point. The approval gate and
the mandatory dry-run are the real mitigations: a wrong version is caught before
the tag exists.

## Known limitation

`preflight-checks.sh` (the `Preflight` workflow) degrades several supply-chain
precondition checks to warnings when the CI token lacks admin scope. That is a
pre-existing property unrelated to this automation; full verification of GHCR
tag-immutability and the Actions allowlist still needs an admin-scoped local
check.
