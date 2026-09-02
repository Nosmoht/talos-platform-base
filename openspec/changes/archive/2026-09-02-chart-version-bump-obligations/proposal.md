# A chart-version default bump is a consumer-visible change

## Why

`module-interface-contract` already states that the two chart-version inputs
declare `nullable = false` so that "the module's declared default [is] the SINGLE
source of truth for the pinned chart version", and that the shipped examples
leave the key commented out so a consumer inherits a base bump. Both halves are
deliberate — and together they mean the default's *value* is what every
conforming consumer's cluster gets.

The argo-cd `9.4.5` → `10.6.0` bump exposed the gap that follows from that. The
commit moving `variables.tf`'s default carried a `Spec-Impact: none` trailer,
escaping `spec:check-staleness` on the file this spec owns — while the same
change's CHANGELOG entry called it BREAKING and shipped five NetworkPolicies into
every consumer's Day-0 machine config. The escape is scoped to "verified
no-behavior-change diffs", so the trailer was wrong; nothing in the spec said so,
because the spec described the *mechanism* (null-means-default) and never the
obligation the mechanism creates.

The staleness gate could not have caught it either. The seed's *contents* are
described by `argocd-module-seed`, whose `primary` is `helm/argocd-values.yaml` —
a file a version bump does not touch. So the version knob and the content
description are owned by different specs, and a bump changes the latter through
the former with no gate connecting them. Only a stated obligation closes that.

The second half is the re-verification obligation. The spec already carries one
for `cilium_chart_version` — the Gateway-API CRD floor, explicitly
reviewer-enforced because no mechanical check exists. `argocd_chart_version` has
the same hazard class and no clause: Argo CD 3.5 drops Kubernetes v1.32, which
3.3 and 3.4 supported, and the module takes `kubernetes_version` as a required
input it cannot validate against the chart.

## What Changes

- `module-interface-contract`: one new requirement fixing what a chart-version
  default bump obliges — that it is a consumer-visible change, that
  `Spec-Impact: none` is not available for it, that the render-side capability
  describing what the pin delivers carries the delta, and that the upstream
  Kubernetes floor and upgrade notes are re-verified at the bump. The
  new requirement cites the existing `cilium_chart_version` Gateway-API clause as
  the precedent for the reviewer-enforced form rather than rewriting it, so that
  clause keeps its component-specific detail.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `module-interface-contract`

## Impact

- Specs: `module-interface-contract`.
- Code: none. This records an obligation on a review step that already exists;
  no mechanical gate is added, and the requirement says so rather than implying
  one.
- Consumers: none directly — it constrains how the base makes a bump, which is
  what reaches them.
- Decision record: none. This does not choose between options the base owns; it
  states a consequence of a contract already recorded here.
