## ADDED Requirements

### Requirement: Component NetworkPolicies in the render

The committed render SHALL carry the chart's per-component NetworkPolicy set, so
the substrate ships Argo CD's upstream network posture rather than an
unrestricted namespace. The set SHALL be per-component allow-rules only: no
document may establish a namespace-wide default deny, and the `argocd-server`
policy SHALL admit ingress from every source, so a consumer terminating TLS at
their own gateway in front of Argo CD is never cut off by the floor.

#### Scenario: The render carries the component policies

- **WHEN** `_rendered/manifests.yaml` is scanned as structured documents
- **THEN** a `networking.k8s.io/v1` NetworkPolicy exists for the
  application-controller, the notifications-controller, redis, the repo-server
  and the server, each selecting only its own component's pods
- **AND** redis admits its named port only from the server, repo-server and
  application-controller components
- **AND** repo-server admits its named service port only from the server,
  application-controller, notifications-controller and applicationset-controller
  components, while its metrics port remains reachable from every namespace
- **AND** the application-controller and notifications-controller policies admit
  only their metrics ports from every namespace

#### Scenario: The server stays reachable and no default deny ships

- **WHEN** those NetworkPolicy documents are inspected
- **THEN** the `argocd-server` policy admits ingress from every source, and no
  document combines an empty pod selector with a deny-shaped rule
