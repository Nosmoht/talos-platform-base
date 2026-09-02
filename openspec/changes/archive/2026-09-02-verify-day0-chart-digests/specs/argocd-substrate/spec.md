## ADDED Requirements

### Requirement: Day-0 and steady-state chart pin parity

The module's Day-0 ArgoCD chart version and SHA-256 SHALL equal the version and
`tgz_sha256` in `chart.lock.yaml`, so both delivery paths consume identical
chart bytes. A required check SHALL reject either divergence.

#### Scenario: Cross-path pins are compared

- **WHEN** the ArgoCD substrate invariants run
- **THEN** the Day-0 and steady-state chart versions and SHA-256 digests are
  equal
