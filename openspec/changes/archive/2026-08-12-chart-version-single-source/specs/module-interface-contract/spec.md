## MODIFIED Requirements

### Requirement: Grouped typed input surface

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

#### Scenario: A null chart version resolves to the module's pinned default

- **WHEN** a caller passes `cilium_chart_version = null` — the example shim's
  behavior when `cluster.yaml` omits `substrate.cilium.chart_version`
- **THEN** the module resolves it to that variable's declared default, and the
  emitted self-management Application's `spec.source.targetRevision` carries a
  chart version rather than `null`
