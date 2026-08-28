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
consequence in `UPGRADING.md`. The removed-spelling half SHALL be enforced
mechanically rather than by review: a check SHALL validate every value path in the
file against the pinned chart's own `values.schema.json` and fail on a path the
chart does not declare, running from the same script locally and in CI so a local
pass means what a CI pass means. Because it needs the chart registry, the check
SHALL skip loudly rather than fail when the registry is unreachable — an outage
must not block unrelated merges — which leaves one stated hole: during an outage a
removed spelling can merge. The changed-default half stays reviewer-enforced, since
no schema can express it. Known exception: a full audit of every value in
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

#### Scenario: A value the pinned chart removed fails the check

- **WHEN** `kubernetes/bootstrap/cilium/values.yaml` sets a value path the pinned
  chart's `values.schema.json` does not declare — for example the flat
  `encryption.strictMode.enabled` spelling that Cilium 1.20 removed
- **THEN** the check fails and names the offending path, instead of Helm dropping
  the value silently at render time
