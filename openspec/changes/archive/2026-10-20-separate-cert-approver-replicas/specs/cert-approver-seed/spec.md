## ADDED Requirements

### Requirement: Replicas above one are separated and budgeted

When `cert_approver_replicas > 1` the seed SHALL give the Deployment's pod
template one required pod anti-affinity term on `kubernetes.io/hostname`
whose `labelSelector.matchLabels` are the approver's `name` and `instance`
labels and whose `matchLabelKeys` is `[pod-template-hash]`, and SHALL add a
`policy/v1` PodDisruptionBudget `kubelet-csr-approver` with the same selector,
`maxUnavailable: 1` and `unhealthyPodEvictionPolicy: AlwaysAllow`. At the
default `1` the seed SHALL render neither.

#### Scenario: Default single replica renders no separation

- **WHEN** the seed is rendered with `cert_approver_replicas` at its default
- **THEN** the Deployment carries no `affinity` and the seed contains no
  PodDisruptionBudget

#### Scenario: Two replicas never share a node

- **WHEN** the seed is rendered with `cert_approver_replicas = 2`
- **THEN** the pod template carries exactly one
  `requiredDuringSchedulingIgnoredDuringExecution` anti-affinity term with
  `topologyKey: kubernetes.io/hostname`, a `labelSelector` equal to the
  approver's `name` and `instance` labels, and `matchLabelKeys`
  `[pod-template-hash]`
- **AND** `pod-template-hash` does not appear in that `labelSelector`

#### Scenario: A drain evicts one replica at a time

- **WHEN** the seed is rendered with `cert_approver_replicas = 2`
- **THEN** it contains one `policy/v1` PodDisruptionBudget
  `kubelet-csr-approver` in namespace `kubelet-csr-approver` carrying the six
  recommended labels, the Deployment's selector, `maxUnavailable: 1` and
  `unhealthyPodEvictionPolicy: AlwaysAllow`

## MODIFIED Requirements

### Requirement: Vendored, chart-rendered, digest-pinned templated manifest

The seed SHALL use the vendored-chart-render pattern: the pinned upstream
Helm chart output is committed at
`tofu/modules/talos-cluster/manifests/kubelet-csr-approver.yaml` and rendered
through OpenTofu `templatefile()` into `local.cert_approver_manifest` (not
read raw via `file()`), with a header recording its provenance and a
digest-pinned container image.

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
- **AND** a modification that renders only at `cert_approver_replicas > 1`
  and was added after the header may instead be described by a comment inside
  its own gated block, so that the default render stays unchanged

#### Scenario: Header pins chart version and render values

- **WHEN** the vendored file's header is read
- **THEN** it records the chart name and version `1.2.15` with appVersion
  `v1.2.15`
- **AND** it records the values used by the `helm template` command

#### Scenario: Only config values and leader-election are templated

- **WHEN** the vendored manifest's template placeholders are listed
- **THEN** only the per-cluster config values, the leader-election blocks and
  the replica-separation blocks are re-parameterized as placeholders

#### Scenario: Pure render stays outside the determinism fence

- **WHEN** the Helm-render-determinism fence is evaluated
- **THEN** the seed is outside it, because `templatefile()` is pure
