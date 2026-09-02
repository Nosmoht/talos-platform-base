# Verify public Day-0 chart downloads before rendering

## Why

The module currently asks the Helm provider to resolve ArgoCD and Cilium by
version from public repositories. A repository can return different bytes under
the same version, and those unchecked manifests enter the privileged Talos
controlplane configuration before GitOps exists.

## What Changes

- Keep the chart archives public rather than packaging them in the base.
- Download each archive into the consumer's `.terraform` cache, verify a
  base-owned SHA-256, and render only that local verified file.
- Reject chart-version overrides for which the base declares no digest.
- Require the ArgoCD Day-0 digest to equal the steady-state chart lock digest.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `argocd-module-seed`
- `argocd-substrate`
- `cilium-cni-delivery`
- `cluster-bootstrap-lifecycle`
- `module-interface-contract`
- `oci-supply-chain`

## Impact

- Consumers keep downloading the public charts but need `curl` and a SHA-256
  command on every apply host.
- Custom Cilium HTTP mirrors remain valid only when they serve the exact pinned
  archive.
- The version-override restriction is breaking and requires the next major
  release.
