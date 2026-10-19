## MODIFIED Requirements

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

#### Scenario: Header pins chart version and render values

- **WHEN** the vendored file's header is read
- **THEN** it records the chart name and version `1.2.15` with appVersion
  `v1.2.15`
- **AND** it records the values used by the `helm template` command

#### Scenario: Only config values and leader-election are templated

- **WHEN** the vendored manifest's template placeholders are listed
- **THEN** only the per-cluster config values and the leader-election blocks
  are re-parameterized as placeholders

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
