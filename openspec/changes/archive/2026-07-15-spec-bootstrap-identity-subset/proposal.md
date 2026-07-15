## Why

`Taskfile.yml#bootstrap:render-root` is a `primary` source of the
`argocd-day-zero-bootstrap` spec, but that spec's three requirements describe
only what the rendered AppProject, the rendered Application and their labels
look like. How the render obtains its values — which four `cluster.yaml` fields
it reads, what happens when one is absent, and the two guards that stop a
`cluster.yaml` value from expanding into something other than itself — is
consumer-facing, observable behavior that no requirement covers.

The gap surfaced while removing spec-duplicated prose from
`knowledge/reference/`: the bootstrap-identity subset was documented **only**
in `knowledge/reference/cluster-yaml.md`. That is backwards. A narrative doc
under `knowledge/` has no gate watching its source, while the spec's owning
gate (`task spec:check-staleness`) fires at fragment granularity on exactly
this Taskfile key. Today an edit to `bootstrap:render-root` that widened the
subset or dropped the `$` rejection would force a touch of a spec that says
nothing about either — the gate would fire and be satisfied by an unrelated
edit.

This is a documentation-to-spec relocation of already-shipped behavior. No code
changes.

## What Changes

- `argocd-day-zero-bootstrap` gains a requirement pinning the bootstrap-identity
  subset: the four fields read (`.cluster.name`, `.repo.url`,
  `.cluster.overlay`, `.cluster.target_revision`), the `"main"` default for the
  revision, and that a missing or null value among the other three fails the
  render rather than substituting empty.
- `argocd-day-zero-bootstrap` gains a requirement for the two envsubst
  containment guards, which today exist in code with no spec behind them:
  1. every read value is rejected when it contains `$`, before any render;
  2. `envsubst` is invoked with an explicit variable allowlist, so a `$NAME`
     sequence surviving into a template is left literal rather than expanded
     from the render host's environment.
  Guard 2 is what makes guard 1 defense-in-depth rather than the only line —
  worth spec'ing precisely because a future refactor could drop either while
  the rendered output still looks correct for well-formed input.
- No requirement is modified or removed; no rendered manifest changes.

## Capabilities

### New Capabilities

None. The behavior belongs to an existing capability.

### Modified Capabilities

- `argocd-day-zero-bootstrap`: two ADDED requirements covering the
  bootstrap-identity subset the render reads and the envsubst containment
  guards. Both describe shipped behavior; the render's observable output for
  well-formed input is unchanged.

## Impact

- Specs: `openspec/specs/argocd-day-zero-bootstrap/spec.md` (two requirements
  added on archive). Its `sources` already list
  `Taskfile.yml#bootstrap:render-root` — no ownership change, so the
  source-ownership partition is unaffected.
- Code: none. `Taskfile.yml#bootstrap:render-root` already implements
  everything asserted here (verified at the source, lines 226–248).
- Docs: `knowledge/reference/cluster-yaml.md` §Two consumers, two subsets
  becomes a narrative restatement of a now-spec'd contract. It stays for the
  consumer-OpenTofu-root half, which no spec covers; the bootstrap half should
  cite the spec instead of carrying the detail — a follow-up to this change,
  not part of it.
- Gates: none added. `task spec:check-staleness` already watches this Taskfile
  fragment; after this change, firing on it points at requirements that
  actually describe the fragment.
