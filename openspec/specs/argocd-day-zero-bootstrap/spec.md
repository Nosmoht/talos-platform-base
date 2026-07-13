---
sources:
  primary:
    - kubernetes/bootstrap/argocd/root-project.yaml.tmpl
    - kubernetes/bootstrap/argocd/root-application.yaml.tmpl
    - Taskfile.yml#bootstrap:argocd
references:
  - AGENTS.md §Repository Purpose (ArgoCD as co-equal pillar, opt-out)
---

# argocd-day-zero-bootstrap

## Purpose

Turn a freshly provisioned cluster into a GitOps-managed one: the one-time,
direct-applied seed that hands control to ArgoCD. `task bootstrap:argocd`
renders the two templates below from the consumer's `cluster.yaml`
bootstrap-identity subset and applies them — the only sanctioned direct-apply
path in the platform.

## Requirements

### Requirement: Root AppProject bootstrap scope

The bootstrap SHALL create an AppProject named `root-bootstrap` in the
`argocd` namespace whose source repos are limited to the consumer repo URL
and whose cluster-resource whitelist permits only Namespaces, with
namespace-scoped resources limited to AppProjects and Applications.

#### Scenario: Rendered AppProject is minimally scoped

- **WHEN** `task bootstrap:argocd` renders `root-project.yaml.tmpl` for a
  consumer `cluster.yaml`
- **THEN** the resulting AppProject allows exactly one `sourceRepos` entry
  (the consumer repo URL) and whitelists only `Namespace` as a cluster
  resource

### Requirement: Root Application app-of-apps seed

The bootstrap SHALL create an Application named `root` in the `argocd`
namespace, bound to project `root-bootstrap`, sourcing
`kubernetes/overlays/<overlay>` of the consumer repo at the pinned
`target_revision`, with automated sync (prune + self-heal), bounded retry,
`CreateNamespace=true` and `ServerSideApply=true`.

#### Scenario: Rendered root Application reconciles the overlay

- **WHEN** the rendered `root` Application is applied to the cluster
- **THEN** ArgoCD reconciles the consumer overlay path automatically,
  pruning drift and self-healing without manual sync

### Requirement: Kubernetes recommended labels on bootstrap resources

Both rendered bootstrap resources SHALL carry the Kubernetes recommended
labels with `app.kubernetes.io/managed-by: bootstrap` (normative label set:
`AGENTS.md §Hard Constraints`).

#### Scenario: Labels present after render

- **WHEN** either template is rendered
- **THEN** the manifest carries `app.kubernetes.io/{name,instance,component,part-of,managed-by}`
