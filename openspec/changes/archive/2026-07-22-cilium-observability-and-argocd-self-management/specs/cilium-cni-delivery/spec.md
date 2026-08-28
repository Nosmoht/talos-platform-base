## MODIFIED Requirements

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

## ADDED Requirements

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
