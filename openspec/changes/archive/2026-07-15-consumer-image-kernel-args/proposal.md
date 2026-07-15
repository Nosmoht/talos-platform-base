## Why

A consumer cluster has no supported way to set custom kernel command-line
arguments on nodes that boot via UKI/systemd-boot (the Talos v1.10+ default
for fresh metal UEFI installs). `tofu/modules/talos-cluster` builds the
Image-Factory schematic field `customization.extraKernelArgs` — the
UKI-correct sink — but feeds it exclusively from the base-owned
`provisioning_profiles` catalog; `machine.install.extraKernelArgs` is ignored
under UKI, so the only existing escape hatch (`config_patches`) silently
no-ops for this purpose.

Shipping the union alone (an image's kargs unioned into the schematic sink)
without also re-scoping the existing kernel-arg conflict guard is a silent
correctness defect: the guard reads profile-resolved args only, so a
consumer arg colliding with a profile arg on the same single-value key would
land on the cmdline alongside it with no error, and the kernel picks
arbitrarily between the two. Re-sourcing the guard onto the whole unioned set
(the naive fix) constructs a NEW false-positive class: it groups every arg on
a node by key, including two args from the same consumer list, which
hard-fails legitimate idioms such as the per-huge-page-size
`hugepagesz=`/`hugepages=` pairing. The chosen guard shape is instead
**cross-source-scoped**: a key is checked only when a selected profile
contributes it AND the image sets a differing value.

Full rationale, rejected alternatives and the guard-scoping decision:
`knowledge/decisions/0017-consumer-image-kernel-args.md` (issue #169).

## What Changes

- `module-interface-contract` gains a requirement: `var.images` accepts an
  optional `extra_kernel_args` (`list(string)`, default `[]`) and rejects at
  plan time an element carrying whitespace, an element whose key begins with
  `-`, an element with an empty key, or any element whose key is `debugfs` —
  naming the offending image and element.
- `hardware-capability-composition` gains three MODIFIED requirements: the
  "predicate-only" requirement's parenthetical (which asserted the module
  exposes no consumer kernel-argument input) is corrected; the
  capability-resolution/schematic-sink-union requirement is widened to union
  the image's `extra_kernel_args`; the composition-conflict-guards requirement
  is re-scoped to the cross-source predicate above.
- `cluster-yaml-sot` gains a MODIFIED requirement: the image catalog entry
  shape gains `extra_kernel_args` (a string array), mirroring the module's
  lexical validation rules so the declarative path rejects the same four
  malformed shapes the module does.
- No requirement is removed. An existing consumer setting no
  `extra_kernel_args` composes to a byte-identical schematic (the type's
  `optional(list(string), [])` default).

## Capabilities

### New Capabilities

None. The behavior extends three existing capabilities.

### Modified Capabilities

- `module-interface-contract`: one ADDED requirement (image kernel-argument
  input validation).
- `hardware-capability-composition`: three MODIFIED requirements (predicate-
  only parenthetical correction, schematic-sink union, conflict guards).
- `cluster-yaml-sot`: one MODIFIED requirement (image catalog entries).

## Impact

- Specs: `openspec/specs/module-interface-contract/spec.md`,
  `openspec/specs/hardware-capability-composition/spec.md`,
  `openspec/specs/cluster-yaml-sot/spec.md` — merged in on archive (this
  change is archived in the same PR that ships the code, per
  `scripts/check-spec-staleness.py` globbing `openspec/specs/*/spec.md` only).
- Code: `tofu/modules/talos-cluster/variables.tf` (the input + four
  validations), `tofu/modules/talos-cluster/composition.tf` (the union + the
  cross-source guard + the error-message rewrite),
  `schemas/cluster.schema.json` (the schema mirror),
  `tofu/modules/talos-cluster/examples/complete/{main.tf,cluster.yaml}` (the
  reference consumer shim), `cluster.yaml.example`.
- Gates: `tests/image-kernel-args.tftest.hcl` (new, offline),
  `tests/conflict-guards.tftest.hcl` and `tests/input-validation.tftest.hcl`
  (new runs), `tests/composition.tftest.hcl` (one new network run),
  `schemas/fixtures/cluster.invalid.yaml` + `.github/workflows/gitops-validate.yml`
  (the six-way schema red-green loop + the module worked-example lint step).
- Docs: `knowledge/decisions/0017-consumer-image-kernel-args.md` (new ADR),
  `knowledge/architecture/capability-composition.md`,
  `knowledge/reference/cluster-yaml.md`, `knowledge/glossary.md`,
  `AGENTS.md` §Key Terms, `UPGRADING.md` (new `v5.1.0` section).
