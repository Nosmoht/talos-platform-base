---
type: decision
title: "ADR: Capability profiles carry only their presence_predicate args — drop iommu=pt"
description: "Removes iommu=pt from the iommu provisioning profile: it is host-DMA tuning, not part of the iommu-enabled contract, and a base-owned profile karg costs the consumer a freedom it never agreed to."
status: accepted
id: base:capability-profile-predicate-only
timestamp: 2026-07-15
deciders:
  - platform-maintainer
consulted: []
informed: []
supersedes: []
superseded_by: []
related:
  - "[Node Capability Composition (the catalog this corrects)](./0009-node-capability-composition.md)"
  - "[Three-Layer Capability Architecture (the Layer-C atom vocabulary)](./0003-three-layer-capability-architecture.md)"
tags: [adr, capability, talos]
---

# ADR: Capability profiles carry only their presence_predicate args — drop iommu=pt

## Context and Problem Statement

The `iommu` provisioning profile in `tofu/modules/talos-cluster/profiles.tf`
carried two kernel args per vendor variant: `intel_iommu=on` (resp.
`amd_iommu=on`) **and** `iommu=pt`. The Layer-C atom the profile `provides`
— `iommu-enabled` in `platform-hardware-features.yaml` — names only the
first in its `presence_predicate`. `iommu=pt` was in the implementation but
not in the contract.

Two facts made that mismatch load-bearing rather than cosmetic:

