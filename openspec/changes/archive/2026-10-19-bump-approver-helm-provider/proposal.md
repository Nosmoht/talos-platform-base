# Bump kubelet-csr-approver and the Helm provider

## Why

postfinance/kubelet-csr-approver v1.2.15 and `hashicorp/helm` 3.x are the
latest stable releases. Two requirements name the old versions: the approver
seed names chart 1.2.14 and its image digest, and the module's version
constraints name `hashicorp/helm` `>= 2.12, < 3.0.0`.

## What Changes

- `cert-approver-seed`: "Vendored, chart-rendered, digest-pinned templated
  manifest" names chart 1.2.15 and the v1.2.15 image digest. The controller
  code is unchanged between the two releases; only dependencies and chart
  templates the vendored manifest does not use moved.
- `module-interface-contract`: "Version constraints and backend agnosticism"
  constrains `hashicorp/helm` to `>= 3.0.0, < 4.0.0` and adds the scenario
  that a consumer lock below 3.0.0 must be refreshed. Raising the floor is
  MAJOR under ADR-0029 §Provider constraints: helm 3 replaced the `set` block
  with a list attribute, so the module's code needs 3.0.0.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `cert-approver-seed`
- `module-interface-contract`

## Impact

- Code: the vendored approver manifest, its version label, the module's
  `versions.tf` and lock, and the one `set` block in `argocd-crds.tf`.
- Consumers: roots with a helm 2.x lock run `tofu init -upgrade`. The
  approver manifest is part of every controlplane's machine configuration, so
  each controlplane gets an apply; the seed is create-only, so a running
  approver moves to v1.2.15 only when `talosctl upgrade-k8s` syncs the
  bootstrap manifests.
