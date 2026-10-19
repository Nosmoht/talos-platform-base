## ADDED Requirements

### Requirement: ArgoCD source classification markers

An ArgoCD Application source SHALL be explicitly classifiable by a non-empty
`chart` (Helm repository source), `path` (git directory source), `ref`
(multi-source values anchor), or a `plugin` block (config-management plugin,
which legitimately runs at the repo root); a source carrying a `helm:` block
SHALL additionally set `chart` or `path`. `policies/conftest/argocd.rego`
denies each violation.

#### Scenario: Each marker classifies a source

- **WHEN** conftest evaluates a source with a `repoURL`, no `helm:` block,
  and a non-empty `chart`, `path`, `ref`, or a `plugin` block
- **THEN** the source is classified as a Helm repository, git directory,
  multi-source values anchor, or config-management plugin source
  respectively, and no classifiability deny is emitted

### Requirement: Disclosed residuals of ArgoCD source classification

The policy SHALL classify a chart-less source that sets `path` as a git
source, so the Helm exact-version requirement applies only to chart-bearing
sources. The floating-revision deny catches only the literal floating
markers (`latest`, `*`, `HEAD`) — a disclosed residual, not a ceiling.

#### Scenario: A path source on a Helm repository is classified as git

- **WHEN** conftest evaluates a chart-less source that sets `path`
- **THEN** it is classified as a git source and the Helm exact-version
  requirement does not apply, because whether its `repoURL` is a Helm
  repository is not mechanically decidable

#### Scenario: A mutable branch or tag name passes mechanically

- **WHEN** a git-classified source sets a mutable branch or tag name such as
  `stable`, `main`, or `v1`
- **THEN** it passes the floating-revision deny mechanically
- **AND** it remains a review concern, not an enforced invariant

## MODIFIED Requirements

### Requirement: ArgoCD Application targeting and source classifiability

Every rendered ArgoCD Application SHALL set `spec.project`, a destination
namespace (unless allowlisted as namespace-optional), and a destination
`server` or `name`; every source SHALL set `repoURL` and SHALL be
explicitly classifiable, and every Helm source SHALL set `targetRevision`;
`policies/conftest/argocd.rego` denies each violation.

#### Scenario: Underspecified Application is denied

- **WHEN** conftest evaluates an Application missing its project or
  destination, a source with an empty `repoURL`, or a Helm source with an
  empty `targetRevision`
- **THEN** the policy emits a deny naming the Application and the missing
  field

#### Scenario: Unclassifiable source is denied

- **WHEN** conftest evaluates an Application whose source carries a
  `helm:` values block and a `repoURL` but none of `chart`, `path`,
  `ref`, or `plugin`
- **THEN** the policy emits a deny naming the Application and requiring
  `chart`, `path`, `ref`, or `plugin`

#### Scenario: Helm-shaped source with only a values anchor is denied

- **WHEN** conftest evaluates an Application whose source carries a
  `helm:` block and a `ref` but neither `chart` nor `path`
- **THEN** the policy emits a deny naming the Application and requiring
  `chart` or `path` alongside the `helm:` block
