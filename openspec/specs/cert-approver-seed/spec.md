---
sources:
  primary:
    - tofu/modules/talos-cluster/manifests/kubelet-csr-approver.yaml
    - tofu/modules/talos-cluster/cert-approver.tf
references:
  - knowledge/decisions/0013-kubelet-serving-cert-rotation.md
  - knowledge/decisions/0019-postfinance-kubelet-csr-approver.md
---

# cert-approver-seed

## Purpose

`postfinance/kubelet-csr-approver` is delivered unconditionally as a
controlplane Talos `cluster.inlineManifests` seed: it approves the
`kubernetes.io/kubelet-serving` CSRs that the module's default-on kubelet
serving-cert rotation triggers. The cluster boots without it; metrics-server
and `kubectl logs|exec|top` need the approved serving certificates. The
approver identity is postfinance (ADR-0019 supersedes ADR-0013 §D2's
alex1989hu choice); unlike the retired approver it denies non-conforming CSRs
terminally and binds each DNS SAN to the requesting node.

## Requirements

### Requirement: Unconditional controlplane inlineManifest seed

The module SHALL always bake the cert-approver into the controlplane machine
configuration as two `cluster.inlineManifests` entries — the
`kubelet-csr-approver` Namespace first (entry name
`kubelet-csr-approver-namespace`), then the vendored manifest (entry name
`kubelet-csr-approver`: ServiceAccount, ClusterRole, ClusterRoleBinding,
Service, Deployment) — with no module variable to disable it.

#### Scenario: Seed present regardless of substrate toggles

- **WHEN** the module plans with any combination of `deploy_cilium` and
  `deploy_argocd` values
- **THEN** the controlplane config patches include the
  `kubelet-csr-approver-namespace` and `kubelet-csr-approver` inlineManifest
  entries in that order

### Requirement: Pairs with default-on kubelet serving-cert rotation

The module SHALL enable kubelet serving-cert rotation on all nodes via an
overridable machine-config patch setting
`machine.kubelet.extraConfig.serverTLSBootstrap: true` on both the
controlplane and worker patch lists, placed before caller `config_patches`
so a consumer can opt out; the seeded approver then approves the resulting
`kubernetes.io/kubelet-serving` CSRs from all nodes.

#### Scenario: Rotation patch applied to both node roles

- **WHEN** the module renders machine configurations
- **THEN** both the controlplane and worker patch lists contain
  `serverTLSBootstrap: true` under `machine.kubelet.extraConfig`, ordered
  before caller-supplied patches

### Requirement: Signer-restricted approval RBAC

The vendored manifest SHALL scope the approver's `approve` permission on
`signers` to the resource name `kubernetes.io/kubelet-serving` only, so the
ServiceAccount cannot approve CSRs for any other signer. The rendered
ClusterRole rule set SHALL stay a closed allowlist carrying no broader verb or
resource.

#### Scenario: Approve verb bound to one signer

- **WHEN** the vendored ClusterRole granting `approve` is inspected
- **THEN** its `signers` rule lists exactly
  `kubernetes.io/kubelet-serving` under `resourceNames`

#### Scenario: Closed allowlist in the default single-replica render

- **WHEN** the ClusterRole of the default single-replica render is inspected
- **THEN** it grants read (`get`/`list`/`watch`) and `update` on
  `certificatesigningrequests`
- **AND** `update` on the `certificatesigningrequests/approval` subresource
- **AND** `approve` on `signers` scoped to `kubernetes.io/kubelet-serving`
- **AND** no broader verb or resource

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

### Requirement: Per-cluster config surface with permissive defaults

The seed SHALL expose exactly three per-cluster knobs threaded through the
`templatefile()` render — `cert_approver_provider_regex` (default `".*"`),
`cert_approver_provider_ip_prefixes` (default `["0.0.0.0/0", "::/0"]`, which
MUST be non-empty), and `cert_approver_replicas` (default `1`) — injected as
the `PROVIDER_REGEX`, `PROVIDER_IP_PREFIXES` and `replicas` fields of the
rendered Deployment.

#### Scenario: Defaults render a permissive, bootable configuration

- **WHEN** the seed is rendered with no per-cluster overrides
- **THEN** the Deployment's environment carries `PROVIDER_REGEX` `".*"`,
  `PROVIDER_IP_PREFIXES` `"0.0.0.0/0,::/0"`, and `BYPASS_DNS_RESOLUTION`
  `"true"`, and `replicas` is `1`

