---
sources:
  primary:
    - tofu/modules/talos-cluster/main.tf
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
regions (including the post-health ArgoCD CRD server-side apply) plus the
Image-Factory and machine-config regions; the latter two are owned
descriptively by the `node-image-composition` and
`machine-config-generation` specs. Day-2 OS and Kubernetes upgrades are
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
every declared node, keyed by hostname and targeted at the node's IP;
nodes are expected to already be reachable in Talos maintenance mode —
the module does not provision hardware or boot nodes.

#### Scenario: Every node receives its role's configuration

- **WHEN** the apply runs over the declared node set
- **THEN** each node receives the machine configuration matching its
  role, addressed at its declared IP, with one apply resource per
  hostname

### Requirement: Single-node bootstrap on a stable target

The module SHALL bootstrap etcd on exactly one node — the controlplane
with the lexicographically lowest hostname — and only after every node's
configuration apply, selecting the target by stable hostname key rather
than list order.

#### Scenario: Node-list reordering does not move the bootstrap target

- **WHEN** `var.nodes` is reordered after the cluster was bootstrapped
- **THEN** the bootstrap target remains the controlplane with the lowest
  hostname and no re-bootstrap is planned

### Requirement: Credential retrieval

The module SHALL retrieve the admin kubeconfig from the bootstrap
controlplane after bootstrap completes, and SHALL derive a talosconfig
whose endpoints are the controlplane IPs and whose node list covers all
declared nodes.

#### Scenario: Credentials follow the bootstrap

- **WHEN** the bootstrap has completed
- **THEN** the admin kubeconfig is pulled from the bootstrap controlplane
  and the talosconfig lists every controlplane as an endpoint and every
  node as a node

### Requirement: Blocking health gate

The module SHALL block the apply until the cluster reports healthy — etcd
quorum established, all declared controlplane and worker nodes Ready,
kubelet and apiserver responding — bounded by the configurable
`cluster_health_timeout`.

#### Scenario: Apply succeeds only for a healthy cluster

- **WHEN** the bootstrap has run but the cluster does not become healthy
  within `var.cluster_health_timeout`
- **THEN** the apply fails instead of returning success
