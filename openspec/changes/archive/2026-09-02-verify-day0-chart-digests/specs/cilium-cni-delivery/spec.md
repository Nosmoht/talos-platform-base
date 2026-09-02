## ADDED Requirements

### Requirement: Verified public chart archive

Before the Cilium Day-0 render, the module SHALL download the chart archive into
the consumer root's `.terraform` cache, verify its SHA-256 against the digest
declared by the base, and pass only that verified local file to the Helm data
source. A mismatched download or altered cached file SHALL fail the plan/apply
before any manifest enters the Talos machine configuration.

A consumer MAY select an HTTP mirror through `cilium_chart_repository`, but the
mirror SHALL serve bytes matching the same base-owned digest.

#### Scenario: Repository serves different bytes

- **WHEN** the selected Cilium repository returns an archive whose SHA-256 does
  not match the base pin
- **THEN** the plan/apply fails before the Cilium seed is rendered
