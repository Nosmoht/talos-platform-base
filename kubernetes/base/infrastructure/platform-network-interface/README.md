# `platform-network-interface`

**Purpose:** Platform Network Interface (PNI) registry + Kyverno ClusterPolicies + Cilium CCNPs — the capability-first network-trust contract this base ships.

## Upstream chart source

This component is not Helm-based; it installs upstream YAML directly via kustomize.

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

(no values.yaml — component does not override defaults)

## Known upgrade gotchas

- Per-instance Kyverno generate/mutate rules (one CCNP per managed CR instance) are the consumer overlay's responsibility — see AGENTS.md §Out of scope for the base.
- All reserved label keys (`platform.io/provide.*`, `platform.io/capability-provider.*`) are listed in the Hard Constraints section of AGENTS.md.

## See also

- [`docs/rendered-manifests.md`](../../../../docs/rendered-manifests.md) — how this component is rendered into `_rendered/manifests.yaml`
- [`docs/capability-architecture.md`](../../../../docs/capability-architecture.md) — capability-first contract overview
- [`UPGRADING.md`](../../../../UPGRADING.md) — release-to-release migration steps
