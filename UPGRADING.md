# Upgrade Guide

For consumer-cluster repos vendoring `talos-platform-base` via OCI.

## How to use this file

- Per-release notes live in [`CHANGELOG.md`](CHANGELOG.md).
- This file documents **cumulative migration steps** for each MAJOR
  bump and any MINOR that requires a manual action.
- Read every section between the version you currently pin and the
  version you want to adopt. Apply in order.
- Always verify the new artifact (cosign + provenance) before vendoring
  — see [`docs/oci-artifact-verification.md`](docs/oci-artifact-verification.md).

## Upgrade workflow (every version)

```bash
# 1. Verify
TAG=v0.2.0; OWNER=nosmoht
cosign verify \
  --certificate-identity-regexp \
    "^https://github.com/${OWNER}/talos-platform-base/\.github/workflows/oci-publish\.yml@refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$" \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  ghcr.io/${OWNER}/talos-platform-base:${TAG}

# 2. Scan your manifests against the NEW registry for deprecated caps
oras pull "ghcr.io/${OWNER}/talos-platform-base:${TAG}" --output /tmp/base-${TAG}
/tmp/base-${TAG}/scripts/capability-deprecation-scan.sh kubernetes/

# 3. Render diff between current and target
kubectl kustomize --enable-helm vendor/base/kubernetes/base/infrastructure/ \
  > /tmp/before.yaml
echo "${TAG}" > .base-version
rm -rf vendor/base && oras pull "ghcr.io/${OWNER}/talos-platform-base:${TAG}" --output vendor/base
kubectl kustomize --enable-helm vendor/base/kubernetes/base/infrastructure/ \
  > /tmp/after.yaml
diff -u /tmp/before.yaml /tmp/after.yaml | less

# 4. Apply consumer-overlay patches for any MAJOR-listed breaking change below.
# 5. Commit, open PR, let ArgoCD reconcile after merge.
```

---

## Pre-`v0.2.0` MINOR releases

### `v0.1.0` (2026-03-XX) — initial public release

Baseline. No upgrade path; cleanroom install.

Capabilities present:

- `monitoring-scrape`, `hpa-metrics`, `tls-issuance`, `gateway-backend`,
  `external-gateway-routes`, `gpu-runtime`, `internet-egress`,
  `controlplane-egress`, `storage-csi`,
  `vault-secrets`, `cnpg-postgres`, `redis-managed`, `rabbitmq-managed`,
  `kafka-managed`, `s3-object`, `admission-webhook-provider`,
  `monitoring-scrape-provider`, `logging-ship`.

`storage-csi` and `monitoring-scrape-provider` are deprecated from day
one in v0.1.0 (see below).

---

## `v0.5.0` — 2026-05-18 — PNI policy rename + cluster-agnostic refactor + Layer-A validation + per-component READMEs

**Type:** MINOR (consumer-visible breaking name change in a Kubernetes
resource name; spec semantics unchanged)
**Breaking?** yes, for any artifact that references the renamed
`pni-contract-audit` ClusterPolicy by its `metadata.name`. No other
consumer-side action is required for the rest of the v0.5.0 surface
(documentation, validation scripts, READMEs — all internal to the
base; the OCI artifact remains the same shape).

### Note on prior git tags

Git tags `v0.2.0`, `v0.3.0`, `v0.4.0` exist in the repository and
have corresponding OCI artifacts on `ghcr.io`, but were not published
as GitHub Releases. They are usable as pinning targets but are
considered pre-release internal markers; v0.5.0 is the first GitHub
Release after v0.1.0.

### Breaking changes (consumer action required)

- `ClusterPolicy/pni-contract-audit` is renamed to
  `ClusterPolicy/pni-contract-enforce`. The new name matches both the
  filename (`kyverno-clusterpolicy-pni-contract-enforce.yaml`) and the
  policy's behaviour (`spec.validationFailureAction: Enforce`). Rule
  names (`require-interface-version`, `require-network-profile`) and
  validation messages are unchanged.
- Consumers must update any of the following that reference the old
  name:
  - PolicyReport queries / alerts (for example Grafana dashboards filtering
    on `policy="pni-contract-audit"`)
  - `metadata.labels` or `metadata.annotations` that name the policy
  - `argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource` or
    similar resource selectors keyed by the old name
  - Documentation links / cookbook snippets

### Migration on a live cluster

PolicyReports keyed on the old `policy="pni-contract-audit"` will be
GC'd by Kyverno when the renamed policy is applied (Kyverno emits a
new PolicyReport for the new resource UID). Brief gap in
PolicyReport continuity during the cutover — expected.

