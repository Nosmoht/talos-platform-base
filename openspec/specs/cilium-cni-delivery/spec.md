---
sources:
  primary:
    - kubernetes/bootstrap/cilium/values.yaml
    - kubernetes/bootstrap/cilium/extras.yaml
    - tofu/modules/talos-cluster/helm/cilium-values.yaml
    - tofu/modules/talos-cluster/cilium-values.tf
  secondary:
    - tofu/modules/talos-cluster/main.tf
references:
  - AGENTS.md §Repository Purpose (three pillars)
---

# cilium-cni-delivery

## Purpose

Cilium is a co-equal substrate pillar delivered by the
`tofu/modules/talos-cluster` module as a controlplane Talos
`cluster.inlineManifests` seed (`deploy_cilium`); the repo additionally ships
reference Helm values and a GatewayClass extra for optional Day-2 Cilium
self-management.

## Requirements

### Requirement: Cilium seeded as a controlplane inlineManifest

The module SHALL, when `deploy_cilium` is true, render the Cilium chart
locally via `data.helm_template.cilium` (CRDs included) and bake the frozen
render into the controlplane machine configuration as a
`cluster.inlineManifests` entry named `cilium`, so the CNI comes up with the
cluster bootstrap without any Helm release or in-cluster apply step.

#### Scenario: Controlplane config carries the Cilium seed

- **WHEN** the module plans with `deploy_cilium = true`
- **THEN** the controlplane config patches include a
  `cluster.inlineManifests` entry named `cilium` whose contents are the
  frozen chart render

#### Scenario: Empty render is rejected at plan time

- **WHEN** the Cilium chart render produces an empty manifest
- **THEN** the plan fails with an error naming the empty Cilium seed instead
  of freezing it

### Requirement: Default CNI and kube-proxy disabled with Cilium delivery

The module SHALL, when `deploy_cilium` is true, apply an authoritative
all-nodes patch that sets the Talos cluster CNI to `none` — placed last so a
caller `config_patches` entry cannot re-enable the default CNI — and SHALL
set `cluster.proxy.disabled` in the same patch when
`cilium_kube_proxy_replacement` is enabled, keeping the Talos side and the
Cilium-side kube-proxy replacement in sync.

#### Scenario: Default CNI cannot resurface via caller patches

- **WHEN** `deploy_cilium = true` and a caller patch carries a `cni` stanza
- **THEN** the rendered machine configuration still sets
  `cluster.network.cni.name: none`, because the module's CNI patch is
  ordered after all caller patches

### Requirement: Seed render frozen against non-deterministic re-renders

The module SHALL consume the Cilium render through a state-frozen resource
(`terraform_data.cilium_render` with `ignore_changes` on its input) so that
render drift at identical inputs never re-pushes machine configuration; a
deliberate re-seed requires an explicit resource replacement.

#### Scenario: Render drift does not churn machine config

- **WHEN** a later plan re-evaluates the chart render and produces different
  bytes at unchanged inputs
- **THEN** the frozen render output — and therefore the machine
  configuration — is unchanged

### Requirement: Cluster-agnostic floor values with layered configuration

The module SHALL render the seed from three value layers, later layer
winning per Helm merge semantics: the shipped floor
`tofu/modules/talos-cluster/helm/cilium-values.yaml` (Talos invariants:
cgroup auto-mount disabled, `SYS_MODULE` absent from the agent capability
set, `cni.exclusive: false`, Hubble disabled for a deterministic render,
single operator replica), then module-computed values derived from typed
inputs (routing mode, kube-proxy replacement, native-routing CIDR, Gateway
API, MTU, encryption, and — issue #188 — Cilium agent and operator
Prometheus metrics and Hubble enablement/metrics/observer-API-TLS), then
the consumer's `cilium_values_override`. The module-computed layer is
computed once, in `tofu/modules/talos-cluster/cilium-values.tf`, and feeds
BOTH this seed render and the opt-in emitted self-management Application
(see the ADDED requirement below) — a single observability data-flow, no
divergent computation between the two delivery paths.

#### Scenario: Consumer override wins over the floor

- **WHEN** `cilium_values_override` sets a key also present in the shipped
  floor values
- **THEN** the rendered seed carries the override's value for that key

#### Scenario: Floor keeps install-time-fixed values out

- **WHEN** the shipped floor values file is read
- **THEN** it contains no routing mode, encryption, native-routing CIDR,
  Gateway API, or kube-proxy-replacement keys — those are emitted only by
  the module's computed layer

