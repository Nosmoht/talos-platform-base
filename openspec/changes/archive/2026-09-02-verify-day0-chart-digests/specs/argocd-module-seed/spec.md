## ADDED Requirements

### Requirement: Verified public chart archive

Before either ArgoCD Day-0 render, the module SHALL download the base-pinned
public chart archive into the consumer root's `.terraform` cache, verify its
SHA-256 against a digest declared by the base, and pass that verified local file
to both Helm data sources. A mismatched download or altered cached file SHALL
fail the plan/apply before any manifest enters the Talos machine configuration.

The Day-0 digest SHALL equal the digest in the steady-state ArgoCD
`chart.lock.yaml`; CI SHALL reject a divergence.

#### Scenario: Upstream bytes change under the same version

- **WHEN** the downloaded argo-cd archive does not match the base digest
- **THEN** the plan/apply fails before the seed or CRD render is consumed

#### Scenario: Both paths use identical chart bytes

- **WHEN** the seed and steady-state chart pins are checked
- **THEN** their versions and SHA-256 digests are equal
