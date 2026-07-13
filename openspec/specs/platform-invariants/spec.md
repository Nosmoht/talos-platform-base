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

### Requirement: Complete ArgoCD Application targeting

Every rendered ArgoCD Application SHALL set `spec.project`, a destination
namespace (unless allowlisted as namespace-optional), and a destination
`server` or `name`; every Helm source SHALL set `repoURL`, `chart`, and
`targetRevision`; `policies/conftest/argocd.rego` denies each omission.

#### Scenario: Underspecified Application is denied

- **WHEN** conftest evaluates an Application missing its project,
  destination, or a Helm source field
- **THEN** the policy emits a deny naming the Application and the missing
  field

### Requirement: Pinned source revisions

Rendered ArgoCD Applications SHALL pin their sources: a Helm
`targetRevision` is an exact version (floating values such as `latest` or
`*` are denied, non-exact values only via the explicit per-Application
allowlist), and a git `targetRevision` is never `HEAD`;
`policies/conftest/argocd.rego` denies each violation.

#### Scenario: Floating Helm revision is denied

- **WHEN** conftest evaluates an Application whose Helm `targetRevision` is
  floating or not an exact version (and the Application is not allowlisted)
- **THEN** the policy emits a deny naming the Application and the revision

#### Scenario: Floating git ref is denied

- **WHEN** conftest evaluates an Application whose git `targetRevision` is
  `HEAD`
- **THEN** the policy emits a deny naming the Application

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
