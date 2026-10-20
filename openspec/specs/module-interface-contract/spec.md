---
sources:
  primary:
    - tofu/modules/talos-cluster/variables.tf
    - tofu/modules/talos-cluster/outputs.tf
    - tofu/modules/talos-cluster/versions.tf
    - tofu/modules/talos-cluster/nodes.tf
references:
  - knowledge/decisions/0029-public-api-and-major-rule.md
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
arguments in the module implementation consume.

## Requirements

### Requirement: Grouped typed input surface

The module SHALL expose its inputs as typed variable groups: cluster
identity (`cluster_name`, `cluster_endpoint`); versions; topology (`nodes`,
`images`, `hardware_capabilities`); machine-config patches (all-nodes,
per-role and per-node lists); substrate delivery; the Cilium observability +
self-management group; cluster network; the machine-config apply mode; and the
cluster health timeout. Each group's members are stated by the requirements
that follow.

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

### Requirement: Version input group

The version group SHALL consist of `talos_version`, the machine-config schema
pin fixed at bootstrap; `talos_install_version`, the installer pin, defaulting
to the schema pin; and `kubernetes_version`.

#### Scenario: The installer pin defaults to the schema pin

- **WHEN** a caller sets `talos_version` and leaves `talos_install_version`
  unset
- **THEN** the effective installer version is `talos_version`

### Requirement: Substrate delivery input group

The substrate delivery group SHALL carry the ArgoCD and Cilium toggles with
their chart-version, namespace, values-override and secret-material knobs,
plus a chart-repository knob for Cilium only; the ArgoCD chart repository is
hardcoded in `argocd-seed.tf`.

#### Scenario: Only Cilium exposes a chart repository input

- **WHEN** a caller looks for a chart-repository input
- **THEN** one exists for Cilium, and none exists for ArgoCD, whose chart
  repository is the one hardcoded in `argocd-seed.tf`

### Requirement: Cert-approver seed tuning inputs

The substrate delivery group SHALL carry the always-on cert-approver seed's
three tuning knobs: `cert_approver_provider_regex` (default `".*"`),
`cert_approver_provider_ip_prefixes` (default `["0.0.0.0/0", "::/0"]`,
non-empty), and `cert_approver_replicas` (default `1`). The seed itself SHALL
have no disable toggle.

#### Scenario: The cert-approver seed cannot be switched off

- **WHEN** a caller supplies none of the three cert-approver knobs
- **THEN** the seed is delivered with the documented defaults, and no input
  exists that disables it

### Requirement: Cilium observability inputs

The module SHALL accept `cilium_agent_metrics` and `cilium_operator_metrics`
as independent Prometheus toggles, `cilium_hubble_enabled`, and
`cilium_hubble_open_metrics` (the OpenMetrics exposition format), each
defaulting to `false`, and `cilium_hubble_metrics` and
`cilium_agent_metric_overrides` as string lists defaulting to `[]`.

#### Scenario: Hubble enablement is metrics-only

- **WHEN** `cilium_hubble_enabled = true`
- **THEN** the computed values force the observer-API server TLS off — the
  scope is metrics-only

#### Scenario: Metric overrides are a delta

- **WHEN** `cilium_agent_metric_overrides` is set
- **THEN** it is format-validated and applied as the chart's add/remove delta
  against its default metric set, not as a replacement for it

### Requirement: Cilium self-management inputs

The module SHALL accept `cilium_self_management` (default `false`, guarded by
the cross-variable validations of the Cilium self-management guard
requirement below) and `cilium_self_management_project` (default
`"default"`).

#### Scenario: Self-management defaults to off

- **WHEN** neither self-management input is set
- **THEN** `cilium_self_management` is `false` and
  `cilium_self_management_project` is `"default"`

### Requirement: Cluster network and apply-mode inputs

The cluster network group SHALL consist of `pod_cidr`, `service_cidr`,
`dual_stack` and `allow_scheduling_on_controlplanes`; the apply-mode group of
`controlplane_apply_mode` and `worker_apply_mode`, both defaulting to `auto` —
see the `cluster-bootstrap-lifecycle` spec for the behaviour they select.

#### Scenario: Apply modes default to auto

- **WHEN** neither apply-mode input is set
- **THEN** both `controlplane_apply_mode` and `worker_apply_mode` are `auto`

### Requirement: SOPS age key under the default toggles

A plan-time precondition SHALL require `sops_age_key` to be a valid age
private key whenever ArgoCD is deployed. Because `deploy_argocd` defaults to
true, `sops_age_key` is de-facto required under the default toggles.

#### Scenario: Default toggles without a valid age key fail

- **WHEN** `deploy_argocd` is left at its default and `sops_age_key` is not a
  valid age private key
- **THEN** the plan fails on the precondition

### Requirement: Non-nullable metric-set inputs

The two metric-set inputs (`cilium_hubble_metrics`,
`cilium_agent_metric_overrides`) SHALL declare `nullable = false`: the shipped
example shim reads `cluster.yaml` through `try()`, which does not catch a key
written with an empty value, so a bare key would otherwise deliver `null` into
conditions that cannot accept it.

#### Scenario: A bare metric-set key does not deliver null

- **WHEN** `cluster.yaml` carries a metric-set key written with an empty value
  and is read through the shipped example shim
- **THEN** the module's conditions never receive `null` for that input

### Requirement: Gateway API CRD floor documentation

The documentation of `cilium_gateway_api_crds_url`, an opaque URL Talos
applies verbatim, SHALL state the Gateway-API CRD floor required by the Cilium
chart version pinned by `cilium_chart_version`, and the channel (standard vs
experimental) that satisfies the Gateway-API-only Hard Constraint — in every
copy that documents it, the module README's Inputs row included.

