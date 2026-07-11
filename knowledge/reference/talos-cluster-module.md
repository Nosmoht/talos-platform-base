---
type: reference
title: talos-cluster Module Interface
description: Typed variable and output contract of the tofu/modules/talos-cluster OpenTofu module, plus the invariants the module enforces in code.
tags: [opentofu, talos, module-interface, substrate]
timestamp: 2026-07-11
sources:
  - tofu/modules/talos-cluster/variables.tf
  - tofu/modules/talos-cluster/outputs.tf
  - tofu/modules/talos-cluster/versions.tf
  - tofu/modules/talos-cluster/main.tf
  - tofu/modules/talos-cluster/composition.tf
  - tofu/modules/talos-cluster/profiles.tf
  - tofu/modules/talos-cluster/examples/complete/main.tf
  - scripts/check-render-determinism.sh
---

# talos-cluster Module Interface

`tofu/modules/talos-cluster` is the sole Talos cluster-lifecycle path of the
base: it turns a set of PXE-booted Talos maintenance-mode nodes into a
bootstrapped Kubernetes cluster (PKI, per-node composed Image-Factory
installer, config apply, etcd bootstrap on the first controlplane, health
gate, kubeconfig/talosconfig). It is backend- and caller-agnostic — no
`terraform { backend ... }` block ships in the module; the caller supplies the
`provider "talos"` block and an **encrypted** state backend (machine secrets
land in state). Decision background:
[0006-opentofu-cluster-lifecycle](../decisions/0006-opentofu-cluster-lifecycle.md).

Hand-maintained per-variable/per-output tables live in
`tofu/modules/talos-cluster/README.md`; this page summarizes the groups and
the invariants instead of duplicating those tables. (The README carries no
`BEGIN_TF_DOCS` injection markers, so `task tofu:docs` does not regenerate
it — the tables are maintained by hand.)

## Provider and version constraints

From `tofu/modules/talos-cluster/versions.tf`:

- OpenTofu `>= 1.7.0`.
- `siderolabs/talos` `>= 0.7.0, < 1.0.0`.
- `hashicorp/helm` `>= 2.12, < 3.0.0` — used **only** for `data.helm_template`
  (local render of the ArgoCD/Cilium seeds); never `helm_release`.
- `hashicorp/local` `>= 2.4` and `hashicorp/null` `>= 3.2` — only for the
  ArgoCD-CRD `kubectl` server-side apply path (instantiated only when
  `deploy_argocd = true`).

## Variable groups

### Identity and versions

| Variable | Type | Default | Validation intent |
| --- | --- | --- | --- |
| `cluster_name` | `string` | required | lowercase RFC-1123 label (used in PKI CNs) |
| `cluster_endpoint` | `string` | required | must be an `https://` URL including port |
| `talos_version` | `string` | required | v-prefixed semver; machine-config **schema pin**, fixed at bootstrap |
| `talos_install_version` | `string` | `""` | empty (falls back to `talos_version`) or v-prefixed semver; the installer-image tag bumped for OS upgrades |
| `kubernetes_version` | `string` | required | v-prefixed semver |

The schema-pin/install-pin split is the Day-2 OS-upgrade pattern: bump
`talos_install_version` only; the consumer's upgrade task reads the resolved
installer URL from tfplan JSON (`installer_images`, `talos_install_version`
outputs) and rolls nodes with `talosctl upgrade` out-of-band — `tofu apply`
alone never re-images a node.

### Topology and capability composition

| Variable | Type | Default | Validation intent |
| --- | --- | --- | --- |
| `nodes` | `list(object)` | required | `hostname`, `ip`, `role`, `image` required; `hardware_capabilities` and `config_patches` optional. Guards: at least one controlplane; `role` in `controlplane\|worker`; hostnames unique; IPs unique |
| `images` | `map(object)` | required | at least one image; `architecture` in `amd64\|arm64` (default `amd64`); `cpu_vendor` in `intel\|amd\|arm` (required, no default); baseline `extensions`; optional SBC `overlay` |
| `hardware_capabilities` | `map(object)` | `{}` | `emits_label` must start with `platform.io/hardware-capability.` (the reserved `hardware-feature.*` namespace is emitted only from base-catalog `provides`) |

