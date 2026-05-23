<!--
GENERATED FILE — DO NOT EDIT BY HAND.
Source of truth: docs/platform-hardware-features.yaml
Regenerate: scripts/render-capability-index.sh
-->

# Platform Hardware Features Registry (Layer C)

**Schema version:** `1`

This document is generated from `docs/platform-hardware-features.yaml`.
It is the **Layer C** catalogue defined in
[ADR — Three-Layer Capability Architecture](./adr-three-layer-capability-architecture.md):
the static catalog of atomic hardware features that nodes in this
platform may carry. Layer A entries reference these via
`requires_hardware_features[]`; consumer-side `cluster.yaml` composite
capabilities reference them via `requires_features[]` under the
`hardware-capabilities:` block.

---

## Summary

| ID | Discovery Source | Node Label Key |
|---|---|---|
| [`nvidia-gpu`](#nvidia-gpu) | `nfd` | `feature.node.kubernetes.io/pci-10de.present` |
| [`vt-x-or-amd-v`](#vt-x-or-amd-v) | `nfd` | `feature.node.kubernetes.io/cpu-cpuid.VMX` |
| [`kvm-kernel-module`](#kvm-kernel-module) | `nfd` | `feature.node.kubernetes.io/kernel-module.kvm` |
| [`drbd-kernel-module`](#drbd-kernel-module) | `talos-machine-config` | `platform.io/hardware-feature.drbd-kernel-module` |
| [`local-nvme-block-device`](#local-nvme-block-device) | `nfd` | `feature.node.kubernetes.io/storage-nonrotationaldisk` |
| [`iommu-enabled`](#iommu-enabled) | `talos-machine-config` | `platform.io/hardware-feature.iommu-enabled` |
| [`ebpf-capable-kernel`](#ebpf-capable-kernel) | `nfd` | `feature.node.kubernetes.io/kernel-version.major` |

---

## Features

### `nvidia-gpu`

**NVIDIA GPU presence** · discovery-source `nfd` · authoritative label `feature.node.kubernetes.io/pci-10de.present`

The node has at least one NVIDIA-vendor GPU (PCI vendor 0x10de)
physically present and accessible to the kernel. Does NOT assert
driver readiness, MIG configuration, or CUDA capability — those are
separate predicates.

**Presence predicate:**

NFD's pci-source detects PCI vendor 10de on the node and emits the
`feature.node.kubernetes.io/pci-10de.present=true` label.

**Alternative label keys:**

- `platform.io/hardware-feature.nvidia-gpu`
- `nvidia.com/gpu.present`

**References:**

- <https://kubernetes-sigs.github.io/node-feature-discovery/master/usage/features.html#pci>
- <https://github.com/NVIDIA/k8s-device-plugin>

### `vt-x-or-amd-v`

**x86 virtualization extensions present and BIOS-enabled** · discovery-source `nfd` · authoritative label `feature.node.kubernetes.io/cpu-cpuid.VMX`

The CPU exposes Intel VT-x (VMX) OR AMD-V (SVM) instruction-set
extensions to the kernel. Required for hardware-accelerated
virtualization (KubeVirt VMs, kata-containers, gVisor with
KVM platform). Presence is BIOS-controlled; a chip may support
VT-x while the BIOS keeps it disabled.

**Presence predicate:**

NFD's cpu-source reports the VMX (Intel) or SVM (AMD) CPUID feature.
Either label being present satisfies the predicate; consumers should
match the OR of both. See `alt_label_keys`.

**Alternative label keys:**

- `feature.node.kubernetes.io/cpu-cpuid.SVM`
- `platform.io/hardware-feature.vt-x-or-amd-v`

**References:**

- <https://kubernetes-sigs.github.io/node-feature-discovery/master/usage/features.html#cpu>

### `kvm-kernel-module`

**KVM kernel module loaded** · discovery-source `nfd` · authoritative label `feature.node.kubernetes.io/kernel-module.kvm`

The `kvm` kernel module (plus the vendor sub-module `kvm_intel` or
`kvm_amd`) is loaded on the node. Implies a `/dev/kvm` character
device that KubeVirt / kata-containers / gVisor-KVM can open. Does
NOT assert hardware virtualization extensions are enabled — see
`vt-x-or-amd-v` for that.

**Presence predicate:**

NFD's kernel-module source reports `kvm` loaded; configurable in
Talos via `machine.kernel.modules` or matched at boot when the
kernel auto-loads on VMX/SVM-capable hardware.

**Alternative label keys:**

- `platform.io/hardware-feature.kvm-kernel-module`

**References:**

- <https://kubernetes-sigs.github.io/node-feature-discovery/master/usage/features.html#kernel>
- <https://www.talos.dev/v1.7/reference/configuration/v1alpha1/config/#Config.machine.kernel>

### `drbd-kernel-module`

**DRBD kernel module loaded** · discovery-source `talos-machine-config` · authoritative label `platform.io/hardware-feature.drbd-kernel-module`

The `drbd` kernel module is loaded on the node. Required for
LINSTOR / Piraeus replicated block-storage workloads. Talos
packages DRBD as a system extension; nodes must select the
drbd-bearing schematic to satisfy this predicate.

**Presence predicate:**

Talos machine config declares the drbd extension in the schematic
AND `machine.nodeLabels` carries
`platform.io/hardware-feature.drbd-kernel-module=true`. NFD's
kernel-module source can also detect this; `alt_label_keys` lists
the NFD equivalent.

**Alternative label keys:**

- `feature.node.kubernetes.io/kernel-module.drbd`

**References:**

- <https://github.com/siderolabs/extensions/tree/main/storage/drbd>
- <https://linbit.com/drbd/>

### `local-nvme-block-device`

**Local NVMe block device attached** · discovery-source `nfd` · authoritative label `feature.node.kubernetes.io/storage-nonrotationaldisk`

The node has at least one locally-attached NVMe block device
(`/dev/nvme*`). Required for capabilities backed by node-local
high-IOPS storage (LINSTOR storage pools, local-path-provisioner
hot tiers, KubeVirt ephemeral disks). Does NOT assert capacity,
partition layout, or filesystem state.

**Presence predicate:**

NFD's storage-source detects at least one non-rotational
(`/sys/block/*/queue/rotational == 0`) block device on the node.
The label does not distinguish NVMe from SATA SSD; consumers
requiring NVMe-specific characteristics should additionally match
the platform-set
`platform.io/hardware-feature.local-nvme-block-device` Layer-C
label declared by Talos `machine.nodeLabels`.

**Alternative label keys:**

- `platform.io/hardware-feature.local-nvme-block-device`

**References:**

- <https://kubernetes-sigs.github.io/node-feature-discovery/master/usage/features.html#storage>

### `iommu-enabled`

**IOMMU enabled in BIOS and kernel** · discovery-source `talos-machine-config` · authoritative label `platform.io/hardware-feature.iommu-enabled`

The IOMMU (Intel VT-d or AMD-Vi) is enabled in BIOS AND the
kernel was booted with `intel_iommu=on` (or `amd_iommu=on`).
Required for safe PCI passthrough (GPU passthrough in KubeVirt,
SR-IOV NIC isolation). NFD does not have a dedicated source for
this predicate; presence is asserted by Talos kernel-cmdline
configuration plus BIOS state, both of which are out of NFD's
observation scope.

**Presence predicate:**

Talos machine config carries `intel_iommu=on` (or `amd_iommu=on`)
in `machine.install.extraKernelArgs` AND the BIOS has IOMMU
enabled. The platform.io label is the consumer's assertion that
both conditions hold; there is no upstream NFD label that asserts
the BIOS half of the predicate.

**References:**

- <https://docs.kernel.org/x86/intel-iommu.html>
- <https://www.talos.dev/v1.7/reference/configuration/v1alpha1/config/#Config.machine.install>

### `ebpf-capable-kernel`

**Kernel supports eBPF (≥ Linux 5.10)** · discovery-source `nfd` · authoritative label `feature.node.kubernetes.io/kernel-version.major`

The running kernel version is at least 5.10, which is the floor
that Cilium 1.16+ assumes for eBPF feature support
(BPF_F_TEST_RUN_ON_CPU, BTF embedded in vmlinuz, bpf_link API).
Talos node images all satisfy this on supported releases; the
predicate exists to make the requirement explicit for any future
LTS-kernel constraint debugging.

**Presence predicate:**

NFD's kernel-source reports kernel `version.major >= 5` AND
`version.minor >= 10`, OR `version.major >= 6`. Consumers
typically match a derived label rather than this raw one; the
Layer-C `platform.io/hardware-feature.ebpf-capable-kernel`
alternative key carries the derived assertion.

**Alternative label keys:**

- `platform.io/hardware-feature.ebpf-capable-kernel`

**References:**

- <https://kubernetes-sigs.github.io/node-feature-discovery/master/usage/features.html#kernel>
- <https://docs.cilium.io/en/stable/operations/system_requirements/>