#### Scenario: Every documented copy carries the floor

- **WHEN** the module README's Inputs row for `cilium_gateway_api_crds_url` is
  read
- **THEN** it states the same CRD floor and channel as the variable's own
  documentation

### Requirement: Gateway API CRD floor is reviewer-enforced

Every `cilium_chart_version` bump SHALL be reviewed for the Gateway API CRD
floor, because the module cannot validate the coupling at plan time and no
mechanical gate enforces it: `spec:check-staleness` proves only that the
owning spec was touched, `check-module-readme-parity.sh` checks row presence
and not prose, and no check compares the CRD version literal against the chart pin.

#### Scenario: A chart bump with a stale CRD floor passes the gates

- **WHEN** `cilium_chart_version` is bumped to a Cilium minor that requires a
  newer Gateway API CRD bundle and the documented floor is not updated
- **THEN** no mechanical check fails, so only review catches it — a mechanical
  coupling remains desirable and unbuilt

### Requirement: Null-means-default chart-version inputs

`cilium_chart_version` and `argocd_chart_version` SHALL declare
`nullable = false` alongside their default, making the declared default the
single source of truth for the pinned chart version: a caller MAY pass `null`
to mean "take the base's pin", and OpenTofu substitutes the default. This is a
per-input contract, NOT a module-wide convention.

#### Scenario: Null on another input stays null

- **WHEN** a caller passes `null` to an input that does not declare
  `nullable = false`
- **THEN** the value stays `null` rather than falling back to the default — no
  other input promises null-means-default

### Requirement: Shipped examples inherit the chart pin

The shipped example shim SHALL pass
`try(local.<component>.chart_version, null)`, and the shipped `cluster.yaml`
examples SHALL leave the chart-version key commented out, with a setting
explained as a deliberate pin against the base rather than as the normal case.

#### Scenario: Omitting the key inherits a base chart bump

- **WHEN** a consumer using the shipped shim omits the chart-version key from
  `cluster.yaml`
- **THEN** a base chart bump reaches it instead of a literal frozen in its
  copied shim
- **AND** a consumer that does set the key keeps full control: the value wins
  over the default as any other input does

### Requirement: Identity and version input validation

The module SHALL reject at plan time a `cluster_name` that is not a
lowercase RFC-1123 label, a `cluster_endpoint` that is not an `https://`
URL, and any of `talos_version`, `kubernetes_version`, or a non-empty
`talos_install_version` that is not a v-prefixed MAJOR.MINOR.PATCH
version with at most a hyphen- or plus-introduced pre-release/build
suffix (the same anchored pattern as `schemas/cluster.schema.json`).

#### Scenario: Malformed identity input is rejected

- **WHEN** `cluster_name` contains characters outside the lowercase
  RFC-1123 label set, or `cluster_endpoint` lacks the `https://` scheme
- **THEN** variable validation fails with the variable's error message

#### Scenario: Version with trailing garbage is rejected

- **WHEN** a version input carries trailing text after the PATCH segment
  that is not a `-`/`+`-introduced suffix
- **THEN** variable validation fails with the variable's error message

#### Scenario: A version with one trailing newline diverges by regex dialect

- **WHEN** a version input ends in exactly one trailing newline
- **THEN** the module's validation rejects it, while the schema validator's
  `$` tolerates it — no plain YAML scalar carries one

### Requirement: Apply-mode input validation

Each apply-mode input SHALL be constrained to the four values the provider has
carried since 0.7.0 — `auto`, `reboot`, `no-reboot`, `staged` — so that no
spelling reaches an apply against a node that the node or the provider does not
act on as written. `staged_if_needing_reboot` SHALL stay outside that set even
though the pinned provider offers it: the provider gates the mode on its bundled
Talos SDK and resolves it to `auto` on Talos 1.14+, which is the version line the
pin exists to reach.

#### Scenario: An out-of-set apply mode is rejected

- **WHEN** either apply-mode input carries a value outside that set — including
  `staged_if_needing_reboot`, which the pinned provider accepts but degrades
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

#### Scenario: An override naming a joint key is rejected

- **WHEN** `cilium_values_override` names `kubeProxyReplacement`,
  `k8sServiceHost` or `k8sServicePort` at its top level
- **THEN** variable validation fails with an error naming the typed input
  that sets both halves, and a key that merely resembles one of the three is
  NOT rejected

#### Scenario: An override that is not a mapping is rejected

- **WHEN** `cilium_values_override` is non-empty and decodes to null or to a
  sequence
- **THEN** variable validation fails on the input rather than on the emitted
  artifact

#### Scenario: A repo URL that is not a resolvable git remote is rejected

- **WHEN** `cilium_self_management_values_source.repo_url` is not one of the git
  remote forms Argo CD resolves (`https://`, `ssh://user@host[:port]/path`,
  `git@host:path`), or carries an embedded PASSWORD — an SSH username is the
  documented form and stays accepted
- **THEN** the plan is rejected — the value becomes `spec.sources[0].repoURL`
  verbatim and decides where a privileged DaemonSet's Helm values are fetched
  from, and a credential there would be committed to git

#### Scenario: One path for both values layers is rejected

- **WHEN** `values_path` and `override_path` name the same file, in the same or
  in an equivalent spelling
- **THEN** the plan is rejected: the two are ordered layers of one Helm merge,
  and the prescribed `local_file` write would overwrite the consumer's override
  with the module-set layer while every other guard — the emptied-override
  warning and the values-digest pair included — stays green

