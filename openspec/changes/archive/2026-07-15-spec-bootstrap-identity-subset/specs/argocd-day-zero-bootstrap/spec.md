## ADDED Requirements

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
