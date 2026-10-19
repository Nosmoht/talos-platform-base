## ADDED Requirements

### Requirement: Notifications argocdUrl is an accepted residual

"No placeholder base URL in the render" SHALL NOT extend to the
chart-derived `argocdUrl` in `argocd-notifications-cm`: the chart renders it
through `default (printf ...)` and Helm's `default` treats `""` as unset, so
it cannot be cleared without disabling the notifications workload. It feeds
notification links, never the SSO redirect.

#### Scenario: The residual argocdUrl does not reach SSO

- **WHEN** the steady-state render's `argocd-notifications-cm` carries a
  chart-derived `argocdUrl`
- **THEN** "No placeholder base URL in the render" is not violated by it

### Requirement: The chart pin names the shipped Argo CD release

The chart pin SHALL name the Argo CD release the substrate ships, so a chart
bump in `kubernetes/substrate/argocd/chart.lock.yaml` is the only way to move
that release.

#### Scenario: Only a chart bump moves the release

- **WHEN** the Argo CD release the substrate ships is to change
- **THEN** the chart pinned in `chart.lock.yaml` is bumped, since any other
  Argo CD tag in either values file or the committed render fails the
  substrate invariant gate

## MODIFIED Requirements

### Requirement: No operator identity in the render

The component SHALL ship no access policy: the rendered `argocd-rbac-cm`
carries no non-empty `policy.csv` and no non-empty `policy.default`, and
`configs.rbac.scopes` is not set; the consumer owns `policy.csv` and the
scopes in their own overlay. `policy.default` SHALL be asserted separately
from `policy.csv`, and both assertions SHALL test EMPTINESS, not absence,
because the chart's `argocd-rbac-cm` template emits the keys unconditionally.

#### Scenario: Render ships no principal

- **WHEN** the steady-state render's `argocd-rbac-cm` is inspected
- **THEN** its `policy.csv` is empty or whitespace-only, and no subject is bound
  to a role

#### Scenario: Render grants no blanket role

- **WHEN** the same ConfigMap's `policy.default` is inspected
- **THEN** it is empty or whitespace-only, so no role is granted to every
  authenticated principal

#### Scenario: An unmatched principal receives no permission

- **WHEN** an authenticated principal matches no policy rule
- **THEN** the shipped `policy.default` value `''`, identical to the chart
  default, grants it no permission

#### Scenario: Only the local admin works until a consumer policy exists

- **WHEN** no consumer has supplied a policy
- **THEN** the local `admin` account, which ArgoCD documents as an
  unrestricted superuser, is the only working access path

### Requirement: No placeholder base URL in the render

The rendered `argocd-cm` SHALL carry no `url` key. The chart derives it from
`global.domain`, whose default is a placeholder hostname, and ArgoCD derives the
OIDC redirect URI from `url` — a placeholder therefore fails at the identity
provider on a human's first login rather than in the cluster. The consumer
supplies the real value in their overlay.

#### Scenario: Render omits the url key

- **WHEN** the steady-state render's `argocd-cm` ConfigMap data is inspected
- **THEN** it carries no `url` key

### Requirement: Argo CD image matches the chart appVersion

Every container image in the committed render, and in the seed render of the
module's values against the same pinned chart, SHALL be either the pinned
chart's Argo CD image — its `global.image.repository` tagged with its
`appVersion` — or an image from a repository the same chart declares for its
other components, or the base's own `viaductoss/ksops` init container. The
requirement binds image references, not the binary a container ends up
executing.

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
