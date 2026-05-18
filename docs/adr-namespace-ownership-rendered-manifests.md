# ADR: Namespace Ownership in the Rendered Manifests Pattern

**Status**: Accepted
**Date**: 2026-05-18
**Related**: [Capability Producer/Consumer Symmetry](adr-capability-producer-consumer-symmetry.md), [Multi-Repo Platform Split](adr-multi-repo-platform-split.md)

## Context

The Rendered Manifests Pattern (this base ships `_rendered/manifests.yaml`
per component, consumers vendor the artifact via OCI) introduces a subtle
ownership conflict for the `Namespace` kind that did not exist in the
prior single-source-tree model.

Both producer and consumer write a namespace:

1. **Producer (this base, v0.3.0+)**: every component under
   `kubernetes/base/infrastructure/<component>/` ships a `namespace.yaml`
   carrying PSA (`pod-security.kubernetes.io/*`), PNI capability labels
   (`platform.io/provide.*`, `platform.io/network-profile`,
   `platform.io/network-interface-version`), and the standard
   `app.kubernetes.io/*` set. Consumer per-component Applications include
   the file via their `_rendered-overlay/kustomization.yaml`, which feeds
   the per-component `_rendered/manifests.yaml`.

2. **Consumer (cluster repo)**: the top-level overlay kustomization is
   processed by an `app-of-apps` root Application. That tree historically
   contained a single `namespaces-psa.yaml` declaring every cluster
   namespace with PSA + capability `consume.*` labels.

Both are valid declarations of the same `Namespace` resource. They do not
conflict on field values (SSA merges by field manager), but they DO
conflict on **lifecycle ownership**.

Concretely, on 2026-05-18 a consumer cluster experienced a cascade
failure with the following kausalkette:

1. The consumer removed six namespace entries from `namespaces-psa.yaml`
   under the assumption that the producer's vendor `namespace.yaml` would
   take over ownership.
2. The root Application reconciled with `prune: true` enabled, saw the
   six namespaces still present in the cluster but no longer in its
   source, and marked them for prune.
3. Among the pruned namespaces was the one hosting ArgoCD itself.
   Cascade-deletion took down all child Applications, AppProjects, and
   the application-controller pod.
4. The Kyverno admission webhook (a `ValidatingWebhookConfiguration`,
   cluster-scoped, not in any pruned namespace) survived. With its
   backing Service gone, fail-closed webhook calls then blocked further
   resource deletions, freezing the cluster in a half-dead state.

The assumption — *vendor namespace.yaml transfers ownership* — is false.
Vendor manifest provides field-value contributions via SSA from the
per-component Application, but it does NOT transfer the **prune
eligibility** that the root Application holds on a tracking-id basis.
Each Application makes its prune decision against its own source tree
in isolation.

## Decision

For every namespace declared in the consumer's root-tracked overlay,
both of the following are mandatory:

### 1. `argocd.argoproj.io/sync-options: Prune=false` annotation

Every `Namespace` resource in the consumer's root-tracked tree carries
this annotation. Forward-protection against the entire bug class: if a
future change removes a namespace from a root-tracked file, the live
resource is preserved. Manual cleanup remains available via
`kubectl delete ns`.

### 2. PNI minimum labels on the stub

Where a consumer chooses to stub a namespace (declaring only that it
exists, leaving labels to vendor SSA), the stub MUST carry the two PNI
contract labels enforced by the
`pni-contract-enforce` ClusterPolicy at admission time:

```yaml
labels:
  platform.io/network-interface-version: v1
  platform.io/network-profile: <managed|privileged|restricted>
```

Without these, the Kyverno admission webhook rejects the stub apply
before the per-component Application's SSA merge can add the full label
set. Sequencing: root Application processes the stub first; per-component
Applications run later (often after their own dependencies via
sync-waves), so the stub must satisfy the admission contract on its own.