#### Scenario: A malformed API-server endpoint is rejected

- **WHEN** `cilium_k8s_service_host` carries a scheme, an embedded port or a
  newline, or `cilium_k8s_service_port` is non-numeric or out of range
- **THEN** variable validation fails, because the value is rendered raw into
  a ConfigMap baked into a create-only machine configuration

### Requirement: Cilium values override decodes to a mapping

`cilium_values_override` SHALL be rejected when it is non-empty and does not
decode to a YAML MAPPING — a comment-only document decodes to null and a
list-rooted one to a sequence, and either would reach a Helm values slot as a
non-object.

#### Scenario: A comment-only override is rejected

- **WHEN** `cilium_values_override` is non-empty but holds only comments
- **THEN** variable validation fails, because the document decodes to null

### Requirement: Cilium values override joint keys

`cilium_values_override` SHALL be rejected when its top-level key set names
`kubeProxyReplacement`, `k8sServiceHost` or `k8sServicePort`, and the
rejection SHALL name the typed inputs that set both halves together —
`cilium_kube_proxy_replacement`, `cilium_k8s_service_host`,
`cilium_k8s_service_port` — which is what makes it cost no capability.

#### Scenario: Setting one half of a joint key is refused

- **WHEN** `cilium_values_override` sets one of the three joint keys
- **THEN** variable validation fails, because the module writes the
  counterpart into the Talos machine config (`cluster.proxy.disabled`) or
  depends on the key to reach the API server before the CNI is up, and one
  half alone yields a cluster with no ClusterIP datapath and no cluster DNS

### Requirement: The joint-key guard is not a boundary

The joint-key rejection is a footgun guard and SHALL NOT be documented as a
boundary: the chart's own `extraConfig` passthrough and a caller
`config_patches` entry both reach the same state around it.

#### Scenario: The guard's documentation names its bypasses

- **WHEN** the joint-key guard is documented
- **THEN** it is described as a footgun guard, never as a boundary that keeps
  `extraConfig` or `config_patches` from reaching the same state

### Requirement: Cilium values override is sensitive

`cilium_values_override` SHALL be marked `sensitive`, because Cilium values
legitimately carry key material (IPsec keys, Hubble and clustermesh TLS, BGP
peer passwords) and the string reaches the machine configuration. The
consequence SHALL be documented rather than mitigated.

#### Scenario: An override change is invisible in plan output

- **WHEN** `cilium_values_override` changes between plans
- **THEN** `tofu plan` does not show the override's diff, so a
  datapath-relevant change to it is invisible in plan output, and the module
  documents that consequence

### Requirement: Values derived from the sensitive override

Values DERIVED from `cilium_values_override` that carry no part of it MAY be
declassified so the secret-free outputs stay exportable; the override's
CONTENT SHALL NOT be.

#### Scenario: The emptiness boolean may be declassified

- **WHEN** the module derives the boolean "is the override empty", which
  decides the emitted Application's shape and is already observable in that
  manifest
- **THEN** that boolean MAY be non-sensitive, while no output exposes any part
  of the override's content

### Requirement: API-server endpoint input validation

`cilium_k8s_service_host` SHALL be constrained to a bare DNS name or IPv4
literal, or an UNBRACKETED IPv6 literal in CANONICAL form — no scheme, no
`:port`, no whitespace, no brackets — and `cilium_k8s_service_port` to a
decimal port in 1-65535, each conjunct in its OWN validation block so a test
binding one cannot pass on the other's rejection.

#### Scenario: A bracketed or ported host is rejected

- **WHEN** `cilium_k8s_service_host` carries brackets, whitespace or a `:port`
- **THEN** variable validation fails

### Requirement: IPv6 API-server host is decided by a parse

The IPv6 half of the `cilium_k8s_service_host` guard SHALL be decided by a
parse rather than a character class, with normalization part of that decision,
as it already is for `var.nodes`.

#### Scenario: A look-alike or non-canonical IPv6 host is rejected

- **WHEN** `cilium_k8s_service_host` merely looks like an IPv6 literal
  ("1:2:3", a nine-group string), or is a non-canonical or IPv4-embedded
  spelling
- **THEN** variable validation fails

### Requirement: API-server endpoint guards are well-formedness guards

The `cilium_k8s_service_host` and `cilium_k8s_service_port` guards SHALL be
treated as well-formedness rather than injection closure: the measured sink is
not the one the raw-render class rule below covers — chart 1.20.3 renders both
into the containers' `KUBERNETES_SERVICE_HOST` / `_PORT` env vars, QUOTED, so
neither can inject a sibling key.

#### Scenario: A malformed endpoint would deadlock bootstrap

- **WHEN** a malformed endpoint reaches the seed path
- **THEN** the render is frozen into a create-only machine configuration, so
  it is a bootstrap deadlock no later apply repairs — which is why the plan
  rejects it

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
gaps, and the ArgoCD namespace labels.

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

### Requirement: Day-0 apply and patch-order audit outputs

The module SHALL expose `argocd_day0_apply_kinds`, the distinct Kubernetes
kinds in the manifest the module applies after the health gate (`[]` when
`deploy_argocd = false`), and a boolean asserting the non-sensitive base patch
list is a prefix of the final controlplane patch list.

#### Scenario: The base patch list stays a prefix

- **WHEN** the controlplane patch list is composed
- **THEN** the boolean output reports whether the non-sensitive base patch
  list is a prefix of the final controlplane patch list

### Requirement: Per-node apply-mode audit output

