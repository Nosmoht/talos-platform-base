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

The pipeline locates the draft it created through the release listing, which is
eventually consistent with the creation. A listing that does not yet report
that draft SHALL be retried within a bounded number of attempts rather than
failing the run: by that point the artifact, its signature, its attestations
and `:latest` are already in place, and the documented recovery for the
resulting half-released tag is a non-idempotent re-run that remaps the tag to a
new digest. Exhausting the retry SHALL fail without publishing anything. A
release for the tag that is already PUBLISHED SHALL still fail on first sight
rather than be retried, because waiting cannot change it.

#### Scenario: A listing that lags the creation does not abandon the tag

- **WHEN** the release listing does not yet report the draft the pipeline just
  created
- **THEN** the pipeline retries the listing, publishes the draft once it
  appears, and fails without publishing anything only once the retries are
  exhausted
