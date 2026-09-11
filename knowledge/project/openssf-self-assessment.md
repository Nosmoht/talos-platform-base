---
type: project
title: OpenSSF Best Practices Self-Assessment
description: Self-assessment against the OpenSSF Best Practices Passing-level criteria, serving as the source of truth for the external enrolment answers.
tags: [project, supply-chain]
generated: { by: human:nosmoht, at: "2026-08-31T00:00:00Z" }
migrated_from: docs/openssf-best-practices.md (deleted in the OKF migration; see git history)
sources:
  - resource: .github/workflows/gitops-validate.yml
  - resource: .github/workflows/docs-lint.yml
  - resource: .github/workflows/scorecard.yml
  - resource: SECURITY.md
  - resource: MAINTAINERS.md
  - resource: CONTRIBUTING.md
  - resource: Taskfile.yml
---

# OpenSSF Best Practices Self-Assessment

Tracks the repo's alignment with the
[OpenSSF Best Practices Badge Program](https://www.bestpractices.dev/)
(formerly CII Best Practices). Self-assessed against the **Passing**
level criteria. **External enrolment** (the form at bestpractices.dev)
is a manual step performed by the maintainer; this document is the
source of truth for the answers that get submitted.

| Level | Status | Target |
| --- | --- | --- |
| Passing | self-assessed below — pending external enrolment | yes |
| Silver | not assessed | future |
| Gold | not assessed | n/a (likely never; out of scale for single-maintainer infra base) |

## Basics

| Criterion | Status | Source |
| --- | --- | --- |
| Project sites | met | `README.md` is the project landing page; the `knowledge/` bundle is the navigable map ([index](../index.md)) |
| Description in own language | met | First sentence of `README.md` |
| Interaction | met | GitHub Issues + GitHub Discussions on `Nosmoht/talos-platform-base` |
| Documentation: basics | met | The `knowledge/` bundle (project / reference / workflows / decisions) |
| Documentation: external | met | `ARCHITECTURE.md` (C4), decision records under [decisions](../decisions/index.md) |
| Other | met | `CONTRIBUTING.md`, `MAINTAINERS.md` |
| License | met | Apache-2.0 (`LICENSE`), REUSE 3.3 compliant (`REUSE.toml`, `LICENSES/`) |
| License location | met | Repo root + `LICENSES/Apache-2.0.txt` (REUSE) |
| FLOSS license | met | Apache-2.0 is OSI-approved |
| FLOSS license OK | met | OSI-approved, no field-of-use restrictions |
| Documentation: includes-distribution | met | `UPGRADING.md` covers vendor + run; the first-consumer-cluster workflow covers Day-0 end-to-end (Day-2 upgrade guidance lives in `UPGRADING.md`, not the tutorial) |

> [2026-07-11 verification] Documentation pointers repointed from the retired
> `docs/` tree to the `knowledge/` bundle (the docs tree was Diátaxis-organised;
> the bundle carries the same content in OKF layout).

## Change control

| Criterion | Status | Source |
| --- | --- | --- |
| Public repository | met | `github.com/Nosmoht/talos-platform-base` (public) |
| Unique version numbers | met | SemVer 2.0 (`UPGRADING.md` documents per-MAJOR migration steps); git tags created by semantic-release; OCI consumption pins by digest ([verify-release](../workflows/verify-release.md)) — ghcr tags are mutable by default |
| Release notes | met | `CHANGELOG.md` (Keep-a-Changelog 1.1.0); GitHub Releases exist for `v2.0.0` and `v3.0.0`. Caveat: `CHANGELOG.md` currently lacks a `v3.0.0` section (jumps Unreleased → v2.0.0); the v3.0.0 Release notes were auto-generated — tracked as a follow-up |
| Release notes vulnerabilities | met | `SECURITY.md` §"Supported versions" lists which streams receive backports |

> [2026-07-11 verification] Two corrections: (1) tags are no longer
> "annotated" — `git cat-file -t v2.0.0`/`v3.0.0` both return `commit`
> (lightweight tags, created by semantic-release per `MAINTAINERS.md`).
> (2) "GitHub Releases since `v0.5.0`" is stale — the pre-`v2.0.0` tags and
> releases were removed with the June-2026 history squash; release notes for
> `v0.1.0`–`v1.2.0` survive only in `CHANGELOG.md`.

## Reporting

| Criterion | Status | Source |
| --- | --- | --- |
| Bug-reporting process | met | GitHub Issues (`.github/ISSUE_TEMPLATE/` forms + `CONTRIBUTING.md` §"Issue → PR workflow") |
| Bug-reporting response | met | `MAINTAINERS.md` §"How to reach a maintainer" documents the contact routes; no bug-response SLA is documented (the only written SLA is the vulnerability-response SLA in `SECURITY.md`) |
| Bug-reporting process: archive | met | GitHub Issues archive is public + indexed |
| Vulnerability report process | met | `SECURITY.md` + `.well-known/security.txt` (RFC 9116) |
| Vulnerability report private | met | Email `thomas.krahn.tk@gmail.com` (private). GitHub private vulnerability reporting is currently DISABLED for the repo — email is the only private channel (enabling PVR tracked as a follow-up) |
| Vulnerability report response | met | `SECURITY.md` §"Response SLA": acknowledgement within 5 business days |

> [2026-07-11 verification] Two corrections: (1) `CONTRIBUTING.md` has no
> §"Filing issues" — the issue-intake section is §"Issue → PR workflow".
> (2) `MAINTAINERS.md` does **not** document a response SLA; the criterion's
> substance (reports get acknowledged) is behavioral and the pointer now
> states honestly what is written down.

## Quality

| Criterion | Status | Source |
| --- | --- | --- |
| Working build system | met | `Taskfile.yml` (go-task, single runner since v3.0.0 — see [Makefile retirement](../decisions/0012-makefile-retirement.md)) + `.github/workflows/gitops-validate.yml`; reproducible from the committed `chart.lock.yaml` |
| Automated test suite | met | conftest Rego over rendered manifests, kubeconform schema validation, Layer-C hardware-features schema lint (the standalone `hardware-features-check` job in `gitops-validate.yml`) |
| New functionality testing | met | every PR runs the full gitops-validate pipeline (CI invokes the `scripts/` stages directly; `task gitops:validate` is the equivalent local entry point); per-component render via `task gitops:render-component` |
| Warning flags | met | markdownlint (`docs-lint.yml`), gitleaks, conftest, kubeconform, REUSE lint — all run in CI |
| Warning addressing | met | branch protection blocks merge on the required checks; documented in `CONTRIBUTING.md` §"Required (CI) before merge" |
| Warning strict | met | conftest exits non-zero on any policy fail; same for kubeconform |

> [2026-07-11 verification] Three corrections: (1) "Working build system"
> named the `Makefile` — retired at v3.0.0 in favour of go-task; a
> deprecation stub remains for one release cycle. (2) The hardware-features
> lint runs in the standalone `hardware-features-check` job of
> `gitops-validate.yml`. (3) "all CI-required" overstated: not every workflow
> is merge-blocking — see the 2026-07-15 note below for the current set.

## Security

| Criterion | Status | Source |
| --- | --- | --- |
| Secure development knowledge | met | Maintainer-attested K8s / Talos / Cilium operator experience (`MAINTAINERS.md` documents the maintainer role and decision authority, not the experience itself) |
| Use basic good cryptographic practices | met | All artefacts signed by cosign keyless OIDC (no long-lived keys); SLSA provenance via OIDC |
| Secure release (delivery against MITM) | met | OCI artefacts signed (cosign) + provenance-attested (SLSA) + SBOM-attested (CycloneDX 1.6); the [verify-release workflow](../workflows/verify-release.md) documents the end-to-end recipe |
| Public known vulnerabilities fixed | met | gitleaks CI + Scorecard CI (`.github/workflows/scorecard.yml`); no current backlog |
| No leaked credentials | met | `gitleaks` CI gate + pre-commit hook; required check |

> [2026-07-11 verification] "documented in `MAINTAINERS.md`" corrected for
> the knowledge criterion — that file documents role and decision authority
> only; the operator-experience claim is maintainer-attested, not written
> evidence.

## Analysis

| Criterion | Status | Source |
| --- | --- | --- |
| Static code analysis | met | conftest Rego policies (`policies/conftest/`) over rendered Kubernetes manifests is the load-bearing static check for a YAML-based repo; supplemented by markdownlint, gitleaks, and the per-component schema validation |
| Static analysis common vulnerabilities | met | gitleaks (credentials) + conftest Rego policy checks (structural correctness) |
| Static analysis fixed | met | main branch protection requires the `validate`, `Secret Scan (gitleaks)`, `Hard Constraints`, `docs-lint`, and `lint-pr-title` status checks; other CI workflows run but are not merge-blocking, and admin enforcement (`enforce_admins`) is disabled |
| Dynamic analysis | n/a | Repo ships YAML manifests + Helm bases, not executable code. Dynamic analysis applies at the consumer-cluster runtime, not at the base. Documented as explicit n/a per Best-Practices guidance for non-executable-code repos. |

> [2026-07-11 verification] "All CI checks required; broken main is
> impossible by branch protection" corrected to the actual protection
> configuration (verified via the GitHub branch-protection API): two required
> contexts, `enforce_admins` off — an admin push can bypass the gate.
>
> [2026-07-15 verification] Re-read via the branch-protection API. Five
> required contexts: `validate`, `Secret Scan (gitleaks)`, `Hard Constraints`,
> `preflight`, `docs-lint`. The 2026-07-11 count of two was accurate for the
> contexts that were *reporting*: `docs-lint` was listed in protection but no
> job emitted that name (the workflow was named `docs-lint`, its job
> `markdownlint`), so it stayed permanently pending and merges ran on admin
> bypass. `Hard Constraints` and `preflight` have since been added to
> protection. The job rename that makes `docs-lint` report is in the same
> change as this note.
>
> Two limits stand, and neither is closed here: `enforce_admins` is off, so an
> admin push still bypasses every gate; and `required_pull_request_reviews` is
> unset, so `CODEOWNERS` routes review attention but blocks nothing. On a
> single-maintainer repo the second is largely moot — GitHub does not let an
> author approve their own PR — but the distinction matters for any claim that
> CODEOWNERS is an enforcement control. It is not.
>
> [2026-08-31 verification] Re-read via the branch-protection API. Still five
> required contexts, but not the same five: `lint-pr-title` was added, and
> `preflight` was removed together with its workflow. `preflight` ran
> `scripts/preflight-checks.sh` with the default `GITHUB_TOKEN`, which cannot
> read branch protection, the Actions permissions, release immutability or the
> merge settings — every check skipped and the required context reported
> success without having read anything it asserts. The script now runs weekly
> from `policy-audit.yml` with a GitHub App token holding `Administration:read`,
> and treats an unreadable setting as a failure. The two limits above are
> unchanged.

## External enrolment

The badge is **earned by submitting** the answers above through the
form at <https://www.bestpractices.dev>. The form asks ~70 questions
keyed to the criteria; this self-assessment maps onto them
one-for-one. Re-evaluate annually (after each MINOR release) and
update both this document and the live submission.

When the badge is awarded, add this line to `README.md` (next to the
REUSE and Scorecard badges):

```markdown
[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/<ID>/badge)](https://www.bestpractices.dev/projects/<ID>)
```

The `<ID>` is assigned when the project is first registered. Until
enrolment is complete the badge MUST NOT appear in the README — an
unearned badge is a misrepresentation.

## Re-assessment trigger

Re-run this self-assessment when:

- a MINOR or MAJOR release ships (the answers may have moved);
- a new criterion is added to the OpenSSF Best Practices Passing level;
- any of the load-bearing tools (cosign, SLSA, Scorecard, REUSE, SBOM)
  change their guarantees in a way that affects an answer above.

## References

- [OpenSSF Best Practices Badge](https://www.bestpractices.dev/)
- [Passing criteria definition](https://www.bestpractices.dev/criteria/0)
- `SECURITY.md`
- `CONTRIBUTING.md`
- `MAINTAINERS.md`
- [Verify-release workflow](../workflows/verify-release.md)
