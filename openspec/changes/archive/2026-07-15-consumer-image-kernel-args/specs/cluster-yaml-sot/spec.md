## MODIFIED Requirements

### Requirement: Image catalog entries

The schema SHALL require at least one entry under `images`, SHALL require
each entry to declare `cpu_vendor` (one of `intel`, `amd`, `arm`), and SHALL
constrain the optional fields: `architecture` to `amd64` or `arm64`,
`extensions` to a string array, `extra_kernel_args` to a string array, and
`overlay` (the single-board-computer overlay) to an object requiring `name`
and `image` when present. The schema SHALL reject an `extra_kernel_args`
element carrying whitespace, an element whose key begins with `-`, an
element with an empty key, or any element whose key is `debugfs` —
mirroring the module's `var.images` validations for the declarative path.

#### Scenario: Image without cpu_vendor is rejected

- **WHEN** an `images` entry omits `cpu_vendor` or uses a value outside the
  enumerated vendors
- **THEN** schema validation fails on that image entry

#### Scenario: A well-formed extra_kernel_args list passes the lint gate

- **WHEN** an `images` entry's `extra_kernel_args` contains only elements
  with a non-empty key, no leading `-`, no whitespace, and no `debugfs` key
- **THEN** the lint gate accepts the cluster.yaml

#### Scenario: A debugfs-keyed element is rejected by the schema

- **WHEN** an `images` entry's `extra_kernel_args` contains an element whose
  key is `debugfs`, at any value
- **THEN** schema validation fails on that element — the reachability the
  base's `hard-constraints-check.yml` cannot cover for a repo-root or
  consumer `cluster.yaml`

#### Scenario: A whitespace-bearing, removal-spelled, or empty-key element is rejected by the schema

- **WHEN** an `images` entry's `extra_kernel_args` contains an element with
  whitespace, an element whose key begins with `-`, or an empty-key element
- **THEN** schema validation fails on that element
