---
sources:
  primary:
    - tofu/modules/talos-cluster/variables.tf
    - tofu/modules/talos-cluster/outputs.tf
    - tofu/modules/talos-cluster/versions.tf
    - tofu/modules/talos-cluster/nodes.tf
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

`nodes.tf` is part of that typed surface rather than of the runtime flow:
it is provider-less, pure `var.nodes`-derived, and holds the node
identity model — the keyed views that make the two node identifiers
structurally unique, and the name-ordered projections the Talos
arguments in `main.tf` consume.

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
`1`); the seed itself has no disable toggle; and the Cilium observability +
self-management group: `cilium_agent_metrics`, `cilium_operator_metrics`
(independent Prometheus toggles, default `false`), `cilium_hubble_enabled`
(default `false`; forces the observer-API server TLS off in the computed
values — metrics-only scope), `cilium_hubble_metrics` (a string list,
default `[]`), `cilium_self_management` (default `false`, guarded by the
cross-variable validations below), and `cilium_self_management_project`
(default `"default"`)); cluster network (`pod_cidr`, `service_cidr`,
`dual_stack`, `allow_scheduling_on_controlplanes`); and the cluster health
timeout. Because `deploy_argocd` defaults to true and a plan-time
precondition requires `sops_age_key` to be a valid age private key
whenever ArgoCD is deployed, `sops_age_key` is de-facto required under the
default toggles.

`cilium_gateway_api_crds_url` carries a cross-component version coupling the
module cannot validate at plan time: Cilium's Gateway API support requires a
minimum Gateway API CRD bundle version that changes across Cilium minors, and
the input is an opaque URL that Talos applies verbatim. Its documentation
SHALL therefore state the Gateway-API CRD floor required by the Cilium chart
version currently pinned by `cilium_chart_version`, together with the channel
(standard vs experimental) that satisfies the platform's Gateway-API-only
Hard Constraint — so a `cilium_chart_version` bump cannot leave the documented
CRD floor silently stale.

#### Scenario: Optional groups fall back to documented defaults

- **WHEN** a caller supplies only the required inputs (identity,
  versions, nodes, images) together with either a valid `sops_age_key`
  or `deploy_argocd = false`
- **THEN** the plan succeeds with the documented defaults: any substrate
  toggle left unset defaults to enabled, the network CIDRs default to
  the Talos defaults, `talos_install_version` falls back to
  `talos_version`, the health timeout defaults to `"10m"`, and the
  Cilium observability + self-management group defaults to all-off /
  empty

#### Scenario: Gateway API CRD floor tracks the pinned Cilium chart

- **WHEN** the `cilium_gateway_api_crds_url` input documentation is read at
  any pinned `cilium_chart_version`
- **THEN** it names the minimum Gateway API bundle version that pinned Cilium
  version requires, and states which channel to seed — including when the
  experimental channel is required instead of standard

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

### Requirement: Node identity

`nodes` SHALL be a map keyed by node name. The key SHALL be the node's Talos
hostname, its Kubernetes node name, and the key of the per-node apply resource,
and SHALL NOT additionally exist as a field of the node object — a node is
declared exactly once, in exactly one place, and a duplicate node name is not
expressible.

Every Talos-facing list the module emits SHALL be a projection of that map,
ordered by node name, so declaration order is not observable in any emitted
value.

#### Scenario: Declaration order is not observable

- **WHEN** the same node set is declared in a different order
- **THEN** `cluster_health.{control_plane_nodes, worker_nodes, endpoints}`, the
  talosconfig `endpoints`/`nodes` and `output.controlplane_ips` are
  byte-identical, and the bootstrap target is unchanged

### Requirement: Topology input validation

The module SHALL reject a node set without at least one controlplane, an EVEN
number of controlplanes, a node role outside `controlplane`/`worker`, duplicate
node IPs, a node key that is not already a canonical Kubernetes node name, two
node keys sharing a first label, a dotted node key while `register_with_fqdn` is
false, an empty image map, an image architecture outside `amd64`/`arm64`, and an
image `cpu_vendor` outside `intel`/`amd`/`arm`.

#### Scenario: An even controlplane count is rejected

- **WHEN** the node set declares 2 or 4 controlplanes
- **THEN** variable validation fails — an even count tolerates no more etcd
  failures than the odd count below it, while adding a member that can break
  quorum

#### Scenario: A non-canonical node key is rejected

- **WHEN** a node key carries uppercase, an underscore, a leading or trailing
  `-`/`.`, or a label longer than 63 characters
- **THEN** variable validation fails — Talos validates hostname LENGTH only and
  silently rewrites the rest on the way to Kubernetes, so the node would arrive
  under a different name than the one declared, and two distinct keys could
  collapse onto one Kubernetes node

#### Scenario: Colliding first labels are rejected

- **WHEN** two node keys share their first label (e.g.
  `node-a.site1.example.org` and `node-a.site2.example.org`)
- **THEN** variable validation fails regardless of `register_with_fqdn` — Talos
  splits the hostname at the first dot, so both machines would carry the same OS
  hostname

