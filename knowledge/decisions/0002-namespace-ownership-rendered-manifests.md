---
type: decision
title: "ADR: Namespace Ownership in the Rendered Manifests Pattern"
description: "Makes the per-component ArgoCD Application the sole lifecycle owner of each platform namespace, so cascade-deletion from double-tracking is structurally impossible."
status: stable
id: base:namespace-ownership-rendered-manifests
decided: "2026-05-18T00:00:00Z"
date-note: choreography amended 2026-05-18 after second incident
deciders:
  - platform-maintainer
consulted:
  - platform-reliability-reviewer
  - team-red (post-incident review #2)
related:
  - base:capability-producer-consumer-symmetry
  - base:multi-repo-platform-split
tags: [adr, gitops]
---

# ADR: Namespace Ownership in the Rendered Manifests Pattern

## Revision history

- 2026-05-18 initial: Architecture C accepted; original migration
  choreography (steps 1–4).
- 2026-05-18 amended: cascade-deletion recurred during argocd
  self-cutover. Root cause: race window between
  tracking-id annotation rewrite and root reconciliation. Choreography
  extended to wrap the live-resource transfer in a temporary
  `automated.prune: false` window on root. See "Race window" section.

## Context

The Rendered Manifests Pattern (this base ships `_rendered/manifests.yaml`
per component, consumers vendor the artifact via OCI) introduces a
namespace-ownership question that did not exist in the prior
single-source-tree model: which Application is the **sole lifecycle
owner** of each platform namespace?

Two paths for a consumer to declare a namespace exist:

1. **Vendor `namespace.yaml`** shipped by this base under
   `kubernetes/base/infrastructure/<component>/namespace.yaml`,
   consumed by the per-component Application via its
   `_rendered-overlay/kustomization.yaml`, ending up in the
   per-component `_rendered/manifests.yaml`.

2. **Consumer-side namespace declaration**, typically in a
   top-level `namespaces-psa.yaml` tracked by an app-of-apps `root`
   Application.

If both declare the same namespace, both Applications claim
ownership. ArgoCD does not have a concept of "shared lifecycle"
across Applications. Each Application decides independently whether
to apply or prune a resource by comparing its current source against
the live cluster. If one Application sees the resource removed from
its source while another still tracks it, the first Application
prunes — **even though the resource is still managed elsewhere**.

This is not a theoretical concern. On 2026-05-18 a consumer cluster
experienced cascade-deletion of its `argocd` namespace caused by
removing namespace entries from a root-tracked file under the
assumption that the producer's vendor `namespace.yaml` would take
over ownership. The assumption was wrong: vendor `namespace.yaml`
contributes field values via Server-Side Apply (SSA) from the
per-component Application, but does NOT transfer prune eligibility
that the root Application holds via tracking-id annotation. Each
Application makes prune decisions against its own source tree in
isolation.

Approaches considered and rejected:

- **Annotate every namespace `argocd.argoproj.io/sync-options: Prune=false`**
  to prevent root from pruning. This is a symptom-fix: it hides the
  intent-mismatch but leaves double-tracking in place. The file's
  presence stops being a meaningful lifecycle signal (resource
  present in source but unable to be removed by source removal).
  Real deletions become two-step manual operations. The bug class
  "lifecycle conflict from double-tracking" stays latent.

- **Add a "transfer" semantic to ArgoCD.** Not available upstream;
  outside this base's scope to invent.

## Decision

**A single Application owns each namespace. The owner is the
component itself.**

For every platform namespace (one shipped by this base), the
per-component Application is the sole lifecycle owner. The vendor
`namespace.yaml` lives in `kubernetes/base/infrastructure/<component>/`
and is consumed by the consumer's per-component overlay's
`_rendered-overlay/kustomization.yaml`. From that point the
per-component Application carries the only ArgoCD tracking-id on
the namespace resource.

A consumer's top-level `root` Application MUST NOT track any
platform namespace. The consumer's `namespaces-psa.yaml` (or
equivalent) carries only **tenant namespaces** — namespaces this
base does not ship a vendor `namespace.yaml` for.

