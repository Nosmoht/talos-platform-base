## 1. Artifact Contract

- [x] 1.1 Add every tracked root-level `talos-cluster` `.tf` file to the OCI
  allowlist and expected fixture; verify the tar listing matches exactly.
- [x] 1.2 Extend the consumability gate to reject an omitted module `.tf` file;
  verify it fails on the old allowlist and passes on the complete allowlist.

## 2. Executable Validation

- [x] 2.1 Add an extracted-artifact `tofu init -backend=false` and
  `tofu validate` target to `tofu:ci`; verify it succeeds against the packaged
  module.
- [x] 2.2 Update release-guard coverage and its lock; verify
  `task supply-chain:check-release-guard` succeeds.

## 3. Consumer Contract and Documentation

- [x] 3.1 Add and archive the `oci-supply-chain` delta; verify
  `task spec:validate` and `task spec:check-regen` succeed.
- [x] 3.2 Correct README and knowledge descriptions of artifact versus git-only
  content; verify `task knowledge:validate` and documentation lint succeed.

## 4. Final Verification

- [x] 4.1 Run the repository-required supply-chain, OpenTofu, spec, knowledge,
  GitOps, and shell checks and record their outcomes in the PR.
