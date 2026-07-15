## ADDED Requirements

### Requirement: Image kernel-argument input validation

The module SHALL admit an optional per-image `extra_kernel_args` string list
(default `[]`) on `var.images`, unioned into the node's schematic
`customization.extraKernelArgs` alongside the selected provisioning profiles'
kernel arguments. The module SHALL reject at plan time, via a validation
naming the offending image and element: an element containing whitespace; an
element whose key begins with `-`; an element with an empty key; and any
element whose key is `debugfs`, regardless of its value. This module-level
validation is the enforcement point for every caller, including one wiring
the module interface by hand; the declarative `cluster.yaml` path is guarded
in addition by the `cluster-yaml-sot` capability's schema mirror — the module
validation is not the only enforcement point.

#### Scenario: Whitespace-bearing element is rejected

- **WHEN** an image's `extra_kernel_args` contains an element with whitespace
- **THEN** the plan fails with an error naming the offending image and
  element — a whitespace-joined element would smuggle a second argument past
  the kernel-argument conflict guard, which keys on `=` and never on
  whitespace

#### Scenario: Removal-spelling element is rejected

- **WHEN** an image's `extra_kernel_args` contains an element whose key
  begins with `-`
- **THEN** the plan fails with an error naming the offending image and
  element — the karg removal/prefix spelling is out of scope and the
  conflict guard cannot see it

#### Scenario: Empty-key element is rejected

- **WHEN** an image's `extra_kernel_args` contains the bare empty string, or
  an element beginning with `=` (which keys as the empty string)
- **THEN** the plan fails with an error naming the offending image and
  element

#### Scenario: debugfs-keyed element is rejected regardless of value

- **WHEN** an image's `extra_kernel_args` contains an element whose key is
  `debugfs`, at any value
- **THEN** the plan fails with an error naming the offending image and
  element, and the error text does not contain the AGENTS.md Hard-Constraint
  forbidden value literal

#### Scenario: A well-formed list is accepted

- **WHEN** an image's `extra_kernel_args` contains only elements with a
  non-empty key, no leading `-`, no whitespace, and no `debugfs` key
- **THEN** the plan proceeds past this validation
