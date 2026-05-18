# `multus-cni`

**Purpose:** Multus CNI meta-plugin — lets pods attach to additional networks beyond the default CNI via NetworkAttachmentDefinition CRs.

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

- This is a resources-only component (no Helm chart) — installed from upstream daemonset YAML pinned in the kustomization.

## See also

- [`docs/rendered-manifests.md`](../../../../docs/rendered-manifests.md) — how this component is rendered into `_rendered/manifests.yaml`
- [`docs/capability-architecture.md`](../../../../docs/capability-architecture.md) — capability-first contract overview
- [`UPGRADING.md`](../../../../UPGRADING.md) — release-to-release migration steps
