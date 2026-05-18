# `dex`

**Purpose:** Dex OIDC provider — federates upstream identity (GitHub, OIDC, LDAP) into a single in-cluster OIDC issuer consumed by ArgoCD, Grafana, and kubeconfig OIDC login.

## Upstream chart source

- **Chart:** [`dex`](https://charts.dexidp.io)
- **Pinned version:** `0.24.0`
- **Lock file:** [`chart.lock.yaml`](./chart.lock.yaml) — includes `tgz_sha256` for reproducible renders.

## Namespace

Deploys into namespace `dex`. See [`namespace.yaml`](./namespace.yaml) for the full PSA + PNI label set.

## Declared PNI capabilities

**Provider labels** (on the namespace; see [ADR — Capability Producer/Consumer Symmetry](../../../../docs/adr-capability-producer-consumer-symmetry.md)):

- ``

**Consumer labels:**

- `platform.io/consume.cnpg-postgres`
- `platform.io/consume.gateway-backend`
- `platform.io/consume.controlplane-egress`

For the full label vocabulary see [`docs/capability-reference.md`](../../../../docs/capability-reference.md).

## Repo-specific Helm-value overrides

Top-level keys in [`values.yaml`](./values.yaml) — anything not listed below uses the upstream chart's default:

- `replicaCount`
- `strategy`
- `podDisruptionBudget`
- `config`
- `resources`
- `securityContext`
- `podSecurityContext`
- `volumes`
- `volumeMounts`

## Known upgrade gotchas

(none documented yet)

## See also

- [`docs/rendered-manifests.md`](../../../../docs/rendered-manifests.md) — how this component is rendered into `_rendered/manifests.yaml`
- [`docs/capability-architecture.md`](../../../../docs/capability-architecture.md) — capability-first contract overview
- [`UPGRADING.md`](../../../../UPGRADING.md) — release-to-release migration steps
