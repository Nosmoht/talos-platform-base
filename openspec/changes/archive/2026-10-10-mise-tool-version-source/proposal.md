# Name the publish workflow as the home of the signing tool's pin

## Why

`.tool-versions` is deleted: binary tool versions move to `mise.toml`
(`knowledge/decisions/0030-mise-single-tool-version-source.md`). The
release-only tools stay out of `mise.toml` for now, so the cosign version is
declared in one place, the publish workflow's installer input. The requirement
"The signing tool's version is pinned and the pin reaches the runner" still
names `.tool-versions`, a file that no longer exists.

## What Changes

- `oci-supply-chain`: "The signing tool's version is pinned and the pin reaches
  the runner" requires the version to be declared in the publish workflow and
  passed explicitly to the installing action, instead of declared in
  `.tool-versions` and passed. The rationale and the scenario's intent — the
  installer never falls back to its own default — are unchanged.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `oci-supply-chain`

## Impact

- Code: none beyond comments in `.github/workflows/oci-publish.yml`; the cosign
  installer already receives `cosign-release: v3.1.3`.
