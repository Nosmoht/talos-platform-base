## MODIFIED Requirements

### Requirement: GitHub Release mirror

Each published tag SHALL carry a GitHub Release whose assets mirror the OCI
layers plus the SBOM (tarball, `checksums.txt`, CycloneDX JSON), with notes
generated from the pull requests merged in the tag's range, and hyphenated tags
marked pre-release. The assets SHALL be
attached while the release is still a draft and the release SHALL be published
only afterwards, so that release immutability — which takes effect at publish
time — never intercepts an asset upload. The publish pipeline SHALL be the
only producer of the release object, and SHALL fail rather than attempt to
amend a release that is already published. After publishing, the pipeline
SHALL read the release back and fail when its asset set is not exactly the
three expected files. The registry artifact remains the authoritative, signed
consumption path.

The pipeline SHALL address the release it publishes by the identity
`gh release create` returned for that release, never by its tag: a tag names a
SET of releases, and the listing that resolves that set is eventually
consistent with the creation. A listing that does not yet report the release
this run created — including one that cannot be read at all — SHALL be retried
within a bounded, backing-off number of attempts rather than failing the run:
by that point the artifact, its signature, its attestations and `:latest` are
already in place, and the documented recovery for the resulting half-released
tag is a non-idempotent re-run that remaps the tag to a new digest. Exhausting
the retry SHALL fail without publishing anything.

A release for the tag that is already PUBLISHED, and a SECOND draft beside the
one this run created, SHALL each fail on first sight rather than be retried.
Waiting improves neither, and re-sampling a set lets an inconsistent listing
act on the wrong member of it.

#### Scenario: Release object exists with mirrored assets

- **WHEN** a `v*` tag is published
- **THEN** a GitHub Release of the same name exists carrying the tarball,
  checksum file, and SBOM as assets

#### Scenario: Assets are attached before the release is published

- **WHEN** the pipeline creates the GitHub Release for a tag
- **THEN** the release is created as a draft, the three assets are attached to
  it, and it is published only after all three are attached

#### Scenario: An already-published release is not amended

- **WHEN** the pipeline runs for a tag whose GitHub Release is already
  published
- **THEN** it exits non-zero without attempting an asset upload, because a
  published release is immutable

#### Scenario: A release missing an asset fails the publication

- **WHEN** the published release's asset names differ from the tarball,
  `checksums.txt`, and CycloneDX JSON expected for the tag
- **THEN** the publish job exits non-zero

#### Scenario: A listing that lags the creation does not abandon the tag

- **WHEN** the release listing does not yet report the draft the pipeline just
  created, or cannot be read at all
- **THEN** the pipeline retries the listing, publishes that draft once it
  appears, and fails without publishing anything only once the retries are
  exhausted

#### Scenario: A draft the pipeline did not create is never published

- **WHEN** a draft release for the tag exists that this run did not create,
  whether or not the listing has reported this run's own draft yet
- **THEN** the pipeline publishes no release other than the one it created,
  and refuses outright once both drafts are visible
