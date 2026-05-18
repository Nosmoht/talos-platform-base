# `kyverno`

**Purpose:** Kyverno policy engine — enforces PNI admission contract, reserved-label/annotation rules, and capability validation via ClusterPolicy CRs.

## Upstream chart source

- **Chart:** [`kyverno`](https://kyverno.github.io/kyverno)
- **Pinned version:** `3.7.1`
- **Lock file:** [`chart.lock.yaml`](./chart.lock.yaml) — includes `tgz_sha256` for reproducible renders.

## Namespace

Deploys into namespace `kyverno`. See [`namespace.yaml`](./namespace.yaml) for the full PSA + PNI label set.

## Declared PNI capabilities

**Provider labels** (on the namespace; see [ADR — Capability Producer/Consumer Symmetry](../../../../docs/adr-capability-producer-consumer-symmetry.md)):

- ``

**Consumer labels:**

- ``

For the full label vocabulary see [`docs/capability-reference.md`](../../../../docs/capability-reference.md).

## Repo-specific Helm-value overrides

Top-level keys in [`values.yaml`](./values.yaml) — anything not listed below uses the upstream chart's default:

- `admissionController`
- `backgroundController`

## Known upgrade gotchas

- Background scans are enabled and may take several minutes after install; `pni-instanced-suffix-required-audit` is the canonical audit-only policy.
- ClusterPolicy renames (e.g. `pni-contract-audit` → `pni-contract-enforce` in v0.4.0) break PolicyReport queries keyed on the old name; see UPGRADING.md.

## See also

- [`docs/rendered-manifests.md`](../../../../docs/rendered-manifests.md) — how this component is rendered into `_rendered/manifests.yaml`
- [`docs/capability-architecture.md`](../../../../docs/capability-architecture.md) — capability-first contract overview
- [`UPGRADING.md`](../../../../UPGRADING.md) — release-to-release migration steps
