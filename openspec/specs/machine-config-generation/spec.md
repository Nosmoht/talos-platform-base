---
sources:
  secondary:
    - tofu/modules/talos-cluster/main.tf
references:
  - AGENTS.md §Hard Constraints — No `debugfs=off`
  - knowledge/decisions/0011-substrate-hard-constraints.md
---

# machine-config-generation

## Purpose

Describe the machine-config region of
`tofu/modules/talos-cluster/main.tf`: per-role machine-configuration
generation and the two-pass patch composition order that layers module
defaults, caller patches and the module's authoritative patches. The
region lives in `main.tf`, whose primary owner is the
`cluster-bootstrap-lifecycle` spec; this spec owns the region
descriptively. The module-generated per-node capability patch it consumes
is composed per the `hardware-capability-composition` spec.

## Requirements

### Requirement: Per-role machine configuration

The module SHALL generate one base machine configuration per node role —
`controlplane` and `worker` — each carrying the cluster name, the cluster
endpoint, the Kubernetes version, the schema-pin Talos version, the shared
machine secrets and the role's composed patch list.

#### Scenario: Node role selects the configuration

- **WHEN** the module applies configuration to a node
- **THEN** a `controlplane` node receives the controlplane machine
  configuration and a `worker` node receives the worker machine
  configuration

### Requirement: Generation-pass patch order

The module SHALL compose each role's generation-pass patch list in this
order: the overridable base cluster patch (pod/service subnets,
controlplane scheduling) and the overridable kubelet rotation patch first,
then all-nodes caller patches (`config_patches`), then the role-specific
caller patches, and only after all caller patches the authoritative CNI
patch. The controlplane list additionally appends the opt-in Gateway API
CRDs patch, the cert-approver seed patch, and — last — the ArgoCD and
Cilium inline-manifest seed patches.

#### Scenario: Caller patch overrides the base cluster patch

- **WHEN** a caller config patch sets a value also set by the base
  cluster patch
- **THEN** the caller value takes effect, because the base patches are
  placed first and later patches win

#### Scenario: Caller patch cannot resurrect the default CNI

- **WHEN** `deploy_cilium` is true and a caller patch carries a
  `cluster.network.cni` stanza
- **THEN** the module's CNI patch (`cni: none`, plus `proxy.disabled`
  when kube-proxy replacement is enabled), placed after all caller
  patches, takes effect

### Requirement: Apply-pass per-node patch order

The module SHALL layer a second, per-node patch pass at configuration
apply, in this order: the module install-image patch, a `HostnameConfig`
document setting the node's static hostname (deleting the
provider-generated `auto` field), the module-generated capability patch,
the node's own `config_patches`, and the CNI patch re-applied last.

#### Scenario: Per-node patch overrides generated capability values

- **WHEN** a node declares a raw config patch that sets a value also
  produced by the module-generated capability patch
- **THEN** the node patch wins because it is applied after the generated
  patch, while the CNI patch still applies last

### Requirement: Kubelet serving-cert rotation default

The module SHALL enable kubelet serving-certificate rotation on both
roles by default via the KubeletConfiguration field
`machine.kubelet.extraConfig.serverTLSBootstrap: true` — not the
deprecated kubelet flag — placed first in each role's patch list so a
caller patch can opt out.

#### Scenario: Rotation wired into both roles

- **WHEN** the module composes the controlplane and worker patch lists
- **THEN** both lists contain the kubelet rotation patch and the
  `kubelet_serving_cert_rotation` output reports `controlplane = true`
  and `worker = true`

### Requirement: Caller-patch and network-input plan guards

The module SHALL fail the plan when any caller-supplied patch string
(all-nodes, role-specific or per-node) references a `-secureboot`
installer image — a substring heuristic (normative: AGENTS.md §Hard
Constraints — No SecureBoot) — and when the IP families of
`pod_cidr`/`service_cidr` disagree with `dual_stack` in either direction.

#### Scenario: SecureBoot-selecting caller patch fails the plan

- **WHEN** any caller config patch contains a `-secureboot` installer
  reference
- **THEN** the plan fails with an error naming the Hard Constraint and
  pointing at the non-SecureBoot installer

#### Scenario: CIDR family and dual_stack mismatch fails the plan

- **WHEN** `dual_stack` is true and `pod_cidr` or `service_cidr` lacks an
  IPv4 or an IPv6 entry, or `dual_stack` is false and either list carries
  an IPv6 entry
- **THEN** the plan fails with an error describing the required family
  combination

### Requirement: Module-shipped patches carry no debugfs disable

The patches the module composes into the machine configuration from its
own locals SHALL contain no `debugfs=off` kernel argument (normative:
AGENTS.md §Hard Constraints — No `debugfs=off`; see
`knowledge/decisions/0011-substrate-hard-constraints.md`).

#### Scenario: Composed module patches are debugfs-clean

- **WHEN** the module composes the generation-pass and apply-pass patch
  lists from its shipped locals
- **THEN** no module-shipped patch carries a `debugfs=off` kernel
  argument
