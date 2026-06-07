---
status: accepted
id: base:task-runner-consolidation
date: 2026-06-07
deciders:
  - Thomas Krahn
consulted: []
informed: []
supersedes: []
related:
  - base:opentofu-cluster-lifecycle
  - base:multi-repo-platform-split
---

# ADR: Consolidate the developer workflow on go-task + devbox (retire the Makefile)

## Context and Problem Statement

The OpenTofu cutover (`#82`, ADR `base:opentofu-cluster-lifecycle`) moved
the Talos cluster-lifecycle out of the `Makefile` into the
`tofu/modules/talos-cluster` module and introduced a `Taskfile.yml` +
`devbox.json` for that subtree. That migration was **partial**: the
`Taskfile` header explicitly scopes itself to `tofu/` and leaves the
kustomize/Kyverno/bootstrap/MCP world in the `Makefile`.

The result is a split developer interface that has a real seam:

- `devbox.json` declares `go-task` (and the tofu toolchain) but **not
  `gnumake`**, and its `init_hook` directs the user to `task --list`. So
  inside `devbox shell`, the `make validate-gitops` / `make argocd-bootstrap`
  targets that `AGENTS.md` names as the primary validation path are not
  runnable from the declared environment.
- The `Taskfile` header states it "mirrors talos-platform-apps" — the
  sibling apps repo runs its full workflow through `go-task`, so the base
  is the outlier.
- The `Makefile` still owns ~18 targets: `init-cluster-yaml`,
  `argocd-install`/`argocd-bootstrap`/`argocd-password`, `validate-gitops`,
  `validate-kyverno-policies`, `render-component`/`render-all`/`verify-rendered`/`chart-pull`,
  `grafana-dashboards-check`, `oci-allowlist-check`, `install-pre-commit`,
  `verify-tools`, `mcp-install`/`mcp-verify`/`mcp-uninstall`. Most are thin
  wrappers over `scripts/`.

A latent correctness bug rides on the same seam: since `#102`
(`deploy_argocd` defaults to `true`) the module seeds ArgoCD as a Talos
`inlineManifest` at `tofu apply`, yet `make argocd-bootstrap` still depends
on `make argocd-install` (`helm upgrade --install argocd …`). The documented
day-zero recipe (`tofu apply` then `make argocd-bootstrap`) therefore
**installs ArgoCD twice** on the default path.

## Decision Drivers

- Single coherent developer entry point (`devbox shell` → `task`) instead of
  two runners with an environment that only ships one of them.
- Consistency with the sibling `talos-platform-apps` repo (already full
  go-task).
- The devbox-without-make seam makes the documented validation commands
  unrunnable from the declared environment — a contributor-onboarding defect.
- Opportunity to fix the ArgoCD double-install during the migration rather
  than preserving it in a retired tool.

## Considered Options

1. **Full consolidation on go-task + devbox** — migrate every Makefile
   target to a `task` target, expand `devbox.json` with the packages those
   tasks need, retire the `Makefile` (or leave a thin delegating shim), fix
   the ArgoCD bootstrap during the move, and rewrite the docs.
2. **Keep the split, close the seam** — add `gnumake` to `devbox.json` and
   document the Make=manifests / Task=tofu split as intentional; fix the
   ArgoCD bug in the Makefile.
3. **Status quo + point-fix** — only fix the ArgoCD double-install in the
   Makefile; leave the two-runner split and the seam.

## Decision Outcome

Chosen option: **Full consolidation on go-task + devbox** (Option 1),
because the declared dev environment is already go-task-centric (no make in
`devbox.json`), the sibling apps repo sets the convention, and a single
`devbox shell` + `task` entry point removes the onboarding seam while giving
a natural home to fix the ArgoCD bootstrap bug.

### Consequences

- Positive: one runner, one declared environment; `devbox shell` + `task`
  runs everything; parity with `talos-platform-apps`; the ArgoCD
  double-install is fixed as part of the move.
- Negative: **breaking change to the contributor interface** — every
  `make <target>` in docs, CI, and muscle memory becomes `task <target>`.
  `devbox.json` grows to declare the manifest/bootstrap toolchain (`kubectl`,
  `helm`, `conftest`, `kubeconform`, `kyverno`, `oras`, `cosign`, `syft`,
  `yq`, `gettext`/`envsubst`, `gh`, `uv`).
- Follow-up: tracked migration issue (see Links) carries the per-target
  mapping + testable ACs; this also resolves the deferred
  `docs/day-zero-pattern.md` Layer-2 rewrite (PR #112) and should reconcile
  the `.tool-versions`/asdf vs `devbox.json` version-pin duplication
  (`verify-tools` reads `.tool-versions`).

## Pros and Cons of the Options

### Option 1 — Full consolidation on go-task + devbox

- Pro: single entry point; environment/runner parity; matches the sibling
  repo; fixes the ArgoCD bug in-flight; removes the devbox-no-make seam.
- Con: largest blast radius (docs + CI + contributor interface); devbox
  package list grows; one migration arc before the repo is consistent again.

### Option 2 — Keep the split, close the seam

- Pro: smallest change; preserves existing muscle memory.
- Con: cements two runners and a dual toolchain declaration permanently;
  diverges from the apps repo; the "why two runners" question recurs for
  every new contributor.

### Option 3 — Status quo + point-fix

- Pro: minimal.
- Con: leaves the seam and the directional inconsistency unresolved; the
  ArgoCD fix lands in a tool the project is drifting away from.

## Validation

The decision is **correct** when:

- `task --list` exposes an equivalent for every former `make` target, and the
  `Makefile` is removed or is a thin `task`-delegating shim.
- `devbox shell -- task validate-gitops` (and the other migrated tasks) run
  with no "command not found" — i.e. `devbox.json` declares the full
  toolchain.
- `grep -rIn '\bmake ' README.md AGENTS.md CONTRIBUTING.md docs/` returns
  only intentional historical references.
- The default bootstrap path contains no second `helm upgrade --install
  argocd` (ArgoCD double-install fixed).
- CI is green after workflows are repointed to `task`.

The decision is **wrong** if a third workflow runner is introduced, or if
the migrated tasks cannot be expressed without re-introducing make-specific
constructs.

## Links

- ADR `base:opentofu-cluster-lifecycle` — the partial migration this completes.
- `Taskfile.yml` header — the documented `tofu/`-only scope + apps-repo mirror note.
- PR #112 — the v1.0.0 doc sync that deferred the `day-zero-pattern.md`
  Layer-2 rewrite to this decision.
- Tracking issue #113 — the per-target migration plan + ArgoCD-fix ACs.