| Namespace category | Owner | Source of truth | Tracked by `root`? |
|---|---|---|---|
| Platform (vendor-shipped) | per-component Application | vendor `namespace.yaml` in `_rendered/manifests.yaml` | NO |
| Tenant (consumer-only) | consumer root Application | consumer `namespaces-psa.yaml` | yes |
| `argocd` itself (special) | Talos inlineManifest seed (initial) → argocd Application (steady-state) | module inlineManifest namespace then vendor namespace.yaml SSA-merge | NO |

The `argocd` namespace is the only chicken-and-egg case. It is created
by the **Talos inlineManifest seed** that the `tofu/modules/talos-cluster`
module bakes into the controlplane machine-config (`deploy_argocd = true`),
before any Application — or even the apiserver's ArgoCD CRDs — exists. The
create-only seed carries the full PSA floor (`enforce: baseline`) + the
recommended labels itself, so the namespace is never delivered
PSA-unenforced (the former Helm `argocd-install` /
`kubernetes/bootstrap/argocd/namespace.yaml` path is retired). Once ArgoCD
is up, the `argocd` Application syncs its `_rendered/manifests.yaml`, which
includes vendor `namespace.yaml`; SSA-merge of labels onto the live
namespace transfers steady-state ownership to the `argocd` Application.

The two writers do not conflict on the security-relevant field: the seed
and the steady-state vendor `namespace.yaml` assert the **same** PSA floor
(`enforce: baseline`, `audit`/`warn: restricted`), so the ownership
transfer carries no PSA gap or flip. The recommended-label sets differ
deliberately — the seed marks `app.kubernetes.io/managed-by: opentofu` (it
created the namespace), the Application's SSA re-marks `managed-by: argocd`
(it now owns it) — the create→steady-state ownership transfer made visible,
not drift.

## Implications for consumer onboarding (new cluster)

A consumer adopting this base from scratch — the multi-cluster reuse
case this ADR is written for — does **not** need to author any
namespace stubs for platform namespaces. Specifically:

- Consumer's `namespaces-psa.yaml` contains only tenant namespaces
  (those whose names are not also a directory under
  `kubernetes/base/infrastructure/` in vendored base).
- Each per-component overlay's `_rendered-overlay/kustomization.yaml`
  references vendor `namespace.yaml` as the first resource (kustomize
  default ordering makes it the first item applied per sync wave).
- No `argocd.argoproj.io/sync-options: Prune=false` annotation is
  needed anywhere. The bug class is structurally impossible because
  there is only one tracking-id per namespace.

## Implications for existing-cluster migration

A consumer cluster that already has platform namespaces under
`root`'s tracking-id must transfer the tracking-id to the
per-component Application **before** removing the namespace from
`root`'s source. Otherwise the source-removal-as-deletion-intent bug
fires (root prunes the namespace it no longer sees in its source,
not knowing that another Application has taken over).

Migration choreography:

1. (kubectl op) Temporarily disable automated pruning on root for the
   duration of the migration:

   ```bash
   kubectl patch application root -n argocd --type=merge \
     -p '{"spec":{"syncPolicy":{"automated":{"prune":false}}}}'
   ```

   This is **mandatory** — see "Race window" below.
2. (kubectl op) For each platform namespace: rewrite
   `argocd.argoproj.io/tracking-id` annotation from
   `root:/Namespace:argocd/<ns>` to `<comp-app>:/Namespace:argocd/<ns>`.
   Also remove any `argocd.argoproj.io/sync-options: Prune=false`
   annotation (it provides no protection at this stage — see Race window).
3. (git op) Remove platform namespaces from `namespaces-psa.yaml`.
   Push, merge.
4. Wait for `root` to reconcile. Expected status: `OutOfSync` with
   "extra resource: Namespace/<ns>" — the namespace exists in the
   cluster but no longer in root's source. With `prune: false` from
   step 1, root does NOT delete it. Verify before continuing:

   ```bash
   argocd app get root  # expect: Health=Healthy, Sync=OutOfSync
   ```

5. (kubectl op) Restore root prune behaviour:

   ```bash
   kubectl patch application root -n argocd --type=merge \
     -p '{"spec":{"syncPolicy":{"automated":{"prune":true}}}}'
   ```

   At this point the foreign tracking-id rule applies — root sees
   the namespace, sees the tracking-id is foreign (`<comp-app>:...`,
   not `root:...`), and treats it as out-of-scope. No-op.
6. Per-component Application's next sync sees namespace with matching
   tracking-id → continues to manage normally.

