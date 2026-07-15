---
sources:
  primary:
    - kubernetes/bootstrap/argocd/root-project.yaml.tmpl
    - kubernetes/bootstrap/argocd/root-application.yaml.tmpl
    - Taskfile.yml#bootstrap:argocd
    - Taskfile.yml#bootstrap:render-root
references:
  - AGENTS.md §Repository Purpose (ArgoCD as co-equal pillar, opt-out)
---

# argocd-day-zero-bootstrap

## Purpose

Turn a freshly provisioned cluster into a GitOps-managed one: the one-time,
direct-applied seed that hands control to ArgoCD. `task bootstrap:argocd`
renders the two templates below from the consumer's `cluster.yaml`
bootstrap-identity subset and applies them — the ArgoCD entry point of the
sanctioned direct-apply exception, which covers the whole
`kubernetes/bootstrap/` tree (AGENTS.md).

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

Both rendered bootstrap resources SHALL carry the full recommended label
set
`app.kubernetes.io/{name,instance,version,component,part-of,managed-by}`
with `app.kubernetes.io/managed-by: bootstrap` and
`app.kubernetes.io/version` set to a label-safe form of the pinned
`target_revision` the root Application tracks — characters outside
`[A-Za-z0-9_.-]` (a git ref may carry `/`) are replaced, the value is
truncated to 63 characters with alphanumeric ends, and the render fails
when nothing label-safe remains; `spec.source.targetRevision` keeps the
raw revision (normative label set: `AGENTS.md §Hard Constraints`).

#### Scenario: Labels present after render

- **WHEN** either template is rendered
- **THEN** the manifest carries
  `app.kubernetes.io/{name,instance,version,component,part-of,managed-by}`,
  with `version` equal to the label-safe form of the rendered
  `target_revision`

#### Scenario: Slash-bearing revision renders a valid label

- **WHEN** `cluster.target_revision` contains characters invalid in a
  Kubernetes label value (for example a `/`-separated branch name)
- **THEN** `app.kubernetes.io/version` carries the sanitized form while
  `spec.source.targetRevision` keeps the raw revision, and the rendered
  manifests pass label validation

### Requirement: Bootstrap-identity subset read from cluster.yaml

The bootstrap render SHALL read exactly four fields from the consumer's
`cluster.yaml` — `.cluster.name`, `.repo.url`, `.cluster.overlay` and
`.cluster.target_revision` — and no others; the file is selected per
invocation (default `cluster.yaml`). `.cluster.target_revision` SHALL default
to `main` when absent. The other three SHALL fail the render when absent or
null, rather than rendering an empty value into a bootstrap manifest.

This is the narrow half of the SoT contract: the full `cluster.yaml` is read
by the consumer's OpenTofu root, while the bootstrap path is deliberately
limited to cluster identity and repo coordinates. Widening the subset widens
what a bootstrap render depends on.

#### Scenario: The four identity fields reach the render

- **WHEN** `task bootstrap:argocd` renders for a `cluster.yaml` carrying
  `.cluster.name`, `.repo.url`, `.cluster.overlay` and
  `.cluster.target_revision`
- **THEN** the rendered root Application and root AppProject carry exactly
  those values, and no other `cluster.yaml` field influences the output

#### Scenario: Absent target_revision defaults to main

- **WHEN** a `cluster.yaml` omits `.cluster.target_revision`
- **THEN** the render proceeds and the root Application tracks `main`

#### Scenario: A missing identity field fails the render

- **WHEN** a `cluster.yaml` omits or nulls `.cluster.name`, `.repo.url` or
  `.cluster.overlay`
- **THEN** the render fails and no bootstrap manifest is written or applied

### Requirement: Envsubst containment of cluster.yaml values

A `cluster.yaml` value SHALL reach a rendered bootstrap manifest as itself and
nothing else. The render SHALL enforce this with two independent guards:

1. every value read from `cluster.yaml` is rejected, before any template is
   rendered, when it contains `$` — the render fails with an error naming the
   offending value;
2. `envsubst` is invoked with an explicit allowlist of the substitution
   variable names the templates use, so any other `$NAME` sequence in a
   template is left literal rather than expanded from the render host's
   environment.

Guard 2 SHALL hold independently of guard 1: it is what keeps a `$`-bearing
value that reached a template — through a future refactor, a widened subset,
or a template edit — from expanding to the render host's environment. Neither
guard is observable in the rendered output for well-formed input, which is
why both are pinned here rather than left to the render's implementation.

#### Scenario: A dollar-bearing value fails the render

- **WHEN** any of the read `cluster.yaml` values contains `$`
- **THEN** the render fails with an error naming the offending value, and no
  bootstrap manifest is written or applied

#### Scenario: Host environment does not leak into a rendered manifest

- **WHEN** a bootstrap template contains a `$NAME` sequence outside the
  render's allowlisted substitution variables, and `NAME` is set in the render
  host's environment
- **THEN** the rendered manifest carries the sequence literally and the host
  value does not appear in it
