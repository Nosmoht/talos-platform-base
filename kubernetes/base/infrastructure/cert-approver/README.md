# `cert-approver`

**Purpose:** kubelet CSR approver — auto-approves serving certificates for kubelet so cert-manager can rotate them without manual intervention.

## Upstream chart source

This component is not Helm-based; it installs upstream YAML directly via kustomize.

## Namespace

Deploys into namespace `kubelet-serving-cert-approver`. See [`namespace.yaml`](./namespace.yaml) for the full PSA label set.

## Repo-specific Helm-value overrides

Top-level keys in [`values.yaml`](./values.yaml) — anything not listed below uses the upstream chart's default:

- `replicas`

## Known upgrade gotchas

(none documented yet)

## See also

- [`docs/rendered-manifests.md`](../../../../docs/rendered-manifests.md) — how this component is rendered into `_rendered/manifests.yaml`
- [`UPGRADING.md`](../../../../UPGRADING.md) — release-to-release migration steps
