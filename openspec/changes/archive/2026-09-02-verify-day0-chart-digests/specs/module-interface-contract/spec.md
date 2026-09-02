## ADDED Requirements

### Requirement: Seed chart versions require base digest pins

The `argocd_chart_version` and `cilium_chart_version` inputs SHALL accept the
base-pinned versions, including `null` resolving to each declared default, and
SHALL reject any other version for which the base declares no SHA-256 digest.

#### Scenario: Consumer selects an unpinned chart version

- **WHEN** either chart-version input names a version other than its base pin
- **THEN** the plan fails on that input and states that no verified digest is
  declared for the requested version
