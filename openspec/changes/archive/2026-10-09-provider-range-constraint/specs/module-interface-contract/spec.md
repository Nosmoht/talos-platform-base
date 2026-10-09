## MODIFIED Requirements

### Requirement: Version constraints and backend agnosticism

The module SHALL require OpenTofu/Terraform `>= 1.9.0` and constrain its
providers to `siderolabs/talos` `>= 0.12.0, < 0.13.0-0`, `hashicorp/helm`
`>= 2.12, < 3.0.0` (local template rendering only — no Helm release or
apply), and `hashicorp/local` `>= 2.4` plus `hashicorp/null` `>= 3.2` (used
only for the ArgoCD CRD apply path). The talos constraint SHALL take the form
ADR-0029 §Provider constraints sets: its floor, 0.12.0, is the oldest version
the module's code needs (the first stable release with the Talos 1.14
machinery), and its upper bound excludes the 0.13 line, its prereleases
included. The committed module lock SHALL select the floor, so the provider
probe, the configuration validation and the module's tests run against it;
later admitted 0.12.x releases are not exercised by those gates. A consumer
root's constraint SHALL admit a version in the range; any constraint
excluding every admitted version SHALL fail initialization. The `>= 1.9.0`
floor (raised from `>= 1.7.0`) is required because the
`cilium_self_management` guard validations below reference OTHER variables in
their `condition` — a cross-variable `validation` feature OpenTofu introduced
at 1.9 — and is parsed at module load regardless of any toggle's value, so it
is a permanent, consumer-visible compatibility floor for one opt-in,
default-off feature. The module SHALL declare no state backend — the backend
is the caller's concern and must be encrypted, because the machine secrets
land in state.

#### Scenario: No backend is imposed on the caller

- **WHEN** the module is initialized from any caller root
- **THEN** it declares no backend block and enforces only the version
  constraints above

#### Scenario: A pre-1.9 caller cannot load the module

- **WHEN** a caller initializes the module with OpenTofu/Terraform
  `< 1.9.0`
- **THEN** module load fails on the `required_version` constraint,
  regardless of whether `cilium_self_management` is set

#### Scenario: A caller root declaring a provider range still resolves

- **WHEN** a consumer root declares a `siderolabs/talos` constraint admitting
  a version in the module's range — an exact `0.12.0` pin or a range such as
  `>= 0.7.0, < 1.0.0`
- **THEN** initialization succeeds and resolves to a version both constraints
  admit

#### Scenario: A caller root constraint that excludes the pin does not resolve

- **WHEN** a consumer root declares a `siderolabs/talos` constraint that
  excludes every version in the module's range — an exact `0.11.0` pin,
  `~> 0.11.0`, or a lower bound at 0.13.0
- **THEN** initialization fails, because no release satisfies both constraints

#### Scenario: A caller root pinning a next-line prerelease does not resolve

- **WHEN** a consumer root pins a 0.13.0 prerelease exactly
- **THEN** initialization fails, because the module's `-0` upper bound
  excludes it

#### Scenario: A caller root's existing lock must be upgraded

- **WHEN** a consumer root carries a dependency lock recording a
  `siderolabs/talos` selection below 0.12.0
- **THEN** a plain initialization fails on that locked selection and the lock
  must be refreshed before a version in the range is installed

#### Scenario: A caller root's lock at the floor needs no refresh

- **WHEN** a consumer root carries a dependency lock recording
  `siderolabs/talos` 0.12.0
- **THEN** a plain initialization succeeds and keeps that selection
