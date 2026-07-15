## Why

`Taskfile.yml#bootstrap:render-root` is a `primary` source of the
`argocd-day-zero-bootstrap` spec, but that spec's three requirements describe
only what the rendered AppProject, the rendered Application and their labels
look like. How the render obtains its values — which four `cluster.yaml` fields
it reads, what happens when one is absent, and the two guards that stop a
`cluster.yaml` value from expanding into something other than itself — is
consumer-facing, observable behavior that no requirement covers.

The gap surfaced while removing spec-duplicated prose from
`knowledge/reference/`: the subset was carried by narrative docs
(`knowledge/reference/cluster-yaml.md` and `knowledge/reference/tasks.md` —
**two** hand-maintained copies, both under `knowledge/`, neither watched by a
gate) and by no requirement. That is backwards: the spec's owning gate
(`task spec:check-staleness`) fires at fragment granularity on exactly this
Taskfile key, so an edit to `bootstrap:render-root` that widened the subset or
dropped the `$` rejection would force a touch of a spec that says nothing about
either — the gate would fire and be satisfied by an unrelated edit.

Review of this change then found that the guards the docs described were not
the guards the render needed: a schema-valid value carrying a newline injected
YAML structure into the rendered AppProject (widening `sourceRepos` to `'*'`),
and an empty `overlay` rendered a root Application pointed at the entire
overlay tree with prune+selfHeal enabled. Both are shipped defects, not
regressions of this change — but a spec that certified containment while they
existed would have been worse than the prose it replaced. So this change
closes them and specs the guards that result.

## What Changes

- `argocd-day-zero-bootstrap` gains a requirement pinning the bootstrap-identity
  subset: the four fields read (`.cluster.name`, `.repo.url`,
  `.cluster.overlay`, `.cluster.target_revision`), the `"main"` default for the
  revision, and that a missing/null/empty/non-string value among the other three
  fails the render. It records that `.cluster.overlay` is **schema-optional but
  bootstrap-required** — the schema admits a `cluster.yaml` without it because a
  consumer may drive only the OpenTofu root; this path is the consumer that
  narrows it.
- `argocd-day-zero-bootstrap` gains a requirement for value containment in the
  rendered manifest. **BREAKING for a `cluster.yaml` that relies on the gap**: a
  value that is empty, multi-line, or non-string is now rejected where it
  previously rendered. Each rejection closes a shipped defect:
  1. `$` — pre-existing guard, would expand against the render host's
     environment;
  2. newline — **new**: schema-valid today (the identity fields carry no
     pattern), previously injected sibling YAML into the manifest;
  3. empty — **new**: `overlay: ""` previously rendered
     `path: kubernetes/overlays/` on a prune+selfHeal Application;
  4. non-string — **new**: a mapping serialized its subtree into the value; a
     flow-style one (`{a: b}`) is single-line, so the newline guard does not
     cover it.
  Separately it pins the `envsubst` SHELL-FORMAT allowlist, which constrains
  TEMPLATE text — not values. `envsubst` is single-pass and never rescans what
  it substituted, so the allowlist is not what keeps a `$`-bearing value
  literal. The two mechanisms cover different surfaces; an earlier draft of this
  proposal claimed otherwise.
- `cluster-yaml-sot` gains a paragraph naming the schema-optional /
  bootstrap-required split from its side, so the two specs no longer disagree
  in silence about `overlay`.
- No requirement is removed. The rendered manifest for a well-formed
  `cluster.yaml` is byte-identical.

## Capabilities

### New Capabilities

None. The behavior belongs to an existing capability.

### Modified Capabilities

- `argocd-day-zero-bootstrap`: two ADDED requirements covering the
  bootstrap-identity subset and value containment in the rendered manifest.
- `cluster-yaml-sot`: one requirement gains a paragraph on the
  schema-optional / bootstrap-required split for `overlay`. No requirement's
  assertion changes.

## Impact

- Specs: `openspec/specs/argocd-day-zero-bootstrap/spec.md` (two requirements
  added on archive), `openspec/specs/cluster-yaml-sot/spec.md` (cross-reference).
  No `sources` change, so the source-ownership partition is unaffected.
- Code: `Taskfile.yml#bootstrap:render-root` gains the newline / empty /
  non-string guards, an explicit `set -e` (the fail-closed property previously
  rested on the go-task runner's shell defaulting to errexit — not on the code),
  quoting of the `{{.ENV}}` interpolation (go-task renders it as raw text before
  `sh` parses it, so `ENV='cluster.yaml; cmd'` executed `cmd`), and a temp-dir
  render so a failure cannot leave a half-populated `_out/`. `render-root` is
  no longer `internal:`, which is what makes it invocable by the check below.
- Gates: **added** — `scripts/check-bootstrap-render.sh`
  (`task bootstrap:check-render`, in the `hardware-features-check` job).
  Without it these requirements would be five WHEN/THEN oracles that nothing
  executes, describing behavior the spec itself calls invisible in the rendered
  output — the failure mode
  `knowledge/decisions/0016-capability-profiles-predicate-only.md` exists to
  record. Every guard is red-green: deleting any one turns the check red
  (verified per-guard).
- Docs: `knowledge/reference/cluster-yaml.md` and `knowledge/reference/tasks.md`
  now cite the spec for the subset instead of restating it.
