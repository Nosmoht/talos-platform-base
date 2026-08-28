---
sources:
  primary:
    - tofu/modules/talos-cluster/composition.tf
    - tofu/modules/talos-cluster/profiles.tf
    - platform-hardware-features.yaml
references:
  - knowledge/decisions/0009-node-capability-composition.md
  - knowledge/decisions/0003-three-layer-capability-architecture.md
---

# hardware-capability-composition

## Purpose

Resolve each node's `hardware_capabilities` through the base-owned
provisioning-profile catalog into two sinks — schematic content
(extensions, kernel arguments, overlay) and machine-config content
(kernel modules, sysctls, node labels) — deterministically and with hard
plan-time invariant guards. Sources: `tofu/modules/talos-cluster/composition.tf`
(composition and guards), `tofu/modules/talos-cluster/profiles.tf` (the
catalog), and `platform-hardware-features.yaml` (the Layer-C atom
registry). The downstream consumption of the composed schematics is owned
by the `node-image-composition` spec.

Every composed artifact is keyed by node NAME, which is the key of the
`nodes` map itself rather than a field of each entry — so the composition
inherits node-name uniqueness structurally and cannot compose two entries
onto one key. The node identity model is owned by the
`module-interface-contract` spec.

## Requirements

### Requirement: Base-owned provisioning-profile catalog

The provisioning-profile catalog SHALL be a module-local constant — not a
variable — so a consumer selects profiles by id through a capability's
`provisioning_profiles` list but cannot author or redefine a profile
(normative anti-override invariant:
`knowledge/decisions/0009-node-capability-composition.md`). Each profile
binds the parts of a provisioned feature: the atoms it `provides`,
Image-Factory extensions, kernel arguments (or vendor variants), kernel
modules and sysctls.

#### Scenario: Unknown profile id fails the plan

- **WHEN** a capability references a provisioning-profile id absent from
  the catalog
- **THEN** the plan fails with an error naming the offending profiles and
  the catalog keys

### Requirement: Profile kernel arguments are predicate-only

A profile's kernel arguments (top-level or vendor-variant) SHALL be
limited to the arguments named by the `presence_predicate` of the atoms
the profile `provides` (`platform-hardware-features.yaml`). Host tuning
is consumer policy and SHALL NOT be carried by a capability profile — this
is an authoring contract over the base-owned catalog
(`knowledge/decisions/0016-capability-profiles-predicate-only.md`), not a
statement that the schematic kernel-argument sink admits no consumer input:
a consumer sets kernel arguments through the per-image `extra_kernel_args`
input instead (`knowledge/decisions/0017-consumer-image-kernel-args.md`),
which is why a profile argument the predicate does not name still costs the
consumer a key — it is now guarded rather than unreachable. It is asserted
mechanically for the shipped catalog by
`tofu/modules/talos-cluster/tests/profile-predicate-only.tftest.hcl` (in
`task tofu:ci`, offline); the predicate-to-argument mapping itself is read
by a human, because a `presence_predicate` is prose — so a NEW profile's
arguments are review-gated, while the existing ones are pinned by set
equality.

#### Scenario: A profile's argument set equals its predicate's argument set

- **WHEN** the catalog defines a profile that `provides` an atom
- **THEN** the profile's `kernel_args` — and each vendor variant's
  `kernel_args`, where variants exist — contain exactly the arguments that
  atom's `presence_predicate` names, and no others

#### Scenario: The iommu profile's variants carry exactly one argument each

- **WHEN** the catalog's `iommu` profile is read
- **THEN** its `intel` variant's `kernel_args` equal `["intel_iommu=on"]`
  and its `amd` variant's equal `["amd_iommu=on"]` — set equality, so any
  added argument violates this scenario regardless of what it does

#### Scenario: A profile providing no atom carries no kernel argument

- **WHEN** the catalog defines a profile whose `provides` is empty (an
  NFD-detected atom has no machine-config predicate to satisfy)
- **THEN** that profile's `kernel_args` are empty — there is no predicate
  naming an argument for it to carry

### Requirement: Referential-integrity guards

The module SHALL fail the plan when a node references an image id absent
from `var.images` or a capability id absent from
`var.hardware_capabilities`, naming the offending nodes and the defined
keys.

#### Scenario: Undefined reference fails the plan

- **WHEN** a node references an undefined image id or an undefined
  capability id
- **THEN** the plan fails with an error naming the offending node and the
  defined ids

### Requirement: Capability resolution and schematic-sink union

The module SHALL resolve each node's `hardware_capabilities` to the union
of their provisioning profiles and SHALL compose the node's schematic
content as the node image's baseline extensions unioned with the selected
profiles' extensions, plus the node image's `extra_kernel_args` unioned
with the selected profiles' kernel arguments — all sorted and deduplicated
so the schematic content is canonical for the content hash and a verbatim
restatement (image vs. profile, or profile vs. profile) is carried once.

#### Scenario: Profile provisions land in the schematic

- **WHEN** a node holds a capability whose resolved profiles carry
  extensions and kernel arguments
- **THEN** the node's composed schematic contains those extensions
  unioned with the image's baseline extensions and those kernel arguments

#### Scenario: An image's kernel arguments land in the schematic beside the profile arguments

- **WHEN** a node's image declares `extra_kernel_args` and the node also
  holds a capability whose resolved profiles carry kernel arguments
- **THEN** the node's composed schematic kernel arguments contain both the
  image's `extra_kernel_args` and the profiles' kernel arguments

### Requirement: Vendor-variant kernel arguments

A profile with vendor variants SHALL contribute the kernel arguments of
the variant matching the node image's `cpu_vendor`, ignoring the
profile's top-level kernel arguments; a selected variant-bearing profile
with no entry for the node image's `cpu_vendor` SHALL fail the plan.