The module SHALL expose `node_apply_mode`, a per-node map of the apply mode
the last apply was written with — the only in-module signal that a role sits
in a staged window.

#### Scenario: A staged window is visible only through the output

- **WHEN** a role's nodes were last applied with the `staged` mode
- **THEN** `node_apply_mode` reports that mode for each of those nodes, while
  the cluster stays healthy on its previous configuration and the next plan
  is clean

### Requirement: Cert-approver seed audit outputs

For the cert-approver seed the module SHALL expose, parsed from the rendered
manifest, `cert_approver_rbac_rules` (the decoded ClusterRole rule set),
`cert_approver_pod_security_context` (the decoded container securityContext),
`cert_approver_container_args` and `cert_approver_env` (the decoded arguments
and `PROVIDER_*`/`BYPASS_DNS_RESOLUTION` environment), and
`cert_approver_replicas` (the rendered replica count).

#### Scenario: Cert-approver outputs feed the seed guards

- **WHEN** the seed's tests read the cert-approver audit outputs
- **THEN** the rule set serves rule-set-closure assertions, the
  securityContext the restricted-PSA guard, and the arguments and environment
  the config-injection and leader-election checks

### Requirement: Cilium seed observability markers output

For the Cilium seed the module SHALL expose
`cilium_seed_observability_markers` — booleans (`agent_metrics`,
`agent_metric_overrides`, `operator_metrics`, `hubble`, `hubble_metrics`,
`hubble_open_metrics`) decoded from the frozen seed render's `cilium-config`
ConfigMap, `{}` when `deploy_cilium = false` — for tests binding the seed
render to the observability inputs without re-rendering the chart.

#### Scenario: No markers without Cilium delivery

- **WHEN** `deploy_cilium = false`
- **THEN** `cilium_seed_observability_markers` is `{}`

### Requirement: Observability markers discriminate their input

A marker SHALL test the rendered key's VALUE where the chart emits that key
unconditionally, and its presence only where the chart gates emission on the
input, because a marker's value must discriminate the input it reports. The
output's documentation SHALL name any marker that fails to discriminate at the
render layer.

#### Scenario: An unconditionally emitted key is tested by value

- **WHEN** the chart emits a marker's key regardless of the input
- **THEN** the marker reads the key's value, not its presence

### Requirement: Observability markers describe the seed

The markers describe the SEED, not the running cluster, and the output's
documentation SHALL state that scope rather than leaving it to be inferred.

#### Scenario: An adopted cluster may differ from the markers

- **WHEN** a cluster has adopted the emitted self-management Application
- **THEN** the frozen seed the markers describe may lag what is actually
  reconciled

### Requirement: Version constraints and backend agnosticism

The module SHALL require OpenTofu/Terraform `>= 1.9.0` and constrain its
providers to `siderolabs/talos` `>= 0.12.0, < 0.13.0-0`, `hashicorp/helm`
`>= 2.12, < 4.0.0` (local template rendering only — no Helm release or
apply), and `hashicorp/local` `>= 2.4` plus `hashicorp/null` `>= 3.2` (used
only for the ArgoCD CRD apply path), and SHALL declare no state backend.

#### Scenario: No backend is imposed on the caller

- **WHEN** the module is initialized from any caller root
- **THEN** it declares no backend block and enforces only the version
  constraints above

#### Scenario: A pre-1.9 caller cannot load the module

- **WHEN** a caller initializes the module with OpenTofu/Terraform
  `< 1.9.0`
- **THEN** module load fails on the `required_version` constraint,
  regardless of whether `cilium_self_management` is set

#### Scenario: A caller root declaring a provider range still resolves

- **WHEN** a consumer root declares a `siderolabs/talos` constraint admitting
  a version in the module's range — an exact `0.12.0` pin or a range such as
  `>= 0.7.0, < 1.0.0`
- **THEN** initialization succeeds and resolves to a version both constraints
  admit

#### Scenario: A caller root constraint that excludes the pin does not resolve

- **WHEN** a consumer root declares a `siderolabs/talos` constraint that
  excludes every version in the module's range — an exact `0.11.0` pin,
  `~> 0.11.0`, or a lower bound at 0.13.0
- **THEN** initialization fails, because no release satisfies both constraints

#### Scenario: A caller root pinning a next-line prerelease does not resolve

- **WHEN** a consumer root pins a 0.13.0 prerelease exactly
- **THEN** initialization fails, because the module's `-0` upper bound
  excludes it

#### Scenario: A caller root's existing lock must be upgraded

- **WHEN** a consumer root carries a dependency lock recording a
  `siderolabs/talos` selection below 0.12.0
- **THEN** a plain initialization fails on that locked selection and the lock
  must be refreshed before a version in the range is installed

#### Scenario: A caller root's lock at the floor needs no refresh

- **WHEN** a consumer root carries a dependency lock recording
  `siderolabs/talos` 0.12.0
- **THEN** a plain initialization succeeds and keeps that selection

### Requirement: Talos provider constraint form

The talos provider constraint SHALL take the form ADR-0029 §Provider
constraints sets: its floor, 0.12.0, is the oldest version the module's code
needs (the first stable release with the Talos 1.14 machinery), and its upper
bound excludes the 0.13 line, its prereleases included.

#### Scenario: The constraint admits the 0.12 line only

- **WHEN** the module's `siderolabs/talos` constraint is evaluated
- **THEN** it admits 0.12.0 and later 0.12.x releases, and excludes every 0.13
  release and prerelease

### Requirement: Committed module lock selects the provider floor

The committed module lock SHALL select the talos provider floor, so the
provider probe, the configuration validation and the module's tests run
against it; later admitted 0.12.x releases are not exercised by those gates.