```bash
# Before merging the v0.5.0 bump:
kubectl get clusterpolicy pni-contract-audit -o yaml > /tmp/pre-rename.yaml

# After merging + ArgoCD reconcile:
kubectl get clusterpolicy pni-contract-enforce -o yaml | diff /tmp/pre-rename.yaml -
# Expected diff: metadata.name only, plus new UID / resourceVersion
```

### Why the rename

The policy was authored as fail-closed enforcement
(`validationFailureAction: Enforce`) but its `metadata.name` carried
an `-audit` suffix from a prior refactor. The mismatch caused two
class-of-error incidents during consumer onboarding (operators
assuming "audit" meant non-blocking, then surprised when admission
denied namespace creation). The rename aligns name, filename, and
behaviour. No spec change.

### New non-breaking surface

- **Layer-A capability-index validation in CI.** The base now ships
  three scripts (`scripts/lint-capability-index.sh`,
  `check-capability-index-refs.sh`, `render-capability-index.sh`) and
  a `capability-index-check` CI job that enforce the Two-Layer
  Capability Architecture invariant. Consumer repos that re-render
  the base inside their own CI will see the new job; no consumer
  manifests are affected.
- **Per-component READMEs.** Each `kubernetes/base/infrastructure/<comp>/`
  directory now ships a README with Purpose / Chart / PNI capabilities /
  Helm-value overrides / Upgrade gotchas. Recommended reading before
  deciding which base components to deploy and which Helm-value
  defaults to override in your consumer overlay.

### Validation steps after upgrade

1. `make validate-gitops` in consumer repo passes.
2. `kubectl get clusterpolicy pni-contract-enforce` returns one
   resource with `ADMISSION=true BACKGROUND=true READY=True`.
3. `kubectl get clusterpolicy pni-contract-audit` returns NotFound.
4. `kubectl get policyreport -A -l policy.kyverno.io/policy-name=pni-contract-enforce`
   returns reports keyed on the new name.

---

## `v0.6.0` (forthcoming) — 5-axis cutover (MAJOR / breaking)

**Type:** MAJOR. Every consumer `cluster.yaml` needs migration plus,
for live clusters, two ClusterPolicy renames.
**Breaking?** yes — coordinated package of seven `cluster.yaml`-level
changes plus the v0.5.0-style PNI policy cleanup. Engineering rationale
per item lives in
[`talos/RELEASE-NOTES-v0.6.0.md`](talos/RELEASE-NOTES-v0.6.0.md); this
section is the consumer migration recipe.

### Migration checklist

Apply in this order. Steps 1–7 edit your `cluster.yaml`; step 8 is the
ClusterPolicy GitOps drift; step 9 verifies.

#### 1. Rename `cluster.api_vip` → `cluster.vip`; drop `gateway_vip`

```diff
 cluster:
   name: homelab
-  api_vip: <api-vip>
-  gateway_vip: <gateway-vip>
+  vip: <api-vip>
   network: <cluster-cidr>
   gateway: <default-gw>
```

A cluster has exactly one Kubernetes API VIP. Gateway / LoadBalancer
VIPs are not cluster-identity — they belong with the respective
`Gateway` / `HTTPRoute` manifests under
`kubernetes/base/infrastructure/<gateway>/values.yaml`. If you carried
`gateway_vip` as a single value, move it to the cluster's Gateway
manifest. If you have multiple Gateway VIPs, this field never matched
them anyway.

#### 2. Rename `cluster.ntp_server` (string) → `cluster.ntp_servers` (array)

```diff
 cluster:
-  ntp_server: <primary-ntp>
+  ntp_servers:
+    - <primary-ntp>
+    - <fallback-ntp>     # ≥2 servers recommended for redundancy
```

Talos `machine.time.servers` is natively an array. Single-NTP is a SPOF
that propagates to etcd cert validation failure on outage. Each element
is charset-validated against `^[A-Za-z0-9.:_-]{1,253}$` to prevent YAML
injection through the NTP slot.

#### 3. Remove `hardware-platforms.nvidia-gpu-node`; GPU nodes use `intel-generic`

```diff
 hardware-platforms:
   intel-generic:
     vendor: Intel
     model: "Generic x86-64 server / NUC"
-
-  nvidia-gpu-node:
-    vendor: NVIDIA
-    model: "x86-64 server with NVIDIA PCIe GPU"

   raspberry-pi-4:
     vendor: Raspberry Pi Foundation
     model: Raspberry Pi 4 Model B
```

And on every GPU node:

```diff
 - name: node-gpu-01
   role: worker
   arch: amd64
   infrastructure-platform: metal
-  hardware-platform: nvidia-gpu-node
+  hardware-platform: intel-generic
   hardware-capabilities: [gpu-nvidia]
```

