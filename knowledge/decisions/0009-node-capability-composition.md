---
type: decision
title: "ADR: Node Capability Composition (γ') — composable per-node features over monolithic classes"
description: "Replaces monolithic node classes with composable per-node hardware capabilities — explicit base-owned provisioning profiles decoupled from detected features, with boot kernel args baked into Image Factory schematics."
status: stable
id: base:node-capability-composition
decided: "2026-06-20T00:00:00Z"
deciders:
  - platform-maintainer
consulted:
  - reviewer (architect / simplicity / docs / security)
  - team-red (pre-mortem, two rounds)
  - Codex (independent cross-model review, two rounds)
supersedes: []
related:
  - "[Three-Layer Capability Architecture (Layer C vocabulary + iommu detection atom)](./0003-three-layer-capability-architecture.md)"
  - "[OpenTofu Cluster Lifecycle (the module this changes)](./0006-opentofu-cluster-lifecycle.md)"
  - "[cluster.yaml as Source-of-Truth](./0007-cluster-yaml-sot.md)"
implementation-tracking-issue: "not yet filed (the P2 γ' issue referenced by base:three-layer-capability-architecture / issue #61)"
tags: [adr, capability]
---

# ADR: Node Capability Composition (γ') — composable per-node features over monolithic classes

> **Status: accepted.** This is the γ' design that
> [issue #61](https://github.com/Nosmoht/talos-platform-base/issues/61)
> names as the *"in-flight γ' Talos-OCI-ification proposal (P2 issue, not
> yet filed): γ' models hardware as multi-membership per-node features."*
> The three-layer ADR established the **detection vocabulary**; this ADR
> specifies the **per-node provisioning composition** the vocabulary implies
> but never bound to the executor (`tofu/modules/talos-cluster`). It was
> reworked twice after parallel reviewer / team-red / Codex review; §"Review
> findings resolved" records each finding and its resolution.

## Context and Problem Statement

The current node model presses **three orthogonal axes into one `class` key**
(`tofu/modules/talos-cluster/variables.tf` `var.classes`): image architecture
(amd64/arm64 + SBC overlay), schematic content (system-extensions), and
machine-config patches. A node gets exactly one `class`, a monolithic bundle.
This breaks on two axes a real cluster exercises:

1. **Combinatorial class explosion.** A node's hardware function is a *set* of
   orthogonal capabilities (replicated storage, KubeVirt compute, GPU, SR-IOV
   gateway, …). One monolithic class per node needs up to 2^N hand-authored
   classes, each re-unioning extensions, kernel args, and modules by hand. The
   the example `gpu` class already re-lists every base extension because YAML
   anchors cannot append
   (`tofu/modules/talos-cluster/examples/complete/cluster.yaml`).

