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
TAG=v2.0.0; OWNER=Nosmoht   # TAG = your target tag; OWNER is case-sensitive in the identity regexp below (must match the owner's exact GitHub casing)
cosign verify \
  --certificate-identity-regexp \
    "^https://github.com/${OWNER}/talos-platform-base/\.github/workflows/oci-publish\.yml@refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$" \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  ghcr.io/${OWNER}/talos-platform-base:${TAG}

# 2. (capability / PNI deprecation scanning moved to the talos-platform-apps
#     catalog as of v2.0.0 — run its scan against your manifests there, not
#     against the substrate base.)

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

## `v3.0.0` — go-task single runner + Makefile retired; kubelet serving-cert rotation default-on + cert-approver seed (MAJOR — dev-facing + consumer-facing)

**Type:** MAJOR (dev-facing). The `Makefile` is retired and go-task is the sole
runner — every former `make <target>` is now a namespaced `task <target>`. A
`Makefile` deprecation stub remains for one release cycle: any `make <target>`
prints the migration mapping and exits non-zero. There is **no consumer-runtime
impact** — the OCI artifact ships neither the Makefile nor the Taskfile, so this
affects only workstation / runbook / CI tooling, not the vendored module or the
rendered manifests. Decision:
[`docs/adr-0012-makefile-retirement.md`](docs/adr-0012-makefile-retirement.md).

**Migration — replace `make` with `task` in any runbook, script, or CI you own:**

| Retired `make` target | Replacement |
|---|---|
| `make validate-gitops` | `task gitops:validate` |
| `make render-component COMPONENT=<c>` | `task gitops:render-component COMPONENT=<c>` |
| `make render-all` | `task gitops:render-all` |
| `make verify-rendered` | `task gitops:verify-rendered` |
| `make argocd-bootstrap` | `task bootstrap:argocd` |
| `make argocd-password` | `task bootstrap:argocd-password` |
| `make init-cluster-yaml` | `task cluster:init-yaml` |
| `make oci-allowlist-check` | `task supply-chain:oci-allowlist` |
| `make mcp-install` / `mcp-verify` / `mcp-uninstall` | `task mcp:install` / `mcp:verify` / `mcp:uninstall` |
| `make install-pre-commit` / `verify-tools` | `task dev:install-pre-commit` / `dev:verify-tools` |

The pre-existing tofu tasks were also namespaced: `task ci` → `task tofu:ci`,
`task test` → `task tofu:test` (and `fmt` / `validate` / `lint` → `tofu:*`).
Run `devbox shell -- task --list` for the full set.

**Dropped (no replacement):**

- `make chart-pull` — for a new `chart.lock.yaml` digest, run
  `helm pull <chart> --repo <repo> --version <v> --destination .helm-cache`
  then `shasum -a 256 .helm-cache/<chart>-*.tgz`.
- `make grafana-dashboards-check` — it scanned a consumer-overlay path
  (`kubernetes/overlays/…`) absent in the substrate base.

**devbox:** `devbox.json` gains `yq-go`, `gettext`, and `ripgrep` (no `gnumake`)
so the folded `bootstrap:*` / `cluster:*` / `gitops:*` tasks run inside
`devbox shell`.

### Kubelet serving-cert rotation default-on + cert-approver seed (consumer action required)

**Type:** consumer-runtime breaking (folded into this MAJOR). Decision:
[`docs/adr-0013-kubelet-serving-cert-rotation.md`](docs/adr-0013-kubelet-serving-cert-rotation.md).

The module now enables `machine.kubelet.extraConfig.serverTLSBootstrap: true` on all
nodes (default-on) and seeds cert-approver as a controlplane `inlineManifest` (it was
a namespace-only stub before). On a **fresh** cluster this is automatic. On an
**already-bootstrapped** cluster adopting this tag:

1. `tofu apply` re-pushes machine config (reconciled) → rotation turns on → kubelets
   emit `kubernetes.io/kubelet-serving` CSRs. But Talos `inlineManifests` are
   **create-only** — the cert-approver seed does **not** land on a cluster that
   already bootstrapped. Without the approver those CSRs sit `Pending` and
   metrics-server / `kubectl logs|exec|top` degrade.