Roles are only `controlplane`/`worker`; hardware specialization is expressed
as the node's `image` plus a **set** of capabilities, composed per node in
`tofu/modules/talos-cluster/composition.tf` and content-hash-deduped into
distinct Image-Factory schematics. See
[capability-composition](../architecture/capability-composition.md) and
[0009-node-capability-composition](../decisions/0009-node-capability-composition.md).

### Machine-config patches

| Variable | Type | Default |
| --- | --- | --- |
| `config_patches` | `list(string)` | `[]` (all nodes) |
| `controlplane_config_patches` | `list(string)` | `[]` |
| `worker_config_patches` | `list(string)` | `[]` |

Caller patches carry all cluster identity (registry mirrors, install disk,
NTP, network) — the module ships none of its own. Per-node `config_patches`
apply after the module-generated capability patch, so a raw patch can still
override generated `machine.kernel.modules` / `sysctls` / `nodeLabels`.

### Cluster network (install-time-fixed)

| Variable | Type | Default | Validation intent |
| --- | --- | --- | --- |
| `pod_cidr` | `list(string)` | `["10.244.0.0/16"]` | at least one valid CIDR |
| `service_cidr` | `list(string)` | `["10.96.0.0/12"]` | at least one valid CIDR |
| `dual_stack` | `bool` | `false` | cross-field family guard, see invariants |
| `allow_scheduling_on_controlplanes` | `bool` | `false` | Talos `cluster.allowSchedulingOnControlPlanes` |

### Substrate delivery — Cilium

| Variable | Type | Default | Validation intent |
| --- | --- | --- | --- |
| `deploy_cilium` | `bool` | `true` | opt-out keeps the Talos-default CNI (Flannel) |
| `cilium_chart_version` | `string` | `"1.19.4"` | SEED knob, not an upgrade knob |
| `cilium_chart_repository` | `string` | `"https://helm.cilium.io"` | no digest pin — trust required |
| `cilium_namespace` | `string` | `"kube-system"` | Talos convention |
| `cilium_values_override` | `string` | `""` | Helm deep-merge on the shipped floor + computed values |
| `cilium_routing_mode` | `string` | `"tunnel"` | `tunnel\|native` |
| `cilium_native_routing_cidr` | `string` | `""` | empty derives from the first IPv4 `pod_cidr` entry |
| `cilium_kube_proxy_replacement` | `bool` | `true` | also sets Talos `cluster.proxy.disabled` |
| `cilium_mtu` | `number` | `0` | `0` = chart auto-detect |
| `cilium_encryption` | `object({type})` | `{ type = "none" }` | `none\|wireguard\|ipsec` |
| `cilium_ipsec_key` | `string` (sensitive) | `""` | empty or starts with a numeric key id; required by a plan-time precondition when `encryption.type = "ipsec"` |
| `cilium_gateway_api` | `bool` | `true` | Gateway API controller in the seed (Hard Constraint: Gateway API only) |
| `cilium_gateway_api_crds_url` | `string` | `""` | empty = CRDs via Day-1 GitOps (air-gap-safe); a URL opt-ins bootstrap seeding via `cluster.extraManifests` (a failed fetch crashloops bootstrap) |

### Substrate delivery — ArgoCD

| Variable | Type | Default | Validation intent |
| --- | --- | --- | --- |
| `deploy_argocd` | `bool` | `true` | ArgoCD is Layer-1 substrate |
| `sops_age_key` | `string` (sensitive) | `""` | plan-time precondition: must start with `AGE-SECRET-KEY-1` when `deploy_argocd = true` (ksops repoServer) |
| `argocd_namespace` | `string` | `"argocd"` | |
| `argocd_chart_version` | `string` | `"9.4.5"` | SEED knob, not an upgrade knob |
| `argocd_values_override` | `string` | `""` | Helm merge on the shipped slim values |
| `cluster_health_timeout` | `string` | `"10m"` | Go duration for the health gate |

## Outputs

`kubeconfig` and `talosconfig` are `sensitive` and gated on the
cluster-health data source — a consumer reading them blocks until the
cluster is genuinely online. `client_configuration` is `sensitive` but NOT
health-gated: it derives solely from `talos_machine_secrets` and is readable
before the cluster is up.

