## ADDED Requirements

### Requirement: Overlay is schema-optional but bootstrap-required

The bootstrap render SHALL refuse a `cluster.yaml` without `.cluster.overlay`
even though the document schema admits one (`cluster-yaml-sot`, Requirement
"Cluster identity, endpoint, and network shape" — `cluster` requires only
`name` and `endpoint`). A `cluster.yaml` can be schema-conformant and still be
refused here; that is the intended split, not a contradiction between the two
specs.

#### Scenario: A schema-conformant file without an overlay is refused

- **WHEN** a `cluster.yaml` that conforms to the document schema omits
  `.cluster.overlay`
- **THEN** the bootstrap render fails and no bootstrap manifest is written or
  applied

### Requirement: YAML round-trip guard on cluster.yaml values

The render SHALL round-trip each read value through the same YAML parser that
will read the manifest and reject the value unless it comes back as itself.
This SHALL catch the class of plain, non-empty, `$`-free,
control-character-free strings that carry YAML syntax changing their meaning
once substituted, which the character-class checks cannot express.

#### Scenario: Each listed YAML-syntax form is caught

- **WHEN** a read value is `'*'` (which parses to `*`, in `sourceRepos` the
  wildcard that trusts every repository), ends in a trailing space (which is
  stripped), contains a space-then-hash (which starts a comment), or is an
  anchor such as `&a`
- **THEN** the round-trip check rejects it and the render fails

### Requirement: Overlay bound to a plain directory name

The render SHALL additionally require `.cluster.overlay` to match
`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`, a positive bound, because its sink is a
path and the other value checks are all negative. The document schema carries
the same pattern; the render SHALL re-check it because the schema does not run
on this path.

#### Scenario: A parent-directory overlay is refused despite passing the rest

- **WHEN** `cluster.yaml` carries `overlay: ".."`, a plain string that passes
  every negative value check
- **THEN** the render fails rather than `path: kubernetes/overlays/${OVERLAY}`
  on an Application with prune and self-heal enabled resolving to
  `kubernetes/` and handing that Application the whole tree

### Requirement: Bounds of the value guards

The value guards SHALL constrain the four identity values only, and only
`cluster.overlay` SHALL be bound positively. They are not a general
YAML-injection defense for the templates and SHALL NOT be read as making a
value correct: `repo.url` is bounded only by round-trip stability, not by a
URL grammar.

#### Scenario: A well-formed wrong repo URL still renders

- **WHEN** `repo.url` is a well-formed URL that points at the wrong repository
- **THEN** the render succeeds and carries that URL

### Requirement: Allowlisted envsubst substitution

`envsubst` SHALL be invoked with an explicit allowlist of the substitution
variable names the templates use, so a `$NAME` sequence a template carries
outside that set stays literal instead of resolving against the render host's
environment. The allowlist constrains the TEMPLATE text, not the values, and
neither it nor the `$` value check SHALL substitute for the other.

#### Scenario: A substituted value is never rescanned

- **WHEN** `envsubst` substitutes a value
- **THEN** it does not rescan the substituted text, being single-pass, so a
  `$`-bearing value would render literally with or without the allowlist

### Requirement: Value guards asserted offline in CI

`scripts/check-bootstrap-render.sh` (`task bootstrap:check-render`, in the
`hardware-features-check` CI job) SHALL mechanically assert the value-guard
scenarios its scenario below names, offline — the render is `yq` +
`envsubst` and contacts no cluster. Removing any single guard SHALL turn it
red.

#### Scenario: The check covers the named guard scenarios

- **WHEN** `task bootstrap:check-render` runs
- **THEN** it asserts the scenarios "A dollar-bearing value fails the render",
  "A line-break-bearing value fails the render", "An empty or non-string
  value fails the render", "A value carrying YAML syntax fails the render",
  "An overlay that is not a plain directory name fails the render" and "Host
  environment does not leak into a rendered manifest"

#### Scenario: Removing a guard turns the check red

- **WHEN** any single one of those guards is removed from the render
- **THEN** `task bootstrap:check-render` fails

#### Scenario: The check runs without a cluster

- **WHEN** the `hardware-features-check` CI job runs
  `task bootstrap:check-render`
- **THEN** it renders with `yq` + `envsubst` only and contacts no cluster

