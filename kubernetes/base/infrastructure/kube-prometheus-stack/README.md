# `kube-prometheus-stack`

**Purpose:** kube-prometheus-stack — Prometheus, Alertmanager, kube-state-metrics, node-exporter, and Grafana, the platform's reference metrics + dashboards stack.

## Upstream chart source

- **Chart:** [`kube-prometheus-stack`](https://prometheus-community.github.io/helm-charts)
- **Pinned version:** `81.6.1`
- **Lock file:** [`chart.lock.yaml`](./chart.lock.yaml) — includes `tgz_sha256` for reproducible renders.

## Namespace

Deploys into namespace `monitoring`. See [`namespace.yaml`](./namespace.yaml) for the full PSA + PNI label set.

## Declared PNI capabilities

**Provider labels** (on the namespace; see [ADR — Capability Producer/Consumer Symmetry](../../../../docs/adr-capability-producer-consumer-symmetry.md)):

- `platform.io/provide.logging-ship`
- `platform.io/provide.monitoring-scrape`

**Consumer labels:**

- ``

For the full label vocabulary see [`docs/capability-reference.md`](../../../../docs/capability-reference.md).

## Repo-specific Helm-value overrides

Top-level keys in [`values.yaml`](./values.yaml) — anything not listed below uses the upstream chart's default:

- `prometheusOperator`
- `prometheus`
- `grafana`
- `kubeProxy`
- `kubeEtcd`

## Known upgrade gotchas

- CRDs are shipped via `includeCRDs: true` in the Helm release — do not duplicate them in the consumer overlay.
- Loki and Tempo references in Grafana datasources are configured in the consumer overlay, not here.

## See also

- [`docs/rendered-manifests.md`](../../../../docs/rendered-manifests.md) — how this component is rendered into `_rendered/manifests.yaml`
- [`docs/capability-architecture.md`](../../../../docs/capability-architecture.md) — capability-first contract overview
- [`UPGRADING.md`](../../../../UPGRADING.md) — release-to-release migration steps
