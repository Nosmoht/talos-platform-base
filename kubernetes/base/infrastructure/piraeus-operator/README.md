# `piraeus-operator`

**Purpose:** Piraeus Operator — declarative LINSTOR + DRBD lifecycle; provides the block-storage-replicated capability (CSI driver `linstor.csi.linbit.com`).

## Upstream chart source

This component is not Helm-based; it installs upstream YAML directly via kustomize.

## Namespace

Deploys into namespace `piraeus-datastore`. See [`namespace.yaml`](./namespace.yaml) for the full PSA + PNI label set.

## Declared PNI capabilities

**Provider labels** (on the namespace; see [ADR — Capability Producer/Consumer Symmetry](../../../../docs/adr-capability-producer-consumer-symmetry.md)):

- `platform.io/provide.admission-webhook`
- `platform.io/provide.monitoring-scrape`

**Consumer labels:**

- `platform.io/consume.controlplane-egress`

For the full label vocabulary see [`docs/capability-reference.md`](../../../../docs/capability-reference.md).

## Repo-specific Helm-value overrides

Top-level keys in [`values.yaml`](./values.yaml) — anything not listed below uses the upstream chart's default:

- `podLabels`
- `imageConfigOverride`

## Known upgrade gotchas

- DRBD kernel module must be loaded on every storage node; Talos requires `kernelModules: ["drbd"]` in the machine-config patch (`talos/patches/drbd.yaml`).
- LinstorCluster + LinstorSatelliteConfiguration CRs are NOT shipped here; consumer overlay deploys them.

## See also

- [`docs/rendered-manifests.md`](../../../../docs/rendered-manifests.md) — how this component is rendered into `_rendered/manifests.yaml`
- [`docs/capability-architecture.md`](../../../../docs/capability-architecture.md) — capability-first contract overview
- [`UPGRADING.md`](../../../../UPGRADING.md) — release-to-release migration steps
