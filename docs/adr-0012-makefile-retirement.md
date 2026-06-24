---
status: accepted
id: base:makefile-retirement
date: 2026-06-22
deciders:
  - Thomas Krahn
consulted: []
informed: []
supersedes:
  - base:task-runner-consolidation
related:
  - base:substrate-only-base
  - base:opentofu-cluster-lifecycle
---

# ADR: Retire the Makefile — go-task is the single runner

## Context and Problem Statement

ADR `base:task-runner-consolidation` (2026-06-07) decided **against** a
wholesale Make→go-task migration, on the premise that most Makefile targets
served the 18 infrastructure components leaving the base under
`base:substrate-only-base`. Its Decision Outcome §4 committed to the convergence
explicitly, but deferred it: *"once Phase-3 lands and the surviving target set is
final and small … fold the survivors into the existing `Taskfile.yml` and retire
the `Makefile`. Doing it now is premature: the survivor set is not yet fixed."*

Phase-3 (the substrate-only ablation, #140) **has landed** at v2.0.0. The tracked
`kubernetes/base/infrastructure/` set is now git-fixed to `{argocd,
cert-approver}`. The precondition the prior ADR named is therefore met, and this
ADR executes its §4 convergence. It is filed as a **supersession** rather than a
mere follow-up because two of the prior ADR's load-bearing premises proved wrong
in execution, and recording that honestly matters more than preserving the
"no migration" headline:

1. **The per-target table mispredicted survivors.** The prior ADR routed
   `validate-gitops` and `render-*`/`verify-rendered` to *EXIT* with the
   catalog-bound components. They did **not**: `argocd` retains a
   `chart.lock.yaml` + a committed `_rendered/` tree (the Rendered Manifests
   Pattern), and `make validate-gitops` still renders both surviving substrate
   components. These targets **survive** and fold into the Taskfile — the
   opposite of the table's prediction. (The ADR's implicit "zero remaining
   render consumers after ablation" assumption was false; argocd is a consumer.)
2. **The interim `gnumake`-in-devbox bridge is now moot.** The prior ADR's §3
   ("add `gnumake` to `devbox.json`") and its §Validation predicate
   (`devbox shell -- make validate-gitops` runs ⇒ `gnumake` present) assumed a
   coexistence window before ablation. Because Phase-3 already landed, that
   window is closed: the bridge was never added (the original #113 was closed
   `COMPLETED` with no deliverable merged), and it will **not** be added — the
   Makefile is *deleted*, not bridged. That predicate is retired here.
3. **Phase-3 landed without folding the Makefile.** The prior ADR said the
   retirement was "folded into the `base:substrate-only-base` Phase-3 ablation
   checklist, not tracked separately." #140 shipped Phase-3 but left the Makefile
   intact, so the standalone action the prior ADR said would not exist is exactly
   this change.

## Decision Drivers

- The deferral precondition ("survivor set fixed") is now satisfied by #140.
- A single runner inside `devbox shell` is the stated convergence direction — the
  `tofu/` subtree and `talos-platform-apps` are already full go-task.
- Two runners (`make` + `task`) is a real contributor-onboarding seam: `devbox`
  declares `go-task`, never `gnumake`, so the `make` path was never runnable from
  the declared shell.
- A flat-vs-namespaced naming split (`make validate-gitops` becoming `validate`
  alongside a tofu `validate`) is ambiguous; one namespaced scheme resolves it.

## Considered Options

1. **Add the `gnumake` bridge now, retire later** — execute the prior ADR's §3
   literally even though Phase-3 already landed.
2. **Retire the Makefile now; fold survivors into the Taskfile** (this decision).
3. **Status quo** — leave the Makefile and the devbox-no-make seam in place.

## Decision Outcome

Chosen option: **Option 2 — retire the Makefile now.** Phase-3 has landed, so the
prior ADR's own §4 trigger fires; bridging (Option 1) would invest in a
coexistence window that no longer exists. Concretely:

1. **Fold every survivor target into `Taskfile.yml`** under a namespaced scheme:
   `tofu:*` (the existing OpenTofu tasks, namespaced), `gitops:*`
   (`validate`, `render-component`, `render-all`, `verify-rendered`),
   `bootstrap:*` (`argocd`, `argocd-password`), `cluster:init-yaml`,
   `supply-chain:oci-allowlist`, `mcp:*` (`install`, `verify`, `uninstall`),
   `dev:*` (`install-pre-commit`, `verify-tools`).
2. **Drop two targets with no replacement.** `chart-pull` is a base-dev helper
   for authoring a new `chart.lock.yaml` (no CI consumer); `grafana-dashboards-check`
   scans `kubernetes/overlays/<cluster>/…`, a **consumer** overlay path absent in
   the substrate base. Both are documented as removed.
3. **Replace the `Makefile` with a one-release deprecation stub** — any
   `make <target>` prints the migration mapping and exits non-zero, so a stale
   habit gets a clear message instead of `No rule to make target`. Deleted next
   MAJOR.
4. **Update `devbox.json`** — add `yq-go` + `gettext` + `ripgrep` (the
   `bootstrap:*` / `cluster:*` tasks read `cluster.yaml` via `yq` and template
   via `envsubst`; `gitops:validate` → `scripts/render_kustomize_safe.sh`
   requires `rg` for its ksops detection). **Not** `gnumake` — the bridge is
   retired, the Makefile is deleted.
5. **Re-point CI** — `tofu-validate.yml` calls `task tofu:ci` / `task tofu:test`
   (the namespaced names).

### Consequences

- Positive: one runner; the devbox-no-make seam is closed by deletion, not a
  package bridge; the `validate` naming collision is resolved (`tofu:validate`
  vs `gitops:validate`); the base matches `talos-platform-apps`.
- Negative: a one-cycle deprecation stub; **dev-facing BREAKING** — consumer
  day-zero runbooks or scripts invoking `make <target>` must switch to
  `task <target>` (the stub + CHANGELOG + UPGRADING document the mapping).
- Follow-up: delete the Makefile stub in the next MAJOR; close #113 (the
  bootstrap fix landed in the sibling PR, the runner retirement here).

