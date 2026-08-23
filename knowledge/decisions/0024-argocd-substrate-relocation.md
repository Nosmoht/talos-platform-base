---
type: decision
title: "ADR: Steady-state ArgoCD lives at kubernetes/substrate/ and ships in the OCI artifact"
description: "The steady-state ArgoCD render relocates from kubernetes/base/infrastructure/argocd/ to kubernetes/substrate/argocd/, the now-empty kubernetes/base/ tree is retired, and the component's consumable files (namespace + rendered manifests + CRDs) are added to the OCI tarball allowlist — closing the gap where the component existed in git but was unconsumable at every published tag."
status: accepted
id: base:argocd-substrate-relocation
decided: "2026-07-29T00:00:00Z"
deciders:
  - maintainer
consulted: []
informed: []
supersedes: []
superseded_by: []
related:
  - /decisions/0004-substrate-only-base.md
  - /decisions/0022-cilium-observability-and-argocd-self-management.md
tags: [adr, argocd, substrate, oci-publish, repo-layout]
---

# ADR: Steady-state ArgoCD lives at kubernetes/substrate/ and ships in the OCI artifact

## Context and Problem Statement

ArgoCD is delivered in two forms: the Day-0 bootstrap seed (a Talos
controlplane `inlineManifest` rendered from
`tofu/modules/talos-cluster/helm/argocd-values.yaml`, create-only) and the
steady-state self-management component (a rendered Helm component the live
ArgoCD reconciles from git). After the ADR-0004 substrate cut and the
cert-approver relocation, the steady-state component was the **sole
occupant** of `kubernetes/base/infrastructure/` — a single-component tree
whose name implied the retired pre-v2.0.0 multi-component layout.

Issue #156 additionally verified a delivery gap: `.ci-oci-tarball-include.txt`
never listed any `kubernetes/base/` path, so the steady-state component
existed in git but was **unconsumable at every published tag** — the
consumer tutorial's `ls vendor/base/kubernetes/base/infrastructure/argocd/`
step could not succeed, and a downstream cluster's argocd overlay could only
render against a stale hand-pulled `vendor/base/`.

## Decision Drivers

- The single-component `infrastructure/` tree communicates a layout that
  ADR-0004 retired; the operator trigger in #156 calls it vestigial.
- The steady-state layer is load-bearing, not decorative: on a live cluster
  `argocd-controller` is the sole field-manager owner of `argocd-cm.url`,
  `argocd-cm.oidc.config`, `argocd-rbac-cm.*` and
  `argocd-notifications-cm.context`, byte-matching the committed render —
  folding it into the create-only seed would strand consumer patches.

  > [2026-08-14 correction, recorded by adr-0025] The "sole field-manager owner"
  > half of this driver was never true. The module's post-health-gate
  > `kubectl apply --server-side --force-conflicts` applied a full chart-default
  > render, which made `kubectl` a co-owner of exactly those keys and re-took
  > them on every re-fire. adr-0025 scopes that apply to CRDs only and drops the
  > force flag. The conclusion drawn here — do not fold the steady-state layer
  > into the create-only seed — is unaffected and stands; only the stated
  > evidence was wrong.
- The component must be consumable from the published artifact, or the
  consumer-facing docs and downstream overlays stay structurally broken.
- Consumer-side cost must stay minimal (a path edit, not a re-architecture).

## Considered Options

1. **Status quo** — argocd stays the lone `infrastructure/` component;
   document it as the deliberate sole exception; add its paths to the
   allowlist.
2. **Fold steady-state into the seed** — drop the rendered component;
   ArgoCD self-manages from the bootstrap seed only.
3. **Relocate** — move the render to `kubernetes/substrate/argocd/`, retire
   `kubernetes/base/`, and add the consumable files to the allowlist.

## Decision Outcome

Chosen option: **Relocate (Option 3)**, because it produces the end-state
the #156 trigger actually asks for — no vestigial single-component
`infrastructure/` tree — at a downstream cost of a three-line `resources:`
edit, while Option 2 is contradicted by live-cluster evidence (the
steady-state layer actively owns config keys the seed never re-runs to
correct). `kubernetes/substrate/` is chosen over a top-level `argocd/`
because it names the component's role in ADR-0004's own vocabulary and
groups naturally beside `kubernetes/bootstrap/`.

### Consequences

- Positive: the repo layout states the substrate split truthfully;
  the component is consumable from the artifact for the first time;
  the stale consumer tutorial step becomes satisfiable.
- Negative: every path-anchored gate and doc had to move in one PR
  (render scripts, kustomize-target fence, release-guard globs, openspec
  sources, OKF references); history (CHANGELOG, accepted ADR bodies)
  retains the old path as historical record.
- Follow-up: #105 decides how the *bootstrap seed* delivers the same CRD
  payload declaratively; it may consume the now-published
  `_rendered/crds.yaml` but does not change this publication path.
  Downstream consumers migrate per `UPGRADING.md` — the three-line
  `resources:` edit plus every other consumer-tree reference to the old
  vendored path (incident runbooks and render scripts carry it too).

## Pros and Cons of the Options

### Option 1 — Status quo + allowlist

- Pro: zero consumer change beyond re-pull; cheapest diff.
- Con: preserves exactly the single-component `infrastructure/` shape the
  issue's trigger calls vestigial; spends reader clarity to save an edit
  that is cheap either way.

### Option 2 — Fold into the seed

- Pro: one delivery mechanism; smallest tree.
- Con: contradicted by evidence — the seed is create-only ("never
  re-runs"), while the steady-state render actively owns live config
  field-manager state; folding strands downstream kustomize patches with
  no base to patch onto.

### Option 3 — Relocate + publish (chosen)

- Pro: end-state matches the trigger; substrate role named in the path;
  consumable artifact; bounded consumer cost.
- Con: widest one-time blast radius across path-anchored gates and docs.

## Amendment to ADR-0004

ADR-0004's mechanical invariant — `find kubernetes/base/infrastructure
-maxdepth 1 -mindepth 1 -type d | wc -l` returns 1 (argocd only) — is
superseded by this decision. The new invariant is tracked-tree-based (so a
dirty working tree with gitignored `charts/` residue cannot fake a
violation or a pass):

```sh
git ls-files kubernetes/base/ | wc -l   # MUST return 0
git ls-files kubernetes/substrate/ | grep -c '^kubernetes/substrate/argocd/'  # MUST equal the tracked file count of the component
```

`.ci-renderable-components.txt` stays `argocd` (component names, not
paths); the `gitops-validate.yml` fence now derives the rendered set from
`kubernetes/substrate/<component>` paths.
