# `nvidia-device-plugin`

**Purpose:** NVIDIA Kubernetes Device Plugin — advertises GPU resources to the kubelet so workloads can request `nvidia.com/gpu`.

## Upstream chart source

- **Chart:** [`nvidia-device-plugin`](https://nvidia.github.io/k8s-device-plugin)
- **Pinned version:** `0.17.4`
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

- `runtimeClassName`
- `tolerations`
- `affinity`

## Known upgrade gotchas

(none documented yet)

## See also

- [`docs/rendered-manifests.md`](../../../../docs/rendered-manifests.md) — how this component is rendered into `_rendered/manifests.yaml`
- [`docs/capability-architecture.md`](../../../../docs/capability-architecture.md) — capability-first contract overview
- [`UPGRADING.md`](../../../../UPGRADING.md) — release-to-release migration steps
