## ADDED Requirements

### Requirement: Native schema example

The canonical example SHALL use Talos 1.14.2 and Kubernetes 1.37.1 with caller patches compatible with the native schema. Existing consumers SHALL retain their bootstrap schema pin during an OS-only upgrade.

#### Scenario: A consumer copies the example

- **WHEN** a consumer copies the example
- **THEN** its version pins and example patches target the native Talos 1.14 schema