#### Scenario: The module's gates run at the floor

- **WHEN** the module's provider probe, validation and tests run
- **THEN** they resolve `siderolabs/talos` 0.12.0 from the committed lock

### Requirement: Caller root provider constraints

A consumer root's constraint SHALL admit a version in the module's range; any
constraint excluding every admitted version SHALL fail initialization.

#### Scenario: A disjoint caller constraint fails initialization

- **WHEN** a consumer root's `siderolabs/talos` constraint admits no version
  in the module's range
- **THEN** initialization fails

### Requirement: OpenTofu 1.9 floor

The `>= 1.9.0` floor (raised from `>= 1.7.0`) SHALL hold because the
`cilium_self_management` guard validations reference OTHER variables in their
`condition` — a cross-variable `validation` feature OpenTofu introduced at
1.9 — which is parsed at module load regardless of any toggle's value.

#### Scenario: The floor binds callers who never opt in

- **WHEN** a caller leaves the opt-in, default-off `cilium_self_management` at
  `false`
- **THEN** the `>= 1.9.0` floor still applies — a permanent, consumer-visible
  compatibility floor for that one feature

### Requirement: Caller-owned encrypted state backend

The state backend SHALL be the caller's concern and SHALL be encrypted,
because the machine secrets land in state.

#### Scenario: Machine secrets land in the caller's backend

- **WHEN** the module is applied from a caller root
- **THEN** its state, machine secrets included, is stored in the backend the
  caller configures, which must be encrypted

### Requirement: Image kernel-argument input validation

The module SHALL admit an optional per-image `extra_kernel_args` string list
(default `[]`) on `var.images`, unioned into the node's schematic
`customization.extraKernelArgs` alongside the selected provisioning profiles'
kernel arguments. The module SHALL reject at plan time, via a validation
naming the offending image and element, an element containing whitespace,
whose key begins with `-`, whose key is empty, or whose key is `debugfs`
regardless of its value.

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

### Requirement: Kernel-argument validation binds every caller

The module-level `extra_kernel_args` validation SHALL be the enforcement point
for every caller, including one wiring the module interface by hand; the
declarative `cluster.yaml` path is guarded in addition by the
`cluster-yaml-sot` capability's schema mirror, so the module validation is not
the only enforcement point.

#### Scenario: A hand-wired caller is still guarded

- **WHEN** a caller bypasses `cluster.yaml` and passes a malformed
  `extra_kernel_args` element directly to the module
- **THEN** the plan fails at the module's validation

### Requirement: Inert typed inputs warn rather than reject

An input whose only failure mode is having no effect SHALL be reported by a
plan-time `check` block, not by a variable `validation`; hard rejection is
reserved for inputs whose misuse causes silent BREAKAGE — a dropped datapath
override, a fatally-exiting workload, an emitted resource with nothing to
reconcile. Each such check SHALL be its own block, because `expect_failures`
matches the checkable object.

#### Scenario: An inert input warns and still plans

- **WHEN** a metric-set input is set while the toggle that makes it effective
  is off
- **THEN** the plan succeeds and reports a warning naming that input and its
  missing prerequisite, rather than failing

#### Scenario: Each check is independently bound

- **WHEN** one such check block is removed
- **THEN** exactly one test leg reports a missing expected failure and every
  other leg stays green

### Requirement: Inert-input checks model the full effectiveness condition

Each inert-input check SHALL model the input's FULL effectiveness condition,
not the one that reads as obvious, including the substrate-delivery toggle —
with the component undelivered there is neither a seed nor an emitted
resource, so every one of its inputs is inert — and any downstream chart gate
the module can observe.

#### Scenario: An undelivered component's inputs are all inert

- **WHEN** an input is set while its component's substrate-delivery toggle is
  off
- **THEN** its check reports it as inert, never as effective — a condition
  that reports an inert input as effective converts a silent no-op into an
  endorsed one

#### Scenario: A prerequisite satisfied through the override still plans

- **WHEN** a prerequisite is satisfied only inside `cilium_values_override`,
  an opaque string the module cannot introspect
- **THEN** the plan still succeeds under the warning tier, where a hard
  rejection would refuse a configuration that works

### Requirement: Chart-derived effectiveness facts are measured

Where an inert-input check's effectiveness condition rests on a rendered-chart
fact, that fact SHALL be measured against the pinned chart and recorded at the
condition.

#### Scenario: A chart gate in a condition carries its measurement

- **WHEN** a check's condition depends on a rendered-chart fact
- **THEN** the condition records that fact as measured against the pinned
  chart

### Requirement: Free-form values reaching the machine config are format-validated

A typed input whose value is rendered verbatim into a resource that becomes
part of the controlplane machine configuration SHALL constrain its accepted
character set by variable `validation`. The obligation is on the input CLASS,
not on individual inputs: every sibling reaching the same rendered document
carries it, or the guard documents a boundary it does not hold.

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

### Requirement: Format guards carry rejection and control test legs

For each format-validated input the module's test suite SHALL carry a
rejection leg per corruption vector plus a negative-space control proving the
documented form is still accepted.

#### Scenario: Every vector and the documented form are bound

- **WHEN** a format-validated input's test suite runs
- **THEN** each corruption vector has its own rejection leg, and a control leg
  passes the documented form

### Requirement: Format guard shape follows the value space

Where the documented form is a narrow token, the format guard SHALL be an
allowlist. Where legitimate values carry structured punctuation, the guard
SHALL instead exclude the measured corruption vectors, and the negative-space
control SHALL exercise the documented structured form.