## Pros and Cons of the Options

### Option 1 — `gnumake` bridge now, retire later

- Pro: literal compliance with the prior ADR's §3.
- Con: invests in a coexistence window that Phase-3 already closed; defers the
  same retirement work behind an extra package + an extra step.

### Option 2 — retire now, fold survivors (chosen)

- Pro: executes the prior ADR's §4 trigger exactly when it fires; single runner;
  no throwaway bridge package.
- Con: a one-cycle stub; a dev-facing breaking change for `make`-based runbooks.

### Option 3 — status quo

- Pro: zero change.
- Con: leaves the devbox-no-make seam open for every contributor indefinitely;
  the prior ADR already rejected this.

## Validation

The decision is **correct** when:

- `devbox shell -- task --list` shows every survivor task with a non-empty
  description, and `task tofu:ci` + `task gitops:validate` exit 0.
- CI `tofu-validate.yml` runs `task tofu:ci` + `task tofu:test` (green).
- `make <any-target>` prints the migration stub and exits non-zero; no
  `make <target>` operational invocation remains in docs / templates / scripts
  (historical ADR bodies excepted).
- `devbox.json` carries `yq-go` + `gettext` and **not** `gnumake`.

The decision is **wrong** if a dropped target (`chart-pull`,
`grafana-dashboards-check`) turns out to have a live consumer — mitigated:
both are base-dev/consumer-overlay only, neither is referenced by CI or the OCI
tarball.

## Links

- ADR `base:task-runner-consolidation` — the superseded decision; this ADR
  executes its Decision Outcome §4 and corrects its per-target table + §Validation
  predicate.
- ADR `base:substrate-only-base` §Amendment 2026-06-03 — the 18/2/2 component
  disposition; Phase-3 ablation (#140) is the trigger this ADR fires on.
- ADR `base:opentofu-cluster-lifecycle` — the partial tooling migration that
  first introduced `Taskfile.yml` + `devbox.json`.
- Tracking issue #113 — the ArgoCD double-install fix and Layer-2 rewrite
  (sibling PR) plus the devbox-no-make seam closure (this PR).
