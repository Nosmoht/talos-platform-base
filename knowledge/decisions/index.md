# Decisions

Architecture decision records for the platform base, in MADR-derived form.
Frontmatter is canonical for status and dates. The group headings and the
`(word)` suffix on each entry below are the MADR record, which §Status
vocabulary maps onto the frontmatter value; where they differ, frontmatter
wins.

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
- [ADR: OpenSpec as the behavioral-requirements surface](0015-openspec-adoption.md) - adopts OpenSpec with a directly-authored backfill of 14 substrate capability specs; openspec/specs/ is normative for behavioral requirements, scoped to consumer-facing platform behavior (accepted; §Ownership model + §"SoT map vs knowledge/reference/" scoped in part by [0021](0021-spec-vs-bundle-normativity.md), §Scope principle and the 2026-07-15 Correction stand)
- [ADR: Capability profiles carry only their presence_predicate args — drop iommu=pt](0016-capability-profiles-predicate-only.md) - removes the host-DMA tuning arg `iommu=pt` from the `iommu` provisioning profile, returning the `iommu` kernel-arg key to consumer control (accepted)
- [ADR: Consumer-supplied schematic extra_kernel_args, cross-source-scoped](0017-consumer-image-kernel-args.md) - adds an optional per-image `extra_kernel_args` input reaching the UKI-correct schematic sink, with the kernel-arg conflict guard scoped to cross-source (profile-vs-image) collisions only (accepted)
- [ADR: Replace cert-approver (alex1989hu) with postfinance/kubelet-csr-approver + a per-cluster config surface](0019-postfinance-kubelet-csr-approver.md) - swaps the seeded kubelet-serving approver to postfinance/kubelet-csr-approver as a chart-rendered templatefile() seed with a three-knob config surface and a default-on per-node DNS-SAN binding; supersedes [0013](0013-kubelet-serving-cert-rotation.md) §D2 (accepted)
- [ADR: Remove the manual release approval gate; replace its MAJOR backstop with a blocking CI guard](0020-automated-release-no-approval-gate.md) - drops the environment:release manual-approval protection so a merge to main releases unattended, replacing the gate's MAJOR-vs-MINOR backstop with a blocking, will-release-gated MAJOR-bump guard plus an [allow-non-major] override (accepted)
- [ADR: OpenSpec specs are the sole normative artifact for schema and module-interface contracts](0021-spec-vs-bundle-normativity.md) - openspec/specs/cluster-yaml-sot and openspec/specs/module-interface-contract become the sole normative artifacts for the two overlapping content classes named in issue #177, with knowledge/reference/cluster-yaml.md thinned to point at them and the module README's duplication kept, gated only at name level; scopes ADR-0015's §Ownership model and §SoT map in part (accepted)
- [ADR: Cilium observability inputs + opt-in ArgoCD self-management delivery mode](0022-cilium-observability-and-argocd-self-management.md) - adds first-class default-off Cilium observability inputs (agent/operator Prometheus metrics, Hubble metrics-only) and an opt-in emitted-Application self-management delivery mode; closes the substrate.cilium schema and bumps the module's OpenTofu floor to >= 1.9 (accepted; §(c) third bullet, §(f) Override-drop hazard and the 2026-08-15 addendum's typed-input substitution claim superseded in part by [0028](0028-consumer-free-helm-value-surface.md), the rest stands)
- [ADR: Node identity is the map key — one definition place, generated lists](0023-node-identity-map-key.md) - `var.nodes` becomes a map keyed by node name and every Talos-facing list a name-ordered projection of it, closing the node-key canonicality, first-label-collision, FQDN-registration and odd-controlplane-count gaps the list model hid (accepted)
- [ADR: Steady-state ArgoCD lives at kubernetes/substrate/ and ships in the OCI artifact](0024-argocd-substrate-relocation.md) - relocates the steady-state ArgoCD render from kubernetes/base/infrastructure/ to kubernetes/substrate/, retires the empty kubernetes/base/ tree, and adds the component's consumable files to the OCI tarball allowlist; amends ADR-0004's infrastructure/ count invariant (accepted)
- [ADR: The Day-0 ArgoCD kubectl apply delivers CRDs and nothing else](0025-argocd-crd-apply-scope.md) - projects the post-health-gate apply down to CustomResourceDefinitions and drops --force-conflicts, ending a Day-2 convergence that pushed chart defaults (bundled Dex included) over ArgoCD's own state and re-took field-manager ownership of argocd-cm and argocd-rbac-cm on every Kubernetes bump; corrects ADR-0024's sole-owner driver (accepted)
- [ADR: The machine-config apply mode is a per-role input defaulting to auto](0026-machine-config-apply-mode.md) - exposes the talos provider's apply_mode as controlplane_apply_mode and worker_apply_mode so a reboot-needing change to a stateful role can be staged and rebooted out of band, one node at a time; the default stays auto because the module's only apply resource also carries the Day-0 install (accepted)
- [ADR: The talos provider is pinned exactly to the 0.12.0-beta.0 prerelease](0027-talos-provider-prerelease-pin.md) - replaces the >= 0.7.0, < 1.0.0 range with an exact pin on the only release bundling the Talos 1.14 machinery, because a range never selects a prerelease; makes the 1.14 document kinds reachable and their defaults generated, at the cost of a prerelease every consumer inherits; only a root whose own constraint excludes that version has to edit anything (accepted)
- [ADR: The consumer's Helm value surface is free-form and reaches every lifecycle phase](0028-consumer-free-helm-value-surface.md) - decides the guarded-vs-tunable question for a tunable value surface: the consumer's free-form layer is last on every ArgoCD and Cilium workload-values path, the closed set narrows to keys whose Talos-side counterpart the module writes (rejected at plan time, never silently re-asserted), the ArgoCD values-level security floor is assigned to the consumer, and per-value typed inputs stop being the answer for the long tail; supersedes [0022](0022-cilium-observability-and-argocd-self-management.md) §(c)/§(f) in part and extends [0024](0024-argocd-substrate-relocation.md)'s payload set (accepted)
- [ADR: Substrate Hard Constraints — boot-loop guards and deprecated-API bans](0011-substrate-hard-constraints.md) - retroactively records the three enforced boot-loop / deprecated-API substrate invariants and their enforcement points (accepted — status decided 2026-08-23, see the ADR's dated banner)

## Proposed

- [ADR: Where the per-node capability-composition logic should live (HCL vs a portable pre-processing layer)](0010-composition-logic-placement.md) - defers HCL-vs-portable-layer extraction of the composition logic, with a hybrid recommendation and concrete revisit triggers (proposed)

## Superseded

- [ADR: Shared Render Artifact as the Cross-Frontend Source of Truth for Per-Node Talos Config](0005-shared-render-artifact.md) - shared JSON render artifact for per-node Talos config composition; superseded by [0006-opentofu-cluster-lifecycle.md](0006-opentofu-cluster-lifecycle.md) (superseded)
- [ADR: No wholesale Make→go-task migration — the Makefile dissolves with substrate-only](0008-task-runner-consolidation.md) - no wholesale Make→go-task migration; superseded by [0012-makefile-retirement.md](0012-makefile-retirement.md) (superseded)

## Status vocabulary

Frontmatter `status` uses the OKF v0.2 lifecycle values; the MADR words this
bundle was authored with survive in ADR bodies and `history:` entries, which
are records and are not rewritten. The MADR words are also what the group
headings above still use, because they group by decision state — the useful
browsing axis, and the one the bodies and `history:` lists agree with.

| ADR record says | frontmatter `status` |
|---|---|
| accepted | `stable` |
| proposed | `draft` |
| superseded | `deprecated` |

The decision's own date lives in `decided`. Decision concepts carry no
`generated` and no `verified`: they derive from no `sources`, so there is
nothing to have been read against, and their content-change date is not
recorded anywhere reliable — the dated in-body banners carry that signal
instead.

A partial supersession leaves `status: stable` and an empty `superseded_by`,
recorded by the dated in-body banner plus the superseding ADR's `supersedes`
with a `§section` qualifier. `deprecated` is reserved for full supersession.

## Authoring convention

1. Copy [template.md](template.md) to the next free `NNNN-<slug>.md` in this
   directory (numeric order, zero-padded to four digits).
2. Fill every frontmatter field: `type`, `title`, `description`, `status`,
   `id`, `deciders`, `tags`, and add `decided:` — the template omits it so a
   copy cannot ship a placeholder date.
3. Frontmatter is canonical — do not duplicate Status/Date lines in the body.
   The `(word)` suffix in the lists above is the MADR record, not a duplicate
   of the field; add the entry with the record's word.
4. `supersedes:` / `superseded_by:` carry bundle-absolute paths
   (e.g. `/decisions/0006-opentofu-cluster-lifecycle.md`); append any
   `§section` qualifier to the path string. Add the entry to the matching
   status group above.
5. Log the addition in [../log.md](../log.md).
