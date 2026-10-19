## ADDED Requirements

### Requirement: CRD projection frozen with intended-input triggers

The module SHALL freeze the CRD projection in
`terraform_data.argocd_crds_render` with `triggers_replace` on the chart
version, the namespace, and a projection discriminator — but NOT on the
Kubernetes version, which does not affect the payload — so the CRD apply
re-runs on an intended input bump but not on render drift.

#### Scenario: Replacement triggers name the intended inputs only

- **WHEN** the `triggers_replace` of `terraform_data.argocd_crds_render` is
  inspected
- **THEN** it carries the chart version, the namespace and the projection
  discriminator, and not the Kubernetes version

### Requirement: CRD payload carries CustomResourceDefinitions only

The CRD apply payload SHALL contain CustomResourceDefinitions and nothing
else, so the apply delivers the CRDs the inlineManifest seed cannot carry and
does not converge, overwrite, or take field-manager ownership of any other
ArgoCD resource. Convergence of the application itself SHALL be left to
ArgoCD self-management.

#### Scenario: The CRD apply owns no other ArgoCD resource

- **WHEN** the CRD apply runs against a cluster where ArgoCD manages itself
- **THEN** it takes field-manager ownership of no resource other than the
  CRDs, and the application's convergence stays with ArgoCD self-management

### Requirement: CRD seed hands ownership to ArgoCD

The CRD apply SHALL be a seed-then-hand-off: the steady-state component ships
the same three CRDs and ArgoCD syncs them server-side, so ArgoCD is their
owner from its first sync. The module SHALL NOT force conflicts, so a
deliberate seed chart bump that has fallen behind the steady state surfaces as
a conflict for an operator to resolve.

#### Scenario: A stale seed bump conflicts instead of rolling back

- **WHEN** a deliberate seed chart bump whose CRDs have fallen behind the
  steady state is applied to a cluster where ArgoCD owns the CRDs
- **THEN** the server-side apply surfaces a conflict for an operator to
  resolve rather than silently rolling the live CRD schema back to the seed
  pin

### Requirement: Plan-time guards on the CRD projection

Three plan-time preconditions SHALL guard the CRD projection, because they
assert different properties and each is satisfied by the others' failure
modes: **completeness** — all three ArgoCD CRDs are present BY NAME, not by
count; **exclusivity** — every surviving document is a
`CustomResourceDefinition`; **parseability** — no non-blank document in the
source render fails to parse.

#### Scenario: Three wrong documents fail the completeness check

- **WHEN** the projection yields three documents that are not the three
  ArgoCD CRDs by name
- **THEN** the plan fails, since a count-based check would be satisfied by
  them

### Requirement: Seeded namespace manifest outside the frozen render

The seeded namespace manifest SHALL NOT be part of the frozen seed render:
its `app.kubernetes.io/version` label follows `argocd_chart_version` on every
plan, so moving that input changes every controlplane's machine configuration
while the frozen render stays unchanged. Talos' inline-manifest controller
creates missing resources only, so the changed label does not reach a running
cluster's namespace.

#### Scenario: The moved label does not reach a running cluster

- **WHEN** the changed machine configuration reaches a running cluster whose
  `argocd` namespace already exists
- **THEN** Talos' inline-manifest controller, which creates missing resources
  only, leaves that namespace's `app.kubernetes.io/version` label unchanged

## MODIFIED Requirements

### Requirement: CRD-only render applied server-side after health

The module SHALL run a second render (`data.helm_template.argocd_crds`)
that renders the argo-cd chart with `include_crds = true` under
chart-default values (no values file), SHALL project that render down to
its `CustomResourceDefinition` documents before freezing it, and SHALL apply
the written file after the cluster health gate with
`kubectl apply --server-side` under a dedicated `--field-manager`, and
without `--force-conflicts`.

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

### Requirement: Seeded namespace labels and PSA floor

The module SHALL seed the `argocd` namespace with the six recommended
labels (`app.kubernetes.io/managed-by: opentofu`, version set to the chart
version) and a pod-security floor of `enforce: baseline` with `audit` and
`warn` at `restricted` (label set normative: AGENTS.md §Hard Constraints —
Kubernetes recommended labels on all resources), matching the PSA floor the
steady-state component asserts so ownership transfer carries no PSA change.

#### Scenario: Namespace never delivered unlabeled

- **WHEN** the seeded namespace manifest is inspected
- **THEN** it carries the six `app.kubernetes.io/*` labels and the
  `baseline`-enforce / `restricted`-audit-and-warn pod-security labels

#### Scenario: A chart-version change moves the namespace label

- **WHEN** `argocd_chart_version` changes on an already-bootstrapped module state
- **THEN** the seeded namespace manifest's `app.kubernetes.io/version` label
  carries the new value and the controlplane machine configuration changes,
  while `terraform_data.argocd_render`'s frozen output does not
