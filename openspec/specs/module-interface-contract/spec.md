---
sources:
  primary:
    - tofu/modules/talos-cluster/variables.tf
    - tofu/modules/talos-cluster/outputs.tf
    - tofu/modules/talos-cluster/versions.tf
---

# module-interface-contract

## Purpose

The typed surface of `tofu/modules/talos-cluster`: the variable groups a
consumer root maps its `cluster.yaml` onto, the in-code validations that
reject invalid input at plan time, the output contract (credentials,
image/upgrade data, audit surfaces), and the provider/version
constraints. The module is backend- and caller-agnostic: the caller
supplies the provider configuration and the state backend, and all
cluster identity arrives through these inputs — the module ships none of
its own.

## Requirements

### Requirement: Grouped typed input surface

The module SHALL expose its inputs as typed variable groups: cluster
identity (`cluster_name`, `cluster_endpoint`); versions (`talos_version`
as the machine-config schema pin fixed at bootstrap,
`talos_install_version` as the installer pin defaulting to the schema
pin, `kubernetes_version`); topology (`nodes`, `images`,
`hardware_capabilities`); machine-config patches (all-nodes, per-role and
per-node lists); substrate delivery (the ArgoCD and Cilium toggles with
their chart-version, namespace, values-override and secret-material
knobs, plus a chart-repository knob for Cilium only — the ArgoCD chart
repository is hardcoded in `main.tf`); cluster network (`pod_cidr`,
`service_cidr`, `dual_stack`, `allow_scheduling_on_controlplanes`); and
the cluster health timeout. Because `deploy_argocd` defaults to true and
a plan-time precondition requires `sops_age_key` to be a valid age
private key whenever ArgoCD is deployed, `sops_age_key` is de-facto
required under the default toggles.

#### Scenario: Optional groups fall back to documented defaults

- **WHEN** a caller supplies only the required inputs (identity,
  versions, nodes, images) together with either a valid `sops_age_key`
  or `deploy_argocd = false`
- **THEN** the plan succeeds with the documented defaults: any substrate
  toggle left unset defaults to enabled, the network CIDRs default to
  the Talos defaults, `talos_install_version` falls back to
  `talos_version`, and the health timeout defaults to `"10m"`

### Requirement: Identity and version input validation

The module SHALL reject at plan time a `cluster_name` that is not a
lowercase RFC-1123 label, a `cluster_endpoint` that is not an `https://`
URL, and any of `talos_version`, `kubernetes_version`, or a non-empty
`talos_install_version` that is not a v-prefixed semantic version.

#### Scenario: Malformed identity input is rejected

- **WHEN** `cluster_name` contains characters outside the lowercase
  RFC-1123 label set, or `cluster_endpoint` lacks the `https://` scheme
- **THEN** variable validation fails with the variable's error message

### Requirement: Topology input validation

The module SHALL reject a node set without at least one controlplane, a
node role outside `controlplane`/`worker`, duplicate node hostnames,
duplicate node IPs, an empty image map, an image architecture outside
`amd64`/`arm64`, and an image `cpu_vendor` outside `intel`/`amd`/`arm`.

#### Scenario: Duplicate hostnames are rejected

- **WHEN** two nodes declare the same hostname
- **THEN** variable validation fails — hostnames key the per-node apply,
  and a duplicate would silently collapse a node out of the apply set

### Requirement: Capability label namespace validation

The module SHALL reject a `hardware_capabilities` entry whose
`emits_label` is outside the `platform.io/hardware-capability.` prefix,
so the reserved `platform.io/hardware-feature.*` Layer-C labels cannot be
emitted through the typed capability path.

#### Scenario: Reserved-namespace label is rejected

- **WHEN** a capability declares an `emits_label` under
  `platform.io/hardware-feature.`
- **THEN** variable validation fails with an error naming the required
  namespace

### Requirement: Network and Cilium input validation

The module SHALL reject an empty `pod_cidr` or `service_cidr` list, a
CIDR entry that is not a valid CIDR, a `cilium_routing_mode` outside
`tunnel`/`native`, a `cilium_encryption.type` outside
`none`/`wireguard`/`ipsec`, and a non-empty `cilium_ipsec_key` that does
not begin with a numeric key id.

#### Scenario: Invalid CIDR entry is rejected

- **WHEN** a `pod_cidr` or `service_cidr` entry is not parseable as a
  CIDR
- **THEN** variable validation fails with the variable's error message

### Requirement: Sensitive credential outputs gated on health

The module SHALL mark `kubeconfig`, `talosconfig` and
`client_configuration` as sensitive outputs; `kubeconfig` and
`talosconfig` SHALL depend on the cluster health gate so a consumer never
receives credentials for a cluster that is not yet reachable, and the
`cluster_health` output SHALL block any consumer that reads it until the
health check has passed.

#### Scenario: Credentials are sensitive and health-gated

- **WHEN** a consumer reads the `kubeconfig` or `talosconfig` output
- **THEN** the value is sensitive-marked (never printed in plan output or
  logs) and is produced only after the cluster health check has passed

### Requirement: Image and upgrade audit outputs

The module SHALL expose `schematic_ids` keyed by content hash,
`installer_images` keyed by node hostname carrying the resolved
non-SecureBoot metal-installer URL (normative: AGENTS.md §Hard
Constraints — No SecureBoot), `node_schematic_hashes`,
`distinct_schematic_count` (known at plan time), and
`talos_install_version` (the effective installer version) for tfplan-JSON
consumption by the consumer's upgrade tooling.

#### Scenario: Upgrade tooling reads the plan outputs

- **WHEN** a consumer inspects the module outputs via tfplan JSON
- **THEN** it can read, per hostname, the resolved installer-image URL
  (containing no `-secureboot` segment) and the effective Talos install
  version

### Requirement: Seed and wiring audit outputs

The module SHALL expose secret-free audit outputs that bind the composed
patch lists to tests: the kubelet serving-cert rotation wiring per role
and the decoded rotation patch content, the cert-approver seed wiring,
namespace labels, RBAC approve scope and per-object recommended-label
gaps, the ArgoCD namespace labels, and a boolean asserting the
non-sensitive base patch list is a prefix of the final controlplane patch
list.

#### Scenario: Audit outputs stay secret-free

- **WHEN** the seed and wiring audit outputs are read
- **THEN** they expose booleans, label maps and decoded patch content
  only — never the seed patch lists that embed Secret material

### Requirement: Version constraints and backend agnosticism

The module SHALL require OpenTofu/Terraform `>= 1.7.0` and constrain its
providers to `siderolabs/talos` `>= 0.7.0, < 1.0.0`, `hashicorp/helm`
`>= 2.12, < 3.0.0` (local template rendering only — no Helm release or
apply), and `hashicorp/local` `>= 2.4` plus `hashicorp/null` `>= 3.2`
(used only for the ArgoCD CRD apply path). The module SHALL declare no
state backend — the backend is the caller's concern and must be
encrypted, because the machine secrets land in state.

#### Scenario: No backend is imposed on the caller

- **WHEN** the module is initialized from any caller root
- **THEN** it declares no backend block and enforces only the version
  constraints above
