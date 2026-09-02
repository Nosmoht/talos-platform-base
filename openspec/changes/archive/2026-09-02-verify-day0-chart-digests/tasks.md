## 1. Verified download

- [x] 1.1 Add an offline-tested downloader that rejects mismatched downloads and
  altered cache files.
- [x] 1.2 Render ArgoCD and Cilium only from the verified local archives.
- [x] 1.3 Reject chart versions without base-owned digest pins.

## 2. Cross-path and artifact gates

- [x] 2.1 Bind the ArgoCD seed digest to the steady-state chart lock digest.
- [x] 2.2 Ship the downloader and integrity declarations in the OCI module.

## 3. Contracts and verification

- [x] 3.1 Update the affected OpenSpec capabilities, module README, upgrade guide,
  changelog, and knowledge decision.
- [x] 3.2 Run all required OpenTofu, spec, knowledge, GitOps, supply-chain, and
  documentation checks before opening the pull request.
