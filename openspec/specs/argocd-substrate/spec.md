---
sources:
  primary:
    - kubernetes/substrate/argocd/README.md
    - kubernetes/substrate/argocd/chart.lock.yaml
    - kubernetes/substrate/argocd/kustomization.yaml
    - kubernetes/substrate/argocd/namespace.yaml
    - kubernetes/substrate/argocd/values.yaml
    - kubernetes/substrate/argocd/_rendered/crds.yaml
    - kubernetes/substrate/argocd/_rendered/manifests.yaml
    - kubernetes/substrate/argocd/_rendered-overlay/kustomization.yaml
references:
  - knowledge/decisions/0002-namespace-ownership-rendered-manifests.md
---

# argocd-substrate

## Purpose

The committed, steady-state ArgoCD substrate component: a pinned Helm-chart
render shipped as `_rendered/` artifacts under
`kubernetes/substrate/argocd/`, consumed by clusters through the
component's kustomization for ArgoCD self-management after bootstrap.

## Requirements

### Requirement: Pinned reproducible chart render

The component SHALL ship its rendered manifests as committed artifacts
produced from the Helm chart pinned in
`kubernetes/substrate/argocd/chart.lock.yaml`, which records the
chart repository, chart name, exact chart version, and the chart tarball's
SHA-256 checksum.

#### Scenario: Lock file pins the render input

- **WHEN** `chart.lock.yaml` is read
- **THEN** it names the upstream chart repository and chart, one exact chart
  version, a `tgz_sha256` checksum, the release name and namespace `argocd`,
  and `values.yaml` as the values input

#### Scenario: Rendered artifacts are committed

- **WHEN** the component directory is inspected
- **THEN** `_rendered/manifests.yaml` (workload, RBAC, ConfigMap, Service,
  and related documents) and `_rendered/crds.yaml` (the `applications`,
  `applicationsets`, and `appprojects` CustomResourceDefinitions) exist as
  committed files

### Requirement: Kustomize consumption surface

The component SHALL be consumable as a single kustomization whose resources are
exactly the namespace manifest and the two committed rendered artifacts, and
that kustomization SHALL be present in the published artifact — otherwise the
property holds in the repository only, and a consumer vendoring a tag receives
loose manifests they must reassemble by hand.

#### Scenario: Component builds from committed inputs only

- **WHEN** `kubectl kustomize kubernetes/substrate/argocd/` runs
- **THEN** the output is assembled from `namespace.yaml`,
  `_rendered/manifests.yaml`, and `_rendered/crds.yaml` with no live chart
  fetch or template step

#### Scenario: The vendored component is buildable

- **WHEN** the published tarball is extracted
- **THEN** `kubernetes/substrate/argocd/kustomization.yaml` is present alongside
  the resources it names, so the component builds from the vendored tree

### Requirement: No operator identity in the render

The component SHALL ship no access policy: the rendered `argocd-rbac-cm`
carries no non-empty `policy.csv` and no non-empty `policy.default`, and
`configs.rbac.scopes` is not set; the consumer owns `policy.csv` and the
scopes in their own overlay. `policy.default` SHALL be asserted separately
from `policy.csv`, and both assertions SHALL test EMPTINESS, not absence,
because the chart's `argocd-rbac-cm` template emits the keys unconditionally.

#### Scenario: Render ships no principal

- **WHEN** the steady-state render's `argocd-rbac-cm` is inspected
- **THEN** its `policy.csv` is empty or whitespace-only, and no subject is bound
  to a role

#### Scenario: Render grants no blanket role

- **WHEN** the same ConfigMap's `policy.default` is inspected
- **THEN** it is empty or whitespace-only, so no role is granted to every
  authenticated principal

#### Scenario: An unmatched principal receives no permission

- **WHEN** an authenticated principal matches no policy rule
- **THEN** the shipped `policy.default` value `''`, identical to the chart
  default, grants it no permission

#### Scenario: Only the local admin works until a consumer policy exists

- **WHEN** no consumer has supplied a policy
- **THEN** the local `admin` account, which ArgoCD documents as an
  unrestricted superuser, is the only working access path

### Requirement: No placeholder base URL in the render

The rendered `argocd-cm` SHALL carry no `url` key. The chart derives it from
`global.domain`, whose default is a placeholder hostname, and ArgoCD derives the
OIDC redirect URI from `url` — a placeholder therefore fails at the identity
provider on a human's first login rather than in the cluster. The consumer
supplies the real value in their overlay.

#### Scenario: Render omits the url key

- **WHEN** the steady-state render's `argocd-cm` ConfigMap data is inspected
- **THEN** it carries no `url` key

### Requirement: Notifications argocdUrl is an accepted residual

"No placeholder base URL in the render" SHALL NOT extend to the
chart-derived `argocdUrl` in `argocd-notifications-cm`: the chart renders it
through `default (printf ...)` and Helm's `default` treats `""` as unset, so
it cannot be cleared without disabling the notifications workload. It feeds
notification links, never the SSO redirect.

#### Scenario: The residual argocdUrl does not reach SSO

- **WHEN** the steady-state render's `argocd-notifications-cm` carries a
  chart-derived `argocdUrl`
- **THEN** "No placeholder base URL in the render" is not violated by it

### Requirement: The consumer wiring path is published and mechanically bound

The repository SHALL publish the consumer-facing wiring contract and SHALL bind
it to a buildable worked overlay, so the documented path cannot drift away from
what the component actually accepts.

The gate SHALL build that overlay against an UNPATCHED control build of the same
component, and assert against the comparison — a one-sided assertion on the
patched build alone would pass identically if the base regressed to shipping the
values the overlay is supposed to supply.

#### Scenario: The documented overlay still wires the component

