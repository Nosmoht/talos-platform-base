## MODIFIED Requirements

### Requirement: Atomic feature entry shape

The schema SHALL require each entry to declare `id`, `name`, `description`,
`discovery_source`, and `presence_predicate`; SHALL constrain `id` to
kebab-case (each id names one atomic hardware predicate, never a composite),
`discovery_source` to one of `nfd`, `talos-machine-config`, `device-plugin`,
or `external-bios-or-firmware`, and `name`, `description`, and
`presence_predicate` to non-empty strings.

#### Scenario: Non-kebab-case id is rejected

- **WHEN** an entry's `id` deviates from kebab-case
- **THEN** schema validation fails on the `id` pattern

#### Scenario: Undeclared discovery source is rejected

- **WHEN** an entry's `discovery_source` is outside the four enumerated
  values
- **THEN** schema validation fails on the `discovery_source` enum

#### Scenario: Informational fields are admitted

- **WHEN** an entry carries `alt_label_keys` as a string array or
  `references` as a URI array
- **THEN** the schema SHALL admit them as informational fields