#### Scenario: Observability inputs surface in the seed render

- **WHEN** the module plans with `cilium_agent_metrics = true`,
  `cilium_operator_metrics = true`, and `cilium_hubble_enabled = true`
  (with a non-empty `cilium_hubble_metrics`)
- **THEN** the rendered seed's `cilium-config` ConfigMap carries the agent
  and operator Prometheus scrape keys and the Hubble enablement + metrics
  keys, and the Hubble observer-API server TLS is off
  (`hubble.tls.enabled = false`) — metrics-only scope, independent of the
  separate Hubble metrics-endpoint TLS knob

### Requirement: Reference values for optional Day-2 self-management

The repo SHALL retain `kubernetes/bootstrap/cilium/values.yaml` as a
reference-only Helm values file for optional Day-2 Cilium self-management —
it is not consumed by the module's seed render — and SHALL ship
`kubernetes/bootstrap/cilium/extras.yaml` providing the `cilium`
GatewayClass that the Helm chart does not generate, consistent with the
platform's Gateway-API-only stance (normative: AGENTS.md §Hard Constraints —
Gateway API only). Because the file is offered to consumers as copy-ready
input for a self-managed Application, every Helm value it sets SHALL use a
spelling the currently pinned `cilium_chart_version` still accepts: Helm
merges value layers without `--strict`, so a value the pinned chart has
removed is dropped silently rather than rejected, and the consumer's
resulting cluster is misconfigured with no error at render or apply time.

#### Scenario: Reference values are marked as non-live

- **WHEN** `kubernetes/bootstrap/cilium/values.yaml` is read
- **THEN** its header states it is reference-only and names
  `tofu/modules/talos-cluster/helm/cilium-values.yaml` as the live seed
  floor

#### Scenario: GatewayClass extra, no Ingress

- **WHEN** `kubernetes/bootstrap/cilium/extras.yaml` is applied
- **THEN** it creates exactly one resource — a GatewayClass named `cilium`
  with the Cilium gateway controller name — and no `kind: Ingress` resource

#### Scenario: Reference values use value spellings the pinned chart accepts

- **WHEN** `kubernetes/bootstrap/cilium/values.yaml` is rendered with
  `helm template` against the chart version pinned by
  `cilium_chart_version`
- **THEN** every value the file sets reaches the rendered output — in
  particular the encryption strict-mode settings appear as
  `encryption-strict-*` keys in the `cilium-config` ConfigMap — and no value
  is silently dropped as an unknown key

### Requirement: Opt-in emitted self-management Application for Day-2 delivery

The module SHALL, when `cilium_self_management = true` (guarded by the
`module-interface-contract` cross-variable validations), expose an
`argoproj.io/v1alpha1` `Application` manifest — via the
`cilium_self_management_app` output, never applied by the module — as the
Day-2 delivery path for a Cilium config change (including the observability
inputs) on an already-bootstrapped cluster, complementing the frozen
create-only bootstrap seed above and the pre-existing static
`kubernetes/bootstrap/cilium/values.yaml` reference file. The emitted
Application's `spec.source.helm.valuesObject` SHALL be the bounded,
module-controlled merge of the floor and computed-values layers ONLY — it
SHALL NOT inherit `cilium_values_override` — because the override is an
opaque free-form string the module cannot introspect for datapath-critical
content (BGP control-plane, L2 announcements, bpf tuning); silently
carrying it forward on ArgoCD adoption could drop it, so
`module-interface-contract`'s guard hard-rejects enabling self-management
while an override is active instead. The Application SHALL carry
`spec.project = var.cilium_self_management_project` (default `"default"`,
the base's sole permissive AppProject; a scoped consumer-created project is
recommended hardening) and SHALL carry no `syncPolicy`, so the consumer
controls sync timing for the graceful-restart-gated DaemonSet roll that
enabling Hubble triggers.

#### Scenario: Emitted Application carries the module-set values only

- **WHEN** `cilium_self_management = true` and `cilium_values_override` is
  empty (the only state the guard permits)
- **THEN** the emitted Application's `valuesObject` equals the floor ⊕
  computed-values merge, and the manifest carries no `syncPolicy` key

#### Scenario: Emitted Application targets the default AppProject unless scoped

- **WHEN** `cilium_self_management_project` is left at its default
- **THEN** the emitted Application's `spec.project` is `"default"` — the
  base's only pre-existing AppProject — functional out-of-the-box, with a
  dedicated scoped project as documented, recommended hardening
