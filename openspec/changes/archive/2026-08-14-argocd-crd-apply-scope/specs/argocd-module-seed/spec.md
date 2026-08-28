## MODIFIED Requirements

### Requirement: CRD-only render applied server-side after health

The module SHALL run a second render (`data.helm_template.argocd_crds`)
that renders the argo-cd chart with `include_crds = true` under
chart-default values (no values file), SHALL project that render down to
its `CustomResourceDefinition` documents before freezing it, and SHALL
freeze the projection in `terraform_data.argocd_crds_render` with
`triggers_replace` on the chart version, the namespace, and a projection
discriminator — but NOT on the Kubernetes version, which does not affect
the payload. It SHALL apply the written file after the cluster health gate
with `kubectl apply --server-side` under a dedicated `--field-manager`, and
without `--force-conflicts`, re-running on an intended input bump but not
on render drift.

The payload SHALL contain CustomResourceDefinitions and nothing else, so
the apply delivers the CRDs the inlineManifest seed cannot carry and does
not converge, overwrite, or take field-manager ownership of any other
ArgoCD resource. Convergence of the application itself is ArgoCD
self-management's responsibility.

The apply is a seed-then-hand-off: the steady-state component ships the same
three CRDs and ArgoCD syncs them server-side, so ArgoCD is their owner from
its first sync. The module SHALL NOT force conflicts, so a deliberate seed
chart bump that has fallen behind the steady state surfaces as a conflict
for an operator to resolve rather than silently rolling the live CRD schema
back to the seed pin.

Three plan-time preconditions SHALL guard the projection, because they assert
different properties and each survives the others' failure modes:

- **completeness** — the projection carries all three ArgoCD CRDs BY NAME. A
  count-based check would be satisfied by three wrong documents.
- **exclusivity** — every surviving document is a `CustomResourceDefinition`.
  The by-name check is a containment test, so a projection that stopped
  filtering would carry the chart's full default render and still satisfy it.
- **parseability** — no non-blank document in the source render fails to parse.
  The kind filter drops what it cannot decode, which silently truncates a CRD
  that a document separator cut in half: the head fragment still decodes with a
  valid kind and name and is kept, and applying it server-side replaces a live
  schema with a truncated one.

#### Scenario: CRD apply follows cluster health

- **WHEN** the module applies with `deploy_argocd = true`
- **THEN** the kubectl apply depends on the cluster health check and runs
  server-side against the module-written kubeconfig, delivering the CRDs

#### Scenario: Payload carries no non-CRD document

- **WHEN** the applied manifest is inspected as structured documents
- **THEN** every document is a `CustomResourceDefinition`, and no
  workload, Service, Secret or ConfigMap from the chart's default render
  is present

#### Scenario: Incomplete projection fails at plan time

- **WHEN** the projection does not yield all three ArgoCD CRDs by name
- **THEN** the plan fails, naming the missing ones, rather than applying an
  incomplete CRD set

#### Scenario: Non-CRD documents in the projection fail at plan time

- **WHEN** the projection yields a document whose kind is not
  `CustomResourceDefinition`
- **THEN** the plan fails, naming the offending kinds — the by-name check alone
  would pass, because it only tests containment

#### Scenario: An unparseable source document fails at plan time

- **WHEN** a non-blank document of the source render does not parse as YAML
- **THEN** the plan fails rather than letting the kind filter discard it, since
  a discarded fragment may be the tail of a CRD that was cut in half

#### Scenario: Chart bump re-applies, drift and Kubernetes bumps do not

- **WHEN** `argocd_chart_version` changes
- **THEN** the frozen CRD projection is replaced and the apply re-runs,
  while a render-byte change at unchanged inputs, or a change to
  `kubernetes_version` alone, triggers no re-apply

## ADDED Requirements

### Requirement: No placeholder Argo CD base URL in the seed

The shipped seed values SHALL set `configs.cm.url` to the empty string, so
the rendered `argocd-cm` ConfigMap carries no `url` key. The chart derives
that key from `global.domain`, whose default is a placeholder hostname, and
Argo CD derives the OIDC redirect URI from `url` — a placeholder therefore
fails at the identity provider rather than in the cluster. The consumer
supplies the real value in their own overlay.

#### Scenario: Seed render omits the url key

- **WHEN** the shipped seed values are rendered against the pinned chart
- **THEN** the `argocd-cm` ConfigMap's data carries no `url` key
