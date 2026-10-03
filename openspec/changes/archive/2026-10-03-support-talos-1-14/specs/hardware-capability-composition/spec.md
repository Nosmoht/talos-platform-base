## ADDED Requirements

### Requirement: Native capability sinks

For schema pins from 1.14 the module SHALL emit kernel modules as named KernelModuleConfig documents, sysctls as SysctlConfig and labels as KubeNodeConfig. Composition, deduplication and node override precedence SHALL remain unchanged.

#### Scenario: A node requests DRBD on a native schema

- **WHEN** a node requests DRBD on a native schema
- **THEN** its module, sysctls and capability labels reach native documents without legacy duplicates
