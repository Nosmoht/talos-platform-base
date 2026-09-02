## MODIFIED Requirements

### Requirement: Complete vendored Talos cluster module

The release tarball SHALL contain every tracked root-level `.tf` file in
`tofu/modules/talos-cluster/` together with all module-local runtime files those
files execute or read, including the Day-0 chart verification helper. The
extracted module SHALL initialize without a backend and pass `tofu validate`.

#### Scenario: Every module implementation file ships

- **WHEN** the published tarball's contents are listed
- **THEN** every tracked root-level `.tf` file from
  `tofu/modules/talos-cluster/` is present
- **AND** adding a root-level module `.tf` file without adding it to the payload
  fails the producer validation

#### Scenario: Extracted module validates

- **WHEN** the allowlist-built tarball is extracted and compatible providers
  are available
- **THEN** `tofu init -backend=false` and `tofu validate` succeed in the
  extracted `tofu/modules/talos-cluster/` directory

#### Scenario: Chart verifier ships with the module

- **WHEN** the published tarball is listed
- **THEN** the chart integrity declarations and executable verification helper
  are both present alongside the module
