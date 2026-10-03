## MODIFIED Requirements

### Requirement: Version constraints and backend agnosticism

The module SHALL require OpenTofu/Terraform `>= 1.9.0` and constrain its
providers to `siderolabs/talos` `0.12.0` (an exact stable pin),
`hashicorp/helm` `>= 2.12, < 3.0.0` (local template rendering only — no Helm
release or apply), and `hashicorp/local` `>= 2.4` plus `hashicorp/null`
`>= 3.2` (used only for the ArgoCD CRD apply path). The talos pin SHALL be
exact to bind the generated configuration contract to a tested stable release.
A consumer root's constraint SHALL admit 0.12.0; any constraint excluding it
SHALL fail initialization. The `>= 1.9.0` floor (raised from `>= 1.7.0`)
is required because the `cilium_self_management` guard validations below
reference OTHER variables in their `condition` — a cross-variable `validation`
feature OpenTofu introduced at 1.9 — and is parsed at module load regardless of
any toggle's value, so it is a permanent, consumer-visible compatibility floor
for one opt-in, default-off feature. The module SHALL declare no state backend
— the backend is the caller's concern and must be encrypted, because the
machine secrets land in state.

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

- **WHEN** a consumer root declares a `siderolabs/talos` version range admitting 0.12.0
  alongside this module
- **THEN** initialization succeeds and resolves to the module's exact
  stable pin, because it satisfies both constraints

#### Scenario: A caller root constraint that excludes the pin does not resolve

- **WHEN** a consumer root declares a `siderolabs/talos` constraint that
  excludes the pinned version — a different exact pin, or a lower bound above it
- **THEN** initialization fails, because no release satisfies both constraints

#### Scenario: A caller root's existing lock must be upgraded

- **WHEN** a consumer root carries a dependency lock recording an older
  `siderolabs/talos` selection
- **THEN** a plain initialization fails on that locked selection and the lock
  must be refreshed before the pinned version is installed
