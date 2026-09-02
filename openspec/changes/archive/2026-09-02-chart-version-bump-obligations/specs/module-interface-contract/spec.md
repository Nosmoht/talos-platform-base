## ADDED Requirements

### Requirement: Chart-version default bumps carry their render-side delta

Because a chart-version input's declared default is the single source of truth
for the pinned chart and the shipped examples leave the key unset, moving that
default is a **consumer-visible change**, not a version literal. What it reaches,
stated precisely, because the seed renders are frozen: a **fresh bootstrap** and
a **deliberate replacement** of the frozen render seed whatever the new chart
emits, including defaults the base does not override; an already-bootstrapped
consumer's machine configuration does NOT change, because
`terraform_data.{argocd,cilium}_render` ignore input changes and the machine
config consumes their frozen outputs. The separately live-reconciled paths — the
steady-state component a consumer syncs, and the CRD apply whose
`triggers_replace` carries the chart version — are what reach a running cluster.

A change moving one of those defaults SHALL therefore carry the behavioural delta
on the capability that describes what the pin delivers — the render or seed
capability, not this one, which owns only the input's presence, its
`nullable = false` contract and its validation. This spec cannot host that delta:
the file describing the seed's contents is not the file a version bump touches, so
the staleness gate cannot reach the render-side spec on its own.

#### Scenario: A bump without its render-side delta is not ready

- **WHEN** a change moves `cilium_chart_version` or `argocd_chart_version`'s
  declared default
- **THEN** the change carries a spec delta on the capability describing what that
  pin renders or seeds

#### Scenario: A bump does not re-seed a running cluster

- **WHEN** an already-bootstrapped consumer vendors a tag whose chart-version
  default moved and re-plans
- **THEN** the frozen render output is unchanged and no machine-config re-push
  results; the new chart reaches the cluster only through the steady-state
  component's next sync, and the CRD apply re-fires on the version change alone
