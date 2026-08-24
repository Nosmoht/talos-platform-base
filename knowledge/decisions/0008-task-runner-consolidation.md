---
type: decision
title: "ADR: No wholesale Make→go-task migration — the Makefile dissolves with substrate-only"
description: "Declined a wholesale Make→go-task migration because most Makefile targets were to exit with the substrate-only ablation; superseded by the Makefile-retirement ADR once Phase-3 landed."
status: deprecated
id: base:task-runner-consolidation
superseded_by:
  - /decisions/0012-makefile-retirement.md
decided: "2026-06-07T00:00:00Z"
history:
  - 2026-06-07 initial (accepted; no wholesale Make→go-task migration — the Makefile dissolves with the substrate-only split)
  - 2026-06-22 superseded (Phase-3 ablation #140 landed; base:makefile-retirement folds the survivors into the Taskfile and retires the Makefile — correcting this ADR's per-target table, where render-*/validate-gitops in fact survive because argocd keeps a chart.lock.yaml, and retiring its gnumake-bridge §Validation predicate)
deciders:
  - platform-maintainer
supersedes: []
related:
  - base:substrate-only-base
  - base:opentofu-cluster-lifecycle
tags: [adr, tooling]
---

> **Superseded by [`0012-makefile-retirement.md`](./0012-makefile-retirement.md)
> (`base:makefile-retirement`, 2026-06-22).** Phase-3 ablation (#140) landed, so
> the Decision Outcome §4 trigger below fired: the Makefile is retired and the
> survivors fold into the Taskfile. Two premises here proved wrong in execution
> and are corrected by the superseding ADR — `validate-gitops` / `render-*`
> **survive** (argocd retains a `chart.lock.yaml`), and the §3 `gnumake`-in-devbox
> bridge + the §Validation predicate that depends on it are **retired** (the
> Makefile is deleted, not bridged). The text below is preserved as the
> historical record.

# ADR: No wholesale Make→go-task migration — the Makefile dissolves with substrate-only

## Context and Problem Statement

The OpenTofu cutover (`#82`, ADR `base:opentofu-cluster-lifecycle`) moved
the Talos cluster-lifecycle into `tofu/modules/talos-cluster` and added a
`Taskfile.yml` + `devbox.json` scoped to that subtree. The `Makefile`
still owns the kustomize/Kyverno/bootstrap/MCP targets, and `devbox.json`
declares `go-task` but **not `gnumake`**, so the `make validate-gitops` /
`make argocd-bootstrap` path `AGENTS.md` names is not runnable from the
declared `devbox shell` — a real seam today.

The first cut of this ADR proposed a **wholesale migration of every
Makefile target to go-task**. That was wrong-scoped. Per the **binding
component disposition** in ADR `base:substrate-only-base` (§Amendment
2026-06-03), the 22 infrastructure components split **18 → catalog
(`talos-platform-apps`), 2 → dissolve (`platform-network-interface`,
`kyverno`), 2 → substrate (`argocd`, `cert-approver`)**. Most Makefile
targets serve components that are **leaving the base**, so migrating them
into a new tool would churn targets that Phase-3 ablation deletes.

Per-target reality:

| Target(s) | Operates on | Fate |
|---|---|---|
| `render-component`/`render-all`/`verify-rendered`/`chart-pull`, `validate-gitops`, `grafana-dashboards-check` | the 22 `kubernetes/base/infrastructure/` components | **EXIT** with the 18 catalog-bound components (Phase-3 ablation) — not migrate |
| `validate-kyverno-policies` (+ PNI policies) | base Kyverno `ClusterPolicy` set | **DISSOLVE** — Conftest moves to apps-CI, Kyverno to consumers (ADR-0018) |
| `argocd-install`, `argocd-bootstrap` (helm path) | ArgoCD bootstrap | **already dead** — the module seeds ArgoCD as a Talos `inlineManifest` since `#102` (`deploy_argocd=true`); `make argocd-bootstrap` re-installs it (double-install) |
| `oci-allowlist-check`, `init-cluster-yaml`, `mcp-install`/`mcp-verify`/`mcp-uninstall`, `verify-tools`, `install-pre-commit` | supply-chain / lifecycle / agent / dev-hygiene | **stay** (small substrate + dev residue) |
| `tofu fmt`/`validate`/`lint` | `tofu/` | already in `Taskfile.yml` (`task ci`) |

## Decision Drivers

- Avoid investing migration effort in targets that substrate-only ablation
  will delete.
- The devbox-without-make seam is real **today** and blocks contributor
  onboarding, even though the affected targets are temporary.
- The ArgoCD double-install is a correctness bug independent of tooling.
- Convergence on `go-task` remains the direction for what *survives*
  (the tofu subtree already is go-task; `talos-platform-apps` is full
  go-task).

## Considered Options

1. **Wholesale Make→go-task migration now** — migrate all ~18 targets.
2. **No wholesale migration; let the Makefile dissolve with substrate-only,
   bridge the seam cheaply, fix the bug now** (this decision).
3. **Status quo + ArgoCD point-fix only** — ignore the devbox seam.

## Decision Outcome

Chosen option: **Option 2 — no wholesale migration.** Concretely:

1. **Do not migrate** the component-validation, Kyverno, and ArgoCD-bootstrap
   targets. They **exit** with their components under `base:substrate-only-base`
   Phase-3 ablation (component-validation + PNI/Kyverno) or are **removed**
   outright (the dead ArgoCD helm path).
2. **Fix the ArgoCD double-install now** — remove or `deploy_argocd=false`-gate
   the `make argocd-install` helm path; the module delivers ArgoCD. Rewrite
   `docs/day-zero-pattern.md` Layer-2 to match (the rewrite deferred from
   PR #112).
3. **Bridge the seam cheaply** — add `gnumake` to `devbox.json` so the
   still-live `make` targets run inside `devbox shell` until ablation. This
   is a one-package bridge, not a tool migration.
4. **Converge at ablation, not before** — once Phase-3 lands and the
   surviving target set is final and small (`oci-allowlist-check`,
   `init-cluster-yaml`, `mcp-*`, dev-hygiene), fold the survivors into the
   existing `Taskfile.yml` and retire the `Makefile`. Doing it now is
   premature: the survivor set is not yet fixed.

because most targets leave with the substrate split, so the Makefile is
dissolved *by* `base:substrate-only-base` rather than by a separate
migration project; the only standalone work is the real bug + the cheap
seam bridge.

### Consequences

- Positive: no churn on soon-deleted targets; the devbox seam **will be
  closed** with one package (#113); the ArgoCD bug **will be fixed** (#113);
  the surviving tool home (go-task) is decided once the set is final. (This
  ADR is decision-only — the changes land in #113, not here.)
- Negative: `make` and `task` coexist until Phase-3 ablation (the bridge is
  explicitly temporary). `devbox.json` **will carry** `gnumake` in the interim
  (added by #113).
- Follow-up: tracking issue #113 (rescoped to the bug fix + Layer-2 rewrite +
  devbox bridge). The Makefile retirement itself is folded into the
  `base:substrate-only-base` Phase-3 ablation checklist, not tracked
  separately.

## Pros and Cons of the Options

### Option 1 — Wholesale Make→go-task migration now

- Pro: single runner immediately.
- Con: migrates ~16 targets that ablation deletes; large doc/CI blast radius
  for temporary artifacts; ignores the substrate-only disposition.

### Option 2 — Dissolve with substrate-only; bridge + bug-fix (chosen)

- Pro: minimal, correctly-scoped; closes the seam; fixes the bug; aligns the
  Makefile retirement with the split that already removes most of it.
- Con: two runners coexist temporarily.

### Option 3 — Status quo + ArgoCD point-fix only

- Pro: smallest.
- Con: leaves the devbox-no-make seam open for every contributor until ablation.

## Validation

The decision is **correct** when:

- `devbox shell -- make validate-gitops` runs (no `make: command not found`)
  — i.e. `gnumake` is in `devbox.json`.
- The default bootstrap path has no second `helm upgrade --install argocd`
  (double-install fixed); `docs/day-zero-pattern.md` Layer-2 describes the
  module `inlineManifest` delivery.
- The `base:substrate-only-base` Phase-3 ablation checklist names "retire the
  Makefile / fold survivors into Taskfile" as a step — no separate migration
  project exists.

The decision is **wrong** if the substrate-only split stalls indefinitely
(then the temporary coexistence becomes permanent and a deliberate migration
is warranted after all).

## Links

- ADR `base:substrate-only-base` §Amendment 2026-06-03 — the binding 18/2/2
  component disposition that drives this decision.
- ADR `base:opentofu-cluster-lifecycle` (#82) — the partial tooling migration.
- `tofu/modules/talos-cluster/README.md` §"ArgoCD delivery + health gate", #102
  — the module-delivered ArgoCD that makes `make argocd-install` redundant.
- PR #112 — the v1.0.0 doc sync that deferred the day-zero Layer-2 rewrite here.
- Tracking issue #113 — ArgoCD double-install fix + Layer-2 rewrite + devbox
  bridge (rescoped from the withdrawn wholesale-migration plan).
