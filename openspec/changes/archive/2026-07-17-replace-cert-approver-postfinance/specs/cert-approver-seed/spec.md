## MODIFIED Requirements

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

### Requirement: Signer-restricted approval RBAC

The vendored manifest SHALL scope the approver's `approve` permission on
`signers` to the resource name `kubernetes.io/kubelet-serving` only, so the
ServiceAccount cannot approve CSRs for any other signer. The rendered
ClusterRole rule set SHALL stay a closed allowlist — in the default
single-replica render: read (`get`/`list`/`watch`) and `update` on
`certificatesigningrequests`, `update` on the `certificatesigningrequests/approval`
subresource, and `approve` on `signers` scoped to
`kubernetes.io/kubelet-serving` — carrying no broader verb or resource.

#### Scenario: Approve verb bound to one signer

- **WHEN** the vendored ClusterRole granting `approve` is inspected
- **THEN** its `signers` rule lists exactly
  `kubernetes.io/kubelet-serving` under `resourceNames`

### Requirement: Vendored, chart-rendered, digest-pinned templated manifest

The seed SHALL use the vendored-chart-render pattern: the pinned upstream
Helm chart output is committed at
`tofu/modules/talos-cluster/manifests/kubelet-csr-approver.yaml` and rendered
through OpenTofu `templatefile()` into `local.cert_approver_manifest` (not
read raw via `file()`), with a header recording the upstream repository, the
chart name and version (`1.2.14`, appVersion `v1.2.14`), the chart tarball
SHA-256, the `helm template` command and values used, and the list of local
modifications. Only the per-cluster config values and the leader-election
blocks are re-parameterized as template placeholders; the container image is
digest-pinned with `imagePullPolicy: IfNotPresent`. Because `templatefile()`
is pure, the seed stays outside the Helm-render-determinism fence.

#### Scenario: Image immutability without registry round-trips

- **WHEN** the Deployment in the rendered manifest is inspected
- **THEN** its container image reference is
  `ghcr.io/postfinance/kubelet-csr-approver:v1.2.14@sha256:c0f6aa1abdc225a32f9a29992fd97f711e78e2df21434f9ce7bc60981f96a5f8`
  with an `@sha256:` digest and `imagePullPolicy: IfNotPresent`

#### Scenario: Provenance recorded for re-vendoring

- **WHEN** the vendored file's header is read
- **THEN** it names the upstream repository, the pinned chart version and
  appVersion, the chart tarball SHA-256 checksum, the `helm template`
  invocation, and the list of local modifications applied to the render

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

## ADDED Requirements

### Requirement: Per-cluster config surface with permissive defaults

The seed SHALL expose exactly three per-cluster knobs threaded through the
`templatefile()` render — `cert_approver_provider_regex` (default `".*"`),
`cert_approver_provider_ip_prefixes` (default `["0.0.0.0/0", "::/0"]`, which
MUST be non-empty), and `cert_approver_replicas` (default `1`) — injected as
the `PROVIDER_REGEX`, `PROVIDER_IP_PREFIXES` and `replicas` fields of the
rendered Deployment. `BYPASS_DNS_RESOLUTION` SHALL be a module-local constant
`"true"`, not a knob. The IP-prefix default of all-IPs is the safe floor: an
empty set would deny every CSR carrying an IP SAN (the approver checks each IP
SAN for set membership unconditionally). Under the defaults every cluster
boots and approves conforming kubelet-serving CSRs out of the box; a consumer
tightens `provider_ip_prefixes` to its node subnets (and optionally
`provider_regex`) to bind IP SANs to the cluster's addresses.

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

### Requirement: Always-on per-node DNS-SAN binding

The seeded approver SHALL bind each DNS SAN on a kubelet-serving CSR to the
requesting node by enforcing that the SAN DNS name is prefixed by the node
hostname derived from the CSR's `system:node:<hostname>` username, independent
of `provider_regex` — so the default `".*"` regex is not "no binding". This is
an observable capability gain over the retired alex1989hu approver, which
performed no SAN-to-node binding. Two source-verified limits hold: the check
is `HasPrefix` (prefix, not exact — `node-1` matches `node-10`), and a CSR
carrying only IP SANs and no DNS name is bounded only by
`provider_ip_prefixes`.

#### Scenario: DNS binding is active under the permissive default regex

- **WHEN** the seed is rendered with the default `provider_regex` `".*"`
- **THEN** `BYPASS_DNS_RESOLUTION` is `"true"` and the per-node
  hostname-prefix DNS-SAN binding still applies — the regex default relaxes
  the cluster-wide pattern gate, never the per-node bind

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
