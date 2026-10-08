# Ship Argo CD v3.5.4 through argo-cd chart 10.10.1

## Why

Both delivery paths pin argo-cd chart `10.6.0`, which ships Argo CD v3.5.2.
GHSA-fmxq-cgp8-87wp (CVE-2026-77459, critical) affects `>= 3.5.0, < 3.5.4`:
AppProject restrictions are bypassed by PreDelete/PostDelete resource hooks, and
no configuration closes the gap while delete hooks are in use. Chart `10.10.1`
is the latest chart and carries appVersion v3.5.4, the latest stable Argo CD.

Reading the bump against the specs exposed two gaps. Nothing bound the shipped
Argo CD image to the chart pin, so a values-level image override or a hand edit
to `_rendered/` could ship a release other than the one the pin names. And
`module-interface-contract` states that an already-bootstrapped consumer's
machine configuration does not change on a chart-version default bump. That is
false for `argocd_chart_version`: the seeded namespace's
`app.kubernetes.io/version` label is set from the input and sits outside the
frozen render, so every controlplane's machine configuration changes. Talos'
inline-manifest controller never updates an existing resource, so nothing
changes live, but the apply runs under the consumer's `controlplane_apply_mode`.

## What Changes

- `argocd-substrate`: one added requirement — every Argo CD image in the render
  carries the pinned chart's appVersion (gate: invariant I7,
  `scripts/check-argocd-image-invariant.sh`, called by
  `scripts/check-argocd-substrate-invariants.sh` and bite-checked by
  `scripts/check-argocd-image-gate-bites.sh`).
- `argocd-module-seed`: the namespace-label requirement states that the version
  label follows `argocd_chart_version` and is not frozen.
- `module-interface-contract`: the bump-reach requirement is corrected per input
  — an `argocd_chart_version` bump changes the controlplane machine
  configuration through that label; a `cilium_chart_version` bump still does not.
- Pins: `kubernetes/substrate/argocd/chart.lock.yaml` and the module's
  `argocd_chart_version` default move to `10.10.1` together (invariant P).

Freezing the namespace label is out of scope and tracked separately.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `argocd-substrate`
- `argocd-module-seed`
- `module-interface-contract`

## Impact

- Specs: the three above.
- Code: `chart.lock.yaml`, `_rendered/manifests.yaml`, `variables.tf` default,
  the I7 gate and its bite-check, wired into `gitops:validate` and CI.
