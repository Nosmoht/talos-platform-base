## Why

Most Cilium settings land only in the `cilium-config` ConfigMap. Without a
pod-template checksum the agent DaemonSet is untouched by such a change, so a
successful Argo CD sync leaves the running agents on the previous configuration
— measured against the pinned 1.20.0 chart, `routingMode: tunnel` and
`routingMode: native` render a byte-identical agent pod template. The Day-2
delivery path opened for `cilium_values_override` made that gap reachable by
every value a consumer overrides, where previously it reached only the
create-only seed.

The base already carried the defect once in typed form: `cilium_hubble_open_metrics`
was documented in six places as requiring a manual
`kubectl -n kube-system rollout restart ds/cilium`. Setting the chart's own
`rollOutCiliumPods` in the floor closes the general case and narrows that manual
obligation to the paths where no re-render happens.

The key belongs in the floor rather than in the computed layer because no typed
input derives it: it is a property of how the chart delivers ANY values change,
not of a per-cluster choice. It is admitted although it is not a Talos or CNI
invariant, and the floor's own charter comment is amended to say so rather than
leaving the next author with a membership rule the file no longer obeys.

## What Changes

- The shipped floor `tofu/modules/talos-cluster/helm/cilium-values.yaml` sets
  `rollOutCiliumPods: true`, so the chart stamps
  `cilium.io/cilium-configmap-checksum` into the agent pod template.
- The Day-2 reference values `kubernetes/bootstrap/cilium/values.yaml` carry the
  same key, so a consumer following the documented copy path does not silently
  keep the defect.
- The single-source emitted `Application`'s `valuesObject` gains the key for
  every consumer on that arm. The compatibility promise that previously read as
  "byte-for-byte the document the preceding revision emitted" is re-scoped to
  what it actually protects — the values-source INPUT moves nothing at one base
  revision — rather than retracted.
- A new offline fence, `scripts/check-cilium-rollout-pods-key.sh`, binds the
  chart key's spelling on the module's side; two render runs in
  `tests/composition.tftest.hcl` bind the rendered annotation and its removal by
  an override.

## Impact

- Affected specs: `cilium-cni-delivery`, `module-interface-contract`.
- MAJOR. The emitted `Application` moves for every self-managing consumer, and
  their next sync rolls `ds/cilium` once at the chart's `maxUnavailable: 2`. An
  already-bootstrapped consumer with `self_management: false` sees nothing move:
  no Application is emitted and the seed render is frozen.
- The opt-out (`rollOutCiliumPods: false` in an override) is real on the seed
  path and on the multi-source arm, and does NOT exist on the single-source arm,
  where `cilium_values_override` is rejected at plan time. That asymmetry is
  stated in `UPGRADING.md` and `CHANGELOG.md` rather than implied away.
