## Why

Release immutability freezes a GitHub Release when it is **published**, and a
published release rejects every asset upload with HTTP 422. `release.yml`
published the release object the moment it tagged, before the assets existed,
so `oci-publish.yml` always arrived to find an immutable release and always
failed. Five tags shipped with no tarball, no `checksums.txt`, and no SBOM
(`v9.2.2`, `v9.2.3`, `v10.0.0`, `v11.0.0`, `v11.0.1`), and the only signal was
a red run on a tag nobody watches.

## What Changes

- Remove `@semantic-release/github` so semantic-release tags and stops, making
  the publish workflow the sole creator of the GitHub Release.
- Create the release as a draft, attach the three assets to the draft, and
  publish it last — the only order an immutable release accepts.
- Read the published release back and fail when its assets are not the three
  expected ones.
- Turn a failed publish into one tracking issue instead of a silent red run.
- Record the already-published asset-less tags as asset-less; immutability
  makes backfilling them impossible.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `oci-supply-chain`: the GitHub Release mirror must be filled before it is
  published, and its asset set is asserted rather than assumed.

## Impact

- `.releaserc.json` loses its publish plugin; release notes come from the
  hand-cut CHANGELOG section on every release, with `--generate-notes` as the
  fallback.
- A publish failing after the draft is published is unrepairable in place;
  recovery is a new tag. A failure before that point leaves a draft the next
  run discards, so re-runs stay idempotent up to the flip.
- Consumers on the `oras pull` path are unaffected — the OCI artifacts of the
  asset-less tags are published, signed, and attested.
