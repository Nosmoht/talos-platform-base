# Track Talos v1.14.4 in examples and validation

## Why

Talos v1.14.3 and v1.14.4 are released. Both are patch releases on the 1.14
line. Two requirements still name v1.14.2 as the supported native version and
as the canonical example's version, so the example, fixtures and `talosctl`
validation pin cannot move without falsifying them.

## What Changes

- `cluster-bootstrap-lifecycle`: "Version-compatible bootstrap" names Talos
  1.14.4 instead of 1.14.2.
- `cluster-yaml-sot`: "Native schema example" names Talos 1.14.4 instead of
  1.14.2. Kubernetes stays at 1.37.1, the version Talos 1.14.4 ships.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `cluster-bootstrap-lifecycle`
- `cluster-yaml-sot`

## Impact

- Code: example, fixture, test and validation-script version strings, and the
  `talosctl` pin in `mise.toml` / `mise.lock`. No module logic changes, and the
  module still pins no Talos version: `talos_version` and
  `talos_install_version` remain consumer inputs.