#### Scenario: Consumer values flow through the render

- **WHEN** the module is rendered with non-default
  `cert_approver_provider_regex` and `cert_approver_provider_ip_prefixes`
- **THEN** the rendered Deployment's `PROVIDER_REGEX` and
  `PROVIDER_IP_PREFIXES` environment values reflect the supplied inputs, and
  a metacharacter-bearing `provider_regex` still renders a parseable manifest

#### Scenario: DNS-resolution bypass is a constant, not a knob

- **WHEN** the module's per-cluster knobs are listed
- **THEN** none controls `BYPASS_DNS_RESOLUTION`
- **AND** it SHALL be the module-local constant `"true"`

#### Scenario: All-IPs prefix default is the safe floor

- **WHEN** the approver evaluates a CSR carrying an IP SAN
- **THEN** it checks each IP SAN for membership in the prefix set
  unconditionally, so an empty set would deny every such CSR
- **AND** the all-IPs default lets every cluster boot and approve conforming
  kubelet-serving CSRs out of the box

#### Scenario: Consumer tightens IP SAN binding

- **WHEN** a consumer sets `provider_ip_prefixes` to its node subnets, and
  optionally tightens `provider_regex`
- **THEN** IP SANs are bound to the cluster's addresses

### Requirement: Always-on per-node DNS-SAN binding

The seeded approver SHALL bind each DNS SAN on a kubelet-serving CSR to the
requesting node by enforcing that the SAN DNS name is prefixed by the node
hostname derived from the CSR's `system:node:<hostname>` username, independent
of `provider_regex` — so the default `".*"` regex is not "no binding".

#### Scenario: DNS binding is active under the permissive default regex

- **WHEN** the seed is rendered with the default `provider_regex` `".*"`
- **THEN** `BYPASS_DNS_RESOLUTION` is `"true"` and the per-node
  hostname-prefix DNS-SAN binding still applies — the regex default relaxes
  the cluster-wide pattern gate, never the per-node bind

#### Scenario: Source-verified limits of the binding

- **WHEN** a CSR's DNS SAN or SAN set is checked against the node
- **THEN** the check is `HasPrefix` (prefix, not exact — `node-1` matches
  `node-10`)
- **AND** a CSR carrying only IP SANs and no DNS name is bounded only by
  `provider_ip_prefixes`

### Requirement: Replicas drive leader-election and leases RBAC

The seed SHALL render a single-replica, least-privilege configuration by
default: at `cert_approver_replicas == 1` the manifest carries no
`-leader-election` container argument and no `coordination.k8s.io/leases`
RBAC. When `cert_approver_replicas > 1` the module SHALL auto-enable
leader-election — rendering the `-leader-election` argument and the derived
`coordination.k8s.io/leases` RBAC rule — so the HA configuration is coherent
without a second knob.

#### Scenario: Single replica keeps least privilege

- **WHEN** the seed is rendered with `cert_approver_replicas` at its default
- **THEN** the manifest sets `replicas: 1`, carries no `-leader-election`
  argument, and its ClusterRole grants no `coordination.k8s.io/leases` rule

#### Scenario: Raising replicas enables leader-election and leases RBAC

- **WHEN** the seed is rendered with `cert_approver_replicas` greater than 1
- **THEN** the Deployment sets that replica count and the `-leader-election`
  argument, and the rendered RBAC includes the `coordination.k8s.io/leases`
  rule

### Requirement: Restricted namespace floor and recommended labels

The module SHALL seed the `kubelet-csr-approver` Namespace with pod-security
labels at `restricted` (enforce, audit, and warn) plus the recommended label
set, and the vendored manifest SHALL carry the recommended labels on every
object and on the pod template (normative: AGENTS.md §Hard Constraints —
Kubernetes recommended labels on all resources); the Deployment's pod
satisfies the restricted profile (non-root, all capabilities dropped,
read-only root filesystem, runtime default seccomp).

#### Scenario: Namespace enforces restricted PSA

- **WHEN** the seeded Namespace manifest is inspected
- **THEN** it carries `pod-security.kubernetes.io/enforce: restricted` and
  the six `app.kubernetes.io/*` recommended labels with
  `app.kubernetes.io/managed-by: opentofu`

#### Scenario: Workload passes the restricted profile

- **WHEN** the Deployment's pod spec is inspected
- **THEN** it sets `runAsNonRoot: true`, drops all capabilities, uses a
  read-only root filesystem, and sets a `RuntimeDefault` seccomp profile

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
