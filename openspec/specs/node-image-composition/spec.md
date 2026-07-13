---
sources:
  secondary:
    - tofu/modules/talos-cluster/main.tf
references:
  - AGENTS.md §Hard Constraints — No SecureBoot
  - knowledge/decisions/0011-substrate-hard-constraints.md
---

# node-image-composition

## Purpose

Describe the Image-Factory region of
`tofu/modules/talos-cluster/main.tf`: committing each node's composed
schematic description to a Talos Image-Factory schematic and deriving the
per-(schematic, architecture) metal-installer URL, with content-hash dedup
so identical nodes share one schematic. The region lives in `main.tf`,
whose primary owner is the `cluster-bootstrap-lifecycle` spec; this spec
owns the region descriptively. The upstream composition of the schematic
content (baseline image unioned with capability-profile provisions) is
owned by the `hardware-capability-composition` spec.

## Requirements

### Requirement: Per-node schematic content

The module SHALL commit each distinct composed schematic with
`customization.systemExtensions.officialExtensions` carrying the resolved
extension set, `customization.extraKernelArgs` present only when the
composed kernel-argument list is non-empty, and a top-level `overlay`
present only when the node's image declares one.

#### Scenario: Empty composition yields the default installer

- **WHEN** a node's composed schematic carries no extensions, no kernel
  arguments and no overlay
- **THEN** the committed schematic bakes an empty `officialExtensions`
  list and no `extraKernelArgs` or `overlay` keys — the resolved installer
  is the default Talos installer without system extensions

### Requirement: Exact extension resolution against the Image Factory

The module SHALL resolve the declared extension names against the Talos
Image Factory at the effective install version (`talos_install_version`,
falling back to `talos_version`) and SHALL commit exactly the declared
set: the provider's substring-matching resolution is intersected back to
the declared names, and the plan SHALL fail when the resolved set is not
set-equal to the declared set.

#### Scenario: Non-canonical extension name fails the plan

- **WHEN** a composed schematic declares an extension name that does not
  resolve to an exactly matching canonical Image Factory package (a typo,
  or a short name the substring filter would expand)
- **THEN** the plan fails with an error naming the declared and resolved
  extension sets and the effective Talos version

#### Scenario: Substring expansion cannot bake unrequested extensions

- **WHEN** the Image Factory resolution returns package names beyond the
  declared set via substring matching
- **THEN** only the declared names are committed into the schematic's
  `officialExtensions`

### Requirement: Content-hash schematic dedup

The module SHALL create one Image-Factory schematic resource per distinct
schematic content hash and one installer URL per distinct
(content hash, architecture) pair, so nodes with identical effective
composition share a single schematic and installer while unique nodes get
unique images.

#### Scenario: Identical nodes share one schematic

- **WHEN** two nodes compose to identical extension, kernel-argument and
  overlay content
- **THEN** both nodes map to the same content hash and the module creates
  a single schematic resource that both nodes' installer URLs reference

### Requirement: Non-SecureBoot installer URL selection

The module SHALL derive every node's installer image from the Image
Factory URL set's plain installer field for platform `metal` at the
effective install version (normative: AGENTS.md §Hard Constraints — No
SecureBoot; see `knowledge/decisions/0011-substrate-hard-constraints.md`).
ARM single-board computers are expressed as `architecture = "arm64"` plus
a schematic overlay; the platform stays `metal`.

#### Scenario: Composed installer URL is not a SecureBoot image

- **WHEN** the module derives the installer URL for any
  (schematic, architecture) pair
- **THEN** the URL is read from `urls.installer` — never
  `urls.installer_secureboot` — and the composed installer URL contains no
  `-secureboot` segment

### Requirement: Installer availability gate

The module SHALL fail at plan time when the Image Factory returns no
metal-installer URL for a composed (schematic, architecture) pair.

#### Scenario: Unproducible schematic/architecture combination fails the plan

- **WHEN** a schematic and architecture combination resolves to an empty
  installer URL from the Image Factory
- **THEN** the plan fails with an error naming the schematic hash and the
  architecture