#### Scenario: Structured values are guarded by exclusion

- **WHEN** an input's legitimate values carry structured punctuation, as
  Hubble's context syntax does with colons, semicolons and equals signs
- **THEN** the guard excludes the measured corruption vectors rather than
  allowlisting a grammar the module does not own and that would break on the
  next upstream option, and a later copy-paste of the wrong guard shape fails
  the negative-space control loudly

### Requirement: Computable-type format guards are semantic predicates

Where the value space is a COMPUTABLE TYPE, the format guard SHALL be a
semantic predicate over that type rather than a lexical rule, admitting
exactly the shape the input is for, and the test suite SHALL carry a leg that
a lexical guard would pass so the distinction cannot silently degrade.

#### Scenario: A semantic predicate rejects without enumerating vectors

- **WHEN** a computable-type input carries any corruption vector
- **THEN** the semantic predicate rejects it without enumerating that vector

### Requirement: The schema mirrors each format guard

The schema SHALL mirror each format guard so the declarative path rejects a
corrupting entry at lint time, and the mirror SHALL account for regex-engine
divergence between the two validators rather than copying the expression
verbatim. Where the module's guard is a semantic predicate the mirror SHALL
constrain the value's SHAPE only, leaving the precise verdict to the module.

#### Scenario: A corrupting entry fails at lint time

- **WHEN** a `cluster.yaml` entry carries a corruption vector a module format
  guard rejects
- **THEN** the schema rejects it at lint time, before any plan

### Requirement: Inputs in the format-validated class

Five inputs SHALL be in the format-validated class, all reaching the
`cilium-config` ConfigMap that the module bakes into a create-only
`inlineManifest`: the Cilium agent metric-delta list, the Hubble metric list,
the native-routing CIDR, `cilium_k8s_service_host` and
`cilium_k8s_service_port`.

#### Scenario: Metric list entries can inject or split

- **WHEN** an entry of the agent metric-delta list or the Hubble metric list,
  both rendered raw and unquoted as list entries, contains a newline with
  matching indentation, or a document separator
- **THEN** unguarded, the newline would escape the surrounding scalar and
  inject arbitrary ConfigMap keys, and the separator would split the rendered
  manifest and blank the seed-marker output that parses it

#### Scenario: Scalar inputs carry the newline vector

- **WHEN** the native-routing CIDR, which is rendered raw as a scalar value,
  carries a newline
- **THEN** unguarded, it carries the same newline vector as the metric lists,
  and so do `cilium_k8s_service_host` and `cilium_k8s_service_port`

#### Scenario: The API-server endpoint guards are allowlists

- **WHEN** the `cilium_k8s_service_host` and `cilium_k8s_service_port` guards
  are classified
- **THEN** their form is an allowlist, stated with the rest of the Cilium
  input validation above, because a bare host and a decimal port are narrow
  tokens rather than a structured grammar the module does not own

### Requirement: Cilium self-management guard validations

The module SHALL reject at plan time, via separate cross-variable
`validation` blocks on `cilium_self_management`: (1) enabling it while
`deploy_argocd` is false or `deploy_cilium` is false — self-management
hands the Day-2 config off from the module-delivered Cilium seed to the
consumer's ArgoCD, so both must be present; and (2) enabling it with a
non-empty `cilium_values_override` and no
`cilium_self_management_values_source`.

#### Scenario: Self-management without ArgoCD or Cilium is rejected

- **WHEN** `cilium_self_management = true` and either `deploy_argocd` or
  `deploy_cilium` is `false`
- **THEN** variable validation fails with an error naming the missing
  prerequisite

#### Scenario: Self-management with an active override is rejected

- **WHEN** `cilium_self_management = true`, `cilium_values_override` is
  non-empty, and `cilium_self_management_values_source` is unset
- **THEN** variable validation fails with an error directing the caller to
  configure the values source the emitted Application would read the override
  from

#### Scenario: An unresolvable values path is rejected

- **WHEN** `cilium_self_management_values_source` carries an empty
  `values_path`, an absolute path, or a path containing a `..` segment
- **THEN** variable validation fails, rather than emitting an Application
  whose `$values/` reference the repo-server cannot resolve

#### Scenario: An override with nowhere to be read from is rejected

- **WHEN** `cilium_self_management_values_source` is set with an empty
  `override_path` while `cilium_values_override` is non-empty
- **THEN** variable validation fails, because the emitted Application would
  otherwise render from the module-set layer alone

#### Scenario: Without a values source the override would be dropped

- **WHEN** guard (2) would be bypassed — self-management on, a non-empty
  `cilium_values_override`, no `cilium_self_management_values_source`
- **THEN** the emitted Application would be single-source and its
  `valuesObject` would carry no override term (see `cilium-cni-delivery`), so
  a seed-active datapath override would be silently dropped on ArgoCD adoption

### Requirement: Cilium self-management values-source guards

The module SHALL further reject, via separate `validation` blocks on
`cilium_self_management_values_source`: a values source missing any of
`repo_url`, `revision` or `values_path`; a `values_path` or `override_path`
that is absolute or contains a `..` segment; and a missing `override_path`
while `cilium_values_override` is non-empty.

#### Scenario: A values source missing a required field is rejected

- **WHEN** `cilium_self_management_values_source` omits `repo_url`,
  `revision` or `values_path`
- **THEN** variable validation fails

#### Scenario: A malformed override path is rejected

- **WHEN** `override_path` is absolute or contains a `..` segment
- **THEN** variable validation fails: both paths are interpolated into a
  `$values/<path>` reference the repo-server resolves against the ref source's
  checkout root, and a malformed one stops all Cilium reconciliation with no
  plan-time signal
