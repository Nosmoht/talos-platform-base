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
to `main` when absent. The other three SHALL fail the render when absent,
null, empty, or not a string.

This is the narrow half of the SoT contract: the full `cluster.yaml` is read
by the consumer's OpenTofu root, while the bootstrap path is deliberately
limited to cluster identity and repo coordinates. Widening the subset widens
what a bootstrap render depends on.

`.cluster.overlay` is **schema-optional but bootstrap-required**: the document
schema admits a `cluster.yaml` without it (`cluster-yaml-sot`, Requirement
"Cluster identity, endpoint, and network shape" — `cluster` requires only
`name` and `endpoint`), because a consumer may drive the OpenTofu root without
ever seeding an App-of-Apps root. This path is the consumer that narrows it: a
`cluster.yaml` can be schema-conformant and still be refused here, and that is
the intended split rather than a contradiction between the two specs.

#### Scenario: The four identity fields reach the render

- **WHEN** `task bootstrap:render-root` renders for a `cluster.yaml` carrying
  the four identity fields
- **THEN** the rendered root Application carries that `repo.url`, that
  overlay as its `path`, and that `cluster.name` as its instance label, and
  the rendered AppProject carries that `repo.url` in `sourceRepos`

#### Scenario: No other cluster.yaml field influences the output

- **WHEN** two `cluster.yaml` files agree on the four identity fields and
  differ in every other field
- **THEN** both render byte-identical root Application and AppProject
  manifests

#### Scenario: Absent target_revision defaults to main

- **WHEN** a `cluster.yaml` omits `.cluster.target_revision`
- **THEN** the render proceeds and the root Application tracks `main`

#### Scenario: A missing identity field fails the render

- **WHEN** a `cluster.yaml` omits or nulls `.cluster.name`, `.repo.url` or
  `.cluster.overlay`
- **THEN** the render fails and no bootstrap manifest is written or applied

### Requirement: Containment of cluster.yaml values in the rendered manifest

A `cluster.yaml` value SHALL reach a rendered bootstrap manifest as a scalar
in its own YAML position, and SHALL NOT expand, or introduce YAML structure,
into the manifest around it. The render SHALL reject, before reading any
template, any read value that:

1. contains `$` — `envsubst` would otherwise expand it against the render
   host's environment;
2. contains a newline — `envsubst` substitutes text, not YAML, so a
   line break carries the rest of the value out of its scalar position and
   into sibling keys or list items;
3. is empty — an empty substitution renders a manifest field that is
   syntactically valid and semantically wrong (an empty overlay names the
   whole overlay tree);
4. is not a string — a mapping or sequence serializes its subtree into the
   value, which is (2) by another route and is not caught by (2) when the
   node serializes to a single line.

None of these is observable in the rendered output for well-formed input,
which is why they are pinned here rather than left to the render's
implementation. The bounds of the claim: the guards constrain the four
identity VALUES. They are not a general YAML-injection defense for the
templates, and they do not validate the values semantically — a syntactically
clean but wrong repo URL renders happily.

Separately, `envsubst` SHALL be invoked with an explicit allowlist of the
substitution variable names the templates use, so a `$NAME` sequence a
template carries outside that set stays literal instead of resolving against
the render host's environment. This constrains the TEMPLATE text, not the
values: `envsubst` is single-pass and never rescans what it substituted, so a
`$`-bearing value would render literally with or without the allowlist. The
two mechanisms cover different surfaces and neither substitutes for the other.

Mechanically asserted for every scenario below by
`scripts/check-bootstrap-render.sh` (`task bootstrap:check-render`, in the
`hardware-features-check` CI job, offline — the render is `yq` + `envsubst`
and contacts no cluster). Removing any single guard turns it red.

#### Scenario: A dollar-bearing value fails the render

- **WHEN** any of the read `cluster.yaml` values contains `$`
- **THEN** the render fails with an error naming the offending value, and no
  bootstrap manifest is written or applied

#### Scenario: A newline-bearing value fails the render

- **WHEN** a read `cluster.yaml` value contains a line break — schema-valid,
  since the identity fields carry no pattern
- **THEN** the render fails and no bootstrap manifest is written or applied,
  rather than the trailing lines becoming sibling YAML in the manifest

#### Scenario: An empty or non-string value fails the render

- **WHEN** a read `cluster.yaml` value is the empty string, or is a mapping or
  sequence rather than a string
- **THEN** the render fails and no bootstrap manifest is written or applied

#### Scenario: Host environment does not leak into a rendered manifest

- **WHEN** a bootstrap template contains a `$NAME` sequence outside the
  render's allowlisted substitution variables, and `NAME` is set in the render
  host's environment
- **THEN** the rendered manifest carries the sequence literally and the host
  value does not appear in it
