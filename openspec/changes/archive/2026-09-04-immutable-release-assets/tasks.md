## 1. Release Ownership

- [x] 1.1 Remove `@semantic-release/github` from `.releaserc.json`; verify from
  the pinned sources that semantic-release still creates and pushes the tag and
  that `publish` is an optional lifecycle step.
- [x] 1.2 Correct `release.yml`'s flow comment and the `plan` job's permission
  rationale, which named the removed plugin rather than the real reason
  (`verifyAuth` runs `git push --dry-run` even under `--dry-run`).

## 2. Draft-then-Publish Release

- [x] 2.1 Create the GitHub Release as a draft, attach the tarball,
  `checksums.txt`, and the CycloneDX SBOM to it, and publish it last; verify
  the workflow parses and the step order matches.
- [x] 2.2 Refuse to touch an already-published release with an error naming the
  recovery section; discard and rebuild a leftover draft so a re-run before the
  publish flip still succeeds.
- [x] 2.3 Assert the published release's asset names against the three expected
  files.

## 3. Failure Visibility and Record

- [x] 3.1 Add a `notify` job opening or updating one tracking issue on a failed
  publish, mirroring `release.yml`.
- [x] 3.2 Record the seven asset-less tags and the forward-only recovery in
  `knowledge/workflows/verify-release.md` and
  `knowledge/workflows/release-process.md`; amend ADR-0020 §Decision 4.

## 4. Final Verification

- [x] 4.1 Run `task spec:validate`, `task spec:check-regen`,
  `task spec:check-staleness`, `task knowledge:validate`, actionlint and
  markdownlint, and record their outcomes in the PR.
