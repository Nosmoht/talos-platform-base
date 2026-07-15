---
type: architecture
title: Capability Composition
description: How per-node hardware capabilities compose Layer-C atoms, the base-owned provisioning-profile catalog, deduplicated schematics, and node labels in the talos-cluster module.
tags: [layer-c, hardware-capabilities, talos, opentofu]
timestamp: 2026-07-15
sources:
  - tofu/modules/talos-cluster/composition.tf
  - tofu/modules/talos-cluster/profiles.tf
  - tofu/modules/talos-cluster/variables.tf
  - platform-hardware-features.yaml
  - schemas/hardware-features.schema.json
  - scripts/lint-hardware-features.sh
  - scripts/check-provisioning-catalog-refs.sh
  - tofu/modules/talos-cluster/tests/composition.tftest.hcl
  - tofu/modules/talos-cluster/tests/conflict-guards.tftest.hcl
  - .github/workflows/gitops-validate.yml
---

# Capability Composition

A node's hardware specialisation is never a role. Kubernetes roles stay
`controlplane | worker`; everything hardware-specific (GPU, replicated storage,
PCI passthrough, SBC boards) is expressed as a **set** of composable
`hardware_capabilities` plus a base `image`, and the `talos-cluster` module
composes that set into installer schematics and machine-config patches.
Rationale and threat model live in
[0003-three-layer-capability-architecture](../decisions/0003-three-layer-capability-architecture.md)
and
[0009-node-capability-composition](../decisions/0009-node-capability-composition.md);
this page describes the model as implemented.

## The three inputs

- **Layer-C atom registry** — `platform-hardware-features.yaml` (base-owned,
  static): the vocabulary of atomic hardware features.
- **Provisioning-profile catalog** — `tofu/modules/talos-cluster/profiles.tf`
  (base-owned, module-local): what the module can bake to *provision* an atom.
- **Consumer composites** — the `hardware-capabilities:` block in a consumer's
  `cluster.yaml`, mapped by the consumer's OpenTofu shim onto the module's
  `var.hardware_capabilities`, plus each node's `hardware_capabilities` list.

## Layer-C atom registry

`platform-hardware-features.yaml` catalogs atomic hardware features. It is not
consumed at runtime by any in-cluster component — it is read at build time by
validation scripts, at PR time by CI, and at design time by humans and agents.
Per entry (schema: `schemas/hardware-features.schema.json`, JSON Schema draft
2020-12, `additionalProperties: false`):

- `id` — kebab-case identifier (`^[a-z0-9]+(-[a-z0-9]+)*$`), referenced by
  composite `requires_features[]`.
- `discovery_source` — one of `nfd | talos-machine-config | device-plugin |
  external-bios-or-firmware`: how a node learns it has the feature.
- `node_label_key` — the authoritative label asserting presence; required for
  every `discovery_source` except `external-bios-or-firmware`.
- `presence_predicate` — prose condition justifying the label.
- `alt_label_keys`, `references` — informational.

The registry currently holds seven atoms (`nvidia-gpu`, `vt-x-or-amd-v`,
`kvm-kernel-module`, `drbd-kernel-module`, `local-nvme-block-device`,
`iommu-enabled`, `ebpf-capable-kernel`). Exactly two carry
`discovery_source: talos-machine-config` — `drbd-kernel-module` and
`iommu-enabled` — and those are the **provisioned** atoms: the ones the module
itself can satisfy by baking content into the node.

## Base-owned provisioning-profile catalog

`profiles.tf` defines `local.provisioning_profiles` as a **module-local
constant — not a `var`** — so a consumer can select profiles by id but "cannot
author or redefine one (closes the consumer-redefine vector mechanically)". It
lives under `tofu/**` so the hard-constraints CI greps (SecureBoot, debugfs)
cover any kernel args it carries. Each profile binds the parts of a provisioned
feature so they cannot drift:

- `provides` — the `talos-machine-config` atom(s) this profile satisfies;
  drives label emission and the symmetry guard. Empty for a profile that
  provisions content for an NFD-detected atom.
- `extensions` — Image-Factory system extensions → schematic.
- `kernel_args` — boot-time cmdline args → schematic
  `customization.extraKernelArgs` (the Talos v1.10+ UKI-correct sink;
  `machine.install.extraKernelArgs` is a no-op under UKI boot).
- `kernel_modules` → `machine.kernel.modules`.
- `sysctls` → `machine.sysctls`.
- `variants` — vendor-specific kernel args resolved by the node image's
  `cpu_vendor`; a profile with variants ignores its top-level `kernel_args`,
  and a missing vendor entry is a hard plan error.

Shipped catalog: `drbd` (provides `drbd-kernel-module`; `siderolabs/drbd`
extension + drbd modules), `iommu` (provides `iommu-enabled`; `vfio-pci`
module + `intel`/`amd` variants carrying `intel_iommu=on`/`amd_iommu=on`),
and `nvidia-lts` (provides nothing — `nvidia-gpu` is an
NFD-detected presence atom; the profile bakes the LTS open-driver extensions,
nvidia kernel modules, and a `net.core.bpf_jit_harden` sysctl).

`local.provisioned_atoms` is derived self-contained from the catalog's
`provides` sets — the module does **not** read the registry at plan time; a CI
cross-reference gate guards the equivalence (see below).

