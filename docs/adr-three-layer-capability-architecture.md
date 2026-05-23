---
status: accepted
date: 2026-05-23
date-history:
  - 2026-05-23 proposed + accepted
deciders:
  - Thomas Krahn
consulted:
  - team-red (Round 1 layer-audit — three-layer necessity verdict)
  - team-red (Round 2 layer-audit — per-entry cleanup classification)
informed: []
companion-docs:
  - "[Two-Layer ADR (superseded)](./adr-two-layer-capability-architecture.md)"
  - "[Platform Capability Index (Layer A)](./platform-capability-index.yaml)"
  - "[Platform Hardware Features Registry (Layer C)](./platform-hardware-features.yaml)"
  - "[Capability Producer/Consumer Symmetry ADR (Layer B)](./adr-capability-producer-consumer-symmetry.md)"
  - "[PNI Capability Architecture (Layer B)](./capability-architecture.md)"
supersedes:
  - "[adr-two-layer-capability-architecture.md](./adr-two-layer-capability-architecture.md)"
implementation-tracking-issue: "https://github.com/Nosmoht/talos-platform-base/issues/61"
---

# ADR: Three-Layer Capability Architecture — Tool-Capability-Index (Layer A) + PNI Network-Trust Registry (Layer B) + Hardware Features Registry (Layer C)