- **AND** a missing `override_path` under a non-empty override is the same
  silent drop as guard (2), one layer down

### Requirement: Self-management guards stay separate blocks

Every self-management guard SHALL remain its own `validation` block rather
than being combined into one `condition`, so each is independently
exercisable by a dedicated `expect_failures` test leg.

#### Scenario: A merged condition would leave a half untested

- **WHEN** an `expect_failures` leg names a guarded variable
- **THEN** it proves only that SOME validation on that variable fired, so each
  guard has its own block and leg rather than a merged condition that would
  leave half a predicate vacuously green

### Requirement: Opt-in Cilium self-management output

The module SHALL expose `cilium_self_management_app` — a YAML-encoded
`argoproj.io/v1alpha1` `Application` manifest string — as `""` when
`cilium_self_management = false` (the default), and as the rendered
Application when `true`. The module SHALL NOT apply this manifest itself — it
is an output only, for the consumer's own GitOps to commit and reconcile.

#### Scenario: Output is empty by default

- **WHEN** `cilium_self_management` is left at its default (`false`)
- **THEN** `cilium_self_management_app` is the empty string

#### Scenario: Output never renders empty while the toggle is on

- **WHEN** `cilium_self_management = true`
- **THEN** `cilium_self_management_app` is non-empty, or the plan fails on
  the output's precondition rather than emitting a hollow Application

#### Scenario: The values-source input moves nothing for a consumer who does not opt in

- **WHEN** `cilium_self_management_values_source` is left unset
- **THEN** the emitted Application is byte-for-byte the golden committed for this
  input set at this revision, so introducing the values-source input moved
  nothing for a consumer who does not configure one

#### Scenario: The override digest tracks a sensitive input

- **WHEN** `cilium_values_override` is non-empty
- **THEN** `cilium_values_override_digest` is its SHA-256, and `""` when the
  input is empty — never the hash of the empty string, so an unset override
  reads as unset

#### Scenario: The values output tracks the emitted shape in both directions

- **WHEN** `cilium_self_management` and `cilium_self_management_values_source`
  are both set
- **THEN** `cilium_self_management_values` is non-empty and carries both the
  floor and the computed layer; and with either unset it is the empty string,
  so a stray file can no more ship than a missing one

### Requirement: Self-management output preconditions

`cilium_self_management_app` SHALL carry `precondition`s rejecting both an
unexpectedly empty render while the toggle is on and a multi-source render
whose first `valueFiles` entry is not a non-empty `$values/<path>` reference —
the addressing predicate, not a list-length one.

#### Scenario: A mis-addressed first values file fails the plan

- **WHEN** a multi-source render's first `valueFiles` entry is not a
  non-empty `$values/<path>` reference
- **THEN** the plan fails on the output's precondition — a length check could
  never fail there, since the first entry is appended unconditionally on that
  arm

### Requirement: Self-management values output

With `cilium_self_management_values_source` set, the module SHALL additionally
expose `cilium_self_management_values`, the module-set values layer as a YAML
document for the consumer to commit at that source's `values_path`, non-empty
exactly when self-management and a values source are both configured.

#### Scenario: The manifest is no longer the sole deliverable

- **WHEN** a values source is configured with self-management on
- **THEN** the consumer commits both the Application and the
  `cilium_self_management_values` document at that source's `values_path`

### Requirement: Self-management outputs are secret-free

Neither `cilium_self_management_app` nor `cilium_self_management_values` SHALL
be marked `sensitive`, and both SHALL be secret-free by construction: the
module SHALL NOT place `cilium_values_override` (which IS sensitive) into
either, referencing it only as a `$values/<path>` string pointing at a file
the consumer authors and commits themselves.

#### Scenario: The override reaches the Application only by reference

- **WHEN** self-management and a values source are configured with a
  non-empty override
- **THEN** neither output contains the override's content, only a
  `$values/<path>` reference to the consumer's file

### Requirement: The override file is plaintext in git

Keeping the override out of the emitted manifest is an integrity property,
NOT a confidentiality one, so the module SHALL document key material at
`override_path` as plaintext in git rather than as protected by the
consumer's secret tooling.

#### Scenario: Argo CD reads the override file unencrypted

- **WHEN** Argo CD renders the Application
- **THEN** it reads the `override_path` file as a plain Helm values document
  and decrypts nothing

### Requirement: Override digest output

The module SHALL expose `cilium_values_override_digest` — the SHA-256 of
`cilium_values_override`, `""` when empty, and NOT `sensitive` — as the
plan-time change detector the input's `sensitive` marking removes.

#### Scenario: An override change shows in the plan through its digest

- **WHEN** `cilium_values_override` changes between plans
- **THEN** `cilium_values_override_digest` changes visibly in plan output,
  although the override itself is hidden

### Requirement: Values source does not move the single-source document

Configuring or not configuring `cilium_self_management_values_source` SHALL
NOT move the single-source document at one base revision, and that promise
SHALL be bound by a whole-document comparison against a committed golden,
since presence and absence assertions cannot observe a field added, renamed
or reordered elsewhere in the manifest.

#### Scenario: A field change elsewhere trips the golden

- **WHEN** a change adds, renames or reorders a field anywhere in the
  single-source document
- **THEN** the whole-document comparison against the committed golden fails

### Requirement: Named per-key assertions back the golden

The golden detects MOVEMENT and certifies no key's correctness — it reports
only that a byte moved, and a deliberate refresh silences it — so the facts a
reader depends on SHALL additionally carry named per-key assertions that a
refresh cannot silence.

