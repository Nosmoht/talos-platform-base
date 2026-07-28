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

The component SHALL be consumable as a single kustomization whose resources
are exactly the namespace manifest and the two committed rendered artifacts.

#### Scenario: Component builds from committed inputs only

- **WHEN** `kubectl kustomize kubernetes/substrate/argocd/` runs
- **THEN** the output is assembled from `namespace.yaml`,
  `_rendered/manifests.yaml`, and `_rendered/crds.yaml` with no live chart
  fetch or template step

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