2. **Before/at the bump, ensure the approver runs.** The vendored seed manifest
   (`tofu/modules/talos-cluster/manifests/cert-approver.yaml`) has its `Namespace`
   document stripped (the namespace is seeded separately by the module), so do NOT
   `kubectl apply` it directly on an existing cluster — it would land the
   ServiceAccount/Deployment into a non-existent namespace. Instead use ONE of:
   - keep your existing upstream cert-approver ArgoCD Application until the seed
     path is confirmed on the next fresh node; OR
   - apply the **complete upstream** manifest once (it is self-contained — namespace
     included): `kubectl apply -f https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/v0.11.0/deploy/standalone-install.yaml`.
3. **Resolve double-management** if you already wired the upstream approver via your
   own Application: the base seed and your Application would both own the
   cluster-scoped ClusterRole/ClusterRoleBinding. Resolve it **without pruning the
   running approver** — the create-only seed does NOT re-create it on an
   already-bootstrapped cluster (step 1), so a cascading delete of your Application
   would leave `serverTLSBootstrap` on with NO approver and kubelet-serving CSRs stuck
   `Pending`. **Orphan** the resources instead: remove the
   `resources-finalizer.argocd.argoproj.io` finalizer from your Application (and/or set
   `spec.syncPolicy.automated.prune: false`) *before* deleting it, so ArgoCD leaves the
   live cert-approver in place rather than pruning it. The seed becomes the owner only
   when a control-plane node is next (re-)bootstrapped and receives the inlineManifest —
   server-side apply then reconciles the identical objects, so there is no lasting
   two-writer conflict once the Application is gone. Do NOT rely on the seed to recreate
   a pruned approver on existing nodes.
4. **Verify:** `kubectl get csr` shows `kubernetes.io/kubelet-serving` CSRs
   `Approved,Issued` on controlplane AND worker nodes; metrics-server works without
   `--kubelet-insecure-tls`.

**Opt-out** (rare): add `- machine: { kubelet: { extraConfig: { serverTLSBootstrap: false } } }`
to `config_patches` in your `cluster.yaml` (the base patch is placed FIRST, so the
override wins; confirm on the homelab apply since the merge is server-side).

**Approver upgrades on a running cluster are manual** (create-only seed):
`kubectl -n kubelet-serving-cert-approver set image deployment/kubelet-serving-cert-approver cert-approver=<new-image@digest>`,
or re-apply the upstream manifest. A plain `tofu apply` does NOT update an
already-seeded approver.

**Availability note (single replica):** the approver runs `replicas: 1` and (absent
worker scheduling) on a control-plane node. A rolling OS upgrade / CP-node reboot
(`talosctl upgrade`) evicts it; any kubelet serving-cert rotation during that window
stalls until it reschedules and is Ready. Time mass-rotation-affecting upgrades
accordingly, and wire a consumer alert on the count of `Pending`
`kubernetes.io/kubelet-serving` CSRs (the approver exposes metrics on port 9090).

**Security — REQUIRED for multi-tenant / untrusted-node clusters (not optional
hardening):** the approver (alex1989hu) validates node identity (CN ==
`system:node:<name>`, Org `system:nodes`) but does NOT bind requested DNS/IP SANs to
the requesting node — a compromised node could mint a serving cert for another node's
SANs (MITM). Rotation is now default-on cluster-wide, so every cluster ships this
residual until you add it. **Add a consumer-cluster Kyverno policy enforcing
SAN-to-node** for `kubernetes.io/kubelet-serving` CSRs (the base ships no admission
policy — ADR-0004 puts the `kubelet-serving` policy surface in consumer clusters).
See adr-0013 §Security.

---

## `v2.0.0` — node-capability composition + substrate-only ablation (MAJOR / breaking)

**Type:** MAJOR. v2.0.0 bundles **two** breaking changes:

1. **Node-capability composition** — the `tofu/modules/talos-cluster`
   interface changes (detailed below).
