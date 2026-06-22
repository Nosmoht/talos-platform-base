# OpenSSF Best Practices — self-assessment

Tracks the repo's alignment with the
[OpenSSF Best Practices Badge Program](https://www.bestpractices.dev/)
(formerly CII Best Practices). Self-assessed against the **Passing**
level criteria. **External enrolment** (the form at bestpractices.dev)
is a manual step performed by the maintainer; this document is the
source of truth for the answers that get submitted.

| Level | Status | Target |
|---|---|---|
| Passing  | self-assessed below — pending external enrolment | yes |
| Silver   | not assessed | future |
| Gold     | not assessed | n/a (likely never; out of scale for single-maintainer infra base) |

## Basics

| Criterion | Status | Source |
|---|---|---|
| Project sites | met | [`README.md`](../README.md) is the project landing page; `docs/` is the navigable map ([`docs/README.md`](README.md)) |
| Description in own language | met | First sentence of `README.md` |
| Interaction | met | GitHub Issues + GitHub Discussions on `Nosmoht/talos-platform-base` |
| Documentation: basics | met | Diátaxis-organised `docs/` (tutorial / how-to / reference / explanation) |
| Documentation: external | met | [`ARCHITECTURE.md`](../ARCHITECTURE.md) (C4), ADRs under `docs/adr-*.md` |
| Other | met | [`CONTRIBUTING.md`](../CONTRIBUTING.md), [`MAINTAINERS.md`](../MAINTAINERS.md) |
| License | met | Apache-2.0 (`LICENSE`), REUSE 3.3 compliant (`REUSE.toml`, `LICENSES/`) |
| License location | met | Repo root + `LICENSES/Apache-2.0.txt` (REUSE) |
| FLOSS license | met | Apache-2.0 is OSI-approved |
| FLOSS license OK | met | OSI-approved, no field-of-use restrictions |
| Documentation: includes-distribution | met | `UPGRADING.md` covers vendor + run; `docs/tutorial-first-consumer-cluster.md` covers Day-0 + Day-2 |

## Change control

| Criterion | Status | Source |
|---|---|---|
| Public repository | met | `github.com/Nosmoht/talos-platform-base` (public) |
| Unique version numbers | met | SemVer 2.0 ([`UPGRADING.md`](../UPGRADING.md)); annotated git tags + immutable OCI tags |
| Release notes | met | [`CHANGELOG.md`](../CHANGELOG.md) (Keep-a-Changelog 1.1.0), GitHub Releases since `v0.5.0` |
| Release notes vulnerabilities | met | [`SECURITY.md`](../SECURITY.md) §"Supported versions" lists which streams receive backports |

## Reporting

| Criterion | Status | Source |
|---|---|---|
| Bug-reporting process | met | GitHub Issues (`.github/ISSUE_TEMPLATE/` or `CONTRIBUTING.md` §"Filing issues") |
| Bug-reporting response | met | `MAINTAINERS.md` documents response SLA |
| Bug-reporting process: archive | met | GitHub Issues archive is public + indexed |
| Vulnerability report process | met | [`SECURITY.md`](../SECURITY.md) + [`.well-known/security.txt`](../.well-known/security.txt) (RFC 9116) |
| Vulnerability report private | met | Email `thomas.krahn.tk@gmail.com` (private), GitHub Security Advisories (private) |
| Vulnerability report response | met | `SECURITY.md` §"Response SLA": acknowledgement ≤ 5 business days |

## Quality

| Criterion | Status | Source |
|---|---|---|
| Working build system | met | `Makefile` + `.github/workflows/gitops-validate.yml`; reproducible from `chart.lock.yaml` |
| Automated test suite | met | conftest Rego over rendered manifests, kubeconform schema validation, Layer-C hardware-features schema lint (`hardware-features-check` CI job) |
| New functionality testing | met | every PR runs full `make validate-gitops`; per-component renderable smoke target |
| Warning flags | met | markdownlint, gitleaks, conftest, kubeconform, REUSE lint — all CI-required |
| Warning addressing | met | CI-required checks block merge; documented in `CONTRIBUTING.md` |
| Warning strict | met | conftest exits non-zero on any policy fail; same for kubeconform |

## Security

| Criterion | Status | Source |
|---|---|---|
| Secure development knowledge | met | Maintainer holds active K8s / Talos / Cilium operator experience; documented in `MAINTAINERS.md` |
| Use basic good cryptographic practices | met | All artefacts signed by cosign keyless OIDC (no long-lived keys); SLSA provenance via OIDC |
| Secure release (delivery against MITM) | met | OCI artefacts signed (cosign) + provenance-attested (SLSA) + SBOM-attested (CycloneDX 1.6); `docs/oci-artifact-verification.md` documents the end-to-end recipe |
| Public known vulnerabilities fixed | met | gitleaks CI + Scorecard CI; no current backlog |
| No leaked credentials | met | `gitleaks` CI gate + pre-commit hook; required check |

## Analysis

| Criterion | Status | Source |
|---|---|---|
| Static code analysis | met | conftest Rego policies (`policies/conftest/*`) over rendered Kubernetes manifests is the load-bearing static check for a YAML-based repo; supplemented by markdownlint, gitleaks, and the per-component schema validation |
| Static analysis common vulnerabilities | met | gitleaks (credentials) + conftest Rego policy checks (structural correctness) |
| Static analysis fixed | met | All CI checks required; broken main is impossible by branch protection |
| Dynamic analysis | n/a | Repo ships YAML manifests + Helm bases, not executable code. Dynamic analysis applies at the consumer-cluster runtime, not at the base. Documented as explicit n/a per Best-Practices guidance for non-executable-code repos. |

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
- [`SECURITY.md`](../SECURITY.md)
- [`CONTRIBUTING.md`](../CONTRIBUTING.md)
- [`MAINTAINERS.md`](../MAINTAINERS.md)
- [`docs/oci-artifact-verification.md`](oci-artifact-verification.md)
