---
sources:
  primary:
    - tofu/modules/talos-cluster/helm/argocd-values.yaml
  secondary:
    - tofu/modules/talos-cluster/main.tf
references:
  - AGENTS.md §Repository Purpose (ArgoCD opt-out, never Day-2 add-on)
---

# argocd-module-seed

## Purpose

The module-side ArgoCD delivery: gated on `deploy_argocd`, the
`tofu/modules/talos-cluster` module renders a deliberately slim ArgoCD seed
into a controlplane Talos `cluster.inlineManifests` entry and, after the
health gate, server-side-applies a full default-values chart render (CRDs
included), so the GitOps engine comes up as part of standing the cluster
up rather than as a Day-2 add-on.

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

### Requirement: Full-chart render applied server-side after health

The module SHALL run a second render (`data.helm_template.argocd_crds`)
that renders the full argo-cd chart with `include_crds = true` under
chart-default values (no values file), frozen by
`terraform_data.argocd_crds_render` with `triggers_replace` on the chart
version, namespace, and Kubernetes version, and SHALL apply the written
render file with `kubectl apply --server-side --force-conflicts` via
`null_resource.argocd_crds` after the cluster health gate, re-running on
an intended input bump but not on render drift. Because the payload is
the full chart render, the server-side apply delivers the CRDs and also
converges the seeded application resources on every re-run — it is not a
CRDs-only apply.

#### Scenario: CRD apply follows cluster health

- **WHEN** the module applies with `deploy_argocd = true`
- **THEN** the full-chart kubectl apply depends on the cluster health
  check and runs server-side against the module-written kubeconfig,
  delivering the CRDs and converging the seeded application resources

#### Scenario: Version bump re-applies, drift does not

- **WHEN** `argocd_chart_version` changes
- **THEN** the frozen full-chart render is replaced and the apply re-runs,
  while a render-byte change at unchanged inputs triggers no re-apply

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
