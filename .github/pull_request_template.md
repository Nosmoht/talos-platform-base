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

- [ ] `make validate-gitops` exits 0
- [ ] `make validate-kyverno-policies` exits 0 (if Kyverno-touching)
- [ ] `kubectl kustomize --enable-helm kubernetes/base/infrastructure/<comp>/` exits 0 for each touched component
- [ ] `markdownlint` clean (if Markdown-touching)
- [ ] If touching the PNI registry: `scripts/render-capability-reference.sh` re-run and committed

## CI gates (required for merge)

These run automatically; PR is blocked until all are green.

- [ ] `gitops-validate` — full render + lint + policy pipeline
- [ ] `hard-constraints-check` — no `Ingress`, no `Endpoints`, no SecureBoot installer, no `debugfs=off`
- [ ] `secret-scan` (gitleaks) — last backstop on bypassed pre-commit
- [ ] `docs-lint` — markdownlint + capability-reference freshness

## Capability-first design rules (if PNI-touching)

- [ ] CCNP `endpointSelector` uses `capability-provider.<cap>` or `capability-consumer.<cap>` — never `app.kubernetes.io/name: <tool>`
- [ ] New producer component ships its own `namespace.yaml` carrying matching `provide.<cap>` labels
- [ ] No central tool-signature whitelist additions
- [ ] No `kube-system` (or other shared system namespace) producer placements
- [ ] Instanced capabilities carry the `.<inst>` suffix

## Documentation

- [ ] CHANGELOG.md `[Unreleased]` updated (Added / Changed / Deprecated / Removed / Fixed / Security)
- [ ] If a public interface changed (Helm values, registry schema, CCNPs, hard constraints): either an ADR or a `docs/*.md` reference updated
- [ ] Auto-generated docs re-rendered if their source changed

## Reviewer checklist

- [ ] Commit messages follow Conventional Commits with scoped types
- [ ] Each commit body explains the **why**, not just the what
- [ ] No literal secrets, tokens, or internal RFC1918 IPs in any committed file
- [ ] No `git commit --no-verify` or hook-skipping artifacts
