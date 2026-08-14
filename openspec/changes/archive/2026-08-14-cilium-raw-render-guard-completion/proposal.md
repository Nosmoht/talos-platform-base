# Close the raw-render guard class and bind the shim to the schema

## Why

Two review findings from the metric-delta change stayed open when it landed.

The format-validation requirement is written on the input CLASS — "every
sibling reaching the same rendered document carries it, or the guard documents
a boundary it does not hold" — and one sibling neither carried it nor was
documented as a boundary. `cilium_native_routing_cidr` reaches the same
`cilium-config` ConfigMap through the same raw, unquoted render: measured
against the pinned chart 1.20.0, the value
`"10.244.0.0/16\n  injected-native-key: pwned"` writes `injected-native-key` as
a standalone ConfigMap key baked into the create-only machine configuration.
The class obligation was stated and then left one member short.

Separately, `cluster-yaml-sot` requires a schema widening and the shipped shim
to land together, because the shim reads `cluster.yaml` through `try()` — a
total function, so a mistyped key yields the default rather than an error and
the declared value silently never reaches the module. Nothing enforced that:
schema lint validates the YAML, `tofu validate`/`plan` accept the shim as valid
HCL, and the module's test suite never loads it. The requirement existed as
prose with no gate behind it.

## What Changes

- `module-interface-contract`: the format-validation requirement gains a third
  guard FORM — a semantic predicate, correct where the value space is a
  computable type — and names the native-routing CIDR as the third sibling
  carrying it.
- `cluster-yaml-sot`: the schema mirrors the new guard, and the
  schema-widening-plus-shim obligation becomes mechanical rather than prose.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `module-interface-contract`
- `cluster-yaml-sot`

## Impact

- Specs: `module-interface-contract`, `cluster-yaml-sot`.
- Code: `tofu/modules/talos-cluster/variables.tf`, `schemas/cluster.schema.json`,
  `scripts/check-shim-key-parity.sh` (new), `Taskfile.yml`.
- Gates: `tofu/modules/talos-cluster/tests/input-validation.tftest.hcl` (four
  new runs: two rejection legs and two negative-space controls covering both
  documented forms); `schemas/fixtures/cluster.invalid.yaml` plus the CI
  assertion loop in `.github/workflows/gitops-validate.yml` (nine violations to
  ten); `task tofu:ci` gains `check:shim-key-parity`, and
  `.github/workflows/tofu-validate.yml` gains `schemas/cluster.schema.json` as a
  trigger path so a schema-only widening still runs it.
- Docs: `tofu/modules/talos-cluster/README.md`, `CHANGELOG.md`,
  `knowledge/reference/cluster-yaml.md`, `knowledge/log.md`.
