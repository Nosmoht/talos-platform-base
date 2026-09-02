## ADDED Requirements

### Requirement: Seed charts are verified before machine-config rendering

Before ArgoCD or Cilium chart output enters a controlplane machine
configuration, the module SHALL verify the downloaded archive against its
base-owned SHA-256 and render the verified local file. A mismatch SHALL fail the
plan/apply before the machine configuration is produced.

#### Scenario: Changed chart bytes cannot enter the seed

- **WHEN** a downloaded seed chart does not match its declared digest
- **THEN** the plan/apply fails before its rendered manifests reach the
  controlplane configuration
