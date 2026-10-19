---
sources:
  primary:
    - policies/conftest/k8s.rego
    - policies/conftest/argocd.rego
references:
  - AGENTS.md §Hard Constraints
  - knowledge/decisions/0011-substrate-hard-constraints.md
  - knowledge/decisions/0002-namespace-ownership-rendered-manifests.md
---

# platform-invariants

## Purpose

Describe the observable invariants every rendered manifest in this base
satisfies. This spec is descriptive, not a second normative source: the
normative sources are `AGENTS.md §Hard Constraints` and the cited decision
records (`knowledge/decisions/0011-substrate-hard-constraints.md`,
`knowledge/decisions/0002-namespace-ownership-rendered-manifests.md`). The
requirements below record what the conftest Rego policies
(`policies/conftest/k8s.rego`, `policies/conftest/argocd.rego`) enforce over
kustomize-rendered manifests, plus the hard-constraint invariants those
manifests observably hold.

## Requirements

### Requirement: No forbidden Kubernetes kinds

Rendered manifests SHALL contain no `kind: Ingress` and no `kind: Endpoints`
resource; endpoint collections use `EndpointSlice` (normative: AGENTS.md
§Hard Constraints — Gateway API only, EndpointSlices only;
knowledge/decisions/0011-substrate-hard-constraints.md).

#### Scenario: Rendered tree is free of banned kinds

- **WHEN** the full rendered manifest set is scanned
- **THEN** no document declares `kind: Ingress` or `kind: Endpoints`

### Requirement: Gateway API routing

HTTP and TLS routing shipped by the base SHALL be expressed as Gateway API
resources (HTTPRoute, TLSRoute) rather than Ingress resources or Ingress
controllers (normative: AGENTS.md §Hard Constraints — Gateway API only).

#### Scenario: Routing intent renders as Gateway API

- **WHEN** a rendered component exposes HTTP or TLS routing
- **THEN** the routing resource is a Gateway API kind, never an Ingress

### Requirement: Kubernetes recommended labels

Rendered resources SHALL carry the Kubernetes recommended labels
(`app.kubernetes.io/{name,instance,version,component,part-of,managed-by}`)
(normative: AGENTS.md §Hard Constraints — Kubernetes recommended labels on
all resources).

#### Scenario: Labels present on rendered resources

- **WHEN** a component's manifests are rendered
- **THEN** each resource carries the recommended `app.kubernetes.io/*`
  label set

### Requirement: Single-owner namespace lifecycle

Each platform namespace SHALL have exactly one owning ArgoCD Application —
the component itself; a consumer `root` Application does not track platform
namespaces, and no platform namespace carries a
`Prune=false` sync-option workaround. The `argocd` namespace is the sole
chicken-and-egg exception: created at bootstrap, then owned by the `argocd`
Application at steady state (normative:
knowledge/decisions/0002-namespace-ownership-rendered-manifests.md).

#### Scenario: One tracking owner per platform namespace

- **WHEN** a platform component's rendered manifests are reconciled
- **THEN** its namespace is tracked by that component's Application alone,
  with no second Application claiming lifecycle ownership

#### Scenario: No prune-suppression workaround on platform namespaces

- **WHEN** rendered platform namespaces are inspected
- **THEN** none carries a `Prune=false` sync-option annotation

### Requirement: Workload hardening floor

Rendered workloads (Deployment, StatefulSet, DaemonSet) outside the
`kube-system` relaxation SHALL NOT enable `hostNetwork`, SHALL NOT run
privileged containers, and SHALL declare `resources` with both `requests`
and `limits` on every container and init container; `policies/conftest/k8s.rego`
denies each violation.

#### Scenario: hostNetwork workload is denied

- **WHEN** conftest evaluates a rendered workload with `hostNetwork: true`
  outside `kube-system`
- **THEN** the policy emits a deny naming the workload

#### Scenario: Privileged or resource-less container is denied

- **WHEN** a rendered container outside `kube-system` sets
  `securityContext.privileged: true`, or omits `resources`,
  `resources.requests`, or `resources.limits`
- **THEN** the policy emits a deny naming the workload and container

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

### Requirement: Pinned source revisions

Rendered ArgoCD Applications SHALL pin their sources: the literal
floating markers `latest`, `*`, and `HEAD` are denied as `targetRevision`
on EVERY source independent of its helm/git classification, and a Helm
`targetRevision` is additionally an exact version (non-exact values only
via the explicit per-Application allowlist);
`policies/conftest/argocd.rego` denies each violation.

#### Scenario: Floating revision is denied on any source

- **WHEN** conftest evaluates an Application whose source — regardless of
  classification — carries a `targetRevision` of `latest`, `*`, or `HEAD`
- **THEN** the policy emits a deny naming the Application and the revision

#### Scenario: Non-exact Helm revision is denied

- **WHEN** conftest evaluates an Application whose Helm `targetRevision` is
  not an exact version (and the Application is not allowlisted)
- **THEN** the policy emits a deny naming the Application and the revision

### Requirement: Sync-safety guards

Every rendered ArgoCD Application with automated sync SHALL set
`syncPolicy.retry.limit` (the `root` Application is the recorded
exemption), and only Applications in the allowlisted projects SHALL target
the `kube-system` namespace; `policies/conftest/argocd.rego` denies each
violation.

#### Scenario: Unbounded automated sync is denied

- **WHEN** conftest evaluates a non-exempt Application with
  `syncPolicy.automated` set but no `retry.limit`
- **THEN** the policy emits a deny naming the Application

#### Scenario: kube-system targeting outside allowed projects is denied

- **WHEN** conftest evaluates an Application whose destination namespace is
  `kube-system` and whose project is not allowlisted
- **THEN** the policy emits a deny naming the Application