## MODIFIED Requirements

### Requirement: Kubernetes recommended labels on bootstrap resources

Both rendered bootstrap resources SHALL carry the full recommended label
set
`app.kubernetes.io/{name,instance,version,component,part-of,managed-by}`
with `app.kubernetes.io/managed-by: bootstrap` and
`app.kubernetes.io/version` set to a label-safe form of the pinned
`target_revision` the root Application tracks, while
`spec.source.targetRevision` keeps the raw revision (normative label set:
`AGENTS.md §Hard Constraints`).

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

#### Scenario: The version label is sanitized and bounded

- **WHEN** `cluster.target_revision` is rendered into
  `app.kubernetes.io/version`
- **THEN** every character outside `[A-Za-z0-9_.-]` (a git ref may carry `/`)
  is replaced
- **AND** the value is truncated to 63 characters with alphanumeric ends

#### Scenario: A revision with no label-safe remainder fails the render

- **WHEN** nothing label-safe remains of `cluster.target_revision` after
  sanitization
- **THEN** the render fails

### Requirement: Bootstrap-identity subset read from cluster.yaml

The bootstrap render SHALL read exactly four fields from the consumer's
`cluster.yaml` — `.cluster.name`, `.repo.url`, `.cluster.overlay` and
`.cluster.target_revision` — and no others; the file is selected per
invocation (default `cluster.yaml`). `.cluster.target_revision` SHALL default
to `main` when absent. The other three SHALL fail the render when absent,
null, empty, or not a string.

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
in its own YAML position, meaning in the rendered manifest exactly what it
means in `cluster.yaml`, and SHALL NOT expand or introduce YAML structure into
the manifest around it. The render SHALL reject, before reading any template,
any read value that contains `$` or a control character, is empty, is not a
string, or does not survive a YAML round-trip as itself.

#### Scenario: A dollar-bearing value fails the render

- **WHEN** any of the read `cluster.yaml` values contains `$`
- **THEN** the render fails with an error naming the offending value, and no
  bootstrap manifest is written or applied

#### Scenario: A line-break-bearing value fails the render

- **WHEN** a read `cluster.yaml` value contains a line break — either `\n` or
  a lone `\r`; `repo.url` and `target_revision` admit one and stay
  schema-valid, since neither carries a pattern
- **THEN** the render fails and no bootstrap manifest is written or applied,
  rather than the trailing text becoming sibling YAML in the manifest

#### Scenario: Any other C0 control character fails the render

- **WHEN** a read `cluster.yaml` value contains any C0 control character, not
  only one of the YAML 1.2 line breaks `\n` and a lone `\r`
- **THEN** the render fails and no bootstrap manifest is written or applied

#### Scenario: An empty or non-string value fails the render

- **WHEN** a read `cluster.yaml` value is the empty string, or is a mapping or
  sequence rather than a string
- **THEN** the render fails and no bootstrap manifest is written or applied

#### Scenario: A single-line mapping or sequence fails the render

- **WHEN** a read `cluster.yaml` value is a mapping or sequence whose node
  serializes to a single line, so it carries no line break
- **THEN** the render still fails as a non-string value and no bootstrap
  manifest is written or applied

#### Scenario: A value carrying YAML syntax fails the render

- **WHEN** a read `cluster.yaml` value is a plain string that does not survive
  a YAML round-trip as itself — quoting (`'*'`), a trailing space, an inline
  comment, or an anchor
- **THEN** the render fails and no bootstrap manifest is written or applied,
  rather than the value meaning something else in the rendered manifest

#### Scenario: An overlay that is not a plain directory name fails the render

- **WHEN** `.cluster.overlay` does not match
  `^[a-z0-9]([-a-z0-9]*[a-z0-9])?$` — a path segment such as `..`, an absolute
  path, or any other non-label value
- **THEN** the render fails and no bootstrap manifest is written or applied,
  rather than the root Application resolving its `path` outside
  `kubernetes/overlays/`

#### Scenario: Host environment does not leak into a rendered manifest

- **WHEN** a bootstrap template contains a `$NAME` sequence outside the
  render's allowlisted substitution variables, and `NAME` is set in the render
  host's environment
- **THEN** the rendered manifest carries the sequence literally and the host
  value does not appear in it
