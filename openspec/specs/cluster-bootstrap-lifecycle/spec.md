---
sources:
  primary:
    - tofu/modules/talos-cluster/main.tf
    - tofu/modules/talos-cluster/kubeconfig-refresh.tf
references:
  - knowledge/decisions/0006-opentofu-cluster-lifecycle.md
---

# cluster-bootstrap-lifecycle

## Purpose

Describe the runtime flow of `tofu/modules/talos-cluster/main.tf` — the
sole Talos cluster-lifecycle path: machine secrets generation, machine
configuration apply to maintenance-mode nodes, single-node etcd bootstrap,
kubeconfig/talosconfig retrieval, and the blocking health gate.

`main.tf` also hosts the ArgoCD, Cilium and cert-approver render/seed
regions (including the post-health ArgoCD CRD server-side apply and the
CRD-only projection bounding it — both owned descriptively by the
`argocd-module-seed` spec) plus the
Image-Factory and machine-config regions; the latter two are owned
descriptively by the `node-image-composition` and
`machine-config-generation` specs. The Cilium value-computation locals
(the module-computed values feeding both the frozen seed and the opt-in
emitted self-management Application, and the emitted-Application local
itself) live in the sibling `cilium-values.tf`, owned by
`cilium-cni-delivery` — moved out of `main.tf` (issue #188) so both
consumers of the computed values read the same map. The cert-approver
region seeds
`postfinance/kubelet-csr-approver` (ADR-0019 supersedes ADR-0013 §D2) by
rendering the vendored chart manifest through `templatefile()` into
`local.cert_approver_manifest` — a pure render, not a raw `file()` read —
and baking it as a controlplane inlineManifest. Day-2 OS and Kubernetes upgrades are
out-of-band: applying configuration alone does not re-image a node — the
consumer runs `talosctl` against the rendered installer URL and version
outputs.

## Requirements

### Requirement: Machine secrets generation

The module SHALL generate the cluster PKI and shared secrets once, pinned
to the schema-pin Talos version, and store them in OpenTofu state; the
caller is responsible for using an encrypted state backend. Adopting an
already-running cluster requires importing the existing secrets before
the first apply.

#### Scenario: Fresh cluster generates fresh PKI

- **WHEN** the module is applied against a state with no existing machine
  secrets
- **THEN** a new secrets bundle is generated at `var.talos_version` and
  persisted in state

### Requirement: Per-node configuration apply

The module SHALL apply the role-appropriate machine configuration to
every declared node, keyed by node name and targeted at the node's IP;
nodes are expected to already be reachable in Talos maintenance mode —
the module does not provision hardware or boot nodes. The apply SHALL
iterate the identity-checked node view rather than the raw input, so the
IP-collision guard is evaluated on the apply path.

#### Scenario: Every node receives its role's configuration

- **WHEN** the apply runs over the declared node set
- **THEN** each node receives the machine configuration matching its
  role, addressed at its declared IP, with one apply resource per
  node name

The controlplane document carries every `inlineManifests` seed at once, so the
module SHALL reject an oversized controlplane payload at PLAN time rather than
letting it fail at apply against real hardware. The bound SHALL be expressed
against a ceiling traceable to a Talos source — the `ApplyConfiguration` message
limit — and SHALL be evaluated over inputs that are known on a first plan, so the
check cannot silently defer to apply. Its failure SHALL name the measured size,
the ceiling, and which substrate seeds are enabled, so the operator can act
without re-deriving the payload. No permanent test binds the ceiling: a synthetic
payload at that scale is impractical to commit, so the binding is a documented
re-runnable procedure (lower the ceiling constant, run the module's test target).

#### Scenario: An oversized controlplane payload fails the plan

- **WHEN** the summed controlplane machine-config patches exceed the module's
  payload ceiling
- **THEN** the plan fails with an error naming the measured byte count, the
  ceiling, and the enabled seeds — the apply is never attempted

### Requirement: Apply mode per role

The module SHALL expose the apply mode of the machine-configuration apply as two
separate inputs, one per role, so an operator can keep an apply from rebooting the
nodes of one role without affecting the other. The default SHALL be the
provider's own `auto`: the same apply resource carries the Day-0 apply to
maintenance-mode nodes, where the apply IS the install, so a staging default
would write the configuration without installing and the bootstrap would then run
against a node that never left maintenance mode. With a staging mode set, the
module SHALL write the configuration and leave the reboot to the operator — an
out-of-band, health-gated step performed one node at a time, outside this module.

#### Scenario: The default keeps the Day-0 install path intact

- **WHEN** neither apply-mode input is set, on a single-node or a multi-node
  cluster
- **THEN** every node's apply resolves to `auto`, and the Day-0 apply installs and
  reboots as before

#### Scenario: One role is staged for a window

- **WHEN** the worker apply mode is set to a staging mode and the controlplane
  input is left at its default
- **THEN** the worker applies carry the staging mode and the controlplane applies
  carry `auto`, so no controlplane reboot follows from the change

### Requirement: Single-node bootstrap on a stable target

The module SHALL bootstrap etcd on exactly one node — the controlplane
with the lexicographically lowest name — and only after every node's
configuration apply, selecting the target by a stable name key.

#### Scenario: The bootstrap target is the lowest-named CONTROLPLANE

- **WHEN** the node set contains a worker whose name sorts below every
  controlplane
- **THEN** the bootstrap target is still the lowest-named controlplane,
  not the lowest-named node

#### Scenario: Re-declaring the node set does not move the bootstrap target

- **WHEN** the same node set is declared again in a different order
- **THEN** the bootstrap target is unchanged and no re-bootstrap is
  planned

Adding a controlplane whose name sorts BELOW the incumbent does move the
target — a known hazard the module cannot resolve on the consumer's
behalf, documented in the module README and `UPGRADING.md`.

### Requirement: Credential retrieval

The module SHALL retrieve the admin kubeconfig from the bootstrap
controlplane after bootstrap completes, and SHALL derive a talosconfig
whose endpoints are the controlplane IPs and whose node list covers all
declared nodes. Both lists SHALL be the name-ordered projections of the
node set, not independently rebuilt filters.

#### Scenario: Credentials follow the bootstrap

- **WHEN** the bootstrap has completed
- **THEN** the admin kubeconfig is pulled from the bootstrap controlplane
  and the talosconfig lists every controlplane as an endpoint and every
  node as a node, each in node-name order

#### Scenario: Kubeconfig regenerates when the advertised endpoint changes

- **WHEN** the advertised cluster endpoint (`var.cluster_endpoint`) changes
  on a later apply
- **THEN** the module regenerates the admin kubeconfig so its emitted
  `server:` reflects the current endpoint, rather than staying frozen at
  the create-time value. Regeneration alone does not make the endpoint
  reachable: the new endpoint's certificate SAN and network propagation
  must also already be in place, which this scenario does not establish

### Requirement: Blocking health gate

The module SHALL block the apply until the cluster reports healthy — etcd
quorum established, all declared controlplane and worker nodes Ready,
kubelet and apiserver responding — bounded by the configurable
`cluster_health_timeout`.

#### Scenario: Apply succeeds only for a healthy cluster

- **WHEN** the bootstrap has run but the cluster does not become healthy
  within `var.cluster_health_timeout`
- **THEN** the apply fails instead of returning success
