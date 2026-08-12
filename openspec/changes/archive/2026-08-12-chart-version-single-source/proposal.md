## Why

A component chart-version bump in this base cannot reach a consumer created from
an earlier tag. The pinned version existed in three uncoupled places — the
module's `variables.tf` default, the example shim's `try(..., "<literal>")`
fallback, and `chart_version` in the shipped `cluster.yaml` examples — and both
consumer-facing copies pass the value EXPLICITLY. The module default is therefore
consulted only by a caller that passes nothing, which no shipped path does.

Consequence, surfaced by the review of the Cilium 1.19.4 → 1.20.0 bump: a
consumer vendors the new base tag and still renders the old chart. No 1.20
render, no self-management move, and every upgrade note inapplicable — with
nothing warning them. The bump's `UPGRADING.md` had to carry a manual
"move your own pin" step as the only mitigation.

The obvious fix — have the shim pass `null` so the module default applies — does
NOT work by itself. Verified empirically on OpenTofu v1.11.8: a `null` passed to
a module input with a default stays `null`; the default is substituted only when
the variable also declares `nullable = false`. That attribute is the missing
precondition and is what this change adds.

## What Changes

- `cilium_chart_version` and `argocd_chart_version` declare `nullable = false`
  beside their defaults, making the module default the single source of truth and
  giving `null` the meaning "take the base's pin".
- The example shim passes `try(local.<component>.chart_version, null)` instead of
  a hard-coded literal, so it carries no version at all.
- `cluster.yaml.example` and `examples/complete/cluster.yaml` comment out
  `chart_version`, documenting that omitting it inherits the base pin and that
  setting it is a deliberate pin which overrides every future bump.
- A `tofu test` run binds the mechanism: passing `cilium_chart_version = null`
  must yield a semver chart version in the emitted Application's
  `spec.source.targetRevision`, never `null`.

The contract is deliberately per-input, not module-wide: no other input promises
null-means-default, and the spec says so, because a reader who generalizes it
would pass `null` to an input that has no `nullable = false` and silently get
`null`.

## Capabilities

- `module-interface-contract` — MODIFIED: the grouped-input requirement gains the
  chart-version single-source contract and its `nullable = false` mechanism, plus
  a scenario binding null-resolves-to-default.

## Impact

Consumer-visible, non-breaking. A consumer who sets `chart_version` in their
`cluster.yaml` is unaffected — an explicit value still wins. A consumer who
omits it moves from "whatever literal my shim was copied with" to "the base's
pin", which is the intended behavior and the point of the change. Existing
consumers who want to adopt the new behavior update their shim's fallback to
`null`; the version literals no longer exist anywhere outside `variables.tf`.

`cluster.yaml.example` is not a `primary` source of any spec and
`substrate.cilium.chart_version` was already optional in
`schemas/cluster.schema.json`, so commenting the key out needs no schema change.
