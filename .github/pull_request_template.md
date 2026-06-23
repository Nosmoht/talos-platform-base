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
- [ ] `kubectl kustomize --enable-helm kubernetes/base/infrastructure/<comp>/` exits 0 for each touched component
- [ ] `markdownlint` clean (if Markdown-touching)
- [ ] `scripts/lint-hardware-features.sh` + `scripts/check-provisioning-catalog-refs.sh` pass (if Layer-C hardware-feature / provisioning-catalog touching)
- [ ] `task tofu:ci` exits 0 (if `tofu/` touching)

## CI gates (required for merge)

These run automatically; PR is blocked until all are green.

- [ ] `gitops-validate` — full render + lint + policy pipeline
- [ ] `hard-constraints-check` — no `Ingress`, no `Endpoints`, no SecureBoot installer, no `debugfs=off`
- [ ] `secret-scan` (gitleaks) — last backstop on bypassed pre-commit
- [ ] `docs-lint` — markdownlint
- [ ] `hardware-features-check` — Layer-C hardware-feature schema + provisioning-catalog refs (if Layer-C touching)

## Documentation

- [ ] CHANGELOG.md `[Unreleased]` updated (Added / Changed / Deprecated / Removed / Fixed / Security)
- [ ] If a public interface changed (Helm values, `tofu/modules/talos-cluster` interface, Layer-C hardware-feature schema, hard constraints): either an ADR or a `docs/*.md` reference updated

## Consumer impact

If this PR changes a public interface (OpenTofu module variables/outputs,
Helm-value defaults, release notes shape, OCI tarball contents):

- [ ] Each known v0.5.x consumer named below with per-PR impact
  (cross-checked against `talos-orchestrator/DEPENDENCIES.md`
  "Consumer Pins" snapshot date):
  - `talos-homelab-cluster` — <no change required | sed/yq migration |
    other>
- [ ] If no other v0.5.x consumer exists at PR merge time, that fact is
  asserted here with the snapshot date.

Skip this section only if the PR is purely internal (no public-interface
change).

## Reviewer checklist

- [ ] Commit messages follow Conventional Commits with scoped types
- [ ] Each commit body explains the **why**, not just the what
- [ ] No literal secrets, tokens, or internal RFC1918 IPs in any committed file
- [ ] No `git commit --no-verify` or hook-skipping artifacts
