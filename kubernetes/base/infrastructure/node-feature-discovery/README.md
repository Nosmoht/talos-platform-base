# `node-feature-discovery`

**Purpose:** Node Feature Discovery — labels nodes with detected hardware features (CPU flags, PCI devices, kernel modules) consumed by GPU/VM scheduling.

## Upstream chart source

- **Chart:** [`node-feature-discovery`](https://kubernetes-sigs.github.io/node-feature-discovery/charts)
- **Pinned version:** `0.17.4`
- **Lock file:** [`chart.lock.yaml`](./chart.lock.yaml) — includes `tgz_sha256` for reproducible renders.

## Namespace

Deploys into namespace `node-feature-discovery`. See [`namespace.yaml`](./namespace.yaml) for the full PSA + PNI label set.

## Declared PNI capabilities

**Provider labels** (on the namespace; see [ADR — Capability Producer/Consumer Symmetry](../../../../docs/adr-capability-producer-consumer-symmetry.md)):

- ``

**Consumer labels:**

- ``

For the full label vocabulary see [`docs/capability-reference.md`](../../../../docs/capability-reference.md).

## Repo-specific Helm-value overrides

Top-level keys in [`values.yaml`](./values.yaml) — anything not listed below uses the upstream chart's default:

- `master`
- `worker`

## Known upgrade gotchas

(none documented yet)

## See also

- [`docs/rendered-manifests.md`](../../../../docs/rendered-manifests.md) — how this component is rendered into `_rendered/manifests.yaml`
- [`docs/capability-architecture.md`](../../../../docs/capability-architecture.md) — capability-first contract overview
- [`UPGRADING.md`](../../../../UPGRADING.md) — release-to-release migration steps
