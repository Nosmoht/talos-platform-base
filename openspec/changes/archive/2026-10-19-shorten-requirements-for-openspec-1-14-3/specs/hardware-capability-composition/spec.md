## MODIFIED Requirements

### Requirement: Profile kernel arguments are predicate-only

A profile's kernel arguments (top-level or vendor-variant) SHALL be
limited to the arguments named by the `presence_predicate` of the atoms
the profile `provides` (`platform-hardware-features.yaml`). Host tuning
is consumer policy and SHALL NOT be carried by a capability profile — an
authoring contract over the base-owned catalog
(`knowledge/decisions/0016-capability-profiles-predicate-only.md`).

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

#### Scenario: A consumer sets kernel arguments through the image input

- **WHEN** a consumer needs a kernel argument that no profile's predicate
  names
- **THEN** it sets the argument through the per-image `extra_kernel_args`
  input (`knowledge/decisions/0017-consumer-image-kernel-args.md`), because
  the predicate-only contract does not mean the schematic kernel-argument
  sink admits no consumer input
- **AND** a profile argument the predicate does not name would still cost
  the consumer that key — guarded rather than unreachable

#### Scenario: Shipped profiles are pinned, new ones review-gated

- **WHEN** `task tofu:ci` runs offline
- **THEN** `tofu/modules/talos-cluster/tests/profile-predicate-only.tftest.hcl`
  pins the shipped catalog's profile arguments by set equality
- **AND** the predicate-to-argument mapping itself is read by a human,
  because a `presence_predicate` is prose, so a NEW profile's arguments are
  review-gated

### Requirement: Capability resolution and schematic-sink union

The module SHALL resolve each node's `hardware_capabilities` to the union
of their provisioning profiles and SHALL compose the node's schematic
content as the node image's baseline extensions unioned with the selected
profiles' extensions, plus the node image's `extra_kernel_args` unioned
with the selected profiles' kernel arguments — all sorted and
deduplicated.

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

#### Scenario: Composed schematic content is canonical

- **WHEN** a node's composed extensions and kernel arguments are emitted
- **THEN** they are sorted and deduplicated, so the schematic content is
  canonical for the content hash
- **AND** a verbatim restatement (image vs. profile, or profile vs.
  profile) is carried once

### Requirement: Node label emission and reserved-namespace provenance

The module SHALL emit, per node, the `emits_label` of each held
capability (in the `platform.io/hardware-capability.*` namespace) plus
one `platform.io/hardware-feature.<atom>` label per atom provided by the
node's resolved profiles. Reserved `platform.io/hardware-feature.*`
labels SHALL derive only from the base catalog's `provides` lists
(normative anti-forgery invariant:
`knowledge/decisions/0009-node-capability-composition.md`).

#### Scenario: Held capability emits both label classes

- **WHEN** a node holds a capability whose resolved profiles provide an
  atom
- **THEN** the node's composed labels carry the capability's
  `emits_label` set to `"true"` and `platform.io/hardware-feature.<atom>`
  set to `"true"`

#### Scenario: Reserved feature labels cannot come through a capability

- **WHEN** a node's composed `platform.io/hardware-feature.*` labels are
  traced to their source
- **THEN** each derives from a base catalog `provides` list, so none can be
  emitted through the typed capability path

#### Scenario: A raw config patch label is outside the module's guard

- **WHEN** a raw per-node `config_patches` string sets `machine.nodeLabels`
  directly
- **THEN** the module does not parse patch content and still applies it
- **AND** enforcement of that vector is consumer-cluster Kyverno per
  `knowledge/decisions/0009-node-capability-composition.md`

### Requirement: Composition conflict guards

The module SHALL fail the plan when, on one node, two selected profiles
contribute the same kernel module with differing parameters, or the same
sysctl key with differing values, or when a selected profile contributes a
single-value kernel-argument key and the node image's `extra_kernel_args`
sets that same key to a differing value (cross-source scoping,
`knowledge/decisions/0017-consumer-image-kernel-args.md`).

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

#### Scenario: A kernel-argument key no profile contributes is unguarded

- **WHEN** a kernel-argument key is contributed by no selected profile
- **THEN** it is not guarded — it is the consumer's own

#### Scenario: A multi-value kernel-argument key is exempt

- **WHEN** a selected profile contributes a kernel-argument key that
  legitimately carries multiple values on one command line
- **THEN** that key is exempt from the single-value check, regardless of
  whether the image also contributes a value for it
