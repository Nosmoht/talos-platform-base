# `external-secrets`

**Purpose:** External Secrets Operator — synchronises Kubernetes Secrets from Vault, AWS SM, and other backends declared in ExternalSecret CRs.

## Upstream chart source

- **Chart:** [`external-secrets`](https://charts.external-secrets.io)
- **Pinned version:** `2.0.1`
- **Lock file:** [`chart.lock.yaml`](./chart.lock.yaml) — includes `tgz_sha256` for reproducible renders.

## Namespace

Deploys into namespace `external-secrets`. See [`namespace.yaml`](./namespace.yaml) for the full PSA + PNI label set.

## Declared PNI capabilities

**Provider labels** (on the namespace; see [ADR — Capability Producer/Consumer Symmetry](../../../../docs/adr-capability-producer-consumer-symmetry.md)):

- `platform.io/provide.monitoring-scrape`

**Consumer labels:**

- `platform.io/consume.controlplane-egress`
- `platform.io/consume.monitoring-scrape`
- `platform.io/consume.vault-secrets`

For the full label vocabulary see [`docs/capability-reference.md`](../../../../docs/capability-reference.md).

## Repo-specific Helm-value overrides

Top-level keys in [`values.yaml`](./values.yaml) — anything not listed below uses the upstream chart's default:

- `installCRDs`
- `processClusterStore`
- `processClusterExternalSecret`
- `processClusterGenerator`
- `processClusterPushSecret`
- `podLabels`
- `webhook`
- `certController`
- `serviceMonitor`
- `resources`

## Known upgrade gotchas

- ClusterSecretStores referencing Vault are NOT shipped here — they live in the consumer overlay so per-cluster Vault endpoints, mounts, and auth-methods stay out of the base.

## See also

- [`docs/rendered-manifests.md`](../../../../docs/rendered-manifests.md) — how this component is rendered into `_rendered/manifests.yaml`
- [`docs/capability-architecture.md`](../../../../docs/capability-architecture.md) — capability-first contract overview
- [`UPGRADING.md`](../../../../UPGRADING.md) — release-to-release migration steps
