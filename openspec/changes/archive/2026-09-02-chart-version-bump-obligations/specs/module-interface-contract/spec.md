## ADDED Requirements

### Requirement: Chart-version default bumps carry their render-side delta

Because a chart-version input's declared default is the single source of truth
for the pinned chart and the shipped examples leave the key unset, moving that
default is a **consumer-visible change**, not a version literal: every conforming
consumer's next render and next Day-0 machine config carry whatever the new chart
emits, including defaults the base does not override.

A change moving one of those defaults SHALL therefore carry the behavioural delta
on the capability that describes what the pin delivers — the render or seed
capability, not this one, which owns only the input's presence, its
`nullable = false` contract and its validation. `Spec-Impact: none` SHALL NOT be
claimed for such a change: the escape is scoped to verified no-behaviour-change
diffs, and the staleness gate cannot reach the render-side spec on its own,
because the file that describes the seed's contents is not the file a version
bump touches.

The change SHALL also re-verify the upstream constraints the module cannot check
at plan time, and record the result where a consumer adopting the tag will read
it: the Kubernetes version range the new upstream version supports, against a
`kubernetes_version` the module takes as a required input and never validates;
and the upstream project's own upgrade notes for every version crossed. This is
**reviewer-enforced**, in the same sense and for the same reason as the
Gateway-API CRD floor below — no mechanical gate compares a chart pin against an
upstream support matrix, and a mechanical coupling remains desirable and unbuilt.

#### Scenario: A bump without its render-side delta is not ready

- **WHEN** a change moves `cilium_chart_version` or `argocd_chart_version`'s
  declared default
- **THEN** the change carries a spec delta on the capability describing what that
  pin renders or seeds, and no commit in it claims `Spec-Impact: none` for the
  variables file

#### Scenario: The upstream support window is stated for the adopting consumer

- **WHEN** such a bump crosses one or more upstream minor versions
- **THEN** the change records the new version's supported Kubernetes range and
  the upstream upgrade notes for every version crossed, in the consumer-facing
  upgrade documentation for the tag that ships it
