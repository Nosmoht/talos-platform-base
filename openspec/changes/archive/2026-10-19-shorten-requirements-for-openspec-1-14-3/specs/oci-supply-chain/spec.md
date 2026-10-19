## ADDED Requirements

### Requirement: Release assets are attached to a draft before publication

The pipeline SHALL attach the assets while the release is still a draft and
SHALL publish the release only afterwards, so that release immutability —
which takes effect at publish time — never intercepts an asset upload. It
SHALL fail rather than attempt to amend a release that is already published,
and after publishing SHALL read the release back and fail when its asset set
is not exactly the three expected files.

#### Scenario: Draft-first publication with a read-back check

- **WHEN** the pipeline publishes the GitHub Release for a tag
- **THEN** the three assets were attached while it was a draft, before it
  was published
- **AND** the pipeline reads the published release back and fails when its
  asset set is not exactly the three expected files

### Requirement: The release is addressed by its creation identity

The pipeline SHALL address the release it publishes by the identity
`gh release create` returned for that release, never by its tag: a tag names
a SET of releases, and the listing that resolves that set is eventually
consistent with the creation.

#### Scenario: Publication targets the created release, not the tag

- **WHEN** the pipeline publishes the draft it created
- **THEN** it addresses that release by the identity `gh release create`
  returned, never by the tag

### Requirement: A lagging release listing is retried with bounded backoff

A listing that does not yet report the release this run created — including
one that cannot be read at all — SHALL be retried within a bounded,
backing-off number of attempts rather than failing the run. Exhausting the
retry SHALL fail without publishing anything.

#### Scenario: Retrying avoids a non-idempotent recovery

- **WHEN** the listing lags at the point where the artifact, its signature,
  its attestations and `:latest` are already in place
- **THEN** the pipeline retries rather than fails, because the documented
  recovery for the resulting half-released tag is a non-idempotent re-run
  that remaps the tag to a new digest
- **AND** once the bounded retries are exhausted it fails without publishing
  anything

### Requirement: A published release or a second draft fails on first sight

A release for the tag that is already PUBLISHED, and a SECOND draft beside
the one this run created, SHALL each fail on first sight rather than be
retried.

#### Scenario: No retry for a published release or a foreign draft

- **WHEN** the listing shows the tag's release already PUBLISHED, or a
  SECOND draft beside the one this run created
- **THEN** the pipeline fails on first sight without retrying, because
  waiting improves neither and re-sampling a set lets an inconsistent
  listing act on the wrong member of it

## MODIFIED Requirements

### Requirement: Steady-state ArgoCD consumables ship in the payload

Per ADR-0024 (`knowledge/decisions/0024-argocd-substrate-relocation.md`), the
steady-state ArgoCD component's consumable files SHALL be in the payload:
`kubernetes/substrate/argocd/namespace.yaml`,
`kubernetes/substrate/argocd/_rendered/manifests.yaml`,
`kubernetes/substrate/argocd/_rendered/crds.yaml`, and
`kubernetes/substrate/argocd/kustomization.yaml` appear in
`.ci-oci-tarball-include.txt`.

#### Scenario: Consumer can source the steady-state render from the artifact

- **WHEN** the published tarball's contents are listed
- **THEN** `kubernetes/substrate/argocd/namespace.yaml`,
  `kubernetes/substrate/argocd/_rendered/manifests.yaml`,
  `kubernetes/substrate/argocd/_rendered/crds.yaml` and
  `kubernetes/substrate/argocd/kustomization.yaml` are present, and no
  other `kubernetes/substrate/` path is

#### Scenario: A renderable component missing its kustomization fails the gate

- **WHEN** a component listed in `.ci-renderable-components.txt` has no
  `kustomization.yaml` entry in `.ci-oci-tarball-include.txt`
- **THEN** `scripts/check-substrate-consumability.sh` fails, naming the
  component

#### Scenario: The kustomization ships as a consumable

- **WHEN** a consumer extracts the steady-state ArgoCD component
- **THEN** `kustomization.yaml` is present as a consumable, not an authoring
  input, making the other three files a buildable unit
- **AND** the component's own "consumable as a single kustomization"
  requirement holds for the artifact, not only in the repository

#### Scenario: Authoring inputs stay outside the payload

- **WHEN** the published tarball's contents are listed
- **THEN** the remaining authoring inputs (`values.yaml`, `chart.lock.yaml`,
  `_rendered-overlay/`) are absent — consumers receive the render and the
  means to build it, not the render pipeline

### Requirement: The signing tool's version is pinned and the pin reaches the runner

The version of every tool the publish workflow installs to produce or push a
release artifact SHALL be declared in that workflow AND passed explicitly to
the action that installs it. A tool an action bundles is pinned by the
action's commit SHA instead.

#### Scenario: The declared cosign version is the one that signs

- **WHEN** the publish workflow installs cosign
- **THEN** the installer is given the version declared in the publish
  workflow, rather than falling back to the installer action's own default

### Requirement: GitHub Release mirror

Each published tag SHALL carry a GitHub Release whose assets mirror the OCI
layers plus the SBOM (tarball, `checksums.txt`, CycloneDX JSON), with notes
generated from the pull requests merged in the tag's range, and hyphenated
tags marked pre-release. The publish pipeline SHALL be the only producer of
the release object. The registry artifact remains the authoritative, signed
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