2. **Kernel arguments are in the wrong layer and are a no-op.** Boot-time
   kernel args (IOMMU/VFIO) are smuggled through
   `config_patches → machine.install.extraKernelArgs`. From Talos **v1.10**,
   fresh UEFI installs boot via UKI + systemd-boot (Secure Boot and
   non-Secure-Boot alike); the UKI bundles the kernel command line, so
   `machine.install.extraKernelArgs` is **ignored**. Boot args must be baked
   into the Image Factory schematic (`customization.extraKernelArgs`), which
   the module's builder (`main.tf` ~389–410) never emits — it emits only
   `systemExtensions` + `overlay`. Consequence: **IOMMU / VFIO / SR-IOV
   passthrough is not correctly expressible in the base today**, and the
   the example `kubevirt` class (`intel_iommu=on` via `machine.install`) is a
   silent no-op on v1.10+.

   *Evidence label (per `rules/capability-claims.md`):* the
   `machine.install.extraKernelArgs`-no-op-under-UKI claim is **confirmed** —
   Talos v1.10 "What's New" states UKIs make the cmdline unmodifiable without
   rebuilding the UKI and that `.machine.install.extraKernelArgs` is ignored
   under systemd-boot (siderolabs/talos #10339, #11145). The Image Factory
   accepting `customization.extraKernelArgs` is confirmed by a live round-trip
   (§Validation). This ADR does **not** claim the field was "removed in v1.12"
   — only that it is a no-op under the v1.10+ UKI default.

A simulation of five topologies (uniform → fully heterogeneous "shares
nothing") showed the monolithic-class model covering only the uniform /
mixed-arch cases and failing both capability-overlap and kernel-arg
correctness.

Roles are **not** part of the problem: Talos `machine.type` is exactly
`{controlplane, worker}` (the earlier `init` / `join` types are gone); a
control-plane node runs workloads via
`cluster.allowSchedulingOnControlPlanes`, not a separate type. Storage /
compute / gateway / GPU are an orthogonal axis realised through node labels +
operators + installer-image content. Architecture: Talos supports **amd64 and
arm64 only**; RISC-V is not a Talos OS target as of 2026 (v1.12 added only a
riscv64 `talosctl` CLI binary).

## Decision Drivers

- **D1.** Cover every topology from uniform to fully heterogeneous in
  `cluster.yaml` without combinatorial hand-authoring.
- **D2.** Boot-time kernel args must reach the booted kernel (schematic, not
  the dead `machine.install` path).
- **D3.** A capability's parts (extension + kernel args + kernel module +
  label) must be bound so they cannot drift apart.
- **D4.** Tool-agnostic, swappable capability names at the node declaration: a
  node declares *replicated storage*, not *drbd*. A DRBD→Ceph swap must not
  edit every node line.
- **D5.** Stay within the substrate-only boundary: the base ships the
  composition *mechanism* + a base-owned provisioning catalog; composite
  capability *names* stay consumer-defined (three-layer ADR).
- **D6.** Emit the Layer-C `platform.io/hardware-feature.*` labels the
  three-layer ADR reserves — but only for atoms the base actually
  provisions (see §"Provisioned vs detected"), so the single-source
  convention is honoured by construction.

## Considered Options

Four schema models, evaluated against seven topology/correctness scenarios
(T1 uniform, T2 single-node, T3 mixed-arch, T4 partial capability overlap, T5
fully heterogeneous, T6 tool-swap DRBD→Ceph, T7 kernel-arg correctness):

1. **M0 — status quo** (monolithic `class` per node).
2. **M1 — composite-capability declaration** (chosen).
3. **M2 — atomic declaration** (node lists atoms/profiles directly).
4. **M3 — hybrid** (capabilities + raw escape hatch).

| Scenario | M0 | M1 | M2 | M3 |
|---|---|---|---|---|
| T1 uniform | ✅ | ✅ | ✅ | ✅ |
| T2 single-node | ✅ | ✅ | ✅ | ✅ |
| T3 mixed-arch | ✅ | ✅ | ✅ | ✅ |
| T4 partial overlap | ❌ 2^N + karg no-op | ✅ union | ✅ union | ✅ |
| T5 fully heterogeneous | ❌ no reuse + karg no-op | ✅ auto-dedup | ✅ auto-dedup | ✅ |
| T6 swap DRBD→Ceph | ❌ scattered | ✅ one line | ❌ every node line | ✅ |
| T7 kernel-arg correctness | ❌ `machine.install` no-op | ✅ schematic | ✅ schematic | ✅ schematic |

## Decision Outcome

Chosen: **M1 — composite-capability composition**. M0 fails T4/T5/T7; M2
fails T6 (it names the tool/atom at the node); M3's escape hatch erodes the D4
swappability M1 provides and is deferred under YAGNI.

### Four concepts — provisioning DECOUPLED from detection

The key correction from review: **provisioning must not be inferred from
`requires_features`**. Most Layer-C atoms are NFD-**detected** hardware facts
that cannot be provisioned — `vt-x-or-amd-v`, `nvidia-gpu` (presence),
`kvm-kernel-module` (auto-loads on VMX/SVM hardware), `local-nvme-block-device`,
`ebpf-capable-kernel` all carry `discovery_source: nfd` in the registry. Only
`drbd-kernel-module` and `iommu-enabled` carry `discovery_source:
talos-machine-config` — i.e. only those two are *provisioned*. Inferring a
profile from an atom therefore left KubeVirt's atoms with no profile and
silently redefined `compute-virt`. The corrected model declares the two
concerns **separately**:

| Tier | Example | Owner | Role |
|---|---|---|---|
| **Runtime capability** (Layer A/B, PNI) | `block-storage-replicated` | operator pods, namespace-anchored | what a workload consumes; swappable |
| **Composite hardware-capability** (consumer) | `storage-replicated: { requires_features: [drbd-kernel-module], provisioning_profiles: [drbd], emits_label: … }` | consumer `cluster.yaml` (three-layer shape, + `provisioning_profiles`) | what a node declares; **two decoupled fields** |
| **Detection atom** (Layer C registry) | `iommu-enabled`, `vt-x-or-amd-v`, `nvidia-gpu` | base `platform-hardware-features.yaml` (unchanged) | the stable predicate `requires_features` points at — for scheduling/label |
| **Provisioning profile** (γ', NEW base catalog) | `drbd`, `iommu` (vendor variants), `nvidia-lts` | **base-owned** catalog | carries the `provisions:` bundle; **selected explicitly** by `provisioning_profiles`, never inferred |

`requires_features` (detection/scheduling, three-layer convention, unchanged)
and `provisioning_profiles` (explicit base-profile selection) are independent
lists. Composite ids are consumer-namespace-local and distinct from Layer-A
tool-capability ids (`storage-replicated` ≠ the Layer-A `block-storage-replicated`).

> This ADR's "four concepts" are the **provisioning** tiers above. They are
> disjoint from the three-layer ADR's separately-numbered "fourth concept"
> (workload-runtime-class labels) — no overlap, no renumbering.

### Provisioned vs detected (resolution invariant)

- **Provisioned atoms** — `discovery_source: talos-machine-config`
  (`drbd-kernel-module`, `iommu-enabled`). The module identifies these
  self-contained as the union of all catalog profiles' `provides` — it does NOT
  read the registry at plan time; that set equals the registry's
  `talos-machine-config` atoms by construction, guarded by a CI cross-reference
  gate. If a composite lists such an atom in `requires_features`, the same
  composite **MUST** include a `provisioning_profile` whose provisions satisfy
  it, else **hard plan-time error** (no label without provisioning). γ' emits the
  `platform.io/hardware-feature.<atom>` label for these.
- **Detected atoms** — `discovery_source: nfd | device-plugin`
  (`vt-x-or-amd-v`, `kvm-kernel-module`, `nvidia-gpu`, `local-nvme-block-device`,
  `ebpf-capable-kernel`). These are hardware facts / auto-loaded modules; they
  need **no** provisioning and γ' does **not** emit their label — NFD / the
  device-plugin owns it (single-source convention satisfied by construction).
  A composite may still list them in `requires_features` for scheduling.

This makes `compute-virt` (basic KubeVirt: `vt-x-or-amd-v` + `kvm-kernel-module`,
both detected) need **zero** provisioning — matching the three-layer ADR
definition exactly, no contradiction — while PCI passthrough is a distinct
capability that *does* provision IOMMU.

### cluster.yaml shape

```yaml
# BASE-OWNED provisioning-profile catalog. This is a MODULE-LOCAL constant (a
# `local` in tofu/modules/talos-cluster, with a documented shape validated at
# plan time by `check` blocks) — NOT a consumer field and NOT a `var` a consumer
# could override. Consumers reference profiles by id from a composite's
# provisioning_profiles; they cannot author or redefine a profile (closes the
# consumer-redefine vector mechanically; the catalog also lives in tofu/** so the
# hard-constraints-check greps cover it). `provides` names the provisioned atom a
# profile satisfies — used for label emission + the symmetry check, NOT for
# selection. An atom is "provisioned" iff some catalog profile `provides` it
# (self-contained; equal by construction to the registry's
# discovery_source: talos-machine-config set — a CI gate guards the equivalence).
provisioning_profiles:
  drbd:
    provides: [drbd-kernel-module]
    extensions: [siderolabs/drbd]
    kernel_modules: [{name: drbd, parameters: [usermode_helper=disabled]}, {name: drbd_transport_tcp}]
  iommu:
    provides: [iommu-enabled]
    kernel_modules: [{name: vfio-pci}]
    variants:                            # explicit vendor selector, not name convention
      intel: {kernel_args: [intel_iommu=on, iommu=pt]}
      amd:   {kernel_args: [amd_iommu=on, iommu=pt]}
  nvidia-lts:                            # no `provides`: nvidia-gpu is NFD-detected presence,
    extensions: [siderolabs/nvidia-open-gpu-kernel-modules-lts, siderolabs/nvidia-container-toolkit-lts]  # not a provisioned atom; name MUST match the device-plugin nodeAffinity selector
    kernel_modules: [{name: nvidia}, {name: nvidia_uvm}, {name: nvidia_drm}, {name: nvidia_modeset}]
    sysctls: {net.core.bpf_jit_harden: "1"}

# CONSUMER-DEFINED composites: requires_features (label/scheduling) AND
# provisioning_profiles (explicit) are SEPARATE lists. `emits_label` MUST be in
# the platform.io/hardware-capability.* namespace — the reserved Layer-C
# platform.io/hardware-feature.* labels are emitted ONLY from a selected profile's
# base-controlled `provides`, never from a consumer emits_label (closes the
# reserved-label-forgery vector; plan-time validated).
hardware-capabilities:
  storage-replicated:
    requires_features: [drbd-kernel-module]          # provisioned atom -> profile required
    provisioning_profiles: [drbd]
    emits_label: platform.io/hardware-capability.storage-replicated
  compute-virt:                                       # basic KubeVirt
    requires_features: [vt-x-or-amd-v, kvm-kernel-module]   # detected only -> NO profile
    provisioning_profiles: []                         # KVM is in-kernel + auto-loads on VMX/SVM HW (common case);
    emits_label: platform.io/hardware-capability.compute-virt   # add a `kvm` profile only if your HW does not auto-load
  compute-virt-passthrough:                           # KubeVirt + PCI passthrough
    requires_features: [vt-x-or-amd-v, kvm-kernel-module, iommu-enabled]
    provisioning_profiles: [iommu]                    # iommu provides iommu-enabled -> it IS in requires_features (symmetry)
    emits_label: platform.io/hardware-capability.compute-virt-passthrough
  compute-gpu-nvidia:                                 # PASSTHROUGH-GPU (vfio) variant shown here to exercise the symmetry
                                                      # rule. The shipped examples/complete fixture instead models a PLAIN
                                                      # device-plugin GPU: requires_features [nvidia-gpu], profiles
                                                      # [nvidia-lts], NO iommu (a non-passthrough GPU needs no IOMMU).
    requires_features: [nvidia-gpu, iommu-enabled]    # nvidia-gpu NFD-detected; iommu-enabled provisioned by the iommu profile
    provisioning_profiles: [nvidia-lts, iommu]        # -> iommu-enabled MUST be declared (symmetry); matches three-layer ADR
    emits_label: platform.io/hardware-capability.compute-gpu-nvidia

# non-composable base-image axis: arch + CPU vendor + image-baseline extensions
# (+ optional SBC overlay). `extensions` here are baked on EVERY node of the image
# regardless of capabilities — baseline content that is NOT a capability (CPU
# microcode, NIC/GPU firmware, base tooling, a default runtime sandbox). The
# node's effective extension set = image.extensions ∪ selected-profile extensions,
# so a plain controlplane (no capabilities) still gets microcode/firmware and
# baseline content stays out of the 2^N capability matrix.
images:
  intel-amd64: {architecture: amd64, cpu_vendor: intel, extensions: [siderolabs/intel-ucode, siderolabs/i915, siderolabs/nvme-cli, siderolabs/gvisor]}
  amd-amd64:   {architecture: amd64, cpu_vendor: amd,   extensions: [siderolabs/amd-ucode, siderolabs/nvme-cli, siderolabs/gvisor]}
  rpi:         {architecture: arm64, cpu_vendor: arm,   extensions: [], overlay: {name: rpi_generic, image: siderolabs/sbc-raspberrypi}}

nodes:
  - {hostname: hci-1, role: worker, image: intel-amd64, hardware_capabilities: [storage-replicated, compute-virt-passthrough]}
  - {hostname: gpu-1, role: worker, image: amd-amd64,   hardware_capabilities: [compute-gpu-nvidia]}
  - {hostname: pi-1,  role: worker, image: rpi,         hardware_capabilities: []}
```

> [2026-07-11 verification] The catalog landed as specified — a module-local
> constant a consumer cannot override, now at
> `tofu/modules/talos-cluster/profiles.tf` — but the plan-time shape/invariant
> validation is implemented as `lifecycle.precondition` blocks on
> `terraform_data.composition_guards`
> (`tofu/modules/talos-cluster/composition.tf`), deliberately **not** top-level
> `check` blocks: top-level `check` blocks only warn and would not fail the plan.

### Composition mechanics (executor contract)

Per node, the module computes:

1. **Select profiles**: union the `provisioning_profiles` listed by the node's
   `hardware_capabilities`. No atom→profile inference — the list is explicit.
2. **Resolve variants**: a profile carrying `variants` is resolved by the
   node's `images.<id>.cpu_vendor`. A profile with `variants` but no entry for
   the node's `cpu_vendor` → **hard error**. A listed profile absent from the
   catalog → **hard error**.
3. **Bind the two lists symmetrically** (hard plan-time errors, both
   directions — closes the drift the review found in both directions):
   - *Forward:* every `requires_features` atom with registry
     `discovery_source: talos-machine-config` must be satisfied by a selected
     profile (closes "label without provisioning").
   - *Inverse:* every `provides` atom of a selected profile must appear in the
     composite's `requires_features` (closes "provisioned but unlabeled" — the
     GPU-passthrough-won't-schedule case). The two lists cannot drift.
4. **Union into two sinks**:
   - **Image Factory schematic** (drives the installer image; a change is a
     Day-2 `talosctl upgrade` re-image): `customization.systemExtensions.officialExtensions`
     (the node's `images.<id>.extensions` baseline ∪ each selected profile's
     `extensions`), `customization.extraKernelArgs` (∪ `kernel_args`),
     top-level `overlay` (from the image — profiles cannot set an overlay).
   - **Machine config** (apply-config; no re-image for labels/sysctls):
     `machine.kernel.modules` (∪ `kernel_modules`), `machine.sysctls`
     (∪ `sysctls`), `machine.nodeLabels` (each composite's `emits_label` + a
     `platform.io/hardware-feature.<atom>` for each selected profile's
     `provides` atom — which the step-3 symmetry check guarantees is in
     `requires_features`).
5. **Canonicalize + dedup**: sort every union list; serialize maps with
   canonical key order and normalize optional fields (always emit
   `parameters`, even when empty) so structurally-identical bundles hash
   identically. The schematic is content-hashed → one schematic per distinct
   (extensions, kernel-args, overlay); one installer per (schematic-hash,
   architecture). The exact canonicalization function is an implementation AC
   verified by a determinism test (two declaration orders → one hash).

### Conflict semantics (hard plan-time errors, never silent merge)

- **kernel module name + differing parameters** across profiles → hard error.
- **sysctl key + differing value** → hard error.
- **kernel arg `key=value` with differing value** (parsed on `=`; bare flags
  compared literally) → hard error. Vendor-exclusive variants already prevent
  the intel/amd case via step 2.
- **extensions** union by name (a duplicate is *not* a conflict — intentional
  shared dependency). Extensions are the one provision type with no conflict
  case; this asymmetry is deliberate, not an omission.

### Design invariants carried forward

- **No SecureBoot (Hard Constraint).** Installer always `urls.installer`,
  never `urls.installer_secureboot`. Content hash keys the schematic;
  `architecture` + `secure_boot=false` key the URL.
- **No `debugfs=off` (Hard Constraint) — already enforced.** Correction from
  review: `.github/workflows/hard-constraints-check.yml` already greps file
  *content* for the literal `debugfs=off` (a separate step from the SecureBoot
  grep); its scope is `kubernetes/**` + `tofu/**`. Because the provisioning
  catalog is **module-embedded under `tofu/`** (a typed module input, not a
  `docs/`-class file), a `debugfs=off` value in a profile's `kernel_args` is
  within scope — no new grep and no placement ambiguity.
- **Single-source labels — satisfied by construction.** γ' emits a
  `platform.io/hardware-feature.<atom>` label only for *provisioned*
  (`talos-machine-config`) atoms; NFD-owned atoms (`nvidia-gpu`, `vt-x-or-amd-v`,
  …) are never γ'-emitted, so γ' and NFD never both write for one feature.
- **iommu-enabled is an assertion, not a probe.** Auto-emitting
  `platform.io/hardware-feature.iommu-enabled` attests the *kernel-arg* half
  (the schematic carries `intel_iommu=on`/`amd_iommu=on`); the *BIOS* half
  remains the operator's assertion — no runtime probe (matches the registry
  predicate framing). Documented limitation. (x86-only today; an arm64 SMMU
  passthrough profile is a future catalog addition, not a model change.)
- **Image-baseline vs capability extensions.** `images.<id>.extensions` carry
  baseline image content that is NOT a capability (CPU microcode, NIC/GPU
  firmware, base tooling, a default runtime sandbox) and is baked on every node
  of the image; capability-driven extensions come from selected profiles, and the
  effective set is the union. This keeps a plain controlplane from silently losing
  baseline content (e.g. CPU microcode — a security regression) just because it
  declares no capabilities, and keeps baseline content out of the 2^N matrix.
- **emits_label is namespace-constrained.** A consumer composite's `emits_label`
  MUST be `platform.io/hardware-capability.*`. The reserved Layer-C
  `platform.io/hardware-feature.*` labels are emitted ONLY from a selected
  profile's base-controlled `provides` — never from a consumer-supplied
  `emits_label` — so a consumer cannot launder a forged reserved label through
  the **typed** paths (plan-time validated). Boundary: a raw `config_patches`
  string can still set `machine.nodeLabels` directly (the module does not parse
  raw patch content), so the raw-patch forgery vector is closed **downstream** by
  the Kyverno `reserved-layer-c-hardware-labels` rule, not by this module — the
  same consumer-overlay boundary as the SecureBoot / podSubnets raw-patch
  residuals.
- **Base-catalog authority + the residual supply-chain vector.** The
  provisioning catalog is base-owned; a consumer selects profiles but cannot
  redefine a profile's bundle (closes the *consumer-redefine* vector). It does
  **not** close the *unpinned-upstream* vector: a profile's `extensions` are
  resolved through the same digest-unpinned Image Factory path the module
  already documents as a residual for the Cilium chart
  (`variables.tf` ~382–384). Same residual, tracked with that one — this ADR
  does not claim to close it. NOTE: the D2 change routes boot-time kernel args
  through this same unpinned path, so the residual's blast radius now includes the
  kernel command line, not only extensions.
- **γ'-generated fields vs raw `config_patches` precedence.** Per the apply
  ordering, a node's raw `config_patches` apply **after** the module-generated
  patch (and `base_cni_patch` strictly last), so a raw patch can override a
  γ'-generated `machine.kernel.modules` / sysctls / nodeLabels value. This stays
  the documented per-node escape hatch (presence composes; per-node *parameters*
  — SR-IOV VF count, hugepages, PCI allowlist, a NIC interface name — live in
  `config_patches`). The override is **silent**: Talos strategic-merge applies
  the raw patch last and the module does not parse raw patch content, so a
  plan-time overlap warning is a documented **follow-up** (not yet implemented).
  Known caveat: a raw patch that drops a generated kernel module while the node
  keeps its provisioning label is drift the inverse-symmetry check does not cover
  (it guards only the generated path).
- **Overlay is a per-image axis.** Talos allows one overlay per schematic;
  `overlay` lives on `images`, not on profiles (a profile `overlay` key is a
  schema error). A feature needing a board overlay is expressed by choosing
  the image. D1 coverage is scoped: *capability* composition is unbounded;
  *overlay* is one-per-image (a Talos constraint, not a model limit).
- **kernel_args scope.** Profile `kernel_args` are boot-time/driver args only
  (IOMMU, VFIO). Platform/console/install args (`talos.platform=`, `console=`)
  remain the module/platform's concern, not blanket-moved.

## Validation

- **Live Image-Factory round-trip — confirmed.** A composed schematic with
  `systemExtensions: [siderolabs/drbd]` AND
  `customization.extraKernelArgs: [intel_iommu=on, iommu=pt]` was uploaded to
  `factory.talos.dev` via the `siderolabs/talos` provider; it returned
  schematic id
  `e4ed980bcf7d818dff6b54f64fcf6252b372f87be2002753244a9cfa62d498d5` and
  installer URL `factory.talos.dev/metal-installer/e4ed980b…:v1.12.6`. The
  factory accepts `extraKernelArgs` and returns a non-empty metal installer.
  Reproducible with a ~25-line harness.
- **Composition + canonical dedup — confirmed offline.** An OpenTofu prototype
  (run in-session, no providers) over a 9-node topology confirmed the
  mechanics: capabilities resolving to the union; kernel args in
  `customization.extraKernelArgs` (not `machine.install`); sorted-union
  content-hash collapsing identical nodes (9 nodes → 7 schematics). The
  mechanics are *specified above* (steps 1–5 + conflict rules); the prototype
  confirms them; the logic lands as committed module code with test fixtures
  in the implementation phase — it is not the design's authority.
- **Unproven until implementation (= the implementation issue's ACs).** The
  module wiring (`machine.kernel.modules` is emitted nowhere today), the
  hard-error paths (steps 2–3 + conflict rules), structured-value
  canonicalization determinism, and a real `tofu plan`/throwaway-cluster boot
  proof.

> [2026-07-11 verification] The implementation has since landed (PR #135):
> `tofu/modules/talos-cluster/composition.tf` emits `machine.kernel.modules` and
> enforces the hard-error paths (steps 2–3 + conflict rules) as preconditions on
> `terraform_data.composition_guards`; the determinism + guard regressions live
> in `tofu/modules/talos-cluster/tests/composition.tftest.hcl`, run by a
> dedicated networked CI job (`task tofu:test` in
> `.github/workflows/tofu-validate.yml`). The catalog↔registry cross-reference
> gate is `scripts/check-provisioning-catalog-refs.sh`, wired into
> `.github/workflows/gitops-validate.yml`. The plan-time overlap *warning* for
> raw `config_patches` overriding γ'-generated values remains a follow-up (still
> not implemented).

### Schema parity decisions (per `rules/schema-contract-parity.md`)

1. **Closed/open field set — deferred-closed.** `images` /
   `hardware-capabilities` / `provisioning_profiles` are intended typed,
   closed module objects (unknown keys rejected, like `var.classes`). The
   enforcing schema ships **with the implementation**; until then the field
   set is proposed, not enforced.
2. **Duplicate keys.** HCL/YAML map decode rejects duplicate keys;
   `node.hostname` / `ip` uniqueness is already validation-guarded.
3. **Version-skew.** No version field; `talos.version` is the schema pin.
   `class → hardware-capabilities` is breaking to the **tofu module
   interface** (`var.classes`) → MAJOR OCI tag bump; the breaking surface is
   the typed module-variable contract, not a Helm value.
4. **In-file untrusted-data marker.** `cluster.yaml` is consumer-authored
   trusted config — no sentinel.
5. **Per-field mutability.** Catalog/capability/image definitions are
   mutable-in-place; `node.hardware_capabilities` is the per-node selection.
   Changing a profile's provisions changes the schematic → Day-2 re-image —
   identical lifecycle to `class.extensions` today.

## Migration (breaking)

`class:` is removed. Mechanical mapping:

| Old (`class`) | New |
|---|---|
| `class.architecture` | `images.<id>.architecture` |
| `class.overlay` | `images.<id>.overlay` |
| `class.extensions` baseline (microcode/firmware/tooling/runtime — e.g. intel-ucode, i915, nvme-cli, gvisor) | `images.<id>.extensions` (image baseline, baked on every node of the image) |
| `class.extensions` capability-specific (drbd, nvidia) | a `provisioning_profile.extensions` selected via a composite |
| `class.config_patches` IOMMU/boot kernel args | a profile's `kernel_args` (→ schematic) |
| `class.config_patches` `machine.kernel.modules` (forward-looking — no live consumer has this today) | a profile's `kernel_modules` |
| `class.config_patches` other | all-nodes / role / node `config_patches` (unchanged) |
| `node.class` | `node.image` + `node.hardware_capabilities` |

**Re-image is expected for the fixed nodes.** Adopting the MAJOR tag
recomputes each node's schematic key. For a node carrying IOMMU/VFIO args the
schematic content **legitimately changes** (the args now actually bake — that
is the D2 fix), so a one-time re-image of those nodes is *correct, not
spurious*, and a `moved{}` shim cannot (and should not) mask it. The
implementation's closure criterion is therefore narrower: **prove no re-image
for nodes whose effective provisioning is unchanged** (e.g. plain
controlplanes), and document the expected one-time re-image for nodes whose
kernel-arg provisioning is corrected — with a throwaway-cluster proof and a
consumer runbook.

## Review findings resolved

Two rework rounds after parallel reviewer / team-red / Codex review.

Round 1 → Round 2 (all verified RESOLVED in Round-2 review): vocabulary
conflation; kernel_modules schematic sink; canonicalization named;
no-op-claim evidence label; parity-decision-1 "deferred-closed"; parity-3
cites module interface; machine.type init/join wording; §Validation honesty.

Round 2 → this revision:

- **`compute-virt` contradicted the three-layer ADR; catalog covered only 3/7
  atoms** → root cause was inferring profiles from `requires_features`. Fixed
  by **decoupling** (`requires_features` vs explicit `provisioning_profiles`)
  plus the **provisioned-vs-detected** rule keyed on registry `discovery_source`.
  `compute-virt` now matches three-layer (detected-only, no provisioning);
  passthrough is its own capability.
- **`cpu_vendor` was name-convention only** → now an **explicit `variants:`
  selector** on the profile, resolved by `images.<id>.cpu_vendor`; no-match →
  hard error.
- **Zero/multi-match + label-without-provisioning** → explicit
  `provisioning_profiles` (no atom inference) + step-3 hard error for
  unprovisioned provisioned-atoms.
- **debugfs CI claim was factually wrong** → corrected: the content-grep
  already covers it; only a file-set confirmation remains.
- **NFD single-source race** → γ' emits labels only for provisioned atoms;
  NFD-owned atoms are never γ'-emitted.
- **Supply-chain over-claim** → narrowed to the consumer-redefine vector; the
  unpinned-upstream residual is named and tied to the existing Cilium-chart
  residual.
- **`config_patches` precedence** → documented (raw patches apply last; a
  plan-time warning surfaces overrides).
- **Extension-merge asymmetry / structured-value canonicalization /
  kernel-arg key parsing** → specified (extensions union intentionally;
  canonical map order + normalize optionals; parse args on `=`) with the exact
  algorithm as an implementation determinism-test AC.
- **Duplicate `## Validation` H2** → the falsification section is renamed
  §"Falsification criteria".

Round 2 → Round 3 (final adversarial pass) → this revision:

- **Profile↔feature one-way drift (NEW HIGH, found independently by team-red +
  Codex):** the `compute-gpu-nvidia` example selected the `iommu` profile but
  omitted `iommu-enabled` from `requires_features` → provisioned-but-unlabeled
  (a passthrough workload selecting on `iommu-enabled` would not schedule
  there). Fixed by a profile-level `provides:` + the **inverse symmetry
  invariant** (step 3) + the example now declares `[nvidia-gpu, iommu-enabled]`,
  matching the three-layer ADR.
- **`kvm-kernel-module` (nfd) optimistic auto-load** → documented: `compute-virt`
  with empty profiles is the common case (KVM is in-kernel, auto-loads on
  VMX/SVM); a `kvm` profile is available where hardware does not auto-load.
- **debugfs grep placement self-contradiction** → the catalog is pinned
  `tofu/`-embedded, within the existing grep scope; the contradiction is
  removed.
- **Catalog-ownership ambiguity** → stated module-local constant (not a consumer
  `cluster.yaml` field; see Round 4 for the typing reconciliation).

Round 3 → Round 4 (implementation-plan review: reviewer + team-red) → this revision:

- **Baseline non-capability extensions had no model home (CRITICAL, verified):**
  every x86 node today carries gvisor / i915 / intel-ucode / nvme-cli as baseline;
  the capability-only extension model dropped them on migration (a silent
  CPU-microcode security regression) and broke the "no re-image for an unchanged
  controlplane" claim (its extension set would change). Fixed by adding
  `images.<id>.extensions` (image baseline); effective extensions = image baseline
  ∪ profile extensions.
- **Catalog NVIDIA package name was wrong (CRITICAL, verified):** the example used
  `siderolabs/nonfree-kmod-nvidia-lts`, but this repo's device-plugin / dcgm
  nodeAffinity select `extensions.talos.dev/nvidia-open-gpu-kernel-modules-lts`
  (and `nonfree-kmod-nvidia` appears nowhere). Corrected — a name mismatch leaves
  GPUs unadvertised and workloads Pending.
- **emits_label forgery (HIGH):** consumer `emits_label` is now namespace-constrained
  to `platform.io/hardware-capability.*`; reserved Layer-C `hardware-feature.*`
  labels come only from base-controlled profile `provides`.
- **Catalog typing (HIGH):** the catalog is a module-local constant with a
  plan-time-validated documented shape (recovering the type checks a bare `local`
  would otherwise lose), reconciling the earlier "typed module input" wording.
- **Provisioned-atom definition (MEDIUM):** defined self-contained as "provided by
  some catalog profile," equal to the registry's `talos-machine-config` set by
  construction and guarded by a cross-reference gate — the module does not read the
  registry at plan time.
- **HCL feasibility / determinism (MEDIUM):** the schematic/installer `for_each`
  keys on the content-hash map (plan-time-known), reading `schematic[hash].id` as a
  value, never as a `for_each` key (avoids the resource-attribute-as-key plan
  error); conflict detection runs before dedup; nested `parameters` lists are
  sorted; kernel args parse on the first `=`. These are implementation ACs with
  determinism + hard-error tests.
- **Supply-chain residual widened:** kernel args now ride the unpinned
  Image-Factory path; the residual note covers the cmdline, not only extensions.

## Pros and Cons of the Options

### M1 (chosen)

- Pro: covers all topologies; fixes T7; binds the parts; D4 swappability;
  single-source-correct labels; minimal model meeting every driver.
- Con: two declared fields per composite (`requires_features` +
  `provisioning_profiles`); a base catalog to govern; a breaking
  module-interface change.

### M2

- Pro: fewer tiers.
- Con: fails T6 — naming the tool/atom at the node makes a swap edit every
  node line.

### M3

- Pro: maximal flexibility.
- Con: two schema paths; the raw path erodes D4.

## Consequences

- **Positive.** Eliminates 2^N classes; fixes the kernel-arg correctness bug
  (factory-confirmed); binds a feature's parts; single-source-correct Layer-C
  labels; tool-swappable node declarations; implements the γ' model #61
  anticipated.
- **Negative.** Breaking `talos-cluster` interface → MAJOR OCI bump with an
  expected one-time re-image for kernel-arg-corrected nodes; a base catalog +
  cross-reference gate to govern.
- **Follow-up.**
  1. Implement the composition in `tofu/modules/talos-cluster` (mechanics §
     above is the contract); emit `machine.kernel.modules` (net-new); gate on
     `task tofu:ci` + a live Image-Factory plan/apply + a throwaway-cluster boot
     proof.
  2. Ship the provisioning-profile catalog + its JSON Schema + a
     cross-reference CI gate (profile / atom id linkage).
  3. Confirm the new catalog path is in `hard-constraints-check`'s grep set.
  4. Migrate the complete example (its `kubevirt` IOMMU is the live bug) + a
     consumer migration runbook with the re-image proof.
  5. File the P2 γ' issue.

## Out of Scope

- **RISC-V.** Not a Talos OS target as of 2026.
- **Runtime hardware-feature discovery.** Layer C stays a static catalog (no
  probing — hence the iommu BIOS-half assertion limitation).
- **The broader "Talos-OCI-ification"** implied by the γ' name — this ADR
  scopes only per-node capability composition.

## Falsification criteria

The decision is wrong if, at implementation, any holds: the Image Factory
rejects a composed schematic (refuted — §Validation); two nodes with an
identical effective provisioning set produce different schematic ids
(canonicalization broken); a node is labeled for a *provisioned* atom it does
not provision (step-3 invariant broken); a composite's listed profile fails to
resolve a variant for the node's `cpu_vendor` without a hard error
(step-2 broken); a node is provisioned for an atom (a selected profile's
`provides`) that the composite omits from `requires_features` (symmetry
invariant broken); a node loses a baseline image extension
(microcode/firmware/tooling) on migration (extension-set-preservation broken); a
GPU node bakes an NVIDIA extension whose Talos label does not match the
device-plugin nodeAffinity selector (capability dead-on-arrival); or a node with
unchanged effective provisioning re-images on the MAJOR-tag adoption (migration
criterion). Each is a mechanical check in the implementation issue.

## Links

- [Three-Layer Capability Architecture](./0003-three-layer-capability-architecture.md)
  — Layer-C vocabulary; this ADR also corrected its `iommu-enabled`
  `presence_predicate` (dead `machine.install.extraKernelArgs` →
  `customization.extraKernelArgs`).
- [issue #61](https://github.com/Nosmoht/talos-platform-base/issues/61) — names the γ' P2 proposal.
- Talos v1.10 "What's New" (UKI ignores `machine.install.extraKernelArgs`):
  <https://www.talos.dev/v1.10/introduction/what-is-new/>
- Talos v1.10 boot assets (schematic kernel args):
  <https://www.talos.dev/v1.10/talos-guides/install/boot-assets/>
- Image Factory API (schematic `customization.extraKernelArgs`):
  <https://github.com/siderolabs/image-factory/blob/main/docs/api.md>
