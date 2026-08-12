## Why

Cilium 1.20.0 was released 2026-07-29. Cilium is one of the base's three
co-equal substrate pillars and has been pinned at chart 1.19.4 since the
`talos-cluster` module was created — this is the repo's first component version
bump, so there is no bump precedent in the specs.

The bump is not a pure string edit. Two upstream changes break documented base
behavior:

1. **Cilium 1.20 removed the flat `encryption.strictMode.{enabled,cidr,
   allowRemoteNodeIdentities}` Helm values** (deprecated in 1.19 in favor of
   `encryption.strictMode.egress.*`). `kubernetes/bootstrap/cilium/values.yaml`
   — a `primary` source of `cilium-cni-delivery` and the file a consumer is told
   to copy into a Day-2 self-managed Application — still sets the flat form.
   Helm does not run `--strict`, so on chart 1.20 those keys are **silently
   dropped**: strict-mode encryption would simply not be configured, with no
   error at render or apply time. Verified by rendering the current file against
   chart 1.20.0 — no `encryption-strict-*` key appears in `cilium-config`.

2. **Cilium 1.20 raises the Gateway API floor from v1.6.1 to a hard minimum**,
   because `TLSRoute` graduated from `v1alpha2` to `v1`. The base documents the
   old floor (GW-API v1.4.1 standard channel) in two `variables.tf` input
   descriptions, the module README, and ADR-0007. Left stale, a consumer
   following base documentation seeds a CRD bundle Cilium 1.20 cannot work
   against.

The Gateway-API coupling is the drift this change also closes structurally: the
Cilium chart pin and the documented Gateway-API-CRD floor were only ever
coupled by prose, so the minor bump silently invalidated the CRD guidance. The
`module-interface-contract` delta binds them.

Chart-internal re-verification at the new pin (all four `cilium-config` marker
keys, the `hubble-metrics` `:9965` Service, seed render determinism, and
ADR-0022's explicit `operator.prometheus.enabled` revisit trigger) is recorded
as a dated addendum in
`knowledge/decisions/0022-cilium-observability-and-argocd-self-management.md`.
Nothing in that ADR is superseded.

## What Changes

- `cilium-cni-delivery`: the reference-values requirement gains a scenario
  binding the reference file's Helm-value spellings to the pinned chart
  version, so a value the pinned chart no longer accepts is a spec violation
  rather than a silent misconfiguration. The file itself migrates to
  `encryption.strictMode.egress.*` — which renders identically on 1.19.x, so it
  is safe for a consumer still pinning the previous minor.
- `module-interface-contract`: the input-surface requirement gains a scenario
  requiring the `cilium_gateway_api_crds_url` documentation to state the
  Gateway-API-CRD floor that the *currently pinned* Cilium chart requires,
  keeping the two version axes in lockstep across future bumps.
- Not a spec change, but shipped here: the `cilium_chart_version` default moves
  `1.19.4` → `1.20.0` at all six literal sites (module variable, the
  `examples/complete` shim fallback, both `cluster.yaml` examples, the README
  Inputs row, and the `outputs.tf` marker-key verification annotation).

`schemas/cluster.schema.json` is deliberately untouched: `chart_version` is a
plain `string` with no `pattern`/`enum`, so `cluster-yaml-sot` is not implicated
and needs no delta.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `cilium-cni-delivery` — one MODIFIED requirement (reference values for
  optional Day-2 self-management).
- `module-interface-contract` — one MODIFIED requirement (grouped typed input
  surface).

## Impact

- Specs: `openspec/specs/cilium-cni-delivery/spec.md`,
  `openspec/specs/module-interface-contract/spec.md` (merged in on archive; this
  change is archived in the same commit that ships the code, per
  `scripts/check-spec-staleness.py` globbing `openspec/specs/*/spec.md` only).
- Code: `tofu/modules/talos-cluster/variables.tf` (chart-version default + two
  Gateway-API input descriptions), `tofu/modules/talos-cluster/outputs.tf`
  (marker-key verification annotation),
  `tofu/modules/talos-cluster/examples/complete/{main.tf,cluster.yaml}`,
  `cluster.yaml.example`, `kubernetes/bootstrap/cilium/values.yaml`
  (`strictMode` migration).
- Gates: `docs-lint` (required) runs `spec:check-staleness`, which fires on
  `variables.tf` and `kubernetes/bootstrap/cilium/values.yaml`; `task tofu:ci`
  covers `check:readme-parity` and `check:render-determinism`. **`task tofu:test`
  is the only gate that actually pulls chart 1.20.0** and re-binds
  `composition.tftest.hcl`'s four seed-render asserts — it is excluded from
  `tofu:ci`, and `tofu-validate` is path-filtered and not a required check, so it
  must be run by hand before push.
- Docs: `tofu/modules/talos-cluster/README.md` (two Inputs rows),
  `knowledge/decisions/0007-cluster-yaml-sot.md` (Gateway-API floor + the
  re-verified `.prov` finding),
  `knowledge/decisions/0022-cilium-observability-and-argocd-self-management.md`
  (dated re-verification addendum), `knowledge/log.md`, `CHANGELOG.md`
  (`### Changed`), `UPGRADING.md` (`## Unreleased (next MINOR)`).