1. **A profile karg is base-owned and consumer-unoverridable.** Kargs reach
   the schematic sink only from selected profiles — the module exposes no
   consumer kernel-arg input at all, so the ownership is total rather than
   merely guarded. Every arg a profile claims is therefore a key the
   consumer permanently loses — spent whether or not the capability needs it.
   (`karg_conflicts` is a profile-vs-profile collision guard on one node; it
   takes no consumer input. Issue #169 proposes a consumer karg path, and
   would be the change that turns this from "no path exists" into "a guard
   must exist" — see §Consequences.)
2. **`iommu=pt` is not a neutral default.** It changes the host's DMA
   translation policy (see §Validation for the verbatim kernel wording), a
   real security/performance trade-off the base was making silently on every
   consumer that selected the capability — for an atom that describes itself
   as "Required for **safe** PCI passthrough".

Git archaeology shows the pair was never decided. `iommu=pt` first entered
the repo in `59147a3` ("rewrite README for base vocabulary + add homelab
example") as *example* code, inside a `machine.install.extraKernelArgs`
patch — the very sink ADR 0009 later identified as a no-op under the Talos
v1.10+ UKI/systemd-boot default. It was carried verbatim into the profile
catalog 19 days later in `d49087b` (#135). No commit in the repo's history
takes a position on it.

## Decision Drivers

- Contract and implementation must agree: a profile that provisions more than
  its atom's `presence_predicate` makes the predicate a partial description of
  what the base actually does to a node.
- A base-owned karg is a freedom cost paid by every consumer of the
  capability. That cost is justified for the arg that *defines* the
  capability; it is not justified for host tuning.
- The substrate provisions capability; host policy is consumer policy
  (`AGENTS.md` §Repository Purpose routing rule).
- A silent security-posture change that no decision record covers is a defect
  regardless of whether the trade-off is a common one.

## Considered Options

1. **Keep `iommu=pt`, add it to the atom's `presence_predicate`** — resolve
   the mismatch by widening the contract instead of narrowing the profile.
2. **Remove `iommu=pt` from the profile** — narrow the profile to its
   predicate.
3. **Dissolve the `iommu` capability entirely** (remove all kargs and
   `provides`) — let consumers own the whole IOMMU story.

## Decision Outcome

Chosen option: **2 — remove `iommu=pt` from the profile**, because the
evidence places it outside the capability's definition, and narrowing the
profile restores the consumer's `iommu` key without weakening the label's
meaning or the vendor-resolution the profile exists to provide.

### Consequences

- Positive: the profile provisions exactly what `iommu-enabled` claims. The
  `iommu` key is free for consumer use, so `iommu=pt` becomes expressible as
  consumer policy once a consumer karg input exists (#169) — no override
  syntax needed, because nothing collides.
- Positive: the base no longer changes host DMA policy as an undeclared side
  effect of selecting a capability.
- Negative: **breaking for bare-metal consumers who relied on the implicit
  `iommu=pt`.** Their node's schematic content hash changes (new schematic id
  → new installer URL → re-image), and their host-owned devices revert from
  passthrough-by-default to **lazy DMA translation** — Talos builds
  `CONFIG_IOMMU_DEFAULT_DMA_LAZY=y` with `CONFIG_IOMMU_DEFAULT_PASSTHROUGH`
  unset (§Validation), so this is a real change, not a no-op. Nor can such a
  consumer restore the prior behavior in this tag: there is no consumer
  kernel-arg input, and the machine-config sink is a no-op for boot args
  under Talos v1.10+ — they must wait for #169. The isolation of devices
  actually passed through is unaffected either way (a `vfio-pci`-bound device
  is isolated by its own VFIO domain, not by the default domain type); the
  exposure is host-owned-device DMA throughput. That exposure is the reason
  to watch the first re-imaged node: host devices moving from identity-mapped
  to translated DMA is the class that surfaces DMAR faults on chassis with
  defective reserved-region (RMRR) reporting.
- Follow-up: #169 (consumer-supplied schematic `extra_kernel_args`) is the
  supported path to re-add `iommu=pt` as an explicit consumer choice. The
  cloud/ARM scoping of the capability itself is tracked separately.

## Pros and Cons of the Options

### Option 1 — widen the predicate

- Pro: no behavior change for existing consumers; the mismatch closes.
- Con: writes a tuning default into a detection contract. The label
  `iommu-enabled` would then assert a DMA policy, which is not what a
  consumer scheduling a passthrough workload is asking about.
- Con: the freedom cost stays — the consumer still cannot set the `iommu` key.
- Con: no Tier-1 evidence supports the pairing as a correctness requirement
  (§Validation); the strongest source found frames it as optional tuning.

### Option 2 — narrow the profile (chosen)

- Pro: contract == implementation, at the lowest possible altitude (one list
  element; no new mechanism).
- Pro: hands the `iommu` key back to the consumer, which is where the
  evidence says the decision belongs.
- Con: a breaking change requiring a re-image for affected bare-metal
  consumers.

### Option 3 — dissolve the capability

- Pro: honest about the capability being bare-metal-x86-only.
- Con: removes the node label with no replacement — `iommu-enabled` has
  `discovery_source: talos-machine-config` precisely because NFD cannot
  detect it, so nothing else can emit it.
- Con: loses the vendor resolution (`intel_iommu` vs `amd_iommu` from the
  image's `cpu_vendor`) and the profile's binding of karg, `vfio-pci` module,
  and label into one unit — which is ADR 0009's core value.
- Con: buys no freedom that opt-out does not already provide — the capability
  is opt-in, so a consumer wanting full control simply does not select it.

## Validation

**Primary-source evidence** (fetched from the kernel documentation, not from
a summary):

- `iommu=` is scoped `[X86,EARLY]` — x86-only.
- `iommu=pt` — "Use passththrough mode by default (Equivalent to
  `iommu.passthrough=1`)" (typo verbatim from the source).
- `iommu.passthrough=` — `[ARM64,X86,EARLY]` "Configure DMA to bypass the
  IOMMU by default. 0 - Use IOMMU translation for DMA. 1 - Bypass the IOMMU
  for DMA. unset - Use value of `CONFIG_IOMMU_DEFAULT_PASSTHROUGH`."

This establishes `iommu=pt` as a **default DMA-translation policy for
host-owned devices**, not a switch that enables PCI passthrough. Devices
bound to VFIO are isolated by the IOMMU either way.

**The Talos build default, looked up rather than assumed.** The kernel-doc
wording above makes the runtime effect conditional on
`CONFIG_IOMMU_DEFAULT_PASSTHROUGH`, so the removal is a no-op if Talos
already builds with it. It does not. `siderolabs/pkgs`
`kernel/build/config-amd64` carries:

```text
# CONFIG_IOMMU_DEFAULT_DMA_STRICT is not set
CONFIG_IOMMU_DEFAULT_DMA_LAZY=y
# CONFIG_IOMMU_DEFAULT_PASSTHROUGH is not set
```

Identical on `config-arm64`, and unchanged across the `v1.10.0`, `v1.11.0`
and `v1.12.0` tags plus `main` (kernel 6.18.38) — consistent with the
upstream `drivers/iommu/Kconfig` choice default (`IOMMU_DEFAULT_DMA_LAZY if
X86 || S390`), which Talos does not override. So `iommu=pt` was **not**
restating the build default: it moved host-owned devices from lazy DMA
translation to bypass. Its removal therefore has a real runtime effect —
host-owned devices return to translated DMA — and the trade-off named in
§Context is established rather than assumed. This also settles the
alternative that would have made this ADR pointless: had the value been `y`,
the change would force a re-image for a zero-behaviour delta.

**How we know this decision is wrong:** a Tier-1 Intel or AMD source
establishing `iommu=pt` as required for VT-d / AMD-Vi passthrough
correctness. No such source was found; the strongest pairing recommendation
located is Red Hat's ("if `intel_iommu=on` works, you can *try adding*
`iommu=pt`", with revert guidance) — Tier 2, and framed as tuning.

**Mechanical check:** `tofu/modules/talos-cluster/tests/composition.tftest.hcl`
asserts profile resolution and karg union; no test asserted the literal
`iommu=pt`, so its removal is behaviour-visible only through the schematic
content hash. A future CI cross-reference gate asserting *profile kargs ⊆
atom presence_predicate args* would make this class of drift mechanical
rather than reviewed — analogous to the existing provisioned-atom
cross-reference gate.

## Links

- Kernel command-line parameters — https://www.kernel.org/doc/html/latest/admin-guide/kernel-parameters.html
- `kernel-parameters.txt` (raw source, verified verbatim) — https://raw.githubusercontent.com/torvalds/linux/master/Documentation/admin-guide/kernel-parameters.txt
- LWN — Intel IOMMU Pass Through Support — https://lwn.net/Articles/329174/
- Red Hat Virtualization — Configuring a Host for PCI Passthrough — https://docs.redhat.com/en/documentation/red_hat_virtualization/4.1/html/installation_guide/appe-configuring_a_hypervisor_host_for_pci_passthrough
