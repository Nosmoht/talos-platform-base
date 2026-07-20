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
repository is hardcoded in `main.tf` — together with the always-on
cert-approver seed's three tuning knobs: `cert_approver_provider_regex`
(default `".*"`), `cert_approver_provider_ip_prefixes` (default
`["0.0.0.0/0", "::/0"]`, non-empty), and `cert_approver_replicas` (default
`1`); the seed itself has no disable toggle); cluster network (`pod_cidr`,
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
`talos_install_version` that is not a v-prefixed MAJOR.MINOR.PATCH
version with at most a hyphen- or plus-introduced pre-release/build
suffix (the same anchored pattern as `schemas/cluster.schema.json`;
regex-dialect edge: the schema validator's `$` tolerates one trailing
newline, the module's does not — no plain YAML scalar carries one).

#### Scenario: Malformed identity input is rejected

- **WHEN** `cluster_name` contains characters outside the lowercase
  RFC-1123 label set, or `cluster_endpoint` lacks the `https://` scheme
- **THEN** variable validation fails with the variable's error message

#### Scenario: Version with trailing garbage is rejected

- **WHEN** a version input carries trailing text after the PATCH segment
  that is not a `-`/`+`-introduced suffix
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
list. For the cert-approver seed the module SHALL additionally expose,
parsed from the rendered manifest, `cert_approver_rbac_rules` (the decoded
ClusterRole rule set, for rule-set-closure assertions),
`cert_approver_pod_security_context` (the decoded container securityContext,
for the restricted-PSA guard), `cert_approver_container_args` and
`cert_approver_env` (the decoded arguments and `PROVIDER_*`/`BYPASS_DNS_RESOLUTION`
environment, for the config-injection and leader-election checks), and
`cert_approver_replicas` (the rendered replica count).

#### Scenario: Audit outputs stay secret-free

- **WHEN** the seed and wiring audit outputs are read
- **THEN** they expose booleans, label maps, decoded RBAC rules,
  securityContext, container args, environment and replica count only —
  never the seed patch lists that embed Secret material

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

### Requirement: Image kernel-argument input validation

The module SHALL admit an optional per-image `extra_kernel_args` string list
(default `[]`) on `var.images`, unioned into the node's schematic
`customization.extraKernelArgs` alongside the selected provisioning profiles'
kernel arguments. The module SHALL reject at plan time, via a validation
naming the offending image and element: an element containing whitespace; an
element whose key begins with `-`; an element with an empty key; and any
element whose key is `debugfs`, regardless of its value. This module-level
validation is the enforcement point for every caller, including one wiring
the module interface by hand; the declarative `cluster.yaml` path is guarded
in addition by the `cluster-yaml-sot` capability's schema mirror — the module
validation is not the only enforcement point.

#### Scenario: Whitespace-bearing element is rejected

- **WHEN** an image's `extra_kernel_args` contains an element with whitespace
- **THEN** the plan fails with an error naming the offending image and
  element — a whitespace-joined element would smuggle a second argument past
  the kernel-argument conflict guard, which keys on `=` and never on
  whitespace

#### Scenario: Removal-spelling element is rejected

- **WHEN** an image's `extra_kernel_args` contains an element whose key
  begins with `-`
- **THEN** the plan fails with an error naming the offending image and
  element — the karg removal/prefix spelling is out of scope and the
  conflict guard cannot see it

#### Scenario: Empty-key element is rejected

- **WHEN** an image's `extra_kernel_args` contains the bare empty string, or
  an element beginning with `=` (which keys as the empty string)
- **THEN** the plan fails with an error naming the offending image and
  element

#### Scenario: debugfs-keyed element is rejected regardless of value

- **WHEN** an image's `extra_kernel_args` contains an element whose key is
  `debugfs`, at any value
- **THEN** the plan fails with an error naming the offending image and
  element, and the error text does not contain the AGENTS.md Hard-Constraint
  forbidden value literal

#### Scenario: A well-formed list is accepted

- **WHEN** an image's `extra_kernel_args` contains only elements with a
  non-empty key, no leading `-`, no whitespace, and no `debugfs` key
- **THEN** the plan proceeds past this validation