#### Scenario: cpu_vendor selects the variant

- **WHEN** a node's image declares a `cpu_vendor` for which a selected
  profile defines a variant
- **THEN** that variant's kernel arguments are unioned into the node's
  schematic

#### Scenario: Missing vendor entry fails the plan

- **WHEN** a selected profile has variants but none matching the node
  image's `cpu_vendor`
- **THEN** the plan fails with an error naming the node and the profile

### Requirement: Machine-config sink and generated per-node patch

The module SHALL union the selected profiles' kernel modules (grouped by
module name, parameters sorted for determinism) and sysctls, and SHALL
emit them together with the composed node labels as one generated
per-node machine-config patch, placed before the node's own
`config_patches`; a node whose composition provisions nothing SHALL
receive no generated patch.

#### Scenario: Generated patch carries modules, sysctls and labels

- **WHEN** a node's resolved profiles contribute kernel modules, sysctls
  or node labels
- **THEN** the module emits one generated patch for that node carrying
  `machine.kernel.modules`, `machine.sysctls` and `machine.nodeLabels`
  for exactly the contributed content

#### Scenario: Empty composition emits no patch

- **WHEN** a node's capabilities resolve to no kernel modules, no sysctls
  and no labels
- **THEN** no generated patch is emitted for that node

### Requirement: Node label emission and reserved-namespace provenance

The module SHALL emit, per node, the `emits_label` of each held
capability (in the `platform.io/hardware-capability.*` namespace) plus
one `platform.io/hardware-feature.<atom>` label per atom provided by the
node's resolved profiles. Reserved `platform.io/hardware-feature.*`
labels SHALL derive only from the base catalog's `provides` lists, so
they cannot be emitted through the typed capability path (normative
anti-forgery invariant:
`knowledge/decisions/0009-node-capability-composition.md`). A raw
per-node `config_patches` string can still set `machine.nodeLabels`
directly — the module does not parse patch content; enforcement of that
vector is consumer-cluster Kyverno per
`knowledge/decisions/0009-node-capability-composition.md`.

#### Scenario: Held capability emits both label classes

- **WHEN** a node holds a capability whose resolved profiles provide an
  atom
- **THEN** the node's composed labels carry the capability's
  `emits_label` set to `"true"` and `platform.io/hardware-feature.<atom>`
  set to `"true"`

### Requirement: Layer-C registry alignment

The hardware-feature registry (`platform-hardware-features.yaml`) SHALL
define each Layer-C atom with an id, a discovery source, an authoritative
node label key and a presence predicate; every atom a catalog profile
`provides` SHALL appear in the registry with
`discovery_source: talos-machine-config` and node label key
`platform.io/hardware-feature.<id>`. The module does not read the
registry at plan time — the catalog/registry equivalence is guarded by a
CI cross-reference gate.

#### Scenario: Provisioned atoms are registry-backed

- **WHEN** a catalog profile provides an atom
- **THEN** the registry lists that atom with
  `discovery_source: talos-machine-config` and node label key
  `platform.io/hardware-feature.<id>`

### Requirement: Per-capability symmetry guards

The module SHALL validate every declared capability against its own
profiles, independent of node composition: a provisioned required feature
that none of the capability's own profiles provides, or a
profile-provided atom the capability omits from `requires_features`,
SHALL fail the plan.

#### Scenario: Forward violation fails the plan

- **WHEN** a capability lists a provisioned atom in `requires_features`
  that none of its own provisioning profiles provides
- **THEN** the plan fails with an error naming the capability and the
  atoms

#### Scenario: Inverse violation fails the plan

- **WHEN** a capability's provisioning profiles provide an atom missing
  from its `requires_features`
- **THEN** the plan fails with an error naming the capability and the
  atoms

### Requirement: Composition conflict guards

The module SHALL fail the plan when, on one node, two selected profiles
contribute the same kernel module with differing parameters, or the same
sysctl key with differing values. For kernel arguments, the module SHALL
fail the plan when a selected profile contributes a single-value
kernel-argument key and the node image's `extra_kernel_args` sets that same
key to a differing value (cross-source scoping,
`knowledge/decisions/0017-consumer-image-kernel-args.md`); a key that no
selected profile contributes is not guarded — it is the consumer's own.
Kernel-argument keys that legitimately carry multiple values on one command
line are exempt from the single-value check whenever a selected profile
contributes that key, regardless of whether the image also contributes a
value for it.

#### Scenario: Conflicting sysctl values fail the plan

- **WHEN** two selected profiles set the same sysctl key to different
  values on one node
- **THEN** the plan fails with an error naming the node and the
  conflicting keys

#### Scenario: An image kernel argument conflicting with a profile's fails the plan

- **WHEN** a node's image sets `extra_kernel_args` to a single-value key
  differing from the value a selected profile contributes for that same
  key
- **THEN** the plan fails with an error naming the node, the conflicting
  key, and the profile and image values

#### Scenario: An image kernel argument restating a profile's verbatim is not a conflict

- **WHEN** a node's image `extra_kernel_args` restates, verbatim, a value a
  selected profile already contributes for that key
- **THEN** the plan succeeds and the node's composed kernel arguments carry
  that value exactly once

#### Scenario: A key no selected profile contributes is not guarded

- **WHEN** a node's image `extra_kernel_args` sets a key to two differing
  values (or sets any key) that no selected profile contributes
- **THEN** the plan succeeds and all the image's arguments for that key
  survive into the node's composed kernel arguments

#### Scenario: An exempt multi-value key coexists across a profile source and an image source

- **WHEN** a selected profile contributes an exempt multi-value key and the
  node's image `extra_kernel_args` also sets that key to a different value
- **THEN** the plan succeeds and both values survive into the node's
  composed kernel arguments
