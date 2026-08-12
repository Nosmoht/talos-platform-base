## MODIFIED Requirements

### Requirement: Reference values for optional Day-2 self-management

The repo SHALL retain `kubernetes/bootstrap/cilium/values.yaml` as a
reference-only Helm values file for optional Day-2 Cilium self-management —
it is not consumed by the module's seed render — and SHALL ship
`kubernetes/bootstrap/cilium/extras.yaml` providing the `cilium`
GatewayClass that the Helm chart does not generate, consistent with the
platform's Gateway-API-only stance (normative: AGENTS.md §Hard Constraints —
Gateway API only). Because the file is offered to consumers as copy-ready
input for a self-managed Application, a `cilium_chart_version` bump SHALL
reconcile this file against the newly pinned chart for its **datapath- and
security-critical** values, covering both failure modes: a value spelling the
chart has **removed** (Helm merges without `--strict`, so it is dropped
silently rather than rejected), and a value whose **default or enforcement
behavior the chart has changed** under a spelling that still parses. In either
case the consumer's cluster is misconfigured or newly failing with no error at
render or apply time, so the bump SHALL either fix the file or document the
consequence in `UPGRADING.md`. Known exception: a full audit of every value in
the file against the pinned chart is out of scope for a version bump, so the
file MAY still carry a value the chart does not recognize. Such a value is inert
rather than harmful — Helm drops it, and removing it leaves the rendered output
byte-identical — but it misleads a consumer copying the file, so a value found to
be unrecognized by the pinned chart SHALL be removed.

#### Scenario: Reference values are marked as non-live

- **WHEN** `kubernetes/bootstrap/cilium/values.yaml` is read
- **THEN** its header states it is reference-only and names
  `tofu/modules/talos-cluster/helm/cilium-values.yaml` as the live seed
  floor

#### Scenario: GatewayClass extra, no Ingress

- **WHEN** `kubernetes/bootstrap/cilium/extras.yaml` is applied
- **THEN** it creates exactly one resource — a GatewayClass named `cilium`
  with the Cilium gateway controller name — and no `kind: Ingress` resource

#### Scenario: Encryption strict mode survives the pinned chart

- **WHEN** `kubernetes/bootstrap/cilium/values.yaml` is rendered with
  `helm template` against the chart version pinned by
  `cilium_chart_version`
- **THEN** the file's encryption strict-mode settings reach the rendered
  `cilium-config` ConfigMap as `enable-encryption-strict-mode-egress`,
  `encryption-strict-egress-cidr` and
  `encryption-strict-egress-allow-remote-node-identities` — they are not
  silently dropped as unknown keys
