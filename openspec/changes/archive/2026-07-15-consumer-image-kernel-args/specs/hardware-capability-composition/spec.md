## MODIFIED Requirements

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