| Output | Sensitive | Purpose |
| --- | --- | --- |
| `kubeconfig` | yes | admin kubeconfig (raw YAML), health-gated |
| `talosconfig` | yes | talosctl client config, health-gated |
| `client_configuration` | yes | Talos CA + client cert/key for chaining |
| `cluster_health` | no | `"healthy (…)"` once etcd quorum + nodes Ready + apiserver reachable |
| `cluster_endpoint` | no | echoed input |
| `controlplane_ips` | no | talosconfig endpoints |
| `schematic_ids` | no | Image-Factory schematic ID per distinct content hash |
| `installer_images` | no | resolved non-SecureBoot installer URL per hostname (tfplan-JSON input for the consumer upgrade task) |
| `node_schematic_hashes` | no | per-node composed-schematic content hash (re-image blast-radius auditing) |
| `distinct_schematic_count` | no | schematic count after dedup |
| `talos_install_version` | no | effective installer version |
| `argocd_namespace_labels` | no | PSA floor + recommended labels the argocd namespace seed bakes |
| `cert_approver_namespace_labels` | no | PSA-restricted floor + labels of the cert-approver namespace seed |
| `cert_approver_seeded` | no | red-green binding: cert-approver seed wired into the controlplane patch list |
| `kubelet_serving_cert_rotation` | no | per-role booleans: rotation patch present in each role's patch list |
| `kubelet_rotation_setting` | no | decoded rotation patch — proves the mechanism is `machine.kubelet.extraConfig.serverTLSBootstrap`, not the deprecated flag |
| `cert_approver_approve_resource_names` | no | RBAC scope of the vendored approver's `approve` verb — must equal `["kubernetes.io/kubelet-serving"]` |
| `cert_approver_seed_missing_labels` | no | recommended-label gaps across the vendored seed manifest — must be empty |
| `controlplane_base_is_prefix_of_final` | no | asserts the sensitive argocd/cilium seeds are only appended after the non-sensitive base patch list |

The audit-shaped outputs exist as binding points for the composition
regression suite (`tofu/modules/talos-cluster/tests/composition.tftest.hcl`,
run via `task tofu:test` — network-bound, not part of `task tofu:ci`).

## Module-enforced invariants

- **Non-SecureBoot installer selection.** The module always selects
  `urls.installer` from `data.talos_image_factory_urls` — never
  `urls.installer_secureboot` — so the module itself cannot emit a SecureBoot
  installer. A plan-time precondition additionally rejects any caller
  `config_patches` string containing `-secureboot` (a substring heuristic;
  schematic-level or renamed SecureBoot images remain consumer-overlay
  responsibility). See
  [0011-substrate-hard-constraints](../decisions/0011-substrate-hard-constraints.md).
- **Authoritative `cni: none`.** When `deploy_cilium = true`, the module sets
  `cluster.network.cni.name = none` (plus `cluster.proxy.disabled` when
  kube-proxy replacement is on) after ALL caller patches in both the
  config-generation pass and the per-node apply pass (in the controlplane
  generation list a few module-owned patches follow, none of which touch
  `cluster.network.cni`), so no caller patch can silently resurrect Flannel.
  The documented opt-out is `deploy_cilium = false`, not a patch.
- **Render-determinism freeze.** `data.helm_template` renders are not
  byte-stable, so each seed render (ArgoCD, Cilium) is frozen in state via a
  `terraform_data` resource with `lifecycle { ignore_changes = [input] }`;
  deliberate re-seed requires `-replace`. The ArgoCD-CRD render (a Day-2
  kubectl convergence, not a create-only seed) additionally carries
  `triggers_replace` mirroring its render-affecting inputs. The static fence
  `scripts/check-render-determinism.sh` (wired as
  `task tofu:check:render-determinism`, part of `task tofu:ci`) fails CI if
  the decoupling regresses.
- **Empty-render refusal.** Plan-time postconditions reject an empty ArgoCD,
  Cilium, or CRD render rather than freezing an ArgoCD-less or CNI-less seed.
