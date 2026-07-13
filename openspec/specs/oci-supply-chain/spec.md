---
sources:
  primary:
    - .github/workflows/oci-publish.yml
    - .ci-oci-tarball-include.txt
    - .ci-oci-tarball-expected.txt
references:
  - knowledge/workflows/verify-release.md
---

# oci-supply-chain

## Purpose

Define the producer-side supply-chain contract for base releases: what every
git tag push publishes, how the payload membership is bounded, and which
signatures and attestations accompany the artifact. The consumer-side
verification recipe (cosign, provenance, SBOM, checksum checks) lives in
`knowledge/workflows/verify-release.md` — this spec covers only what the
publish pipeline guarantees.

## Requirements

### Requirement: Tag-triggered OCI publication

Every push of a git tag matching `v*` SHALL publish an OCI artifact to
`ghcr.io/<owner>/talos-platform-base:<tag>` with artifact type
`application/vnd.talos-platform-base.v1+tar`, carrying two layers: the
release tarball (`application/gzip`) and a `checksums.txt` (`text/plain`)
holding the tarball's SHA-256, both produced in the same workflow run.

#### Scenario: Tag push yields a pullable artifact

- **WHEN** a `v*` tag is pushed
- **THEN** the tag resolves at `ghcr.io` to an artifact whose layers are the
  release tarball and its checksum file

### Requirement: Fail-closed allowlist payload

The release tarball SHALL contain exactly the paths listed in
`.ci-oci-tarball-include.txt` — any path not listed is excluded by default —
and the build SHALL fail when the include list is missing. The tarball
listing SHALL be diffed against the committed
`.ci-oci-tarball-expected.txt` fixture, any divergence SHALL fail the
publication, and an absent fixture SHALL itself fail the publication —
deleting the fixture cannot disable the membership gate.

#### Scenario: Unlisted path never ships

- **WHEN** a file exists in the repository but is absent from
  `.ci-oci-tarball-include.txt`
- **THEN** the published tarball does not contain it

#### Scenario: Membership drift fails the build

- **WHEN** the built tarball's sorted listing differs from
  `.ci-oci-tarball-expected.txt`
- **THEN** the workflow exits non-zero before any push, sign, or attest step
  runs

#### Scenario: Absent fixture fails the build

- **WHEN** no `.ci-oci-tarball-expected.txt` fixture is committed
- **THEN** the workflow exits non-zero before any push, sign, or attest
  step runs

### Requirement: Repo-internal surfaces stay outside the payload

The `openspec/`, `.claude/`, and `.codex/` trees SHALL be outside the OCI
payload: no path under them appears in `.ci-oci-tarball-include.txt`, and
the fail-closed allowlist excludes everything unlisted.

#### Scenario: Spec and harness trees are absent from the tarball

- **WHEN** the published tarball's contents are listed
- **THEN** no entry begins with `openspec/`, `.claude/`, or `.codex/`

### Requirement: Keyless signature keyed to the digest

The published artifact SHALL be cosign-signed with keyless OIDC, anchored to
the publishing workflow's GitHub OIDC token identity, and keyed to the
artifact's manifest digest (captured after push) rather than the mutable
tag. A failure to capture the digest SHALL fail the publication.

#### Scenario: Signature verifies against the workflow identity

- **WHEN** a consumer verifies the artifact's signature by digest
- **THEN** the certificate chains to the GitHub Actions OIDC issuer and the
  publishing workflow's identity

### Requirement: SLSA provenance and CycloneDX SBOM attestations

The publication SHALL attach SLSA build provenance (pushed to the registry,
subject keyed to the artifact digest) and a CycloneDX JSON SBOM
generated over the release tarball, attached as a cosign attestation of
type `cyclonedx` keyed to the same digest.

#### Scenario: Both attestations resolve by digest

- **WHEN** a consumer queries the registry for the artifact digest's
  attestations
- **THEN** a SLSA build-provenance attestation and a CycloneDX SBOM
  attestation are present

### Requirement: Pre-release tags never become latest

The `:latest` tag SHALL be applied only for tags without a hyphen; any
SemVer pre-release tag (`v*-*`) SHALL leave `:latest` untouched.

#### Scenario: Hyphenated tag skips latest

- **WHEN** a hyphenated `v*` tag is pushed
- **THEN** `:latest` continues to resolve to the previous non-pre-release
  artifact

### Requirement: GitHub Release mirror

Each published tag SHALL carry a GitHub Release whose assets mirror the OCI
layers plus the SBOM (tarball, `checksums.txt`, CycloneDX JSON), with notes
taken from the matching CHANGELOG section when present and auto-generated
otherwise, hyphenated tags marked pre-release, and idempotent re-runs that
re-upload assets instead of failing. The registry artifact remains the
authoritative, signed consumption path.

#### Scenario: Release object exists with mirrored assets

- **WHEN** a `v*` tag is published
- **THEN** a GitHub Release of the same name exists carrying the tarball,
  checksum file, and SBOM as assets
