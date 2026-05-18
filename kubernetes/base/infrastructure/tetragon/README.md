# `tetragon`

**Purpose:** Cilium Tetragon — eBPF-based runtime security observability; emits TracingPolicy events for syscall and capability use.

## Upstream chart source

- **Chart:** [`tetragon`](https://helm.cilium.io/)
- **Pinned version:** `1.6.1`
- **Lock file:** [`chart.lock.yaml`](./chart.lock.yaml) — includes `tgz_sha256` for reproducible renders.

## Namespace

Deploys into namespace `tetragon`. See [`namespace.yaml`](./namespace.yaml) for the full PSA + PNI label set.

## Declared PNI capabilities

**Provider labels** (on the namespace; see [ADR — Capability Producer/Consumer Symmetry](../../../../docs/adr-capability-producer-consumer-symmetry.md)):

- ``

**Consumer labels:**

- ``

For the full label vocabulary see [`docs/capability-reference.md`](../../../../docs/capability-reference.md).

## Repo-specific Helm-value overrides

Top-level keys in [`values.yaml`](./values.yaml) — anything not listed below uses the upstream chart's default:

- `extraVolumes`
- `tetragon`
- `tetragonOperator`
- `export`
- `tolerations`

## Known upgrade gotchas

- TracingPolicy CRs default to `monitoring` namespace for the scrape endpoint; do not move the namespace without updating the CCNP.

## See also

- [`docs/rendered-manifests.md`](../../../../docs/rendered-manifests.md) — how this component is rendered into `_rendered/manifests.yaml`
- [`docs/capability-architecture.md`](../../../../docs/capability-architecture.md) — capability-first contract overview
- [`UPGRADING.md`](../../../../UPGRADING.md) — release-to-release migration steps
