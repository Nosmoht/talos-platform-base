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
default `[]`), `cilium_agent_metric_overrides` (a string list, default `[]`,
format-validated — the chart's add/remove delta against its default metric
set, not a replacement for it), `cilium_hubble_open_metrics` (default
`false`, the OpenMetrics exposition format), `cilium_self_management`
(default `false`, guarded by the cross-variable validations below), and
`cilium_self_management_project`
(default `"default"`)); cluster network (`pod_cidr`, `service_cidr`,
`dual_stack`, `allow_scheduling_on_controlplanes`); the machine-config apply mode
(`controlplane_apply_mode` and `worker_apply_mode`, both defaulting to `auto` —
see the `cluster-bootstrap-lifecycle` spec for the behaviour they select); and the
cluster health timeout. Because `deploy_argocd` defaults to true and a plan-time
precondition requires `sops_age_key` to be a valid age private key
whenever ArgoCD is deployed, `sops_age_key` is de-facto required under the
default toggles.

The two metric-set inputs SHALL declare `nullable = false`: the shipped
example shim reads `cluster.yaml` through `try()`, which does not catch a
key written with an empty value, so a bare key would otherwise deliver
`null` into conditions that cannot accept it.

`cilium_gateway_api_crds_url` carries a cross-component version coupling the
module cannot validate at plan time: Cilium's Gateway API support requires a
minimum Gateway API CRD bundle version that changes across Cilium minors, and
the input is an opaque URL that Talos applies verbatim. Its documentation
SHALL therefore state the Gateway-API CRD floor required by the Cilium chart
version currently pinned by `cilium_chart_version`, together with the channel
(standard vs experimental) that satisfies the platform's Gateway-API-only
Hard Constraint — in every copy that documents it, the module README's Inputs
row included. No mechanical gate enforces this: `spec:check-staleness` proves
only that the owning spec was touched, `check-module-readme-parity.sh` checks
row presence and not prose, and no check compares the CRD version literal
against the chart pin. It is therefore a **reviewer-enforced** obligation on
every `cilium_chart_version` bump, and a mechanical coupling remains desirable
and unbuilt.

The two chart-version inputs (`cilium_chart_version`, `argocd_chart_version`)
SHALL declare `nullable = false` alongside their default, which makes the
module's declared default the SINGLE source of truth for the pinned chart
version: a caller MAY pass `null` to mean "take the base's pin", and OpenTofu
substitutes the default. This is a per-input contract, NOT a module-wide
convention — no other input promises null-means-default, and a `null` passed to
an input that does not declare `nullable = false` stays `null` rather than
falling back. The convention exists so a consumer who omits the corresponding
`cluster.yaml` key inherits a base chart bump instead of freezing whatever
literal their copied shim carried: the shipped example shim SHALL therefore pass
`try(local.<component>.chart_version, null)`, and the shipped `cluster.yaml`
examples SHALL leave the key commented out, with a setting explained as a
deliberate pin against the base rather than as the normal case. A consumer that
does set the key keeps full control; the value simply wins over the default as
any other input does.

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

#### Scenario: A null chart version resolves to the module's pinned default

- **WHEN** a caller passes `cilium_chart_version = null` — the example shim's
  behavior when `cluster.yaml` omits `substrate.cilium.chart_version`
- **THEN** the module resolves it to that variable's declared default, and the
  emitted self-management Application's `spec.source.targetRevision` carries a
  chart version rather than `null`

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

### Requirement: Apply-mode input validation

Each apply-mode input SHALL be constrained to the value set supported across the
whole provider range the module declares — not the set the newest provider
accepts — so that neither an unsupported spelling nor a mode newer than a
consumer's in-range provider reaches an apply against a node.

#### Scenario: An out-of-set apply mode is rejected

- **WHEN** either apply-mode input carries a value outside that set — including
  a mode the newest provider accepts but the declared floor does not
