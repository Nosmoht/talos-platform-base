# Talos library v0.6.0 — 5-axis cutover (MAJOR / breaking)

v0.6.0 is the coordinated breaking release that turns the v0.5.x 5-axis
preview into the only supported path. Every consumer `cluster.yaml`
needs migration. The detailed step-by-step migration lives in
[`UPGRADING.md` §`v0.6.0`](../UPGRADING.md); this file is the engineering
changelog plus the rationale per item.

## What's in this release

1. **Cluster identity field renames** — `api_vip` → `vip`; `gateway_vip`
   removed.
2. **NTP servers as a list** — `cluster.ntp_server` (string) →
   `cluster.ntp_servers` (array).
3. **Achse 4 cleanup** — `nvidia-gpu-node` removed from
   `hardware-platforms`. GPU servers are `intel-generic` x86-64 platforms
   carrying a PCIe card; GPU presence is captured on Axis 5
   (`gpu-nvidia` capability), not Axis 4.
4. **gVisor moved out of `hardware-capabilities`** — workload-runtime-class
   labels are not hardware predicates (ADR Three-Layer §D7). The
   `worker-gvisor.yaml` patch lives in `roles.<role>.patches[]` per the
   slot ladder in `talos/AGENTS.md §Patch slots — where things go`.
5. **`hardware_capabilities` underscore alias removed** — the v0.5.4
   grace-window alias is gone from the schema, `argv-print.sh`, and
   `validate-schematics.sh`. Use the canonical kebab-case
   `hardware-capabilities` everywhere.
6. **`hardware-capabilities[*].patches[].file` is now auto-composed** —
   previously declarative-only. `argv-print.sh` emits cap-patches as
   `--config-patch` after role-patches (later-wins per talosctl merge
   semantics). Watch for accidental duplication with `roles.<role>.patches[]`.
7. **Legacy `talos/Makefile` deleted** — consumers MUST include
   `$(BASE_DIR)/Makefile.lib`. The 439-LOC pattern-rule generator is gone.
8. **PNI policy name/behaviour cleanup** —
   `pni-capability-validation-audit` →
   `pni-capability-validation-enforce`; `pni-reserved-labels-audit` →
   `pni-reserved-labels-enforce`. Rule names, validation messages, and
   `validationFailureAction: Enforce` semantics are unchanged. Same
   mechanism as the v0.5.0 `pni-contract` rename.

## Per-item rationale

### 1. `api_vip` → `vip`, `gateway_vip` removed

A cluster has **exactly one** Kubernetes API VIP. The legacy `api_vip`
name implied there could be other VIPs at cluster-identity scope —
which is wrong. Gateway / LoadBalancer VIPs are not cluster-identity:
a cluster may host multiple Gateway-API `Gateway` objects, each with
its own LB IP, declared in the respective `Gateway` / `HTTPRoute`
manifests under `kubernetes/base/infrastructure/<gateway>/values.yaml`.
Removing `gateway_vip` from the base contract eliminates the
"one Gateway VIP per cluster" implicit constraint that v0.5.x carried.

### 2. NTP servers as a list

Talos `machine.time.servers` is natively an array. Pinning the contract
to a single NTP server is a SPOF: NTP outage → clock drift → etcd cert
validation failure → cluster outage. v0.6.0 widens the field to
`ntp_servers: [...]` (minItems 1; ≥2 recommended). Every element is
charset-validated against `^[A-Za-z0-9.:_-]{1,253}$` at `argv-print.sh`
to prevent YAML injection through the NTP slot.

### 3. `nvidia-gpu-node` removed from Axis 4

Axis 4 (`hardware-platforms`) names the CPU mainboard / chassis class:
`intel-generic`, `raspberry-pi-4`, future Ampere/Altra etc. A PCIe
GPU is **peripheral**, not platform. The `nvidia-gpu-node` entry
double-encoded GPU presence on both Axis 4 (platform identity) and
Axis 5 (capability) and forced two contracts to stay in sync.
v0.6.0 drops the Axis-4 entry; GPU nodes declare
`hardware-platform: intel-generic` and add `gpu-nvidia` to their
Axis-5 capability list.

### 4. gVisor moved out of `hardware-capabilities`

gVisor is a **workload-runtime-class** label
(`sandbox.atlas.dev/gvisor: "true"`), not a hardware predicate. The
[Three-Layer Capability ADR §D7](../docs/adr-three-layer-capability-architecture.md)
classifies workload-runtime-class labels as out-of-scope for Axes A/B/C;
the v0.5.x consumer mismatch (homelab cluster carried `gvisor` as an
Axis-5 capability) was a 5-axis schema-gap audit-finding (F12).

