# `vault-operator`

**Purpose:** HashiCorp Vault server — KV/PKI/Transit secrets backend referenced by external-secrets, vault-config-operator, and cert-manager.

## Upstream chart source

- **Chart:** [`vault-operator`](oci://ghcr.io/bank-vaults/helm-charts)
- **Pinned version:** `1.23.4`
- **Lock file:** [`chart.lock.yaml`](./chart.lock.yaml) — includes `tgz_sha256` for reproducible renders.

## Namespace

Deploys into namespace `vault`. See [`namespace.yaml`](./namespace.yaml) for the full PSA + PNI label set.

## Declared PNI capabilities

**Provider labels** (on the namespace; see [ADR — Capability Producer/Consumer Symmetry](../../../../docs/adr-capability-producer-consumer-symmetry.md)):

- `platform.io/provide.monitoring-scrape`
- `platform.io/provide.admission-webhook`

**Consumer labels:**

- ``

For the full label vocabulary see [`docs/capability-reference.md`](../../../../docs/capability-reference.md).

## Repo-specific Helm-value overrides

Top-level keys in [`values.yaml`](./values.yaml) — anything not listed below uses the upstream chart's default:

- `watchNamespace`
- `podLabels`
- `resources`

## Known upgrade gotchas

- This is the *operator* (HelmRelease + CRDs), not a running Vault instance — the actual `Vault` CR is deployed by the consumer overlay because keys, unsealing strategy, and storage backend are per-cluster.

## See also

- [`docs/rendered-manifests.md`](../../../../docs/rendered-manifests.md) — how this component is rendered into `_rendered/manifests.yaml`
- [`docs/capability-architecture.md`](../../../../docs/capability-architecture.md) — capability-first contract overview
- [`UPGRADING.md`](../../../../UPGRADING.md) — release-to-release migration steps
