## ADDED Requirements

### Requirement: Version-compatible bootstrap

The module SHALL support Talos 1.14.2 native configurations for both roles while preserving the legacy format for schema pins below 1.14. The installer pin SHALL NOT choose the schema format.

#### Scenario: A consumer upgrades only its installer pin

- **WHEN** a consumer upgrades only its installer pin
- **THEN** the generated configuration retains its bootstrap schema format
