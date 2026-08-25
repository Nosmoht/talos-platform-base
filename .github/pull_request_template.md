<!--
Thanks for the PR. Read CONTRIBUTING.md before opening if you have not.
The CI gates below are REQUIRED and will block merge if any fail.
-->

## Summary

<!-- One-paragraph "what changed and why". The why matters more than the what. -->

## Scope

Resolves: <!-- #N — issue this PR closes -->
Refs: <!-- #N — issues this PR touches but does not close -->

- [ ] In scope of the linked issue's Acceptance Criteria (no scope drift)
- [ ] Non-Goals respected
- [ ] Boundaries respected (✅ / ⚠️ / 🚫 per the issue)

## Type of change

- [ ] `feat` — new functionality
- [ ] `fix` — bug fix
- [ ] `docs` — documentation only
- [ ] `refactor` — internal restructuring, no behavior change
- [ ] `test` — test infrastructure
- [ ] `chore` — repo hygiene
- [ ] `ci` — pipeline change
- [ ] **Breaking change** (consumer overlays affected) — described in CHANGELOG `### Removed` or `### Changed` with `BREAKING — …` prefix

## Validation locally (required before opening)

- [ ] `task gitops:validate` exits 0
- [ ] `kubectl kustomize --enable-helm kubernetes/substrate/<comp>/` exits 0 for each touched component
- [ ] `markdownlint` clean (if Markdown-touching)
- [ ] `scripts/lint-hardware-features.sh` + `scripts/check-provisioning-catalog-refs.sh` pass (if Layer-C hardware-feature / provisioning-catalog touching)
- [ ] `task tofu:ci` exits 0 (if `tofu/` touching)

## CI gates (required for merge)

These run automatically; PR is blocked until all are green.

- [ ] `gitops-validate` — full render + lint + policy pipeline
- [ ] `hard-constraints-check` — no `Ingress`, no `Endpoints`, no SecureBoot installer, no `debugfs=off`
- [ ] `secret-scan` (gitleaks) — last backstop on bypassed pre-commit
- [ ] `docs-lint` — markdownlint + OKF bundle validation + offline link gate + AGENTS.md managed-block drift + the release-guard coverage/bite checks
- [ ] `preflight` — release-time org-policy preconditions (branch protection,
      Actions allowlist, GHCR tag immutability, merge methods)

`Commit Lint` (Conventional-Commit PR title) becomes required once the
merge-method settings land; until then it runs and is worth reading, but does
not block. `scripts/preflight-checks.sh` Check 1 is the source of truth for the
required set — this list is a convenience copy.

Not merge-blocking, but run on every PR and worth reading:
`hardware-features-check`, `OCI Allowlist Check`, `tofu-validate`,
`release-guard-advisory` (see below).

## Documentation

- [ ] CHANGELOG.md `[Unreleased]` updated (Added / Changed / Deprecated / Removed / Fixed / Security)
- [ ] If a public interface changed (Helm values, `tofu/modules/talos-cluster` interface, Layer-C hardware-feature schema, hard constraints): either a decision record (`knowledge/decisions/`) or the matching `knowledge/` concept updated
- [ ] If `knowledge/rules/` changed: ran `task knowledge:rules-apply` and committed the regenerated `AGENTS.md` block (never hand-edited)

## Consumer impact

If this PR changes a public interface (OpenTofu module variables/outputs,
Helm-value defaults, release notes shape, OCI tarball contents):

- [ ] Each known v0.5.x consumer named below with per-PR impact
  (cross-checked against the platform dependency manifest's
  "Consumer Pins" snapshot date):
  - `<consumer-cluster>` — <no change required | sed/yq migration |
    other>
- [ ] If no other v0.5.x consumer exists at PR merge time, that fact is
  asserted here with the snapshot date.

Skip this section only if the PR is purely internal (no public-interface
change).

## Reviewer checklist

- [ ] Commit messages follow Conventional Commits with scoped types
- [ ] Each commit body explains the **why**, not just the what
- [ ] No literal secrets, tokens, or internal RFC1918 IPs in any committed file
- [ ] **If the `release-guard-advisory` job lists any guarded path**: this merge
      blocks the next release unless the computed bump is MAJOR. To let it
      through, merge with an attestation in the commit BODY —
      `gh pr merge <N> --merge --subject "<conventional subject>" --body $'<why>\n\nAllow-Non-Major: <reason>'`.
      The attestation clears **every** guarded path changed since the last tag,
      not only this PR's, and a placeholder reason is refused. Full procedure:
      [`knowledge/workflows/release-process.md`](../knowledge/workflows/release-process.md)
      §When the release is blocked — the authoritative copy.
- [ ] No `git commit --no-verify` or hook-skipping artifacts