A PCIe GPU is peripheral, not platform. GPU presence already lives on
Axis 5 as the `gpu-nvidia` capability; the Axis-4 entry was a
duplicate contract.

#### 4. Move gVisor out of `hardware-capabilities` into role-patches

```diff
 hardware-capabilities:
-  gvisor-sandbox:
-    description: "Run untrusted workloads in gVisor sandbox"
-    patches:
-      - file: patches/worker-gvisor.yaml

   drbd-storage:
     description: "DRBD-based replicated block storage (LINSTOR)"
```

Add `patches/worker-gvisor.yaml` to the relevant role's `patches[]`:

```diff
 roles:
   worker:
     description: "Kubernetes worker node"
     patches:
       - patches/common.yaml
+      - patches/worker-gvisor.yaml
```

And strip the capability from every node that listed it:

```diff
 - name: node-04
-  hardware-capabilities: [gvisor-sandbox, drbd-storage, kubevirt-networking]
+  hardware-capabilities: [drbd-storage, kubevirt-networking]
```

gVisor is a **workload-runtime-class** label
(`sandbox.atlas.dev/gvisor: "true"`), not a hardware predicate (ADR
Three-Layer §D7). Role-uniform static labels belong on roles, not on
Axis 5. The correct slot for this concern is documented in
`talos/AGENTS.md §"Patch slots — where things go"`.

#### 5. Rename `hardware_capabilities` (underscore) → `hardware-capabilities` (kebab)

```diff
 - name: node-04
   role: worker
-  hardware_capabilities:
+  hardware-capabilities:
     - drbd-storage
```

The v0.5.4 grace-window underscore alias is removed in v0.6.0.
The schema, `argv-print.sh`, and `validate-schematics.sh` now read
only kebab-case. Underscore-only `cluster.yaml` documents fail
schema validation with:

```text
$.nodes[0]: 'hardware-capabilities' is a required property
```

#### 6. Replace legacy `talos/Makefile` with `Makefile.lib` include

The 439-LOC pattern-rule generator at `talos/Makefile` is deleted from
base. Consumer-side `talos/Makefile` MUST include `Makefile.lib` from
the vendored base:

```makefile
ENV ?= ../cluster.yaml
SCHEMATIC_CACHE ?= .schematic-cache.yaml
BASE_DIR ?= ../vendor/base/talos
ifneq ($(wildcard $(BASE_DIR)/Makefile.lib),)
include $(BASE_DIR)/Makefile.lib
else
$(error Base library not found at $(BASE_DIR)/Makefile.lib. Run 'make pull-base-oci' from repo root.)
endif
```

See the homelab consumer's `talos/Makefile` for the reference pattern.

#### 7. Audit role/cap patch duplication (cap-patches now auto-composed)

`hardware-capabilities[*].patches[].file` entries were declarative-only
in v0.5.x — listed in the schema but ignored by `argv-print.sh`. In
v0.6.0 they are auto-composed into the per-node talosctl argv as
`--config-patch` after role-patches.

This means a patch listed in both `roles.<role>.patches[]` AND a
capability's `patches[].file` is emitted **twice**. For identical
content this is harmless (talosctl merge is idempotent); for content
that diverges between the two paths, behaviour is now
last-`--config-patch`-wins (cap overrides role).

Action: grep your `cluster.yaml` for each patch file. If it appears in
both a role's `patches[]` AND a capability's `patches[].file`, pick
one source. Convention: hardware-predicate patches live on the
capability, role-uniform patches live on the role.

#### 8. PNI policy renames (live-cluster GitOps drift)

Two ClusterPolicy renames inherit the v0.5.0 `pni-contract-audit` →
`-enforce` mechanism:

| Old `metadata.name` | `spec.validationFailureAction` | New `metadata.name` |
|---|---|---|
| `pni-capability-validation-audit` | `Enforce` | `pni-capability-validation-enforce` |
| `pni-reserved-labels-audit` | `Enforce` | `pni-reserved-labels-enforce` |

File names already matched the behaviour; only `metadata.name` is
renamed. Rule names, validation messages, and
`validationFailureAction: Enforce` are unchanged.

Update any of the following that reference the old names:

- PolicyReport queries / alerts (Grafana dashboards filtering on
  `policy="pni-capability-validation-audit"` etc.)
- `metadata.labels` / `metadata.annotations` that name either policy
- ArgoCD `sync-options` resource selectors keyed by the old names
- Documentation links / cookbook snippets

On the live cluster, Kyverno GCs the old PolicyReports keyed on the
renamed resource UID and emits fresh ones for the new name. Brief gap
in PolicyReport continuity during cutover — expected.

