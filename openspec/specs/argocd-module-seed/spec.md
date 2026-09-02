---
sources:
  primary:
    - tofu/modules/talos-cluster/helm/argocd-values.yaml
  secondary:
    - tofu/modules/talos-cluster/main.tf
references:
  - AGENTS.md §Repository Purpose (ArgoCD opt-out, never Day-2 add-on)
  - kubernetes/substrate/argocd/ (steady-state twin; relocated per knowledge/decisions/0024-argocd-substrate-relocation.md)
---

# argocd-module-seed

## Purpose

The module-side ArgoCD delivery: gated on `deploy_argocd`, the
`tofu/modules/talos-cluster` module renders a deliberately slim ArgoCD seed
into a controlplane Talos `cluster.inlineManifests` entry and, after the
health gate, server-side-applies the chart's CustomResourceDefinitions —
which the inlineManifest cannot carry — so the GitOps engine comes up as
part of standing the cluster up rather than as a Day-2 add-on.

## Requirements

### Requirement: Seed delivery gated on deploy_argocd

The module SHALL, when `deploy_argocd` is true, bake three
`cluster.inlineManifests` entries into the controlplane machine
configuration in apply order: the `argocd` namespace, the `sops-age-key`
Secret built from `var.sops_age_key`, and the frozen ArgoCD chart render;
setting `deploy_argocd` to false is the opt-out that removes all three.

#### Scenario: Seed entries present in order

- **WHEN** the module plans with `deploy_argocd = true`
- **THEN** the controlplane config patches carry the inlineManifest entries
  `argocd-namespace`, `argocd-sops-age-key`, and `argocd` in that order

#### Scenario: Opt-out removes the seed

- **WHEN** the module plans with `deploy_argocd = false`
- **THEN** no ArgoCD inlineManifest entry, CRD render, or CRD apply resource
  is created

### Requirement: Slim seed render without CRDs

The module SHALL render the seed from the shipped slim values
`tofu/modules/talos-cluster/helm/argocd-values.yaml` with chart CRDs
excluded (`include_crds = false` and `crds.install: false`), keeping the
inlineManifest within the Talos size budget; the shipped values keep the
bundled Dex server disabled and configure the repo-server for ksops-based
SOPS decryption; an optional `argocd_values_override` is merged on top,
later layer winning.

#### Scenario: Seed render carries no CRDs

- **WHEN** the seed render is inspected
- **THEN** it contains no CustomResourceDefinition documents

#### Scenario: Bundled Dex stays off in the seed

- **WHEN** the shipped seed values are rendered
- **THEN** no Dex server workload is produced, matching the steady-state
  render's substrate invariant

### Requirement: Age-key precondition for the ksops repo-server

The module SHALL fail at plan time when `deploy_argocd` is true and
`var.sops_age_key` does not start with the age private-key prefix
`AGE-SECRET-KEY-1`, because the seeded repo-server mounts the
`sops-age-key` Secret and reads it via `SOPS_AGE_KEY_FILE` to decrypt SOPS
manifests.

#### Scenario: Non-key input rejected before apply

- **WHEN** the module plans with `deploy_argocd = true` and an empty or
  malformed `sops_age_key`
- **THEN** the plan fails with an error naming the required key prefix

### Requirement: Seed render frozen in state

The module SHALL freeze the ArgoCD seed render via
`terraform_data.argocd_render` with `ignore_changes` on its input, so
non-byte-stable chart re-renders never re-push machine configuration on a
live cluster, and SHALL fail the plan if the render is empty; a deliberate
re-seed requires an explicit resource replacement.

#### Scenario: Render drift is inert for the seed

- **WHEN** a later plan produces different render bytes at unchanged inputs
- **THEN** the frozen seed output is unchanged and no machine-config
  re-push results

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
different properties and each is satisfied by the others' failure modes:

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

### Requirement: Component NetworkPolicies in the seed

The slim Day-0 seed SHALL carry the same per-component NetworkPolicy set as the
steady-state render, so a freshly bootstrapped cluster is policed from the
inlineManifest apply onward rather than from Argo CD's first self-management
sync. The seed values SHALL NOT disable the chart's NetworkPolicy creation.

#### Scenario: The seed render carries the component policies

- **WHEN** the seed render is inspected
- **THEN** it contains the same five `networking.k8s.io/v1` NetworkPolicy
  documents the steady-state render carries, and it stays within the Talos
  inlineManifest size budget
