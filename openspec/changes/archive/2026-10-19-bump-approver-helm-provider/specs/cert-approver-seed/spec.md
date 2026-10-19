## MODIFIED Requirements

### Requirement: Vendored, chart-rendered, digest-pinned templated manifest

The seed SHALL use the vendored-chart-render pattern: the pinned upstream
Helm chart output is committed at
`tofu/modules/talos-cluster/manifests/kubelet-csr-approver.yaml` and rendered
through OpenTofu `templatefile()` into `local.cert_approver_manifest` (not
read raw via `file()`), with a header recording the upstream repository, the
chart name and version (`1.2.15`, appVersion `v1.2.15`), the chart tarball
SHA-256, the `helm template` command and values used, and the list of local
modifications. Only the per-cluster config values and the leader-election
blocks are re-parameterized as template placeholders; the container image is
digest-pinned with `imagePullPolicy: IfNotPresent`. Because `templatefile()`
is pure, the seed stays outside the Helm-render-determinism fence.

#### Scenario: Image immutability without registry round-trips

- **WHEN** the Deployment in the rendered manifest is inspected
- **THEN** its container image reference is
  `ghcr.io/postfinance/kubelet-csr-approver:v1.2.15@sha256:6469ef517d2b6d3cb108fce8a913483533a48b1cd78b5d4af307fa09e04a7818`
  with an `@sha256:` digest and `imagePullPolicy: IfNotPresent`

#### Scenario: Provenance recorded for re-vendoring

- **WHEN** the vendored file's header is read
- **THEN** it names the upstream repository, the pinned chart version and
  appVersion, the chart tarball SHA-256 checksum, the `helm template`
  invocation, and the list of local modifications applied to the render