#### Scenario: A golden refresh leaves per-key facts bound

- **WHEN** the golden is deliberately refreshed
- **THEN** the named per-key assertions still check the facts a reader
  depends on

### Requirement: Single-source document movement across revisions

The no-movement promise does not extend across revisions: a floor or
computed-layer change moves this document for every consumer on this arm, so
such a change SHALL carry an `UPGRADING.md` note and a deliberate golden
refresh; its release class follows ADR-0029 — row 12, MINOR with that note
although this arm has no opt-out, and the higher class only if row 9 applies.

#### Scenario: A floor change is a noted, consumer-visible change

- **WHEN** a change moves the floor or computed layer of the single-source
  document
- **THEN** it carries an `UPGRADING.md` note and a deliberate golden refresh

### Requirement: Operator replica count input and provenance output

The module SHALL accept an optional Cilium operator replica count and SHALL
reject a value that is not an integer of at least 1, or that exceeds the number
of declared nodes. The over-count rejection sits on the REJECT side of the
inert-input tier rule rather than the warn side. Each conjunct SHALL be its
own validation block, per the guard-isolation obligation the module's other
cross-variable validations carry.

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

#### Scenario: The over-count rejection rests on three grounds

- **WHEN** the over-count rule is classified against the inert-input tier rule
- **THEN** it rejects rather than warns, because the declared node set is not
  an estimate of the environment but the cluster the module builds, so the
  predicate is decidable from the module's own state
- **AND** the operator's `podAntiAffinity` is `requiredDuringScheduling` on
  `kubernetes.io/hostname`, so the surplus can never place
- **AND** the value is baked into a create-only `inlineManifest`, so the
  bootstrap that carries it cannot be corrected by a later apply

### Requirement: Operator replica count provenance output

The module SHALL expose a secret-free plan-time output reporting the resolved
operator replica count together with the mechanism that produced it — the
explicit pin, the node-count derivation, or the shipped floor — so an operator
debugging a live Deployment can attribute the number without reading module
internals.

#### Scenario: An explicit pin reports itself as the origin

- **WHEN** the operator replica count is set explicitly with Cilium delivered
- **THEN** the output reports that count with the explicit pin as its origin

### Requirement: Chart-version default bumps carry their render-side delta

Moving a chart-version input's declared default SHALL be treated as a
**consumer-visible change**, not a version literal, and SHALL carry the
behavioural delta on the capability that describes what the pin delivers —
the render or seed capability, not this one, which owns only the input's
presence, its `nullable = false` contract and its validation.

#### Scenario: A bump without its render-side delta is not ready

- **WHEN** a change moves `cilium_chart_version` or `argocd_chart_version`'s
  declared default
- **THEN** the change carries a spec delta on the capability describing what that
  pin renders or seeds

#### Scenario: A bump does not re-seed a running cluster

- **WHEN** an already-bootstrapped consumer vendors a tag whose chart-version
  default moved and re-plans
- **THEN** the frozen render output is unchanged; the new chart reaches the
  cluster only through the steady-state component's next sync, and the CRD apply
  re-fires on the version change alone
- **AND** a moved `cilium_chart_version` default causes no machine-config
  re-push, while a moved `argocd_chart_version` default changes every
  controlplane's machine configuration through the seeded namespace's version
  label only

#### Scenario: The staleness gate cannot route the delta

- **WHEN** a version bump touches only the chart-version default
- **THEN** the staleness gate does not reach the render-side spec on its own,
  because the file describing the seed's contents is not the file the bump
  touches, so the delta is carried by the change itself

### Requirement: Reach of a chart-version default bump

A moved chart-version default SHALL reach a **fresh bootstrap** and a
**deliberate replacement** of the frozen render, which seed whatever the new
chart emits, including defaults the base does not override; an
already-bootstrapped consumer SHALL NOT be re-seeded, because
`terraform_data.{argocd,cilium}_render` ignore input changes and the machine
config consumes their frozen outputs.

#### Scenario: Only live-reconciled paths reach a running cluster

- **WHEN** a chart-version default moves under a running cluster
- **THEN** only the separately live-reconciled paths reach it — the
  steady-state component a consumer syncs, and the CRD apply whose
  `triggers_replace` carries the chart version

### Requirement: Machine-config effect of a chart-version default bump

A moved `cilium_chart_version` default SHALL NOT change the machine
configuration. A moved `argocd_chart_version` default does: the seeded
`argocd` namespace manifest carries the input as its
`app.kubernetes.io/version` label outside the frozen render, so every
controlplane receives a machine-configuration apply under its
`controlplane_apply_mode`.

#### Scenario: The namespace label change does not reach the running namespace

- **WHEN** a moved `argocd_chart_version` default triggers the controlplane
  machine-configuration apply
- **THEN** Talos' create-only inline-manifest controller does not carry the
  new label into the running `argocd` namespace

### Requirement: Cert-approver replica-separation audit outputs

For the cert-approver seed the module SHALL also expose, parsed from the
rendered manifest, `cert_approver_affinity` (the Deployment's decoded
pod-template affinity, `{}` when none renders) and
`cert_approver_pod_disruption_budgets` (every PodDisruptionBudget in the seed
as `api_version`, `name`, `namespace` and `spec`).

#### Scenario: Replica-separation outputs feed the seed guards

- **WHEN** the seed's tests read the two outputs
- **THEN** at the default replica count the affinity is `{}` and the list is
  empty, and at `cert_approver_replicas = 2` they carry the anti-affinity term
  and the one PodDisruptionBudget the cert-approver seed requires