#### Scenario: A dotted node key without FQDN registration is rejected

- **WHEN** a node key contains a dot while `register_with_fqdn` is false
- **THEN** variable validation fails — Kubernetes would only ever see the first
  label, silently dropping the domain part from the cluster's identity

#### Scenario: Duplicate node IPs are rejected

- **WHEN** two nodes declare the same IP
- **THEN** variable validation fails with an error naming the rule; the module's
  IP-keyed view is the structural backstop that fails the plan even if that
  validation is removed

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
`cert_approver_replicas` (the rendered replica count). For the Cilium seed
the module SHALL additionally expose `cilium_seed_observability_markers`
— booleans (`agent_metrics`, `operator_metrics`, `hubble`, `hubble_metrics`)
decoded from the frozen seed render's `cilium-config` ConfigMap, `{}` when
`deploy_cilium = false` — for tests binding the seed render to the
observability inputs without re-rendering the chart.

#### Scenario: Audit outputs stay secret-free

- **WHEN** the seed and wiring audit outputs are read
- **THEN** they expose booleans, label maps, decoded RBAC rules,
  securityContext, container args, environment and replica count only —
  never the seed patch lists that embed Secret material

#### Scenario: Cilium observability markers reflect the seed render

- **WHEN** `deploy_cilium = true` and the Cilium observability inputs are
  set
- **THEN** `cilium_seed_observability_markers` decodes booleans from the
  frozen seed's `cilium-config` ConfigMap matching those inputs, without a
  second chart render

### Requirement: Version constraints and backend agnosticism

The module SHALL require OpenTofu/Terraform `>= 1.9.0` and constrain its
providers to `siderolabs/talos` `>= 0.7.0, < 1.0.0`, `hashicorp/helm`
`>= 2.12, < 3.0.0` (local template rendering only — no Helm release or
apply), and `hashicorp/local` `>= 2.4` plus `hashicorp/null` `>= 3.2`
(used only for the ArgoCD CRD apply path). The `>= 1.9.0` floor (raised
from `>= 1.7.0`) is required because the `cilium_self_management` guard
validations below reference OTHER variables in their `condition` — a
cross-variable `validation` feature OpenTofu introduced at 1.9 — and is
parsed at module load regardless of any toggle's value, so it is a
permanent, consumer-visible compatibility floor for one opt-in,
default-off feature. The module SHALL declare no state backend — the
backend is the caller's concern and must be encrypted, because the
machine secrets land in state.

#### Scenario: No backend is imposed on the caller

- **WHEN** the module is initialized from any caller root
- **THEN** it declares no backend block and enforces only the version
  constraints above

#### Scenario: A pre-1.9 caller cannot load the module

- **WHEN** a caller initializes the module with OpenTofu/Terraform
  `< 1.9.0`
- **THEN** module load fails on the `required_version` constraint,
  regardless of whether `cilium_self_management` is set

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

### Requirement: Cilium self-management guard validations

The module SHALL reject at plan time, via two separate cross-variable
`validation` blocks on `cilium_self_management`: (1) enabling it while
`deploy_argocd` is false or `deploy_cilium` is false — self-management
hands the Day-2 config off from the module-delivered Cilium seed to the
consumer's ArgoCD, so both must be present; and (2) enabling it while
`cilium_values_override` is non-empty — the emitted Application's
`valuesObject` does not inherit `cilium_values_override` (see
`cilium-cni-delivery`), so a seed-active datapath override would be
silently dropped on ArgoCD adoption. The two guards SHALL remain separate
`validation` blocks (not combined into one `condition`) so each is
independently exercisable by a dedicated `expect_failures` test leg.

#### Scenario: Self-management without ArgoCD or Cilium is rejected

- **WHEN** `cilium_self_management = true` and either `deploy_argocd` or
  `deploy_cilium` is `false`
- **THEN** variable validation fails with an error naming the missing
  prerequisite

#### Scenario: Self-management with an active override is rejected

- **WHEN** `cilium_self_management = true` and `cilium_values_override`
  is non-empty
- **THEN** variable validation fails with an error directing the caller
  to migrate the override into their own Cilium Application and empty
  `cilium_values_override` before enabling self-management

### Requirement: Opt-in Cilium self-management output

The module SHALL expose `cilium_self_management_app` — a YAML-encoded
`argoproj.io/v1alpha1` `Application` manifest string — as `""` when
`cilium_self_management = false` (the default), and as the rendered
Application when `true`, with a `precondition` rejecting an unexpectedly
empty render while the toggle is on. The module SHALL NOT apply this
manifest itself — it is an output only, for the consumer's own GitOps to
commit and reconcile.

#### Scenario: Output is empty by default

- **WHEN** `cilium_self_management` is left at its default (`false`)
- **THEN** `cilium_self_management_app` is the empty string

#### Scenario: Output never renders empty while the toggle is on

- **WHEN** `cilium_self_management = true`
- **THEN** `cilium_self_management_app` is non-empty, or the plan fails on
  the output's precondition rather than emitting a hollow Application
