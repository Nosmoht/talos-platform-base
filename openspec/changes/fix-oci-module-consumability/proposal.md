## Why

The signed OCI artifact advertises the `talos-cluster` module as consumable but
omits five root-level `.tf` files required by that module. The fail-closed
membership diff stays green because it proves only that the tarball matches its
allowlist, not that the allowlisted payload works.

## What Changes

- **BREAKING**: ship every tracked root-level `.tf` file from
  `tofu/modules/talos-cluster/`, making the vendored module complete.
- Fail CI when a current or future root-level module file is absent from the OCI
  allowlist.
- Extract the allowlist-built payload and run `tofu init -backend=false` plus
  `tofu validate` against the vendored module in the existing tofu validation
  chain.
- Correct the README and knowledge workflow so artifact content and git-only
  bootstrap tooling are described accurately.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `oci-supply-chain`: require the published payload to carry a complete,
  OpenTofu-valid `talos-cluster` module.

## Impact

- Published payload membership and release guard fixtures.
- OCI and OpenTofu validation tasks.
- Consumer documentation for vendoring and bootstrap tooling.
- The next release requires a MAJOR bump under the repository's release policy.
