## ADDED Requirements

### Requirement: No operator identity in the render

The component SHALL ship no access policy: the rendered `argocd-rbac-cm`
carries no non-empty `policy.csv`, and `configs.rbac.scopes` is not set. An
access policy names principals of a specific organisation, which a
cluster-agnostic substrate cannot know; the consumer owns both keys in their
own overlay.

The assertion is on EMPTINESS, not absence — the chart's `argocd-rbac-cm`
template emits `policy.csv` unconditionally, so the shipped state is the empty
string and a presence check would be satisfied forever. `policy.default: ''`
remains set, pinning a value identical to the chart default: an authenticated
principal matching no rule receives no permission.

Consequence, stated so the posture is not misread: until a consumer supplies a
policy, the local `admin` account is the only working access path, and ArgoCD
documents it as an unrestricted superuser.

#### Scenario: Render ships no principal

- **WHEN** the steady-state render's `argocd-rbac-cm` is inspected
- **THEN** its `policy.csv` is empty or whitespace-only, and no subject is bound
  to a role

### Requirement: No placeholder base URL in the render

The rendered `argocd-cm` SHALL carry no `url` key. The chart derives it from
`global.domain`, whose default is a placeholder hostname, and ArgoCD derives the
OIDC redirect URI from `url` — a placeholder therefore fails at the identity
provider on a human's first login rather than in the cluster. Absent is the
visible state; the consumer supplies the real value in their overlay.

`argocd-notifications-cm`'s `argocdUrl` is an accepted residual: the chart
renders it through `default (printf ...)` and Helm's `default` treats `""` as
unset, so it cannot be cleared without disabling the notifications workload. It
feeds notification links, never the SSO redirect.

#### Scenario: Render omits the url key

- **WHEN** the steady-state render's `argocd-cm` ConfigMap data is inspected
- **THEN** it carries no `url` key

### Requirement: The consumer wiring path is published and mechanically bound

The repository SHALL publish the consumer-facing wiring contract and SHALL bind
it to a buildable worked overlay, so the documented path cannot drift away from
what the component actually accepts.

The gate SHALL build that overlay against an UNPATCHED control build of the same
component, and assert against the comparison — a one-sided assertion on the
patched build alone would pass identically if the base regressed to shipping the
values the overlay is supposed to supply.

#### Scenario: The documented overlay still wires the component

- **WHEN** the worked overlay and the unpatched component are both built
- **THEN** the control build carries neither a `url` nor a non-empty
  `policy.csv`, while the patched build carries a non-empty `url`, an
  `oidc.config` that parses as YAML with both `issuer` and `clientID`, and a
  non-empty `policy.csv`

#### Scenario: A replacing patch is rejected

- **WHEN** the overlay's merged ConfigMap `.data` key sets are compared against
  the control build's
- **THEN** every base-shipped key is still present, so a JSON6902 or
  `$patch: replace` patch that drops the component's own configuration fails the
  gate

## MODIFIED Requirements

### Requirement: Kustomize consumption surface

The component SHALL be consumable as a single kustomization whose resources are
exactly the namespace manifest and the two committed rendered artifacts, and
that kustomization SHALL be present in the published artifact — otherwise the
property holds in the repository only, and a consumer vendoring a tag receives
loose manifests they must reassemble by hand.

#### Scenario: Component builds from committed inputs only

- **WHEN** `kubectl kustomize kubernetes/substrate/argocd/` runs
- **THEN** the output is assembled from `namespace.yaml`,
  `_rendered/manifests.yaml`, and `_rendered/crds.yaml` with no live chart
  fetch or template step

#### Scenario: The vendored component is buildable

- **WHEN** the published tarball is extracted
- **THEN** `kubernetes/substrate/argocd/kustomization.yaml` is present alongside
  the resources it names, so the component builds from the vendored tree