> **Status:** accepted on first proposal. The two-round adversarial audit
> archived at `.work/issues/layer-audit/` produced an unambiguous Layer-C
> necessity verdict; per-entry classification for the Layer-A cleanup was
> settled in the same audit. The implementation tooling (Layer-C lint
> script, refs-check extension, Kyverno reserved-label extension) lands
> as part of [issue #61](https://github.com/Nosmoht/talos-platform-base/issues/61);
> CI enforcement gates closure of the issue.

## Context and Problem Statement

The [Two-Layer ADR](./adr-two-layer-capability-architecture.md) (accepted
2026-05-18, superseded by this document) chose Option 2 from three
candidates: separate Layer A (Tool-Capability-Index) from Layer B (PNI
Network-Trust Registry). That decision was correct for the two layers it
considered — but the considered-options enumeration never named hardware
as a candidate concern. Decision Drivers D1–D7 in the predecessor ADR
contain zero hardware-shaped drivers; `grep -E
'hardware|NFD|GPU|NVMe|IOMMU|schematic|machine.nodeLabels'` against the
predecessor returns no matches. The "two layers" count was a framing
artifact of the candidate set, not a derived consequence of the problem
space.

The two-round layer-audit (`.work/issues/layer-audit/findings.md` Round 1
+ `.work/issues/layer-audit/cleanup-scope.md` Round 2) established three
load-bearing facts that motivate this supersession:

1. **A de-facto hardware layer already exists across ≥7 artifacts** —
   `kubernetes/base/infrastructure/cluster.yaml.example` lines 46–67
   (per-node GPU/storage/role declarations), `talos/.schematic-ids.mk`
   (now removed by issue #60 per cluster-agnostic mandate), five
   `talos/patches/worker-{gpu,kubevirt,gvisor,pi,drbd}.yaml` patches
   (each encoding a hardware predicate), and the `node-feature-discovery`
   infra component (Layer-C producer-tooling, currently mis-classified
   as Layer-A `gpu-runtime.composition[]`). None of these are governed
   by any schema, validation script, or cross-reference. The hardware
   concern is the bare elephant in the room.
2. **Six Layer-A entries carry undeclared hardware predicates** —
   `gpu-runtime`, `vm-runtime`, `block-storage-replicated`,
   `block-storage-local`, `secondary-network-attachment`, and
   `cluster-provisioning` each require specific node hardware
   (NVIDIA GPU + IOMMU, VT-x/AMD-V + KVM kernel module, DRBD kernel
   module, local NVMe block device, …) but the Layer-A schema has no
   `requires_hardware_features` field, so these predicates are
   undeclared. Consumers cannot honestly answer "will this capability
   land on this node?" from the Layer-A index alone.
3. **The `gpu-runtime` entry conflates layers** —
   `gpu-runtime.composition[]` includes `node-feature-discovery`, but
   NFD is Layer-C producer-tooling (it discovers and labels hardware
   features), not a swappable Layer-A tool. This conflation propagates:
   `gpu-runtime.independence_test.alt_impls_exist: false` is then read
   as "no alternative GPU-runtime stack exists" when in fact the
   `false` value is an artifact of the NFD+device-plugin+DCGM bundle
   choice — the device-plugin layer alone has alt-impls.

A third layer is therefore not an additive opinion — it is a correction
to a misclassification that already pervades the Layer-A artifact.

## Decision Drivers

- **D1.** The vocabulary must align with the CNCF TAG App Delivery
  *Platforms White Paper* (2023) "capabilities comprised of features"
  hierarchy. A composite capability (e.g., `compute-virt`, `storage`,
  `compute-gpu-nvidia`) is a derived predicate over atomic features
  (e.g., `vt-x-or-amd-v` AND `kvm-kernel-module`), not an atom itself.
- **D2.** The Two-Layer ADR's decision to keep Layer A and Layer B as
  separate artifacts with disjoint namespaces and a shared
  identifier scheme must be preserved unchanged. Layer C adds, it does
  not relitigate.
- **D3.** Hardware features must be expressible per-node in
  `cluster.yaml` (γ' 5-axis model: role · arch ·
  infrastructure-platform · hardware-platform · hardware-capabilities)
  *without* the base defining a composite-capability registry. Composite
  capabilities are downstream concerns; the base ships only the atomic
  feature catalog.
- **D4.** NFD-discovered labels (`feature.node.kubernetes.io/*`) and
  vendor-discovered labels (`nvidia.com/*`) live in label namespaces
  the base does not own. The Layer-C reservation must NOT relabel,
  proxy, or duplicate them — convention-based ownership is documented,
  enforcement is bounded to `platform.io/*`.
- **D5.** The Reserved-label rule (AGENTS.md §"PNI v2 Capability-First
  Contract") already governs `platform.io/{provide,
  capability-{provider,consumer,endpoint,protocol}}.*` namespaces. The
  hardware-feature and hardware-capability reservations extend this
  rule; they do not introduce a new enforcement primitive.
- **D6.** Validation tooling (`scripts/lint-capability-index.sh`,
  `scripts/check-capability-index-refs.sh`,
  `scripts/render-capability-index.sh`) must extend over the new layer
  without breaking the existing Layer A / Layer B contracts.
- **D7.** Workload-runtime-class labels (`sandbox.atlas.dev/gvisor`,
  future `runtime-class.platform.io/*`, podSecurity-class hints) are a
  distinct concern — not capabilities, not features. The ADR explicitly
  marks them out-of-scope rather than silently bundling them into
  Layer A/B/C.

## Considered Options

**Option 1 — Single hardware-features layer (chosen).** Introduce
`docs/platform-hardware-features.yaml` as Layer C, a static catalog of
atomic hardware features. Existing Layer-A entries gain a
`requires_hardware_features[]` field referencing Layer-C ids. Composite
capabilities are downstream-defined in consumer `cluster.yaml`
`hardware-capabilities:` blocks, each declaring `requires_features:`
that resolves to Layer-C atoms.

**Option 2 — Field-on-Layer-A.** Add `requires_hardware_features[]` to
Layer-A entries directly, with the feature ids defined inline (no
separate registry). Avoids a third file but loses cross-reference
validation, sacrifices the CNCF "capabilities comprised of features"
hierarchy, and forces hardware features to be re-declared in every
Layer-A entry that needs them (e.g., `nvidia-gpu` would appear in
`gpu-runtime`, `cluster-provisioning`, and a hypothetical
`gpu-scheduling` entry — three sources of truth for one fact).

**Option 3 — Two-layers-with-runtime-discovery-only.** Reject a static
Layer-C registry; defer all hardware-feature semantics to NFD at runtime
on a live cluster. NFD-discovered labels become the Layer-C surface
implicitly. This option fails three drivers: (a) the base cannot
validate `cluster.yaml` references without runtime context (D3
violation); (b) the base has no way to govern the
`platform.io/hardware-feature.*` namespace at admission time
(D5 violation); (c) the implicit-layer-via-NFD design re-creates the
exact mis-classification (`gpu-runtime.composition[]` includes NFD)
that motivated this ADR (D1 violation).

## Decision Outcome

**Chosen: Option 1.** Introduce Layer C as a static catalog mirror to
Layer A's pattern — separate YAML file, separate JSON Schema, separate
validation pass. Compose at the consumer-`cluster.yaml` boundary via the
`requires_features:` cross-reference.

### Three layers

| Layer | Scope | SOT | Example entry id |
|---|---|---|---|
| **A — Tool-Capability-Index** | What functional services this base provides, with which tools today, and what swap classes exist between alternative implementations. | `docs/platform-capability-index.yaml` | `gpu-runtime` |
| **B — PNI Network-Trust Registry** | Which cross-namespace L4/L7 traffic patterns are permitted, governed by Kyverno + Cilium. Subset of Layer A by id. | `kubernetes/base/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml` | `monitoring-scrape` |
| **C — Hardware Features Registry** | What atomic hardware predicates a node must satisfy. Referenced by Layer A entries (via `requires_hardware_features[]`) and by consumer `cluster.yaml` composite capabilities (via `requires_features[]`). | `docs/platform-hardware-features.yaml` | `nvidia-gpu` |

Layer A and Layer B remain in the relationship documented by the
predecessor ADR: every Layer-B entry has a Layer-A counterpart by id;
the reverse is not required. Layer C is structurally disjoint from B
(network-trust ≠ hardware) and additively reference-able from A.

### Reserved label namespaces

The Reserved-label rule (AGENTS.md §"PNI v2 Capability-First Contract")
extends to cover both Layer-C namespaces. Tenants MUST NOT set keys in
these namespaces on tenant-owned resources (Pods, Namespaces, Services):

| Namespace | Layer | Set by | Tenant-set allowed? |
|---|---|---|---|
| `platform.io/provide.<cap>` | B | base manifests (RBAC-gated) | no |
| `platform.io/capability-provider.<cap>` | B | producer Helm `podLabels` | no (namespace-anchored) |
| `platform.io/capability-consumer.<cap>` | B | consumer Helm `podLabels` | yes |
| `platform.io/capability-endpoint.<cap>` | B | producer Service annotation | no |
| `platform.io/capability-protocol.<cap>` | B | producer Service annotation | no |
| `platform.io/hardware-feature.<feat>` | C | Talos `machine.nodeLabels`, NFD relay, or device-plugin (atomic, Layer-C-emitted) | no |
| `platform.io/hardware-capability.<cap>` | C-composite | Talos `machine.nodeLabels` (downstream-defined per the composite-capability convention) | no |

Upstream-owned namespaces are governed by convention, not by base
policy:

- **`feature.node.kubernetes.io/*`** — owned by NFD chart. The base does
  not relabel, proxy, or duplicate NFD-emitted labels into the
  `platform.io/hardware-feature.*` namespace. Both namespaces coexist;
  consumers choose which to reference for which decision.
- **`nvidia.com/*`** — owned by the NVIDIA device plugin. Convention:
  vendor namespaces follow the package name. Base policy does not
  govern these.

Kyverno enforcement of the two new `platform.io/hardware-{feature,
capability}.*` reservations is added to the existing
`kyverno-clusterpolicy-pni-reserved-labels-enforce.yaml` (or a
co-located sibling policy) — same rule shape, extended key list.

**Enforcement scope (intentional limits):**

- **Standard-workload kinds, direct + template label paths.** The rule
  matches Pod, Deployment, StatefulSet, DaemonSet, ReplicaSet,
  ReplicationController, Job, CronJob, Service, Namespace, and denies
  reserved-label keys on both the resource's own `metadata.labels` AND
  on workload-template paths (`spec.template.metadata.labels`,
  `spec.jobTemplate.spec.template.metadata.labels`). Closing the
  template path prevents controller-mediated propagation to child Pods
  from defeating direct-Pod admission.
- **Tenant-deployable CRD instances** (KubeVirt `VirtualMachine`, CNPG
  `Cluster`, `RabbitmqCluster`, `RedisFailover`, `Kafka`, KubeVirt
  `DataVolume`, etc.) carry their own template-label paths. Per-CRD
  enforcement is the **operator's responsibility** (parallel to the
  per-instance generate/mutate machinery the
  [Producer/Consumer Symmetry ADR](./adr-capability-producer-consumer-symmetry.md)
  scopes to consumer overlays). A follow-up issue tracks per-CRD policy
  generation; the base does not pre-empt operator-specific admission
  shapes.
- **`Node` is NOT in the rule's match list.** Legitimate writers are
  Talos `machine.nodeLabels` (cluster-bootstrap path) and operators
  with `nodes/patch` RBAC. The trust boundary for Node-target writes
  is Kubernetes RBAC, not this policy. Consumer clusters that grant
  `nodes/patch` to a tenant workload must add an audit-mode policy on
  Node-update or accept that the tenant can write Layer-C labels to
  Nodes it has RBAC for.

These scope limits were surfaced by the Round-1 adversarial review
(`team-red`); the rule scope and ADR claim were tightened together.
Findings ledger: `.work/reviews/r1/team-red.md`.

### Composite capability convention

The CNCF Platforms White Paper "capabilities comprised of features"
hierarchy maps onto a two-tier vocabulary:

- **Layer C — atomic hardware features.** Observable hardware facts:
  `nvidia-gpu`, `vt-x-or-amd-v`, `kvm-kernel-module`,
  `drbd-kernel-module`, `local-nvme-block-device`, `iommu-enabled`,
  `ebpf-capable-kernel`. Each carries an `id`, `discovery_source`
  (`nfd` / `talos-machine-config` / `device-plugin` /
  `external-bios-or-firmware`), and a `presence_predicate`. The base
  ships the catalog; it does NOT discover features at runtime.
- **Composite capabilities (downstream-defined).** Consumer cluster
  repos declare these in their `cluster.yaml` `hardware-capabilities:`
  block. Each composite entry names atoms it requires:

  ```yaml
  hardware-capabilities:
    compute-virt:
      requires_features: [vt-x-or-amd-v, kvm-kernel-module]
      emits_label: platform.io/hardware-capability.compute-virt
    compute-gpu-nvidia:
      requires_features: [nvidia-gpu, iommu-enabled]
      emits_label: platform.io/hardware-capability.compute-gpu-nvidia
    storage-local-nvme:
      requires_features: [local-nvme-block-device]
      emits_label: platform.io/hardware-capability.storage-local-nvme
  ```

  Composite capabilities emit `platform.io/hardware-capability.<cap>=true`
  node labels via Talos `machine.nodeLabels` (rendered into the per-node
  config by the consumer's lifecycle automation). Kubernetes
  scheduling, taints/tolerations, nodeSelector, and node-affinity then
  consume these labels for placement decisions.

**The base ships no composite-capability registry.** Composite ids are
free to vary across consumer cluster repos (homelab may define
`compute-virt`; office may define `compute-virt-nested`; both are
local-namespace ids). Cross-cluster comparability is achieved at the
*atomic-feature* level, not the composite level.

### NFD placement

Per `.work/issues/layer-audit/cleanup-scope.md` Q2 verdict (B): NFD is
**Layer-C producer-tooling**, not a Layer-A swappable tool. It MAY have
a META Layer-A entry to document its presence and lifecycle (this is an
open question deferred from issue #61's scope — see "Out of scope for
v1" below). It MUST NOT appear in any Layer-A entry's `composition[]`.

**Single-source convention for per-feature labels.** Where the platform
ships *both* NFD AND a Talos-`machine.nodeLabels` path for the same
atomic feature (current example: `nvidia-gpu`), consumer cluster repos
MUST pick exactly one source and MUST NOT have both writing labels for
the same feature on the same Node. Allowing both creates a label-drift
hazard (Round-1 reviewer MED — `.work/reviews/r1/reviewer.md`): NFD
might transiently miss a PCI re-enumeration while the Talos label stays
stale `true`, or vice versa. Scheduling decisions then diverge depending
on which key the consumer's nodeSelector references. The two
`node_label_key` and `alt_label_keys` columns in
`docs/platform-hardware-features.yaml` document the available sources;
they do NOT authorize using more than one per cluster.

Concretely: `docs/platform-capability-index.yaml` entry `gpu-runtime`
removes `node-feature-discovery` from `composition[]` and gains
`requires_hardware_features: [nvidia-gpu, iommu-enabled]` referencing
Layer-C atoms. The `independence_test.alt_impls_exist` field is
re-evaluated post-NFD-removal: the bundle's `false` value was an
artifact of the bundle choice; the device-plugin layer alone has
alt-impls per the entry's own notes.

### Workload-class out-of-scope

Workload-runtime-class labels — `sandbox.atlas.dev/gvisor`, future
`runtime-class.platform.io/*`, podSecurity-class hints — are a distinct
**fourth concept** *not* governed by this ADR. They are scheduling
hints owned by the corresponding infra-component Layer-A entries
(e.g., `gvisor-runtime` for `sandbox.atlas.dev/gvisor`); ownership
flows from the component manifest into the workload at admission time,
not from a centralized registry.

Reasons for deferral:

1. Cross-component need has not yet surfaced — only one workload-class
   label (gvisor) currently exists in the base.
2. Co-locating workload-class with hardware-features would re-introduce
   the conflation pattern this ADR is supersizing the Two-Layer ADR to
   correct.
3. Workload-class semantics may evolve under the Kubernetes
   RuntimeClass + PodSecurityStandards trajectory; pinning a registry
   shape now risks misalignment.

A follow-up ADR may be filed when cross-component need surfaces.

### Out of scope for v1

- **A Layer-A META entry for NFD-the-tool** — the ADR clarifies the
  option exists (NFD is allowed in Layer A as a META entry; only the
  `composition[]` inclusion is forbidden) but does not require it in
  v1.
- **Runtime hardware-feature discovery extensions in the base** —
  per-node feature probing via Talos boot-hooks or NFD custom rules.
  Layer C is a static catalog, not a runtime state store.
- **An upstream NFD policy filing** — for NFD to formally publish a
  label-namespace reservation policy. Marked `[assumption-gap]` and
  deferred.
- **A base-side composite-capability registry.** Composite capabilities
  remain consumer-defined per the convention above.
- **Backstage entity-model adapter or Crossplane XRD mapping.** Both
  are forward-looking per [`vision.md`](./vision.md) and unchanged by
  this ADR.

## Consequences

### Positive

- **C+1.** Single answer for "what hardware does this capability
  require?" — Layer-A `requires_hardware_features[]` resolves
  mechanically against Layer C.
- **C+2.** Consumer `cluster.yaml` validation gains a per-feature
  resolution check (`make validate-schematics` exits 1 with
  `feature-id not in Layer-C registry` diagnostic — see issue #63
  AC6f).
- **C+3.** The NFD mis-classification in `gpu-runtime` is corrected;
  `independence_test` becomes an honest claim.
- **C+4.** The composite-capability convention gives downstream cluster
  repos a uniform pattern for labeling nodes without forcing a
  centralized composite registry.
- **C+5.** Reserved-label vocabulary covers the full
  `platform.io/{provide, capability-*, hardware-feature,
  hardware-capability}.*` surface; tenants without elevated RBAC
  cannot forge hardware-attestation claims through standard-workload
  kinds (Pod, Service, Namespace, Deployment, StatefulSet, DaemonSet,
  ReplicaSet, ReplicationController, Job, CronJob — direct labels and
  workload-template labels). Per-CRD instance forgery (KubeVirt VM,
  CNPG Cluster, etc.) and Node-target forgery (requires `nodes/patch`
  RBAC) are out of this rule's scope — see §"Enforcement scope
  (intentional limits)" above for the rationale and follow-up issue
  pointer.
- **C+6.** The four-concept boundary (capabilities Layer A; trust
  Layer B; hardware Layer C; workload-class explicitly out-of-scope)
  is now stated rather than implicit.

### Negative

- **C–1.** Three artifacts must stay in sync where IDs cross-reference.
  Mitigated by the extended `scripts/check-capability-index-refs.sh`
  pass + the `capability-index-check` CI job.
- **C–2.** Composite capabilities being downstream-defined means
  cluster-to-cluster comparability requires careful naming discipline.
  Mitigated by the convention being documented in this ADR + base
  shipping the atomic-feature catalog (the cross-cluster invariant).
- **C–3.** NFD-emitted `feature.node.kubernetes.io/*` labels and
  Layer-C `platform.io/hardware-feature.*` labels coexist. Consumers
  may pick either for scheduling. This is by design (D4 — convention
  not policy for upstream namespaces) but may confuse first-time
  readers.
- **C–4.** The Two-Layer ADR's body is preserved with only a frontmatter
  flip + a superseded-note. Readers may need to read both ADRs to
  understand the evolution. Mitigated by the `companion-docs:`
  cross-references and the `supersedes:` / `superseded_by:` pointers.

### Neutral

- **C±1.** Workload-class deferral may grow into a fourth ADR. The
  cost of premature ADR-authoring exceeds the cost of explicit
  scope-narrowing here.
- **C±2.** NFD MAY appear as a META Layer-A entry; not deciding either
  way in v1 keeps the door open.

## References

- CNCF TAG App Delivery — *Platforms White Paper* (2023):
  https://tag-app-delivery.cncf.io/whitepapers/platforms/
- Kubernetes Node Feature Discovery:
  https://kubernetes-sigs.github.io/node-feature-discovery/
- NVIDIA device plugin label namespace:
  https://github.com/NVIDIA/k8s-device-plugin
- Talos `machine.nodeLabels`:
  https://www.talos.dev/v1.7/reference/configuration/v1alpha1/config/#Config.machine.nodeLabels
- Companion ADR (superseded): [adr-two-layer-capability-architecture.md](./adr-two-layer-capability-architecture.md)
- Companion ADR (Layer B): [adr-capability-producer-consumer-symmetry.md](./adr-capability-producer-consumer-symmetry.md)
- Audit trail (Round 1): `.work/issues/layer-audit/findings.md`
- Audit trail (Round 2): `.work/issues/layer-audit/cleanup-scope.md`
- Implementation tracking: [issue #61](https://github.com/Nosmoht/talos-platform-base/issues/61)
