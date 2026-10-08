## ADDED Requirements

### Requirement: Argo CD image matches the chart appVersion

Every `quay.io/argoproj/argocd` image in the committed render, and in the seed
render of the module's values against the same pinned chart, SHALL carry the
pinned chart's `appVersion` as its tag, so the chart pin names the Argo CD
release the substrate ships and a chart bump is the only way to move it.

#### Scenario: The render ships the pinned release

- **WHEN** the committed component is kustomize-built, and both values files are
  rendered against the sha256-verified chart named in `chart.lock.yaml`
- **THEN** at least one `quay.io/argoproj/argocd` image is present in each, and
  every one carries the chart's `appVersion` tag

#### Scenario: An image override is rejected

- **WHEN** either values file or the committed render sets an Argo CD image tag
  other than the chart's `appVersion`
- **THEN** the substrate invariant gate fails and names the offending image
