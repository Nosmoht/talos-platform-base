---
sources:
  primary:
    - schemas/hardware-features.schema.json
    - scripts/lint-hardware-features.sh
references:
  - knowledge/decisions/0003-three-layer-capability-architecture.md
---

# hardware-features-vocabulary

## Purpose

Define the Layer-C vocabulary contract: the schema every entry in the
platform hardware-features registry must satisfy, and the lint gate that
enforces it. The registry file itself (`platform-hardware-features.yaml` at
the repo root) is owned by the hardware-capability-composition capability;
this spec owns only the vocabulary — entry shape, atomicity and naming
rules, and the reserved label namespaces the vocabulary feeds (normative:
knowledge/decisions/0003-three-layer-capability-architecture.md).

## Requirements

### Requirement: Registry document shape

The schema SHALL require exactly two top-level fields — `schema_version` (a
digit string, bumped on breaking schema changes) and `hardware_features` (an
array with at least one entry) — and SHALL reject any other top-level key.

#### Scenario: Registry without a schema version is rejected

- **WHEN** a registry document omits `schema_version` or
  `hardware_features`, or carries an undeclared top-level key
- **THEN** schema validation fails and the lint gate exits non-zero

### Requirement: Atomic feature entry shape

The schema SHALL require each entry to declare `id`, `name`, `description`,
`discovery_source`, and `presence_predicate`; SHALL constrain `id` to
kebab-case (each id names one atomic hardware predicate, never a composite),
`discovery_source` to one of `nfd`, `talos-machine-config`, `device-plugin`,
or `external-bios-or-firmware`, and `name`, `description`, and
`presence_predicate` to non-empty strings; and SHALL admit the informational
`alt_label_keys` (string array) and `references` (URI array) fields.

#### Scenario: Non-kebab-case id is rejected

- **WHEN** an entry's `id` deviates from kebab-case
- **THEN** schema validation fails on the `id` pattern

#### Scenario: Undeclared discovery source is rejected

- **WHEN** an entry's `discovery_source` is outside the four enumerated
  values
- **THEN** schema validation fails on the `discovery_source` enum

### Requirement: Unique feature ids

Each entry's `id` SHALL be unique across the registry; lookup is by id,
and array order is non-significant. Uniqueness is a documented
convention, declared in the schema via the `uniqueItemProperties`
keyword — an AJV-only extension that `check-jsonschema` (the validator
behind `scripts/lint-hardware-features.sh`) silently ignores — and is
NOT enforced by the repo's lint gate.

#### Scenario: Duplicate id passes the lint gate

- **WHEN** two `hardware_features` entries declare the same `id`
- **THEN** the `task`-level lint currently passes — `check-jsonschema`
  ignores `uniqueItemProperties` — and uniqueness relies on review

### Requirement: Discovery-conditional label key

The schema SHALL require a non-empty `node_label_key` whenever
`discovery_source` is `nfd`, `talos-machine-config`, or `device-plugin`,
and SHALL admit a null `node_label_key` only for
`external-bios-or-firmware`, where no kernel-observable label exists.

#### Scenario: Label-emitting source without a label key is rejected

- **WHEN** an entry with a label-emitting `discovery_source` omits
  `node_label_key` or sets it null or empty
- **THEN** schema validation fails the conditional requirement

### Requirement: Reserved label namespaces

The Layer-C vocabulary SHALL feed two reserved node-label namespaces
(normative: knowledge/decisions/0003-three-layer-capability-architecture.md):
`platform.io/hardware-feature.<id>` for atomic features (Layer-C-emitted
only — Talos machine config, NFD relay, or device plugin) and
`platform.io/hardware-capability.<cap>` for downstream-defined composite
capabilities. Enforcement against tenant-set keys is consumer-cluster
admission policy; the base ships the vocabulary, not the policy.

#### Scenario: Atomic mirror label uses the feature id

- **WHEN** a registry entry documents a Layer-C mirror label in
  `alt_label_keys`
- **THEN** the key takes the `platform.io/hardware-feature.<id>` form with
  `<id>` equal to the entry's registry id — a documented convention the
  schema does not mechanically check (`alt_label_keys` is informational)

#### Scenario: Composite labels stay out of the atomic namespace

- **WHEN** a downstream composite capability emits a node label
- **THEN** the key lands in `platform.io/hardware-capability.*`, never in
  the atomic `platform.io/hardware-feature.*` namespace — a documented
  convention the schema does not mechanically check

### Requirement: Lint gate behavior

The `scripts/lint-hardware-features.sh` gate SHALL validate its target file
(defaulting to the repo-root registry) against
`schemas/hardware-features.schema.json` using `check-jsonschema` (with a
`uvx` fallback when the binary is absent), and SHALL exit `0` on a passing
registry, `1` on at least one schema violation, and `2` on an environment or
argument error.

#### Scenario: Passing registry yields exit 0 with a feature count

- **WHEN** the target registry satisfies the schema
- **THEN** the script exits `0` and prints an `OK` summary with the number
  of features validated

#### Scenario: Missing registry or validator yields exit 2

- **WHEN** the target registry or the schema file does not exist, or
  neither `check-jsonschema` nor `uvx` is on `PATH`
- **THEN** the script exits `2` with an error on stderr