### Race window — why steps 1 and 5 exist

The reverse-order bug (git op before kubectl op) is documented as the
2026-05-18 cascade-deletion bug class. There is a **second** race
that the original choreography (without steps 1 and 5) does NOT
prevent:

- Step 2 writes the new tracking-id annotation directly to the live
  resource (not to the source manifest).
- If `root` reconciles between step 2 and step 3 (typical interval:
  3 minutes), it observes the namespace **still listed in its source
  manifest with the original `root:/Namespace:...` tracking**, and
  SSA-applies the namespace, **overwriting** the freshly-written
  annotation. The cluster is now back in the pre-step-2 state.
- When step 3 lands and root reconciles, the namespace is gone from
  source AND its annotation still says `root:/...`. Root's
  `automated.prune: true` then deletes it (second cascade event,
  observed during the incident).

`argocd.argoproj.io/sync-options: Prune=false` on the resource itself
does NOT close this race: sync-options are interpreted only while
the resource is in the source manifest. The moment the resource is
removed from the source, the sync-option annotation is no longer
consulted; the App-level `automated.prune` setting controls deletion.

Disabling `automated.prune` on `root` for the duration of the
migration is the only deterministic protection against this race
window for the resource being transferred.

### Structurally safer alternative

Set `automated.prune: false` as the **default** for the root
Application template (`root-application.yaml.tmpl` in
`kubernetes/bootstrap/argocd/`). Intentional prunes then require
explicit `argocd app sync root --prune` invocations. Removes the
class of "source-edit-as-prune-intent" bugs at root level — the
prune is always operator-acknowledged, never automatic. Trade-off:
intentional removals require an additional manual step.

Either approach is acceptable; per-cluster choice. Document the
choice in the cluster repo's `AGENTS.md` or `CLAUDE.md` so future
operators understand the policy.

## Consequences

### Positive

- Cascade-deletion of a platform namespace from a source-tree edit
  in `root` is structurally impossible. The base does not ship a
  resource that two Applications co-track.
- Consumer onboarding does NOT require manual authoring of namespace
  labels for platform namespaces. PSA labels and the recommended
  `app.kubernetes.io/*` labels all come from vendor `namespace.yaml`
  shipped by this base. Consumer's role: vendor the OCI artifact and run
  `task bootstrap:argocd`.
- Decommissioning a platform component is a single act: removing
  the per-component Application also cascade-deletes its namespace
  (correct semantics — the component is gone, no reason for its
  namespace to persist).
- Multi-cluster reuse: any consumer of any tag ≥ v0.3.0 inherits a
  vendor `namespace.yaml` for every base component with full labels.
  No per-cluster customization for platform namespaces.

### Negative

- Existing-cluster migrations require a one-time kubectl operation
  (tracking-id transfer) before the git change. New clusters do not.
- The `argocd` namespace special case (bootstrap-created, then
  Application-owned) is the one exception to "component is sole owner
  from day 1". The bootstrap pre-creates the namespace, and the
  argocd Application takes over via SSA-merge. Documented as a
  transitional special case.
- Removing a platform component from a consumer overlay does delete
  its namespace (correct intent), which cascade-deletes any workloads
  inside. Consumers must understand this when adding their own
  resources to a platform namespace (anti-pattern: don't).

### Migration impact for existing consumers

Consumers already on the Rendered Manifests Pattern who previously
declared platform namespaces in a `namespaces-psa.yaml` should:

1. Apply the tracking-id transfer to the live cluster (see migration
   choreography section above — **including the temporary
   `prune: false` window on root**, omitting it reproduces the
   2026-05-18 15:30 cascade-deletion).
2. Remove platform namespace entries from `namespaces-psa.yaml`.
3. Remove any `argocd.argoproj.io/sync-options: Prune=false`
   annotation that was added as a workaround — it provides no
   protection at the cutover moment and is no longer needed at
   steady state.

Consumers onboarding from scratch start in the Architecture C state
by construction; no migration applies.

## References

- ArgoCD tracking-id annotation:
  https://argo-cd.readthedocs.io/en/stable/user-guide/resource_tracking/
- Kubernetes Server-Side Apply (SSA):
  https://kubernetes.io/docs/reference/using-api/server-side-apply/
- Incident timeline: ArgoCD application-controller log (internal reference).