- **WHEN** the worked overlay and the unpatched component are both built
- **THEN** the control build carries none of a `url`, a non-empty `oidc.config`
  or a non-empty `policy.csv`, while the patched build carries a non-empty
  `url`, an `oidc.config` that parses as YAML with both `issuer` and
  `clientID`, and a non-empty `policy.csv`. The control covers every key the
  patched side asserts: a key left out of it makes its own assertion one-sided

#### Scenario: A replacing patch is rejected

- **WHEN** the overlay's merged ConfigMap `.data` key sets are compared against
  the control build's
- **THEN** every base-shipped key is still present, so a JSON6902 or
  `$patch: replace` patch that drops the component's own configuration fails the
  gate

### Requirement: argocd namespace ownership

The component SHALL ship the `argocd` Namespace manifest as part of its own
render so the argocd Application is the namespace's steady-state lifecycle
owner, with the bootstrap seed as the documented chicken-and-egg exception
that pre-creates the namespace before ownership transfers via server-side
apply (ownership model: `knowledge/decisions/0002-namespace-ownership-rendered-manifests.md`).

#### Scenario: Namespace carries the PSA floor

- **WHEN** `namespace.yaml` is applied
- **THEN** the `argocd` Namespace carries pod-security labels enforcing
  `baseline` with `audit` and `warn` at `restricted`, plus
  `app.kubernetes.io/managed-by: argocd`

### Requirement: Bundled Dex disabled in the render

The component SHALL render with the chart's bundled Dex server disabled, so
no Dex workload document and no `server.dex.server`-prefixed ConfigMap data
key appears in the committed render.

#### Scenario: No Dex resources in the committed render

- **WHEN** `_rendered/manifests.yaml` is scanned as structured documents
- **THEN** no document carries the label
  `app.kubernetes.io/component: dex-server` and no ConfigMap has a `.data`
  key prefixed `server.dex.server`

### Requirement: h2c application protocol baked into the server Service

The render pipeline SHALL patch the `argocd-server` Service's HTTP port with
`appProtocol: kubernetes.io/h2c` via
`_rendered-overlay/kustomization.yaml`, so the committed render carries the
gRPC-capable port declaration.

#### Scenario: Committed render carries the patched port

- **WHEN** the `argocd-server` Service document in
  `_rendered/manifests.yaml` is inspected
- **THEN** its `http` port entry declares
  `appProtocol: kubernetes.io/h2c`

### Requirement: Recommended labels on rendered resources

Rendered resources SHALL carry the Kubernetes recommended label set
(normative: AGENTS.md §Hard Constraints — Kubernetes recommended labels on
all resources).

#### Scenario: Labels present in the committed render

- **WHEN** documents in `_rendered/manifests.yaml` are inspected
- **THEN** every document carries
  `app.kubernetes.io/{name,instance,part-of,managed-by,version}` labels, and
  all but a small set of chart-emitted ConfigMaps additionally carry
  `app.kubernetes.io/component`

### Requirement: Component NetworkPolicies in the render

The committed render SHALL carry the chart's per-component NetworkPolicy set, so
the substrate ships Argo CD's upstream network posture rather than an
unrestricted namespace. The set SHALL be per-component allow-rules only: no
document may establish a namespace-wide default deny, and the `argocd-server`
policy SHALL admit ingress from every source, so a consumer terminating TLS at
their own gateway in front of Argo CD is never cut off by the floor.

#### Scenario: The render carries the component policies

- **WHEN** `_rendered/manifests.yaml` is scanned as structured documents
- **THEN** a `networking.k8s.io/v1` NetworkPolicy exists for the
  application-controller, the notifications-controller, redis, the repo-server
  and the server, each selecting only its own component's pods
- **AND** redis admits its named port only from the server, repo-server and
  application-controller components
- **AND** repo-server admits its named service port only from the server,
  application-controller, notifications-controller and applicationset-controller
  components, while its metrics port remains reachable from every namespace
- **AND** the application-controller and notifications-controller policies admit
  only their metrics ports from every namespace

#### Scenario: The server stays reachable and no default deny ships

- **WHEN** those NetworkPolicy documents are inspected
- **THEN** the `argocd-server` policy admits ingress from every source, and no
  document combines an empty pod selector with a deny-shaped rule

### Requirement: Argo CD image matches the chart appVersion

Every container image in the committed render, and in the seed render of the
module's values against the same pinned chart, SHALL be either the pinned
chart's Argo CD image — its `global.image.repository` tagged with its
`appVersion` — or an image from a repository the same chart declares for its
other components, or the base's own `viaductoss/ksops` init container. The
requirement binds image references, not the binary a container ends up
executing.

#### Scenario: The render ships the pinned release

- **WHEN** the committed component is kustomize-built, and both values files are
  rendered against the sha256-verified chart named in `chart.lock.yaml`
- **THEN** each contains at least one container on the pinned Argo CD image, and
  every other container image comes from an allowed repository

#### Scenario: An image override is rejected

- **WHEN** either values file or the committed render gives any container
  another Argo CD tag, an untagged or digest Argo CD reference, or an image from
  a repository the chart does not declare
- **THEN** the substrate invariant gate fails and names the offending image

### Requirement: The chart pin names the shipped Argo CD release

The chart pin SHALL name the Argo CD release the substrate ships, so a chart
bump in `kubernetes/substrate/argocd/chart.lock.yaml` is the only way to move
that release.

#### Scenario: Only a chart bump moves the release

- **WHEN** the Argo CD release the substrate ships is to change
- **THEN** the chart pinned in `chart.lock.yaml` is bumped, since any other
  Argo CD tag in either values file or the committed render fails the
  substrate invariant gate
