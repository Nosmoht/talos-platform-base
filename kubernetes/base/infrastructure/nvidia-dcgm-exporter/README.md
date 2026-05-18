# `nvidia-dcgm-exporter`

**Purpose:** NVIDIA DCGM Exporter — exposes per-GPU metrics (utilisation, memory, temperature) to Prometheus on GPU nodes.

## Upstream chart source

- **Chart:** [`dcgm-exporter`](https://nvidia.github.io/dcgm-exporter/helm-charts)
- **Pinned version:** `4.8.1`
- **Lock file:** [`chart.lock.yaml`](./chart.lock.yaml) — includes `tgz_sha256` for reproducible renders.

## Namespace

Deploys into namespace `nvidia-dcgm-exporter`. See [`namespace.yaml`](./namespace.yaml) for the full PSA + PNI label set.

## Declared PNI capabilities

**Provider labels** (on the namespace; see [ADR — Capability Producer/Consumer Symmetry](../../../../docs/adr-capability-producer-consumer-symmetry.md)):

- ``

**Consumer labels:**

- ``

For the full label vocabulary see [`docs/capability-reference.md`](../../../../docs/capability-reference.md).

## Repo-specific Helm-value overrides

Top-level keys in [`values.yaml`](./values.yaml) — anything not listed below uses the upstream chart's default:

- `runtimeClassName`
- `arguments`
- `tolerations`
- `affinity`
- `serviceMonitor`

## Known upgrade gotchas

(none documented yet)

## See also

- [`docs/rendered-manifests.md`](../../../../docs/rendered-manifests.md) — how this component is rendered into `_rendered/manifests.yaml`
- [`docs/capability-architecture.md`](../../../../docs/capability-architecture.md) — capability-first contract overview
- [`UPGRADING.md`](../../../../UPGRADING.md) — release-to-release migration steps