All other labels (PSA `enforce/audit/warn`, capability `provide.*`,
`consume.*`, `app.kubernetes.io/*`) may be left to vendor SSA from the
per-component Application.

## Two viable ownership models

A given consumer namespace falls into one of two categories. The choice
is per-namespace and documented inline in the consumer's overlay.

### Model A — Consumer fully owns the namespace

Used when: the platform-base ships no vendor `namespace.yaml` for the
component, OR the consumer needs cluster-specific labels (e.g.,
`platform.io/consume.<cap>` for tenant workloads).

The `Namespace` resource in the consumer carries the full label set:
PSA, PNI labels, `app.kubernetes.io/*`, and the `Prune=false`
annotation.

### Model B — Vendor co-owned (stub + SSA merge)

Used when: the platform-base ships a vendor `namespace.yaml` for the
component, and the consumer has no additional label requirements.

The consumer ships a STUB carrying only:
- `metadata.name`
- `metadata.annotations[argocd.argoproj.io/sync-options]: Prune=false`
- `metadata.labels[platform.io/network-interface-version]: v1`
- `metadata.labels[platform.io/network-profile]: <value>`

The per-component Application's SSA apply fills in the rest from
vendor `namespace.yaml`.

The two models coexist in a single consumer overlay. The choice is
per-namespace and noted in the file's header comment.

## Why not move ownership entirely to per-component App

Considered and rejected for this iteration:

- **Move the namespace declaration out of the root-tracked tree
  entirely**, letting only the per-component Application own it. This
  fixes the prune issue at the root, but introduces a new ordering
  problem: the per-component Application's destination namespace must
  exist before ArgoCD can apply any of its resources, and the
  per-component App cannot create its own destination namespace without
  `CreateNamespace=true` sync option. Combined with vendor namespace.yaml
  carrying capability labels that admission policies enforce, this
  reduces to "who calls the Namespace into being first."
- **Use ApplicationSet PreInstall hooks** to ensure namespace ordering.
  Adds another layer of indirection and a hook that itself needs RBAC.
  Heavier than the stub + annotation solution.

The stub-plus-annotation approach keeps the root tree as the canonical
namespace lifecycle owner (matching ArgoCD's natural app-of-apps
processing order), uses native ArgoCD prune-protection, and lets vendor
SSA carry the full label content. It is the lightest sufficient form
that resolves both the prune-cascade risk and the admission-blocked
stub issue.

## Consequences

### Positive

- Cascade-deletion of platform namespaces from a single source-tree edit
  is structurally impossible going forward.
- Consumer overlays carry minimal namespace boilerplate; full labels
  remain a single source of truth in the producer.
- Multi-cluster reuse: consumers of any tag ≥ v0.3.0 inherit a vendor
  `namespace.yaml` for every base component; they only need stubs in the
  root tree.

### Negative

- Two-line minimum overhead per stub (network-interface-version +
  network-profile). Cannot be reduced because Kyverno admission fires
  on the first apply.
- `Prune=false` means deleting a namespace from the source tree no
  longer cascades to the live resource. Explicit manual cleanup required
  when removing a component. Documented in the file header in the
  consumer.

### Migration impact for existing consumers

Consumers already on the Rendered Manifests Pattern should:

1. Audit every `Namespace` resource in their root-tracked overlay.
2. Add `argocd.argoproj.io/sync-options: Prune=false` to each.
3. For any namespace already declared as a bare stub (relying on vendor
   for labels), add the two PNI minimum labels.

See `docs/tutorial-first-consumer-cluster.md` for the consumer-side
template.

## References

- ArgoCD sync options:
  https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/
- Kubernetes Server-Side Apply (SSA):
  https://kubernetes.io/docs/reference/using-api/server-side-apply/
- PNI contract ClusterPolicy:
  `kubernetes/base/infrastructure/platform-network-interface/resources/kyverno-clusterpolicy-pni-contract-enforce.yaml`
- 2026-05-18 incident timeline: ArgoCD application-controller log,
  syncId `12807-QfBNf`.
