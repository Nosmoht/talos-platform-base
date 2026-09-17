## 1. Floor and reference values

- [x] 1.1 Set `rollOutCiliumPods: true` in `tofu/modules/talos-cluster/helm/cilium-values.yaml`; amend the file's charter comment and its now-false "a consumer override replaces any key here" line.
- [x] 1.2 Set the same key in `kubernetes/bootstrap/cilium/values.yaml`.

## 2. Bindings

- [x] 2.1 Add `scripts/check-cilium-rollout-pods-key.sh` and wire it into `tofu:ci`.
- [x] 2.2 Add the named `cilium_effective_values.rollOutCiliumPods` assertion to `tests/input-validation.tftest.hcl`.
- [x] 2.3 Replace the no-roll assert in `tests/composition.tftest.hcl` with two dedicated runs: the annotation is stamped, and an override removes it again.
- [x] 2.4 Refresh the golden fixture and rewrite its provenance header.

## 3. Documents that carried the now-false claim

- [x] 3.1 `variables.tf`, `README.md` (3 places), `schemas/cluster.schema.json`, `cluster.yaml.example`, `examples/complete/cluster.yaml`.
- [x] 3.2 `UPGRADING.md` §3 of the values-source section, the adoption residual, and the break-glass step 4 (which stays mandatory).
- [x] 3.3 New `UPGRADING.md` section for the tag; `CHANGELOG.md` MAJOR entry.

## 4. Specs

- [x] 4.1 `cilium-cni-delivery`: the floor's enumerated contents, the reference-values file, and the single-source no-movement clause.
- [x] 4.2 `module-interface-contract`: re-scope the byte-identity requirement and its scenario to the input.
