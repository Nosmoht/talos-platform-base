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
- [ ] **Breaking change** (MAJOR under the [ADR-0029 rule](../knowledge/decisions/0029-public-api-and-major-rule.md#classification)) — described in CHANGELOG `### Removed` or `### Changed` with `BREAKING — …` prefix

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
- [ ] `docs-lint` — markdownlint + OKF bundle validation + offline link gate + AGENTS.md managed-block drift + the release-step bite check
- [ ] `lint-pr-title` — Conventional-Commit PR title; it becomes the squash
      subject, the only input to the version bump

Account policy (branch protection, Actions allowlist, release immutability,
merge methods) is not checked here: the default token cannot read any of it, so
a PR-attached check could only report success without looking. It runs weekly
in `policy-audit.yml` with an App token instead. `scripts/preflight-checks.sh`
Check 1 is the source of truth for the required set — this list is a
convenience copy.

Not merge-blocking, but run on every PR and worth reading:
`hardware-features-check`, `OCI Allowlist Check`, `tofu-validate`.

## Documentation

- [ ] CHANGELOG.md `[Unreleased]` updated (Added / Changed / Deprecated / Removed / Fixed / Security)
- [ ] If the public API ([ADR-0029 §Public API](../knowledge/decisions/0029-public-api-and-major-rule.md#public-api)), a Helm-value default or a hard constraint changed: either a decision record (`knowledge/decisions/`) or the matching `knowledge/` concept updated
- [ ] If `knowledge/rules/` changed: ran `task knowledge:rules-apply` and committed the regenerated `AGENTS.md` block (never hand-edited)

## Consumer impact

If this PR changes the public API
([ADR-0029 §Public API](../knowledge/decisions/0029-public-api-and-major-rule.md#public-api)),
a Helm-value default, a hard constraint or the release notes shape:

- [ ] Each known v0.5.x consumer named below with per-PR impact
  (cross-checked against the platform dependency manifest's
  "Consumer Pins" snapshot date):
  - `<consumer-cluster>` — <no change required | sed/yq migration |
    other>
- [ ] If no other v0.5.x consumer exists at PR merge time, that fact is
  asserted here with the snapshot date.

Skip this section only if the PR changes none of the items listed above.

## Reviewer checklist

- [ ] Commit messages follow Conventional Commits with scoped types
- [ ] Each commit body explains the **why**, not just the what
- [ ] No literal secrets, tokens, or internal RFC1918 IPs in any committed file
- [ ] The PR title's class matches
      [ADR-0029 §Classification](../knowledge/decisions/0029-public-api-and-major-rule.md#classification)
      (`!` for MAJOR). It is the only input to the version bump; merge with
      `state:close` (`AGENTS.md §Issue-Interface`), which copies the title.
- [ ] No `git commit --no-verify` or hook-skipping artifacts
