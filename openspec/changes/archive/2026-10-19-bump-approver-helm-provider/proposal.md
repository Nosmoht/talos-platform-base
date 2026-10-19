# Bump kubelet-csr-approver and the Helm provider

## Why

postfinance/kubelet-csr-approver v1.2.15 and `hashicorp/helm` 3.x are the
latest stable releases. Two requirements name the old versions: the approver
seed names chart 1.2.14 and its image digest, and the module's version
constraints cap `hashicorp/helm` below 3.0.0.

## What Changes

- `cert-approver-seed`: "Vendored, chart-rendered, digest-pinned templated
  manifest" names chart 1.2.15 and the v1.2.15 image digest. The controller
  code is unchanged between the two releases; only dependencies and chart
  templates the vendored manifest does not use moved.
- `module-interface-contract`: "Version constraints and backend agnosticism"
  widens `hashicorp/helm` to `>= 2.12, < 4.0.0`. The floor stays: the module
  passes chart values through `values`, which both lines accept, so widening
  is not MAJOR under ADR-0029 §Provider constraints.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `cert-approver-seed`
- `module-interface-contract`

## Impact

- Code: the vendored approver manifest, its version label, the module's
  `versions.tf` and lock, and the one `set` block in `argocd-crds.tf`.
- Consumers: a root's helm 2.x lock keeps working. The approver manifest is
  part of every controlplane's machine configuration, so each controlplane
  gets an apply; the seed is create-only, so a running approver moves to
  v1.2.15 only when `talosctl upgrade-k8s` syncs the bootstrap manifests.
