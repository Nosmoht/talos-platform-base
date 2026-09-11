## MODIFIED Requirements

### Requirement: GitHub Release mirror

Each published tag SHALL carry a GitHub Release whose assets mirror the OCI
layers plus the SBOM (tarball, `checksums.txt`, CycloneDX JSON), with notes
taken from the matching CHANGELOG section when present and auto-generated
otherwise, and hyphenated tags marked pre-release. The assets SHALL be
attached while the release is still a draft and the release SHALL be published
only afterwards, so that release immutability — which takes effect at publish
time — never intercepts an asset upload. The publish pipeline SHALL be the
only producer of the release object, and SHALL fail rather than attempt to
amend a release that is already published. After publishing, the pipeline
SHALL read the release back and fail when its asset set is not exactly the
three expected files. The registry artifact remains the authoritative, signed
consumption path.

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