```bash
# Before the v0.6.0 ArgoCD reconcile:
kubectl get clusterpolicy pni-capability-validation-audit -o yaml > /tmp/pre-cap-rename.yaml
kubectl get clusterpolicy pni-reserved-labels-audit -o yaml > /tmp/pre-rlbl-rename.yaml

# After reconcile:
kubectl get clusterpolicy pni-capability-validation-enforce -o yaml \
  | diff /tmp/pre-cap-rename.yaml -
# Expected diff: metadata.name only, plus new UID / resourceVersion
```

#### 9. Validate the migrated `cluster.yaml`

```bash
# Schema validation
check-jsonschema --schemafile vendor/base/talos/schemas/cluster.schema.json \
  --default-filetype yaml cluster.yaml

# Schematics + Layer-C cross-refs + capability resolution
make -C talos validate-schematics ENV=../cluster.yaml

# Per-node argv-print spot-check
make -C talos argv-print NODE=<node-name> ENV=../cluster.yaml
```

Live-cluster checks (post-reconcile):

```bash
make validate-gitops    # consumer-side
kubectl get clusterpolicy pni-capability-validation-enforce \
                         pni-reserved-labels-enforce
# Both should return one resource each with ADMISSION=true BACKGROUND=true READY=True
kubectl get clusterpolicy pni-capability-validation-audit pni-reserved-labels-audit
# Both should return NotFound
```

### Why not bundle the substrate split into v0.6.0

`docs/adr-substrate-only-base.md` (accepted 2026-05-27) reclassifies
the platform-network-interface, Kyverno, observability stack, and
17 further `kubernetes/base/infrastructure/` components as platform
**offerings**, not substrate. They move to a separate
`talos-platform-apps` repository in **v1.0.0** — not in v0.6.0.

Rationale: v0.6.0 was already in the consumer-cluster preparation
pipeline when the substrate-only ADR landed. Bundling the substrate
split into v0.6.0 would have invalidated that preparation; sequencing
it to v1.0.0 preserves consumer planning at the cost of touching the
PNI cleanup work twice (here in v0.6.0, then again at the v1.0.0
move). See the ADR's §Release sequencing and §Migration plan.

Consumers who reference `platform-network-interface/**` paths from
this repo will need to re-source from `talos-platform-apps` at the
v1.0.0 cut. The v0.6.0 PNI cleanup is forward-compatible with that
move — the renamed `-enforce` ClusterPolicies travel as-is.

---

## Pending sunsets

These deprecations are scheduled to remove via PR F (alias removal),
which auto-fires when the sunset date passes. PR F bumps the next OCI
tag's **MAJOR** version.

| Capability | Status | Sunset | Replacement |
|---|---|---|---|
| `storage-csi` | deprecated | 2026-11-13 | `block-storage-replicated`, `block-storage-local` |
| `monitoring-scrape-provider` | deprecated | 2026-08-13 | `monitoring-scrape` (folded) |

### Action for consumers

Before the sunset date:

1. Run `scripts/capability-deprecation-scan.sh kubernetes/` in your
   consumer repo CI. Failing the scan means you reference a
   deprecated capability.
2. Migrate `consume.storage-csi` to one of the split capabilities.
   Read [`docs/capability-reference.md`](docs/capability-reference.md)
   §`storage-csi` for the `disambiguation` guide on which split to
   choose.
3. Migrate `consume.monitoring-scrape-provider` to plain
   `consume.monitoring-scrape`.
4. Commit and merge in your consumer repo *before* you adopt the
   PR-F-bearing MAJOR tag.

---

## Template for future MAJOR/MINOR sections

When a new release ships, add a section in the format below:

```markdown
### `vX.Y.Z` (YYYY-MM-DD) — <one-line summary>

**Type:** MAJOR | MINOR | PATCH
**Breaking?** yes | no

#### Breaking changes (consumer action required)

- <bullet> — for example "Helm value `loki.write.s3.endpoint` renamed to
  `loki.write.objectStorage.endpoint`. Patch your consumer overlay."

#### New capabilities

- `<cap-id>` — see capability reference

#### Removed capabilities / sunsets fired

- `<cap-id>` — sunset reached, alias removed

#### Validation steps after upgrade

1. `make validate-gitops` in consumer repo
2. `kubectl get policyreport -A` in live cluster — expect no new
   PNI advisories
```

---

## See also

- [`CHANGELOG.md`](CHANGELOG.md) — per-release notes
- [`SECURITY.md`](SECURITY.md) — supported versions
- [`docs/oci-artifact-verification.md`](docs/oci-artifact-verification.md) — verify before vendoring
- [`docs/capability-architecture.md`](docs/capability-architecture.md) §"Backwards compatibility"
