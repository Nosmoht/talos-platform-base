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

## 3. Mechanical Binding

- [x] 3.1 Add a bite-check that extracts both steps from the workflow and
  drives them through every release state against a stub `gh`, asserting the
  call ORDER; wire it into the required `docs-lint` context. Verify it fails
  when `--draft` is removed from the step.
- [x] 3.2 Assert in the same check that `.releaserc.json` declares no publish
  plugin and that no second semantic-release config shadows it — the fix's
  other half is an absence, and the plugin ships as a dependency of
  semantic-release itself. Verify the assertion fails when the plugin is
  re-added.

## 4. Failure Visibility and Record

- [x] 4.1 Add a `notify` job opening or updating one tracking issue on a
  publish that does not succeed, and a `notify-resolved` closing it, mirroring
  `release.yml`. Bound the job's runtime; scope the concurrency group per tag
  so no run is evicted before its jobs report.
- [x] 4.2 Record the asset-less tags — separating the five whose artifacts
  exist from the two that have none, verified against the registry — the
  forward-only recovery, and the cost of a re-run, in
  `knowledge/workflows/verify-release.md`,
  `knowledge/workflows/release-process.md`, `UPGRADING.md` and the glossary;
  amend ADR-0020 §Decision 4.

## 5. Final Verification

- [x] 5.1 Run `task spec:validate`, `task spec:check-regen`,
  `task spec:check-staleness`, `task knowledge:validate`, `task docs:lint`,
  `task gitops:validate`, `task supply-chain:check-release-step`, actionlint,
  shellcheck and Vale, and record their outcomes in the PR.