Resolution: `worker-gvisor.yaml` lives in `roles.<role>.patches[]` per
the slot ladder in `talos/AGENTS.md §Patch slots`. Role-uniform static
labels are a role concern, not a capability concern. The
`translate-legacy-cluster-yaml.sh` helper no longer emits a `gvisor`
entry in the rendered `hardware-capabilities` block.

### 5. `hardware_capabilities` underscore alias removed

Schema, `argv-print.sh`, and `validate-schematics.sh` now read only the
canonical kebab-case `hardware-capabilities` field on `node-spec`. The
v0.5.4 deprecation note (planned-removal: v0.6.0) is honoured. The
schema's `required` list now hard-includes `hardware-capabilities`;
underscore-only documents fail validation with:

```text
$.nodes[0]: 'hardware-capabilities' is a required property
```

### 6. `hardware-capabilities[*].patches[].file` auto-composed

In v0.5.x, capability `.patches[]` was declarative-only — listed in the
schema but never emitted into the per-node talosctl argv. Consumers
who wanted a capability's patch to apply on a node had to manually
include the patch file in `roles.<role>.patches[]`.

v0.6.0 auto-composes file-form entries: for every capability on a
node, `argv-print.sh` emits its `patches[].file` entries as
`--config-patch` after role-patches and before `nodes/<n>.yaml`.
Inline `{pointer, value}` entries remain declarative-only (auto-composition
of pointer-form is a separate concern; tracked for post-v0.6.0).

Cap-patches are emitted **after** role-patches, so a capability that
sets the same `machine.*` key as a role-patch wins (later
`--config-patch` overrides earlier in talosctl). Duplicate-file
detection across role+cap and inter-cap is intentionally not
implemented in `argv-print.sh`; the same patch listed in both a role
and a capability will be emitted twice (harmless when content is
identical; surfaced as a diagnostic by `validate-schematics`).

### 7. Legacy `talos/Makefile` deleted

The 439-LOC pattern-rule generator in `talos/Makefile` was the v0.5.x
dual-path artifact. With the 5-axis path now default, the dual-path is
gone. Consumers' `talos/Makefile` MUST include `$(BASE_DIR)/Makefile.lib`
(see `talos-homelab-cluster/talos/Makefile` for the reference pattern).

### 8. PNI policy name/behaviour cleanup

v0.5.0 (#40) renamed `pni-contract-audit` → `-enforce` to fix the
file-name/behaviour mismatch (`metadata.name` claimed `audit`,
`validationFailureAction` was `Enforce`). Two further policies missed
that pass: `pni-capability-validation-audit` and
`pni-reserved-labels-audit`. v0.6.0 renames both to `-enforce`. Same
mechanism as v0.5.0; consumer impact and migration are covered in
[`UPGRADING.md` §`v0.6.0` → "PNI policy renames"](../UPGRADING.md).

## Forward-looking: substrate-only base in v1.0.0

[`docs/adr-substrate-only-base.md`](../docs/adr-substrate-only-base.md)
(accepted 2026-05-27) reclassifies the platform-network-interface
(PNI) and the remaining 20 `kubernetes/base/infrastructure/`
components as **platform offerings**, not substrate. The repo is
substrate-only; PNI registry, Kyverno policies, and the capability
scripts move to a new `talos-platform-apps` repository in **v1.0.0**.

v0.6.0 still ships the PNI cleanup in this repo for consumer compatibility.
The substrate split lands **after** v0.6.0 and bumps the next OCI tag to
`v1.0.0` (MAJOR) when the move happens. Consumers who reference
`platform-network-interface/**` paths from this repo will need to
re-source from `talos-platform-apps` at the v1.0.0 cut — see the
ADR's §Migration plan for the six-phase sequencing.

## Verification before tag

- `make validate-gitops` passes against the in-repo `cluster.yaml.example`,
  `talos/test/cluster.yaml.example`, and all `talos/test/fixtures/valid-*`
  with no schema or schematic diagnostics.
- Each `talos/test/fixtures/invalid-*.yaml` continues to trigger its
  named diagnostic (regression coverage for the negative cases).
- `make validate-kyverno-policies` confirms the renamed PNI policies
  pass server-side validation.
- `make argv-print NODE=<n>` against the test fixture emits one
  ephemeral NTP patch followed by role-patches + cap-patches +
  `nodes/<n>.yaml` + install-image JSON-patch in that order.

## Why this was not bundled with v0.5.4

v0.5.4 was an emergency schema-hygiene release on a hot branch;
bundling the 5-axis cutover would have blocked the urgent fix on a
multi-week soak. v0.5.4 added the kebab-case alias **without** the
runtime cutover so consumers could migrate the schema-side first; the
runtime cutover (and the rest of v0.6.0) is the coordinated breaking
package.