## Consumer composites and node selection

`var.hardware_capabilities` entries are tool-agnostic composites ("a node
declares `storage-replicated`, not `drbd`") with provisioning **decoupled**
from detection:

- `requires_features` — Layer-C atom ids for scheduling/labels.
- `provisioning_profiles` — base-catalog profile ids to apply; explicit, never
  inferred from `requires_features`.
- `emits_label` — the label a holding node gets; a variable validation forces
  the `platform.io/hardware-capability.*` namespace.

Each node lists `hardware_capabilities` (any set — storage + compute + GPU —
without a hand-authored node class) and an `image` (architecture, `cpu_vendor`,
baseline extensions, optional SBC overlay) from `var.images`.

## The composition pipeline

`composition.tf` resolves, per node: capabilities → union of selected profiles
→ variant resolution by the image's `cpu_vendor` → a union of provisions into
two sinks:

- **Schematic sink** — `customization.systemExtensions.officialExtensions`
  (image baseline UNION profile extensions), `customization.extraKernelArgs`
  (UNION of kernel args), plus the image's overlay.
- **Machine-config sink** — a generated per-node patch carrying
  `machine.kernel.modules` (grouped by name, parameters sorted),
  `machine.sysctls` (merged), and `machine.nodeLabels`.

The generated patch is concatenated **before** the node's own
`config_patches` (so a raw patch can still override — the documented escape
hatch) and before the base CNI patch, which stays strictly last.

### Content-hash dedup

Extensions and kernel args are sorted/deduplicated so the schematic YAML is
canonical, then hashed: `substr(sha256(yaml), 0, 16)`. Hash content is the
declared extensions + kernel args + overlay — **not** architecture, which keys
the installer instead. Distinct schematics are grouped by hash, so identical
nodes collapse onto one Image-Factory schematic; installers are keyed
`"<hash>:<arch>"`, so a schematic shared across architectures gets one
installer per arch pointing at the same schematic. Capability-order
independence is a tested property: two nodes listing the same capabilities in
reversed order hash identically.

## Label emission and anti-forgery

Two label families, with different provenance:

- `platform.io/hardware-capability.<name>` — the composite's `emits_label`,
  consumer-chosen but namespace-constrained by variable validation.
- `platform.io/hardware-feature.<atom>` — emitted **only** from a profile's
  base-controlled `provides`, one label per provided atom. A consumer cannot
  emit a reserved `hardware-feature.*` label through the typed interface.

Residual (documented in `variables.tf`): a raw per-node `config_patches`
string can still set `machine.nodeLabels` directly — the module does not parse
patch content. That forgery path is the downstream consumer-cluster Kyverno
boundary, the same residual class as the raw-patch SecureBoot/podSubnets
vectors.

## Plan-time guards

Cross-variable invariants are hard **plan-time errors** via `lifecycle`
preconditions on `terraform_data.composition_guards` (top-level `check` blocks
only warn). Tolerant `try()`/`contains()` locals keep invalid input from
raising a cryptic map-index error before the precondition prints its message.
The guarded invariants:

- undefined `node.image`, undefined capability id, undefined profile id;
- variant mismatch — a selected profile has `variants` but no entry for the
  image's `cpu_vendor`;
- **per-capability symmetry, both directions**: forward — a capability
  requires a provisioned atom its own profiles do not provide (label without
  provisioning); inverse — a profile provides an atom the capability omits
  from `requires_features` (provisioned but unlabeled). Checked per capability
  (including unused ones), not per node union, so two individually malformed
  capabilities cannot mask each other by compensating in the union;
- merge conflicts — same-name kernel modules with differing parameters,
  same-key sysctls with differing values, same-key kernel args with differing
  values (with a multi-value allowlist: `console`, `module_blacklist`,
  `initcall_blacklist`, `blacklist`).

## CI gates

The `hardware-features-check` job in `.github/workflows/gitops-validate.yml`
runs:

- `scripts/lint-hardware-features.sh` — validates the registry against
  `schemas/hardware-features.schema.json` via `check-jsonschema`.
- `scripts/check-provisioning-catalog-refs.sh` — asserts the load-bearing
  equivalence the composition guards rely on: the set of atoms any catalog
  profile `provides` equals the registry's
  `discovery_source: talos-machine-config` set, so a registry-only (or
  catalog-only) atom addition cannot silently defeat the symmetry guard. It
  also enforces kebab-case on every provided atom id, since the id is
  interpolated into a `platform.io/hardware-feature.<atom>` node label.

## Module tests

- `tofu/modules/talos-cluster/tests/composition.tftest.hcl` — plan-only
  regression suite (network: resolves the live Image Factory; run via
  `task tofu:test`, not part of the offline `task tofu:ci`). Covers schematic
  dedup and capability-order determinism, forward/inverse symmetry violations,
  the union-masking pair, variant mismatch, undefined image/capability, and
  rejection of a reserved `hardware-feature.*` `emits_label`.
- `tofu/modules/talos-cluster/tests/conflict-guards.tftest.hcl` — offline
  red-green binding for the module/sysctl/kernel-arg conflict guards, using a
  synthetic colliding catalog fixture that symlinks the real `composition.tf`
  (the shipped catalog never collides, and the catalog is module-local, so no
  `variables {}` input can trigger these guards).
