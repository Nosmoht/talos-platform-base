# `alloy`

**Purpose:** Grafana Alloy agent — collects logs and metrics from cluster workloads and forwards them to the Loki/Prometheus stack via Prometheus remote-write and Loki push.

## Upstream chart source

- **Chart:** [`alloy`](https://grafana.github.io/helm-charts)
- **Pinned version:** `1.6.0`
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

- `controller`
- `alloy`
- `serviceMonitor`

## Known upgrade gotchas

(none documented yet)

## See also

- [`docs/rendered-manifests.md`](../../../../docs/rendered-manifests.md) — how this component is rendered into `_rendered/manifests.yaml`
- [`docs/capability-architecture.md`](../../../../docs/capability-architecture.md) — capability-first contract overview
- [`UPGRADING.md`](../../../../UPGRADING.md) — release-to-release migration steps
