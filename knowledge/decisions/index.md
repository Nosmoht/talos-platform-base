# Decisions

Architecture decision records for the platform base, in MADR-derived form.
Frontmatter is canonical for status and dates.

## Accepted

- [ADR: Multi-Repo Platform Split for Multi-Cluster Reuse](0001-multi-repo-platform-split.md) - splits the platform into base / harness / consumer repository roles with OCI Day-0 consumption and Multi-Source-Application Day-2 reconciliation (accepted)
- [ADR: Namespace Ownership in the Rendered Manifests Pattern](0002-namespace-ownership-rendered-manifests.md) - one Application owns each platform namespace (the component itself), making double-tracking cascade-deletion structurally impossible (accepted)
- [ADR: Three-Layer Capability Architecture](0003-three-layer-capability-architecture.md) - adds the Layer-C Hardware Features Registry of atomic hardware predicates; only Layer C remains base-resident after v2.0.0 (accepted)
- [ADR: Substrate-Only Base + Separate Apps Repository](0004-substrate-only-base.md) - the base carries only Talos + Cilium + ArgoCD + cert-approver glue; everything else moves to the talos-platform-apps catalog or dissolves (accepted)
- [ADR: OpenTofu module is the sole Talos cluster-lifecycle path](0006-opentofu-cluster-lifecycle.md) - replaces the make/5-axis pipeline with the backend- and identity-agnostic `tofu/modules/talos-cluster` module (accepted)
- [ADR: Module-delivered Cilium + `cluster.yaml` as the declarative cluster SoT](0007-cluster-yaml-sot.md) - the module seeds Cilium via inlineManifest and `cluster.yaml` becomes the declarative Source-of-Truth over the tofu executor (accepted)
- [ADR: Node Capability Composition (γ') — composable per-node features over monolithic classes](0009-node-capability-composition.md) - composable per-node hardware capabilities with explicit base-owned provisioning profiles replace monolithic node classes (accepted)
- [ADR: Retire the Makefile — go-task is the single runner](0012-makefile-retirement.md) - surviving targets fold into namespaced Taskfile tasks behind a one-release deprecation stub (accepted)
- [ADR: Kubelet serving-cert rotation as substrate default + cert-approver as a Talos seed](0013-kubelet-serving-cert-rotation.md) - serving-cert rotation default-on for all nodes; cert-approver seeded unconditionally via controlplane inlineManifest (accepted; §D2 approver identity + seed mechanism superseded in part by [0019](0019-postfinance-kubelet-csr-approver.md), §D1 stands)
- [ADR: Ship tool-generated AI artifacts in the base](0014-ship-ai-tool-artifacts.md) - the base commits tool-generated, regenerable AI-tool artifacts (OpenSpec skill/command trees); hand-authored harness primitives remain external (accepted)
- [ADR: OpenSpec as the behavioral-requirements surface](0015-openspec-adoption.md) - adopts OpenSpec with a directly-authored backfill of 14 substrate capability specs; openspec/specs/ is normative for behavioral requirements, scoped to consumer-facing platform behavior (accepted)
- [ADR: Capability profiles carry only their presence_predicate args — drop iommu=pt](0016-capability-profiles-predicate-only.md) - removes the host-DMA tuning arg `iommu=pt` from the `iommu` provisioning profile, returning the `iommu` kernel-arg key to consumer control (accepted)
- [ADR: Consumer-supplied schematic extra_kernel_args, cross-source-scoped](0017-consumer-image-kernel-args.md) - adds an optional per-image `extra_kernel_args` input reaching the UKI-correct schematic sink, with the kernel-arg conflict guard scoped to cross-source (profile-vs-image) collisions only (accepted)
- [ADR: Replace cert-approver (alex1989hu) with postfinance/kubelet-csr-approver + a per-cluster config surface](0019-postfinance-kubelet-csr-approver.md) - swaps the seeded kubelet-serving approver to postfinance/kubelet-csr-approver as a chart-rendered templatefile() seed with a three-knob config surface and a default-on per-node DNS-SAN binding; supersedes [0013](0013-kubelet-serving-cert-rotation.md) §D2 (accepted)

## Proposed

- [ADR: Where the per-node capability-composition logic should live (HCL vs a portable pre-processing layer)](0010-composition-logic-placement.md) - defers HCL-vs-portable-layer extraction of the composition logic, with a hybrid recommendation and concrete revisit triggers (proposed)
- [ADR: Substrate Hard Constraints — boot-loop guards and deprecated-API bans](0011-substrate-hard-constraints.md) - retroactively records the three enforced boot-loop / deprecated-API substrate invariants and their enforcement points (proposed)

## Superseded

- [ADR: Shared Render Artifact as the Cross-Frontend Source of Truth for Per-Node Talos Config](0005-shared-render-artifact.md) - shared JSON render artifact for per-node Talos config composition; superseded by [0006-opentofu-cluster-lifecycle.md](0006-opentofu-cluster-lifecycle.md) (superseded)
- [ADR: No wholesale Make→go-task migration — the Makefile dissolves with substrate-only](0008-task-runner-consolidation.md) - no wholesale Make→go-task migration; superseded by [0012-makefile-retirement.md](0012-makefile-retirement.md) (superseded)

## Authoring convention

1. Copy [template.md](template.md) to the next free `NNNN-<slug>.md` in this
   directory (numeric order, zero-padded to four digits).
2. Fill every frontmatter field: `type`, `title`, `description`, `status`,
   `timestamp`, `id`, `deciders`, `tags`.
3. Frontmatter is canonical — do not duplicate Status/Date lines in the body.
4. `supersedes:` / `superseded_by:` carry bundle-absolute paths
   (e.g. `/decisions/0006-opentofu-cluster-lifecycle.md`); append any
   `§section` qualifier to the path string. Add the entry to the matching
   status group above.
5. Log the addition in [../log.md](../log.md).
