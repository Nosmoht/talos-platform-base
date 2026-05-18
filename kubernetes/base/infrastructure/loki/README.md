# `loki`

**Purpose:** Grafana Loki — log aggregation and query backend; the active implementation of the logs-storage and logs-query capabilities.

## Upstream chart source

- **Chart:** [`loki`](https://grafana.github.io/helm-charts)
- **Pinned version:** `6.53.0`
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

- `deploymentMode`
- `loki`
- `global`
- `singleBinary`
- `read`
- `write`
- `backend`
- `serviceMonitor`
- `lokiCanary`

## Known upgrade gotchas

- The S3 endpoint is set in the consumer overlay, not the base `values.yaml` — base previously hardcoded a homelab MinIO endpoint, fixed in Phase 1.5.

## See also

- [`docs/rendered-manifests.md`](../../../../docs/rendered-manifests.md) — how this component is rendered into `_rendered/manifests.yaml`
- [`docs/capability-architecture.md`](../../../../docs/capability-architecture.md) — capability-first contract overview
- [`UPGRADING.md`](../../../../UPGRADING.md) — release-to-release migration steps