- **THEN** the plan fails on that variable's validation, naming the accepted
  values

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
gaps, the ArgoCD namespace labels, the distinct Kubernetes kinds in the
manifest the module applies after the health gate
(`argocd_day0_apply_kinds`, `[]` when `deploy_argocd = false`), a per-node map of the apply mode
the last apply was written with (`node_apply_mode`) — the only in-module
signal that a role sits in a staged window, since the cluster stays healthy
on its previous configuration and the next plan is clean while it does — and a
boolean asserting the non-sensitive base patch list is a prefix of the
final controlplane patch list. For the cert-approver seed the module SHALL
additionally expose,
parsed from the rendered manifest, `cert_approver_rbac_rules` (the decoded
ClusterRole rule set, for rule-set-closure assertions),
`cert_approver_pod_security_context` (the decoded container securityContext,
for the restricted-PSA guard), `cert_approver_container_args` and
`cert_approver_env` (the decoded arguments and `PROVIDER_*`/`BYPASS_DNS_RESOLUTION`
environment, for the config-injection and leader-election checks), and
`cert_approver_replicas` (the rendered replica count). For the Cilium seed
the module SHALL additionally expose `cilium_seed_observability_markers`
— booleans (`agent_metrics`, `agent_metric_overrides`, `operator_metrics`,
`hubble`, `hubble_metrics`, `hubble_open_metrics`) decoded from the frozen
seed render's `cilium-config` ConfigMap, `{}` when `deploy_cilium = false` —
for tests binding the seed render to the observability inputs without
re-rendering the chart.

Because a marker's value must discriminate the input it reports, a marker
SHALL test the rendered key's VALUE where the chart emits that key
unconditionally, and its presence only where the chart gates emission on the
input. The output's documentation SHALL name any marker that fails to
discriminate at the render layer.

The markers describe the SEED, not the running cluster. On a cluster that has
adopted the emitted self-management Application the frozen seed may lag what
is actually reconciled, so the output's documentation SHALL state that scope
rather than leaving it to be inferred.

#### Scenario: Audit outputs stay secret-free

- **WHEN** the seed and wiring audit outputs are read
- **THEN** they expose booleans, label maps, decoded RBAC rules,
  securityContext, container args, environment, replica count and kind
  names only — never the seed patch lists that embed Secret material

#### Scenario: Day-0 apply kinds reflect the CRD-only projection

- **WHEN** `deploy_argocd = true`
- **THEN** `argocd_day0_apply_kinds` is exactly
  `["CustomResourceDefinition"]`, and it is `[]` when `deploy_argocd` is
  false

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

### Requirement: Inert typed inputs warn rather than reject

An input whose only failure mode is having no effect SHALL be reported by a
plan-time `check` block, not by a variable `validation`. The module reserves
hard rejection for inputs whose misuse causes silent BREAKAGE — a dropped
datapath override, a fatally-exiting workload, an emitted resource with
nothing to reconcile — and an input that merely does nothing is a lower tier.

Each such check SHALL model the input's FULL effectiveness condition, not the
one that reads as obvious. That includes the substrate-delivery toggle (with the
component undelivered there is neither a seed nor an emitted resource, so every
one of its inputs is inert) and any downstream chart gate the module can observe
— a condition that reports an inert input as effective is worse than no check,
because it converts a silent no-op into an endorsed one. Where the effectiveness
condition rests on a rendered-chart fact, that fact SHALL be measured against
the pinned chart and recorded at the condition.

The distinction is load-bearing rather than stylistic: a prerequisite may be
satisfied through `cilium_values_override`, an opaque string the module cannot
introspect, so a hard rejection would refuse a configuration that works. The
warning tier lets that consumer proceed while still surfacing the far more
common case, where the prerequisite really is missing.

Each such check SHALL be its own block. `expect_failures` matches the checkable
object, so merging two conditions collapses both test legs onto one predicate
and leaves either half untested — the same isolation obligation the module's
cross-variable validations carry.

#### Scenario: An inert input warns and still plans

- **WHEN** a metric-set input is set while the toggle that makes it effective
  is off
- **THEN** the plan succeeds and reports a warning naming that input and its
  missing prerequisite, rather than failing

#### Scenario: Each check is independently bound

- **WHEN** one such check block is removed
- **THEN** exactly one test leg reports a missing expected failure and every
  other leg stays green

### Requirement: Free-form values reaching the machine config are format-validated

A typed input whose value is rendered verbatim into a resource that becomes
part of the controlplane machine configuration SHALL constrain its accepted
character set by variable `validation`, and the module's test suite SHALL
carry a rejection leg per corruption vector plus a negative-space control
proving the documented form is still accepted. The obligation is on the input
CLASS, not on individual inputs: every sibling reaching the same rendered
document carries it, or the guard documents a boundary it does not hold.

