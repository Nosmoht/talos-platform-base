## ADDED Requirements

### Requirement: Argo CD image matches the chart appVersion

Every container image in the committed render, and in the seed render of the
module's values against the same pinned chart, SHALL be either the pinned
chart's Argo CD image — its `global.image.repository` tagged with its
`appVersion` — or an image from a repository the same chart declares for its
other components, or the base's own `viaductoss/ksops` init container. The chart
pin therefore names the Argo CD release the substrate ships, and a chart bump is
the only way to move it. The requirement binds image references, not the binary
a container ends up executing.

#### Scenario: The render ships the pinned release

- **WHEN** the committed component is kustomize-built, and both values files are
  rendered against the sha256-verified chart named in `chart.lock.yaml`
- **THEN** each contains at least one container on the pinned Argo CD image, and
  every other container image comes from an allowed repository

#### Scenario: An image override is rejected

- **WHEN** either values file or the committed render gives any container
  another Argo CD tag, an untagged or digest Argo CD reference, or an image from
  a repository the chart does not declare
- **THEN** the substrate invariant gate fails and names the offending image
