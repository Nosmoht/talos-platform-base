## ADDED Requirements

### Requirement: Complete vendored Talos cluster module

The release tarball SHALL contain every tracked root-level `.tf` file in
`tofu/modules/talos-cluster/` together with the module-local runtime files those
files read. The extracted module SHALL initialize without a backend and pass
`tofu validate`, so a consumer can use the signed artifact without obtaining
missing module implementation from the Git checkout.

#### Scenario: Every module implementation file ships

- **WHEN** the published tarball's contents are listed
- **THEN** every tracked root-level `.tf` file from
  `tofu/modules/talos-cluster/` is present
- **AND** adding a root-level module `.tf` file without adding it to the payload
  fails the producer validation

#### Scenario: Extracted module validates

- **WHEN** the allowlist-built tarball is extracted and the provider registry is
  available
- **THEN** `tofu init -backend=false` and `tofu validate` succeed in the
  extracted `tofu/modules/talos-cluster/` directory