- **Kubelet serving-cert rotation default-on + cert-approver seed.** A
  base patch sets `machine.kubelet.extraConfig.serverTLSBootstrap = true` on
  all nodes (placed first, so a caller patch can opt out), and the vendored
  `tofu/modules/talos-cluster/manifests/cert-approver.yaml` is seeded
  unconditionally as a controlplane `inlineManifest` (namespace first, then
  the signer-scoped approver) to approve the resulting
  `kubernetes.io/kubelet-serving` CSRs. See
  [0013-kubelet-serving-cert-rotation](../decisions/0013-kubelet-serving-cert-rotation.md).
- **Composition guards (hard plan-time errors).** Preconditions on a
  `terraform_data` gate fail the plan on: undefined `node.image`, undefined
  capability, undefined provisioning profile, a profile with variants but no
  entry for the image's `cpu_vendor`, capability/profile symmetry violations
  in both directions, and same-name kernel-module / same-key sysctl /
  same-key kernel-arg conflicts between selected profiles.
- **Dual-stack family cross-check.** `dual_stack = true` requires both an
  IPv4 and an IPv6 entry in each of `pod_cidr`/`service_cidr`;
  `dual_stack = false` requires IPv4-only lists (v6-only single-stack is
  unsupported), enforced bidirectionally at plan time.
- **Stable bootstrap target.** etcd bootstrap and credential pulls are pinned
  to the lowest controlplane hostname, so reordering `nodes` after bootstrap
  cannot move the bootstrap node.
- **Health gate.** `tofu apply` blocks until etcd quorum, nodes Ready, and
  apiserver reachability hold (timeout `cluster_health_timeout`); only then
  are the ArgoCD CRDs applied and the credential outputs released.
- **ArgoCD CRDs via kubectl server-side.** The roughly 1.8 MB CRDs are too
  large for a Talos `inlineManifest`; they are applied by a `local-exec`
  `kubectl apply --server-side` after the health gate. Contract: every apply
  host must ship `kubectl`.

## Adoption and Day-2 boundaries

- **Fresh-PKI warning.** `talos_machine_secrets` generates new cluster PKI
  into state. A blind `tofu apply` against an already-running cluster would
  push mismatched PKI; adoption is supported only via `tofu import` of the
  existing secrets (and the bootstrap resource) **before** the first apply —
  runbook in `UPGRADING.md`. The imported secrets bundle must be the
  cluster's real current one, because the first post-import apply re-pushes
  the rendered machine config, which embeds that PKI.
- **Kubernetes upgrades are out-of-band.** The `siderolabs/talos` provider
  ships no Kubernetes-upgrade resource; bump `kubernetes_version` to keep the
  machine config in sync and run `talosctl upgrade-k8s --to <version>`
  against the cluster.
- **OS upgrades are rendered, not executed.** Bumping `talos_install_version`
  (or changing a node's composed schematic) re-renders `machine.install.image`
  via apply-config, but only the consumer-driven `talosctl upgrade` actually
  re-images nodes.

## Provisioning-profile catalog

`tofu/modules/talos-cluster/profiles.tf` is a module-local constant (not a
variable), so consumers can select profiles by id but cannot author or
redefine one. Catalog at this tag: `drbd` (provides `drbd-kernel-module`),
`iommu` (provides `iommu-enabled`; vendor-variant kernel args for
intel/amd), `nvidia-lts` (provides nothing — `nvidia-gpu` is NFD-detected;
bakes the open GPU kernel modules + container toolkit).

## Examples entry point

`tofu/modules/talos-cluster/examples/complete/` is the worked consumer root:
a thin `yamldecode` shim over a declarative `cluster.yaml`
(see [cluster-yaml](cluster-yaml.md)) mapping onto the module's typed
interface, with a mixed amd64 + arm64 topology (controlplanes, kubevirt
workers, a GPU worker, a Raspberry-Pi worker). It is a `tofu validate`/`plan`
fixture with RFC5737 documentation IPs and no state backend — not a runnable
apply. Secrets (`sops_age_key`, `cilium_ipsec_key`) enter via `TF_VAR_*`
variables declared in `tofu/modules/talos-cluster/examples/complete/variables.tf`;
`sops_age_key` deliberately has no default so a copied root cannot silently
apply a non-functional ksops key.