The rule's FORM follows the value space, in three shapes. Where the documented
form is a narrow token, an allowlist is correct. Where legitimate values carry
structured punctuation — Hubble's context syntax uses colons, semicolons and
equals signs — an allowlist would encode a grammar the module does not own and
would break on the next upstream option; there the rule SHALL instead exclude
the measured corruption vectors, and the negative-space control SHALL exercise
the documented structured form so a later copy-paste of the wrong guard shape
fails loudly. Where the value space is a COMPUTABLE TYPE, the rule SHALL be a
semantic predicate over that type rather than a lexical rule: it admits exactly
the shape the input is for, so it rejects every corruption vector without
enumerating one, and the test suite SHALL carry a leg that a lexical guard
would pass so the distinction cannot silently degrade.

The schema SHALL mirror each such guard so the declarative path rejects a
corrupting entry at lint time, and the mirror SHALL account for regex-engine
divergence between the two validators rather than copying the expression
verbatim. Where the module's guard is a semantic predicate the mirror SHALL
constrain the value's SHAPE only, leaving the precise verdict to the module.

Three inputs are in the class, all reaching the `cilium-config` ConfigMap that
the module bakes into a create-only `inlineManifest`. The Cilium agent
metric-delta list and the Hubble metric list are rendered raw and unquoted as
list entries: an entry containing a newline with matching indentation escapes
the surrounding scalar and injects arbitrary ConfigMap keys; an entry
containing a document separator splits the rendered manifest and blanks the
seed-marker output that parses it. The native-routing CIDR is rendered raw as a
scalar value and carries the same newline vector.

#### Scenario: A corrupting entry is rejected at plan time

- **WHEN** an entry contains an embedded newline, a document separator, or
  omits the required add/remove prefix
- **THEN** the plan fails at the variable, naming the offending value

#### Scenario: The documented form is not rejected

- **WHEN** every entry is a well-formed add or remove of a metric name
- **THEN** the plan succeeds and the list reaches the computed values layer
  intact

#### Scenario: A malformed native-routing CIDR is rejected at plan time

- **WHEN** the native-routing CIDR is neither empty nor a well-formed CIDR —
  whether because it carries an embedded newline or because it is an address
  with no prefix length, which a lexical guard would accept
- **THEN** the plan fails at the variable

#### Scenario: Both documented native-routing forms are accepted

- **WHEN** the native-routing CIDR is a well-formed CIDR, or is empty
- **THEN** the plan succeeds, and the empty form keeps deriving the value from
  the first IPv4 pod CIDR entry

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

### Requirement: Operator replica count input and provenance output

The module SHALL accept an optional Cilium operator replica count and SHALL
reject a value that is not an integer of at least 1, or that exceeds the number
of declared nodes. The over-count rejection sits on the REJECT side of the
inert-input tier rule rather than the warn side, on three grounds: the declared
node set is not an estimate of the environment but the cluster the module
builds, so the predicate is decidable from the module's own state; the operator's
`podAntiAffinity` is `requiredDuringScheduling` on `kubernetes.io/hostname`, so
the surplus can never place; and the value is baked into a create-only
`inlineManifest`, so the bootstrap that carries it cannot be corrected by a later
apply. Each conjunct SHALL be its own validation block, per the guard-isolation
obligation the module's other cross-variable validations carry.

The module SHALL additionally expose a secret-free plan-time output reporting
the resolved count together with the mechanism that produced it — the explicit
pin, the node-count derivation, or the shipped floor — so an operator debugging
a live Deployment can attribute the number without reading module internals.
This is a different kind of audit surface from the seed markers: those report
what was baked in, this reports which rule decided it.

#### Scenario: A replica count below one or fractional is rejected

- **WHEN** the operator replica count is set to 0, or to a fractional value
- **THEN** variable validation fails, with each conjunct bound by its own
  rejected shape so neither can be relaxed while the other still fails

#### Scenario: A replica count above the declared node count is rejected

- **WHEN** the operator replica count exceeds the number of declared nodes
- **THEN** variable validation fails — rejection rather than a warning,
  because the surplus can never place and the value reaches a create-only
  seed

#### Scenario: A count that cannot reach an operator warns

- **WHEN** the operator replica count is set with Cilium delivery off
- **THEN** the plan succeeds and reports a warning: the input is inert
  rather than wrong, which is the lower tier

#### Scenario: The resolved count reports its origin

- **WHEN** the module plans with Cilium delivered
- **THEN** the audit output carries the resolved count together with one of
  the three origins — pin, node-count derivation, or floor — and its shape
  and value types do not vary with the delivery toggle
