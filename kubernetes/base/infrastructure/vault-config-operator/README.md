# `vault-config-operator`

**Purpose:** Vault Config Operator — manages Vault policies, auth-methods, and engine mounts via CRDs so secret configuration is GitOps-tracked.

## Upstream chart source

- **Chart:** [`vault-config-operator`](https://redhat-cop.github.io/vault-config-operator)
- **Pinned version:** `v0.8.38`
- **Lock file:** [`chart.lock.yaml`](./chart.lock.yaml) — includes `tgz_sha256` for reproducible renders.

## Namespace

Deploys into namespace `(no namespace.yaml)`. See [`namespace.yaml`](./namespace.yaml) for the full PSA + PNI label set.

## Declared PNI capabilities

**Provider labels** (on the namespace; see [ADR — Capability Producer/Consumer Symmetry](../../../../docs/adr-capability-producer-consumer-symmetry.md)):

(none)

**Consumer labels:**

(none)

For the full label vocabulary see [`docs/capability-reference.md`](../../../../docs/capability-reference.md).

## Repo-specific Helm-value overrides

Top-level keys in [`values.yaml`](./values.yaml) — anything not listed below uses the upstream chart's default:

- `replicaCount`
- `enableMonitoring`
- `enableCertManager`
- `resources`
- `env`
- `volumes`
- `volumeMounts`

## Known upgrade gotchas

- Reads Vault root token from a Kubernetes Secret named `vault-config-operator-token` in this namespace — consumer overlay creates the Secret via External Secrets from Vault itself, a chicken-and-egg the consumer initialises by hand on Day-0.

## See also

- [`docs/rendered-manifests.md`](../../../../docs/rendered-manifests.md) — how this component is rendered into `_rendered/manifests.yaml`
- [`docs/capability-architecture.md`](../../../../docs/capability-architecture.md) — capability-first contract overview
- [`UPGRADING.md`](../../../../UPGRADING.md) — release-to-release migration steps
