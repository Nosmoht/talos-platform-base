# Generate every release's notes from the merged pull requests

## Why

`CHANGELOG.md` is retired. No section has been cut since `v9.1.0`, so every
release since then already took the generated-notes fallback, and what a
consumer must do to adopt a tag lives in `UPGRADING.md`. The requirement
"GitHub Release mirror" still says the notes come from the matching CHANGELOG
section when present.

## What Changes

- `oci-supply-chain`: "GitHub Release mirror" requires the notes to be
  generated from the merged pull requests in the tag's range, instead of taken
  from a CHANGELOG section with generation as the fallback. Assets, draft
  ordering, publication and the listing rules are unchanged.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `oci-supply-chain`

## Impact

`.github/workflows/oci-publish.yml` drops the CHANGELOG extraction and always
passes `--generate-notes`; `scripts/check-release-step-bites.sh` asserts that
flag. Release assets and the OCI artifact are unchanged.