2. **Substrate-only ablation** — the base is reduced to substrate
   (Talos + Cilium + ArgoCD + `cert-approver`); the entire PNI /
   capability-network contract and every non-substrate component move to
   the [`talos-platform-apps`](https://github.com/devobagmbh/talos-platform-apps)
   catalog (see [`docs/adr-0004-substrate-only-base.md`](docs/adr-0004-substrate-only-base.md)).
   See [§Substrate-only ablation](#substrate-only-ablation-consumer-action-required)
   below for the consumer action.

v1.0.0 shipped earlier **without** the ablation; the ablation lands in
v2.0.0.

### Node-capability composition (consumer action required)

The `tofu/modules/talos-cluster` interface changes: the monolithic per-node
`class` is replaced by a composable `image` + a SET of `hardware_capabilities`.
Boot kernel args now bake into the Image Factory schematic
(`customization.extraKernelArgs`) — the v1.10+ UKI correctness fix; the old
`machine.install.extraKernelArgs` path was a silent no-op. See
[`docs/adr-0009-node-capability-composition.md`](docs/adr-0009-node-capability-composition.md)
(the §Migration table is authoritative).

- **`var.classes` and `node.class` are removed.** Map your `cluster.yaml`:
  - `class.architecture` / `class.overlay` → `images.<id>.architecture` / `.overlay`
  - `class.extensions` **baseline** (microcode/firmware/tooling/runtime — for
    example `intel-ucode`/`i915`/`nvme-cli`/`gvisor`) → `images.<id>.extensions`
  - `class.extensions` **capability-specific** (drbd, nvidia) → a base
    provisioning profile selected via a `hardware_capabilities` composite
  - `class.config_patches` IOMMU/boot kernel args → the `iommu` profile (now
    actually bakes); other `class.config_patches` → role / node `config_patches`
  - `node.class` → `node.image` + `node.hardware_capabilities: [...]`
- **`installer_images` output is now keyed by node hostname** (was per class).
  Update any consumer `talos:upgrade:cluster` task that reads it from tfplan JSON.
- **One-time re-image is expected** for nodes whose kernel-arg provisioning is
  corrected (for example, the kubevirt IOMMU that was a no-op now actually
  applies). A node whose *effective provisioning is unchanged* (for example, a
  plain controlplane
  whose baseline extensions are preserved in its `image`) keeps a stable
  schematic hash and does **not** re-image. Verify with `tofu plan` before the
  MAJOR-tag adoption; the re-image rolls out via the usual out-of-band
  `talosctl upgrade`. To see *exactly which* nodes re-image, diff
  `tofu output node_schematic_hashes` before and after — every changed hash is a
  re-imaging node (see the module README "Re-image blast-radius").

A worked migration is the `tofu/modules/talos-cluster/examples/complete/`
fixture (its `kubevirt` IOMMU is the live no-op this fixes) and the module README
Usage block.

### Substrate-only ablation (consumer action required)

As of v2.0.0 the base is **substrate-only**:
`kubernetes/base/infrastructure/` ships only `argocd/` and
`cert-approver/`. The PNI / capability-network contract and every
non-substrate component (observability, storage, the capability registry
and its policies, the application-supporting services) have **dissolved
out of the base** — the PNI surface is now realized by apps-CI Conftest
plus consumer-cluster Kyverno, and the components live as independently
versioned, signed OCI artifacts in the
[`talos-platform-apps`](https://github.com/devobagmbh/talos-platform-apps)
catalog. Decision + sequencing:
[`docs/adr-0004-substrate-only-base.md`](docs/adr-0004-substrate-only-base.md).

Consumer action:

- **Re-source non-substrate components from `talos-platform-apps`.** Any
  consumer that referenced `kubernetes/base/infrastructure/<comp>/` paths
  for a non-substrate component (anything other than `argocd/` /
  `cert-approver/`) must now pull that component from the apps catalog by
  the OCI artifact it needs.
- **Move PNI / capability-network enforcement to your cluster.** The
  reserved-label, capability-registry, and CCNP machinery the base used
  to ship is gone; adopt the corresponding Conftest + Kyverno from the
  apps catalog and run them in your own CI / cluster.
- **ArgoCD cert-manager Certificate is now opt-in (Helm-value default change).**
  `argocd` no longer renders a `cert-manager.io/v1 Certificate` by default
  (`server.certificate.enabled: false`), so the substrate floor carries no
  cert-manager dependency. The substrate argocd-server already runs with
  `server.insecure=true` — it serves plaintext at the pod; terminate TLS at your
  gateway / ingress. A consumer that relied on the base-rendered
  `argocd-server-tls` cert re-enables `server.certificate` in a values overlay and
  provides the `vault-internal` `ClusterIssuer` (cert-manager comes from the apps
  catalog); to have the pod itself serve TLS, also set `server.insecure=false`.
- **Layer-C node-capability work stays in the base.**
  `docs/platform-hardware-features.yaml`,
  `docs/adr-0009-node-capability-composition.md`,
  `docs/adr-0003-three-layer-capability-architecture.md`, and the
  `tofu/modules/talos-cluster` provisioning catalog are substrate and
  remain here — no consumer move needed for those.

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

- **Layer-A capability-index validation in CI.** v0.5.0 added a set of
  capability-index lint/render scripts and a CI job that enforced the
  two-layer capability-architecture invariant. *Historical only:* this
  Layer-A capability surface dissolved out of the substrate in v2.0.0
  (see [§Substrate-only ablation](#substrate-only-ablation-consumer-action-required)) —
  the scripts and job no longer exist in the base, and the concern moved
  to [`talos-platform-apps`](https://github.com/devobagmbh/talos-platform-apps).
- **Per-component READMEs.** Each `kubernetes/base/infrastructure/<comp>/`
  directory shipped a README with Purpose / Chart / capabilities /
  Helm-value overrides / Upgrade gotchas. *Historical only:* with the
  v2.0.0 ablation only `argocd/` and `cert-approver/` remain in the base;
  the non-substrate component READMEs travelled to the apps catalog.

### Validation steps after upgrade

1. `task gitops:validate` in consumer repo passes.
2. `kubectl get clusterpolicy pni-contract-enforce` returns one
   resource with `ADMISSION=true BACKGROUND=true READY=True`.
3. `kubectl get clusterpolicy pni-contract-audit` returns NotFound.
4. `kubectl get policyreport -A -l policy.kyverno.io/policy-name=pni-contract-enforce`
   returns reports keyed on the new name.

---

## `v0.6.0` (forthcoming) — 5-axis cutover (MAJOR / breaking)

> **Superseded by the OpenTofu cluster-lifecycle cutover** (see the section
> below). The 5-axis `cluster.yaml` schema this checklist migrates *to* has
> itself been removed — the entire `talos/Makefile.lib` + 5-axis generator is
> gone. This section is retained for historical context only; consumers
> migrate per the OpenTofu cutover instead.

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
   name: example-cluster
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
 - name: node-a
-  hardware-capabilities: [gvisor-sandbox, drbd-storage, kubevirt-networking]
+  hardware-capabilities: [drbd-storage, kubevirt-networking]
```

gVisor is a **workload-runtime-class** label
(`platform.io/gvisor: "true"`), not a hardware predicate (ADR
Three-Layer §D7). Role-uniform static labels belong on roles, not on
Axis 5. The correct slot for this concern is documented in
`talos/AGENTS.md §"Patch slots — where things go"`.

#### 5. Rename `hardware_capabilities` (underscore) → `hardware-capabilities` (kebab)

```diff
 - name: node-a
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

See a consumer cluster repo for the reference pattern.

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
task gitops:validate    # consumer-side
kubectl get clusterpolicy pni-capability-validation-enforce \
                         pni-reserved-labels-enforce
# Both should return one resource each with ADMISSION=true BACKGROUND=true READY=True
kubectl get clusterpolicy pni-capability-validation-audit pni-reserved-labels-audit
# Both should return NotFound
```

### Why not bundle the substrate split into v0.6.0

`docs/adr-0004-substrate-only-base.md` (accepted 2026-05-27) reclassifies
the platform-network-interface, Kyverno, observability stack, and the
further `kubernetes/base/infrastructure/` components as platform
**offerings**, not substrate. They moved to the separate
[`talos-platform-apps`](https://github.com/devobagmbh/talos-platform-apps)
catalog **as of v2.0.0** — not in v0.6.0, and not in v1.0.0 (which
shipped without the ablation).

Rationale: v0.6.0 was already in the consumer-cluster preparation
pipeline when the substrate-only ADR landed. Bundling the substrate
split into v0.6.0 would have invalidated that preparation; sequencing
it later preserved consumer planning at the cost of touching the
PNI cleanup work twice (here in v0.6.0, then again at the v2.0.0
ablation). See the ADR's §Release sequencing and §Migration plan.

Consumers who reference `platform-network-interface/**` paths from
this repo re-source from `talos-platform-apps` at the v2.0.0 cut — see
[§Substrate-only ablation](#substrate-only-ablation-consumer-action-required).

---

## `v0.7.0` (2026-06-02) — OpenTofu cluster-lifecycle cutover (MAJOR / breaking)

**Type:** MAJOR. The Talos cluster lifecycle moves from the removed
`talos/Makefile.lib` + 5-axis `cluster.yaml` generator to the OpenTofu module
`tofu/modules/talos-cluster`. Rationale + consequences:
[`docs/adr-0006-opentofu-cluster-lifecycle.md`](docs/adr-0006-opentofu-cluster-lifecycle.md).

**Breaking?** Yes. Consumers stop generating Talos configs with
`make -C talos gen-configs` and instead author an OpenTofu root that calls the
module.

### Migration checklist

1. **Stop vendoring the `talos/` make path.** It no longer exists in the base.
   `make -C talos gen-configs`, `argv-print.sh`, `validate-schematics.sh`,
   `Makefile.lib`, and the 5-axis `cluster.schema.json` are gone.
2. **Slim your `cluster.yaml`.** Keep only the ArgoCD-bootstrap identity:
   `cluster.{name,overlay,target_revision}` and `repo.url`. Remove the Talos
   sections (`roles`, `architectures`, `infrastructure-platforms`,
   `hardware-platforms`, `hardware-capabilities`, `nodes`, `cluster.vip`,
   `cluster.ntp_servers`, `kubeconfig`). `task bootstrap:argocd` still reads the
   slim file.
3. **Author an OpenTofu root** in your consumer repo that calls the module:

   ```hcl
   module "cluster" {
     source = "git::https://github.com/Nosmoht/talos-platform-base.git//tofu/modules/talos-cluster?ref=<tag>"
     # cluster_name / talos_version / kubernetes_version / cluster_endpoint
     # nodes = [{ hostname, ip, role, class, config_patches? }, ...]
     # classes = { standard = { architecture, extensions, overlay?, config_patches } , ... }
     # config_patches = [...]  # NTP, registry mirrors, install disk
   }
   ```

   Map your old `cluster.yaml` axes onto module inputs: per-node `role` →
   `controlplane`/`worker` only; GPU/Pi/storage specialisations → a node
   `class`; extension sets → `classes[class].extensions`; ARM/Pi → `class`
   with `architecture = "arm64"` + an `overlay`; capability/kubevirt patches →
   `classes[class].config_patches`; per-node NIC → `node.config_patches`; NTP
   (formerly `cluster.ntp_servers`) → a `config_patches` entry. The
   [`examples/complete/`](tofu/modules/talos-cluster/examples/complete) fixture is
   a full mixed amd64+arm64 worked example.
4. **Supply provider + encrypted backend** in your root (state holds
   `machine_secrets`). See the module README for an example `versions.tf`.
5. **Validate**: `task tofu:ci` (or `tofu fmt -check` + `tofu validate` + `tflint`).
6. **⚠️ Already-running cluster?** The module *generates* fresh PKI by default,
   so a naive `tofu apply` against a live cluster would regenerate PKI and
   re-bootstrap etcd — destroying it. Do **not** apply against a running cluster
   without first following the import-based adoption runbook in
   [§Adopting an already-running cluster](#adopting-an-already-running-cluster-no-re-bootstrap)
   below. Greenfield clusters need no special steps.

### Adopting an already-running cluster (no re-bootstrap)

> **Status: validated against a live, already-bootstrapped cluster** (issue #97
> AC#2). Proven on a real 9-node cluster (amd64 controlplanes + amd64 workers +
> a GPU worker + an arm64 Raspberry-Pi worker) with the **v0.7.0** module,
> provider **siderolabs/talos v0.11.0**, OpenTofu **v1.12.1**: import + `tofu
> plan` reported `0 to destroy` — neither identity resource is replaced, so no
> PKI roll and no re-bootstrap. Still **dry-run it on your own cluster** (import
> and plan only, never apply blind) before trusting it against production —
> provider defaults and your version pins shape the exact plan (see step 5).

Use this when the cluster is **already running** and its PKI lives in a
`talosctl gen secrets` bundle (for example a SOPS-encrypted `talos/secrets.yaml`
from the old Makefile path), and you want to move it onto the module **without
regenerating PKI or re-bootstrapping etcd**. The module needs no code change —
adoption is a `tofu import` of the two identity-bearing resources before the
first apply.

**Why two imports make it safe** — they neutralise the two cluster-destroying
actions a fresh apply would take:

| A fresh `tofu apply` would… | The import that prevents it |
|---|---|
| generate fresh `machine_secrets` → every node certificate invalid, cluster unreachable | import `talos_machine_secrets.this` ← your existing `secrets.yaml` |
| call `MachineBootstrap` on already-bootstrapped etcd | import `talos_machine_bootstrap.this` (marks done in state; no RPC) |

**Critical precondition — the imported bundle must be the cluster's *real,
current* PKI.** `talos_machine_configuration_apply` is **not importable** (the
provider exposes no import for it), so after the two imports the per-node apply
resources plan as *to be created* and the first apply re-pushes the
module-rendered machine config to the running nodes. That rendered config
**embeds the cluster PKI** (`data.talos_machine_configuration` injects
`machine_secrets`). So the apply does **not** reconcile "config only" — it
re-asserts the **same** PKI you imported. If the imported `secrets.yaml` is the
node's actual current bundle, that is a no-op for PKI and at most a **rolling
reboot** if non-PKI config fields differ (never a wipe). If the bundle is
**stale, partial, or from another cluster**, the apply pushes *mismatched* PKI
and can sever node↔etcd / kubelet↔apiserver trust on the live controlplane. Use
the exact, current bundle; verify the diff in step 5 before applying.

**Runbook** (adjust `module.cluster` to your module instance name):

```bash
# 0. Author your OpenTofu root (steps 1–4 above) so module + provider + an
#    ENCRYPTED state backend are wired. Init, but do NOT apply yet.
#    - `tofu import` of machine_secrets sets talos_version to the PROVIDER
#      DEFAULT (observed v1.3 with provider v0.11.0) — it is NOT read from the
#      bundle. So if your var.talos_version is pinned higher, expect an in-place
#      `update` (talos_version: v1.3 -> <your pin>) on machine_secrets. That is
#      a metadata reconcile and preserves the PKI bytes (verified, sha256
#      identical); it is NOT a replacement. See step 5 — only a destroy/create
#      (replacement) is the stop condition.
tofu init

# 0a. CONFIRM state encryption is active BEFORE importing — the import writes the
#     full PKI into Tofu state. With an unencrypted/local backend you would leak
#     plaintext PKI to disk. Verify your encryption {} block / backend is wired
#     (e.g. inspect the backend config; a freshly-written state file must not
#     contain readable cert PEM blocks).

# 1. Decrypt your existing Talos secrets bundle to a TEMP plaintext file.
#    Prefer a RAM-backed dir so no plaintext ever hits persistent storage:
#      Linux:  TMPDIR=/dev/shm
#      macOS:  create a RAM disk, or accept that secure single-file erase is
#              unreliable on APFS/SSD (see "Plaintext hygiene" below).
umask 077
SECRETS_PLAINTEXT="$(mktemp "${TMPDIR:-/tmp}/talos-secrets-XXXXXX.yaml")"
sops -d talos/secrets.yaml > "$SECRETS_PLAINTEXT"

# 2. Import the existing PKI — no fresh generation. Import ID is the file path.
tofu import 'module.cluster.talos_machine_secrets.this' "$SECRETS_PLAINTEXT"

# 3. Import bootstrap state — no re-bootstrap RPC. The id is arbitrary.
#    BOTH imports must succeed. If this one fails or is skipped while step 2
#    succeeded, the next apply will run MachineBootstrap on live etcd. Verify:
#      tofu state list | grep -E 'talos_machine_(secrets|bootstrap)\.this'
#    must list BOTH before you proceed.
tofu import 'module.cluster.talos_machine_bootstrap.this' adopted

# 4. Remove the plaintext (see "Plaintext hygiene" — on SSD/COW this is best
#    effort; rotation is the real remedy if the workstation is untrusted).
rm -f "$SECRETS_PLAINTEXT"

# 5. PROOF the adoption neither regenerated PKI nor scheduled a re-bootstrap.
#    Use -refresh=false so the plan reflects imported state, not a live re-read.
tofu plan -refresh=false
#    PRIMARY GATE — the plan summary MUST end with "0 to destroy":
#        Plan: <N> to add, <M> to change, 0 to destroy.
#      `0 to destroy` == no resource is REPLACED == no PKI roll, no re-bootstrap.
#      Any non-zero destroy count is a STOP — investigate before applying.
#    EXPECTED "to change" (in-place update, NOT replacement — both are safe):
#      * module.cluster.talos_machine_secrets.this    -> update
#        (talos_version: v1.3 import-default -> your pin; PKI bytes preserved.
#         The computed machine_secrets/client_configuration show "known after
#         apply" as a CONSEQUENCE of that metadata change — not a regen.)
#      * module.cluster.talos_machine_bootstrap.this  -> update  (no re-bootstrap)
#    EXPECTED "to add" (not importable / recomputed; none re-bootstrap or roll PKI):
#      * module.cluster.talos_image_factory_schematic.per_class[*]  (factory
#        compute, no cluster contact)
#      * module.cluster.talos_machine_configuration_apply.this["<host>"]  (on a
#        real apply, pushes config — review the rendered diff vs the running
#        nodes first; a no-op if it matches, else a rolling reboot)
#      * module.cluster.talos_cluster_kubeconfig.this  (pulls a kubeconfig from
#        the first controlplane — a read RPC, harmless on a healthy cluster)
#    Anything with a destroy, or a create/change OUTSIDE this set, is a STOP.

# 6. Apply only once the plan shows "0 to destroy" and matches the above.
tofu apply
```

**Plaintext hygiene.** The import reads a *plaintext* file (the provider has no
native SOPS support). Minimise exposure: `umask 077`, and decrypt into a
RAM-backed location (`/dev/shm` on Linux; a RAM disk on macOS) so the plaintext
never reaches persistent storage. Note that `shred`/`rm -P` do **not** reliably
erase a single file on SSD or copy-on-write filesystems (APFS, Btrfs, ZFS) and
`shred` is absent on stock macOS — do not rely on overwrite-delete for
assurance. If the workstation is untrusted or the plaintext may have been
swapped/snapshotted, the real remedy is to **rotate the Talos secrets**, not to
trust an in-place erase. Never commit or persist the plaintext.

**Prove it on your own cluster first.** This was validated against one live
cluster (status note above), but provider defaults and your version pins shape
the exact plan — dry-run it yourself before trusting it against production.
Two reproducible harness scripts live in the module's
[`test/`](tofu/modules/talos-cluster/test/README.md):

- `pki-reconcile-microtest.sh` — self-contained (no cluster); proves the
  `talos_version: v1.3 -> <pin>` reconcile preserves the `machine_secrets` bytes.
- `run-adoption-proof.sh` — drives the import + `tofu plan` against an isolated
  copy of your root (never your real backend) and asserts `0 to destroy`.

Run both, and confirm step 5 shows no `machine_secrets`/`machine_bootstrap`
replacement, before adopting any real cluster.

---

## Pending sunsets

Capability deprecations and their sunset schedule are no longer a
substrate-base concern. The capabilities and the PNI / capability-network
contract that defined them dissolved out of the base in v2.0.0 (see
[§Substrate-only ablation](#substrate-only-ablation-consumer-action-required)).

Capability deprecation scanning and the per-capability replacement guidance
(for example the former `storage-csi` → `block-storage-replicated` /
`block-storage-local` split, or `monitoring-scrape-provider` folding into
`monitoring-scrape`) now live in the
[`talos-platform-apps`](https://github.com/devobagmbh/talos-platform-apps)
catalog. Run that catalog's deprecation scan against your manifests, and
follow its replacement guidance, before adopting a catalog artifact that
fires a sunset.

---

## Template for future MAJOR/MINOR sections

Releases are now tagged automatically by semantic-release (see
[`docs/release-automation.md`](docs/release-automation.md)), which does **not**
write this file. Migration sections here are curated by a maintainer
retroactively — typically alongside the release for a MAJOR/MINOR with consumer
impact — using the format below:

```markdown
### `vX.Y.Z` (YYYY-MM-DD) — <one-line summary>

**Type:** MAJOR | MINOR | PATCH
**Breaking?** yes | no

#### Breaking changes (consumer action required)

- <bullet> — for example "Substrate Helm value `argocd.server.replicas`
  default changed. Patch your consumer overlay." or "`tofu/modules/talos-cluster`
  input `<var>` renamed."

#### Validation steps after upgrade

1. `task gitops:validate` in consumer repo
2. `task tofu:ci` (for `tofu/` interface changes)
3. `scripts/lint-hardware-features.sh` (for Layer-C hardware-feature changes)
```

---

## See also

- [`CHANGELOG.md`](CHANGELOG.md) — per-release notes
- [`SECURITY.md`](SECURITY.md) — supported versions
- [`docs/oci-artifact-verification.md`](docs/oci-artifact-verification.md) — verify before vendoring
- [`docs/adr-0004-substrate-only-base.md`](docs/adr-0004-substrate-only-base.md) — substrate-only scope; PNI dissolution
- [`docs/adr-0009-node-capability-composition.md`](docs/adr-0009-node-capability-composition.md) — node-capability composition migration
