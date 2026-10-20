---
sources:
  primary:
    - tofu/modules/talos-cluster/coredns-seed.tf
references:
  - knowledge/decisions/0031-coredns-required-node-separation.md
---

# coredns-seed

## Purpose

An opt-in controlplane inline-manifest seed that replaces the Talos built-in
CoreDNS, so the cluster DNS replicas run on separate nodes and a drain evicts
them one at a time. The seed keeps every object identity of the built-in, so
`talosctl upgrade-k8s` updates the running objects in place and the `kube-dns`
ClusterIP survives the cutover (ADR-0031).

## Requirements

### Requirement: Opt-in seed under the built-in identities

When `coredns_node_separation` is true, the module SHALL disable the Talos
built-in CoreDNS and seed one controlplane inline manifest `coredns` carrying
the built-in's objects under their kinds, names and namespaces, plus a
PodDisruptionBudget `kube-system/coredns-node-separation`. When the input is
false the module
SHALL write no CoreDNS setting and no seed.

#### Scenario: The seed keeps every built-in identity

- **WHEN** the seed is rendered
- **THEN** its objects are, in order, the ServiceAccount
  `kube-system/coredns`, the ClusterRole and ClusterRoleBinding
  `system:coredns`, the ConfigMap and the Deployment `kube-system/coredns`, the
  Service `kube-system/kube-dns` and the PodDisruptionBudget
  `kube-system/coredns-node-separation`
- **AND** the `talosctl upgrade-k8s` sync updates the running objects instead
  of pruning them

#### Scenario: The default leaves the built-in in place

- **WHEN** `coredns_node_separation` is unset
- **THEN** the module writes no CoreDNS document and no seed manifest

### Requirement: Built-in disable on both schema lines

The module SHALL disable the built-in with a `KubeCoreDNSConfig` document
carrying `enabled: false` on a native schema pin, and with
`cluster.coreDNS.disabled: true` on an earlier one, placed after every caller
patch and reasserted after each control plane's own patches.

#### Scenario: A native schema pin

- **WHEN** the schema pin is 1.14 or later and the seed is on
- **THEN** the controlplane patch list carries `KubeCoreDNSConfig` with
  `enabled: false`

#### Scenario: An earlier schema pin

- **WHEN** the schema pin is earlier than 1.14 and the seed is on
- **THEN** the controlplane patch list carries `cluster.coreDNS.disabled: true`

### Requirement: Required node separation and disruption budget

The seeded Deployment SHALL keep the selector `k8s-app: kube-dns` and carry
exactly one pod anti-affinity term, required, on `kubernetes.io/hostname`,
selecting `k8s-app: kube-dns` with `matchLabelKeys: [pod-template-hash]`. The
PodDisruptionBudget SHALL select `k8s-app: kube-dns` with `maxUnavailable: 1`
and `unhealthyPodEvictionPolicy: AlwaysAllow`.

#### Scenario: Replicas never share a node

- **WHEN** the seeded Deployment schedules its replicas
- **THEN** no two replicas of one ReplicaSet land on the same node, and a
  rolling update is not blocked by the previous ReplicaSet's pods

#### Scenario: A drain evicts one replica at a time

- **WHEN** a node holding a CoreDNS replica is drained with `kubectl drain`
- **THEN** the budget admits that one eviction and the other replica keeps
  serving

### Requirement: Drains run through kubectl before Talos operations

The budget holds only a drain that waits for the eviction API, such as
`kubectl drain`; machined's own drain gives up after five minutes and proceeds,
and while two budgets select a pod every drain of it fails or proceeds at once.
The documented cutover, back-out and recovery procedures SHALL therefore run
`kubectl drain` on a node, to completion, before any Talos lifecycle operation
on it, and none while two CoreDNS budgets exist.

#### Scenario: A drain the budget does not allow waits

- **WHEN** one replica is Pending and the node of the Ready replica is drained
  with `kubectl drain`
- **THEN** the drain waits instead of evicting it, and the procedure starts no
  Talos lifecycle operation on that node

### Requirement: Service and Corefile equal the built-in

The `kube-dns` Service SHALL carry the built-in's selector, ports and
ClusterIP: the tenth address after the base of each `service_cidr` entry, the
first IPv4 address first, with `RequireDualStack` when both families are
present and `SingleStack` otherwise. The Corefile SHALL equal the one Talos
renders for the DNS domain `cluster.local`.

#### Scenario: The ClusterIP survives the cutover

- **WHEN** the seed replaces the built-in on a cluster with the default
  service CIDR
- **THEN** the Service keeps the ClusterIP `10.96.0.10`

#### Scenario: A dual-stack cluster

- **WHEN** `service_cidr` carries an IPv4 and an IPv6 entry
- **THEN** the Service carries both tenth addresses, IPv4 first, with
  `RequireDualStack`

### Requirement: Network inputs the seed depends on

The module SHALL fail the plan when the seed is on and the rendered
controlplane or worker configuration, or a node's own patch, carries a DNS
domain other than `cluster.local` or service subnets other than
`service_cidr`, or sets a CoreDNS image other than `coredns_image`, or when a
rendered role configuration states no service subnets.

#### Scenario: A caller patch changes the DNS domain

- **WHEN** a caller patch sets another DNS domain and the seed is on
- **THEN** the plan fails with an error naming the domain and service-subnet
  dependency

#### Scenario: A caller patch sets another CoreDNS image

- **WHEN** a caller patch sets the Talos CoreDNS image and the seed is on
- **THEN** the plan fails rather than silently replacing it with
  `coredns_image`

### Requirement: Patches cannot delete the seed's inputs or replace the seed

The module SHALL fail the plan when the seed is on and a patch deletes the DNS
domain, the service subnets or a parent with `$patch`, or a node's own patch is
a JSON6902 patch whose path or `from` names one of them,
`cluster.inlineManifests` or a parent, or carries an inline manifest named
`coredns` or a `$patch` on `cluster.inlineManifests`.

#### Scenario: A node patch replaces the seed

- **WHEN** a node's own patch carries an inline manifest named `coredns`, in
  either schema form, and the seed is on
- **THEN** the plan fails, because the seed cannot be written again after the
  node patches

#### Scenario: A node patch deletes the network

- **WHEN** a node's own patch carries `$patch: delete` on `cluster.network` and
  the seed is on
- **THEN** the plan fails instead of letting Talos fall back to its default
  service subnet

### Requirement: The network guard reads every document or fails

A document of the guarded sources that does not decode as YAML, or is neither a
mapping nor a JSON6902 patch, SHALL fail the plan. Documents SHALL be split on
every YAML separator line, with or without a trailing comment and with LF or
CRLF line ends, and the service subnets SHALL be compared without regard to
order.

#### Scenario: A patch document the guard cannot read

- **WHEN** a node patch carries a document that does not decode as YAML, or a
  document whose `cluster.network` is not a mapping
- **THEN** the plan fails instead of passing the document unchecked

#### Scenario: The service subnets in another order

- **WHEN** the rendered configuration lists the `service_cidr` subnets in
  another order
- **THEN** the guard passes, because the ClusterIP takes the first address of
  each family

### Requirement: The budget carries the seed digest

The PodDisruptionBudget SHALL carry the annotation
`talos-platform-base.io/seed-digest` equal to the output `coredns_seed_digest`,
the sha256 of every seed object without that annotation.

#### Scenario: A control plane renders the current seed

- **WHEN** a control plane's rendered `99-coredns` manifest is read
- **THEN** it shows `coredns_seed_digest` exactly when the node runs the seed
  the module renders now

### Requirement: Seed objects carry the recommended labels

Every object in the seed SHALL carry the six `app.kubernetes.io/*`
recommended labels (normative: AGENTS.md §Hard Constraints).

#### Scenario: No seed object lacks a recommended label

- **WHEN** the seed objects are decoded
- **THEN** none of them misses one of the six labels
