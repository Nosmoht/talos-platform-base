# Module `talos-cluster`

Turns a set of PXE-booted Talos **maintenance-mode** nodes into a bootstrapped
Kubernetes cluster, and returns the admin `kubeconfig` + `talosconfig`.

This is the substrate base's **only** Talos cluster-lifecycle path (it replaced
the former `talos/Makefile.lib` + 5-axis `cluster.yaml` generator — see
[`knowledge/decisions/0006-opentofu-cluster-lifecycle.md`](../../../knowledge/decisions/0006-opentofu-cluster-lifecycle.md)).
The module is **backend- and caller-agnostic**: it contains no
`terraform { backend ... }` block. A consumer cluster repo pulls the base as an
OCI artifact, supplies the `provider "talos"` block + an **encrypted** state
backend, and calls the module directly with a `tofu apply` from a workstation.
No higher-level orchestrator is required.

## Scope

In scope:

- Generate cluster PKI / machine secrets.
- Render controlplane + worker machine configs (k8s/Talos version + caller patches).
- Resolve a per-node Image-Factory installer image by composing the node's base `image` (architecture + CPU vendor + baseline extensions + optional SBC overlay) with its `hardware_capabilities` (extensions + boot kernel args), content-hash-deduped so identical nodes share one schematic/installer.
- Apply config to each node, bootstrap etcd on the first controlplane.
- **Wait until the cluster is healthy** (etcd quorum, nodes Ready, apiserver reachable) before returning.
- **Deliver Cilium** as the CNI: disable the Talos default CNI (`cni.name: none`) + kube-proxy, then bake a locally-rendered Cilium chart into the controlplane `cluster.inlineManifests` as a bootstrap seed (Layer-1 substrate) — opt-out via `deploy_cilium = false`. So a fresh cluster comes up on Cilium, **not Flannel**.
- **Deliver ArgoCD** as a Talos `cluster.inlineManifest` (Layer-1 substrate, C4 layer model) — opt-out via `deploy_argocd = false`.
- Output `kubeconfig` and `talosconfig`.

Out of scope (caller / elsewhere):

- Hardware provisioning + PXE boot (DHCP `next-server`, iPXE).
- Cluster identity (node IPs, endpoint, NTP, install disk, registry mirrors) → caller via variables/patches.
- Day-2 platform components (cert-manager, …), **Cilium steady-state** (Hubble export, L2/BGP announcements — Cilium inlineManifests are create-only seeds), and **ArgoCD steady-state** (RBAC, OIDC, TLS cert, app-of-apps) → ArgoCD GitOps self-management. The module only seeds the *bootstrap* Cilium + ArgoCD installs.
- **Adopting an already-running cluster** — see the warning below.

Precondition: every node in `var.nodes` is reachable on the Talos API port,
i.e. already booted into Talos maintenance mode.

> ⚠️ **Already-running cluster (PKI adoption).** This module *generates* fresh
> `talos_machine_secrets` into Tofu state, so a naive `tofu apply` against a
> cluster that is **already bootstrapped** (its PKI living elsewhere, e.g. a
> SOPS `secrets.yaml` from the old Makefile path) would roll new PKI and
> re-bootstrap etcd — destroying it. Adoption **is** supported, but only via a
> `tofu import` of the existing secrets + bootstrap state **before** the first
> apply — never apply blind. Full runbook:
> [`UPGRADING.md` §Adopting an already-running cluster](../../../UPGRADING.md#adopting-an-already-running-cluster-no-re-bootstrap).
> The no-replacement proof must still be observed on a real adopted cluster
> (issue #97).

## What's in scope

| Phase | Module-managed |
|---|---|
| Day-1: cluster PKI | `talos_machine_secrets` |
| Day-1: machine config (per role) | `data.talos_machine_configuration` |
| Day-1: per-node installer image (content-hash deduped) | `talos_image_factory_extensions_versions` → `talos_image_factory_schematic` → `talos_image_factory_urls` (one schematic per distinct extensions+kernel-args+overlay; one installer per `(schematic-hash, architecture)`) |
| Day-1: apply config to each node | `talos_machine_configuration_apply` (hostname + install.image + module-generated capability patch [`machine.kernel.modules`/`sysctls`/`nodeLabels`] + node patches) |
| Day-1: etcd bootstrap | `talos_machine_bootstrap` (first controlplane only) |
| Day-1: kubeconfig + talosconfig | `talos_cluster_kubeconfig` + `data.talos_client_configuration` |
| Day-1: wait for healthy cluster | `data.talos_cluster_health` (blocks `apply` until etcd quorum + nodes Ready + apiserver reachable; gates the credential outputs) |
| Day-1: CNI + Cilium bootstrap | base machine config sets `cluster.network.cni.name: none` + `cluster.proxy.disabled: true` + pod/service subnets; `data.helm_template.cilium` (floor `helm/cilium-values.yaml` + typed `cilium_*` inputs + `cilium_values_override`) → controlplane `cluster.inlineManifests` seed (+ `cilium-ipsec-keys` Secret when `cilium_encryption.type = ipsec`). Opt-out: `deploy_cilium = false`. |
| Day-1: ArgoCD bootstrap | `data.helm_template.argocd` (app, no CRDs) → `cluster.inlineManifests` (namespace → `sops-age-key` Secret for ksops → ArgoCD app); the ~1.8 MB CRDs are applied via `kubectl` server-side post-health-gate (`null_resource`). Opt-out: `deploy_argocd = false`. |
| **Day-2: Talos OS upgrade** | Bumping `talos_install_version` re-renders the affected per-node installer images and `talos_machine_configuration_apply` writes the new `install.image`, but `apply-config` alone does not re-image a node — the actual roll-out is out-of-band `talosctl upgrade` (see below). |
| **Day-2: image / capability changes** | Edit `images` (baseline extensions/overlay), `hardware_capabilities`, or the base provisioning-profile catalog → an affected node's composed schematic ID + installer URL change → `machine_configuration_apply` writes the new `install.image`; the same out-of-band `talosctl upgrade` re-images affected nodes. |

> **Re-image blast-radius — diff the hashes before adopting a change.** A node
> re-images only when its composed schematic hash changes. `tofu plan` does not
> warn which nodes that is, so before applying a base-tag bump, a
> `hardware_capabilities` edit, or a profile-catalog change, capture
> `tofu output node_schematic_hashes` (and `distinct_schematic_count`) before and
> after and diff them: every changed hash is a node that will re-image on the next
> out-of-band `talosctl upgrade`. Nodes with an unchanged hash keep their installer
> and do NOT re-image.

**Two Day-2 ops stay out-of-band** — the `siderolabs/talos` provider ships no
OS- or Kubernetes-upgrade resource, so both are imperative `talosctl` commands
the consumer Taskfile drives. The **OS upgrade** is `talosctl upgrade --image
…:<version>` (bump `talos_install_version`; tofu renders the new installer URL
into tfplan JSON, the Taskfile rolls each node — see §"Versions: schema-pin vs
install-pin"). The **Kubernetes upgrade** is `talosctl upgrade-k8s --to
<version>` (bump `kubernetes_version` to keep the machine-config in sync). In
both cases tofu owns the declarative state and the talosctl command performs the
rolling upgrade. Tracked follow-up for when the provider exposes these as
resources.

## Node roles vs images + capabilities

Kubernetes node **roles** are ONLY `controlplane` and `worker`. Hardware
specialisation — GPU, single-board-computer, storage — is **not** a role. A node
sits on one base **`image`** (architecture + CPU vendor + baseline extensions +
optional SBC overlay) and holds a **SET** of **`hardware_capabilities`** that
compose independently. So a node can be storage + compute + GPU at once without a
hand-authored class, and a heterogeneous multi-arch cluster (amd64 servers + an
arm64 Raspberry Pi worker) is expressible in one apply. Capability names are
tool-agnostic — a node declares `storage-replicated`, not `drbd`; the base
provisioning-profile catalog maps each to extensions / kernel args / modules. See
[`knowledge/decisions/0009-node-capability-composition.md`](../../../knowledge/decisions/0009-node-capability-composition.md).

### The provisioning-profile catalog

[`profiles.tf`](profiles.tf) is a module-local **constant**, not a variable: a
consumer selects profiles by id through a capability's
`provisioning_profiles`, but cannot author or redefine one (the anti-override
invariant in ADR-0009). `profiles.tf` is the source of truth; the catalog at
this tag is:

| Profile id | Provides (Layer-C atom) | What it bakes |
|---|---|---|
| `drbd` | `drbd-kernel-module` | DRBD extension + kernel module — the replication layer LINSTOR builds on |
| `iommu` | `iommu-enabled` | vendor-variant kernel args only: `intel_iommu=on` / `amd_iommu=on`, selected by the node image's `cpu_vendor`. Predicate-only — no host tuning (ADR-0016) |
| `nvidia-lts` | *(nothing)* | open GPU kernel modules + container toolkit. Provides no atom because `nvidia-gpu` is NFD-detected at runtime, not asserted by machine config |

A profile's kernel args are limited to what its atom's `presence_predicate`
names — asserted by `tests/profile-predicate-only.tftest.hcl` in `task tofu:ci`.

## Usage

```hcl
module "complete" {
  source = "git::https://github.com/Nosmoht/talos-platform-base.git//tofu/modules/talos-cluster?ref=<tag>"

  cluster_name       = "example-cluster"
  talos_version      = "v1.12.6"
  kubernetes_version = "v1.35.0"
  cluster_endpoint   = "https://api.example:6443"

  images = {
    intel = { architecture = "amd64", cpu_vendor = "intel", extensions = ["siderolabs/intel-ucode", "siderolabs/nvme-cli"] } # baseline (every node of the image)
    pi    = { architecture = "arm64", cpu_vendor = "arm", extensions = [], overlay = { name = "rpi_generic", image = "siderolabs/sbc-raspberrypi" } }
  }

  # Consumer composites (tool-agnostic). requires_features (scheduling/labels) and
  # provisioning_profiles (what the base catalog bakes) are SEPARATE lists;
  # emits_label MUST be platform.io/hardware-capability.*.
  hardware_capabilities = {
    storage-replicated = {
      requires_features     = ["drbd-kernel-module"]
      provisioning_profiles = ["drbd"]
      emits_label           = "platform.io/hardware-capability.storage-replicated"
    }
    compute-gpu-nvidia = {
      requires_features     = ["nvidia-gpu"]
      provisioning_profiles = ["nvidia-lts"]
      emits_label           = "platform.io/hardware-capability.compute-gpu-nvidia"
    }
  }

  # Keyed by node name — the key IS the Talos hostname / Kubernetes node name.
  # One node, one definition place. The controlplane count must be ODD.
  nodes = {
    node-cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["storage-replicated"] }
    node-gpu-1 = { ip = "192.0.2.31", role = "worker", image = "intel", hardware_capabilities = ["storage-replicated", "compute-gpu-nvidia"],
    config_patches = [file("${path.module}/patches/gpu-nic.yaml")] } # per-node NIC binding
    node-pi-1 = { ip = "192.0.2.41", role = "worker", image = "pi", hardware_capabilities = [] } # arm64
  }

  # Cluster-wide patches the caller owns (NTP, registry mirrors, install disk).
  config_patches = [file("${path.module}/patches/cluster-common.yaml")]
}
```

A runnable-shaped `tofu validate` fixture covering this exact topology lives in
[`examples/complete/`](examples/complete).

The caller owns the `provider "talos" {}` block and the (encrypted) backend.
Example root `versions.tf`:

```hcl
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    talos = { source = "siderolabs/talos", version = ">= 0.7.0, < 1.0.0" }
  }
  # State holds machine_secrets — the backend MUST be encrypted.
  encryption {
    key_provider "pbkdf2" "k" { passphrase = var.tf_encryption_passphrase }
    method "aes_gcm" "m" { keys = key_provider.pbkdf2.k }
    state { method = method.aes_gcm.m }
  }
}

provider "talos" {}
```

## Inputs

| Name | Type | Default | Description |
|---|---|---|---|
| `cluster_name` | string | — | RFC-1123 label, used in PKI CNs |
| `talos_version` | string | — | **Schema-pin**, v-prefixed semver. Fixed at bootstrap; do NOT change. Drives `talos_machine_secrets` and `data.talos_machine_configuration`. |
| `talos_install_version` | string | `""` | **OS-version pin** — what's installed on the nodes. Defaults to `talos_version`. Bump for OS upgrades. |
| `kubernetes_version` | string | — | v-prefixed semver. Bump triggers out-of-band `talosctl upgrade-k8s`. |
| `cluster_endpoint` | string | — | `https://…:6443` API endpoint / VIP |
| `nodes` | map(object) | — | **Keyed by node name** — the key IS the Talos hostname, the Kubernetes node name and the per-node apply resource's state address, so a node cannot be declared twice. Keys must already be canonical Kubernetes node names (lowercase `[a-z0-9-.]`, no leading/trailing `-`/`.`, ≤63 per label, ≤253 total): Talos validates hostname LENGTH only and silently rewrites the rest, so a non-canonical key would land in the cluster under a different name. First labels must be unique (Talos splits at the first dot); a dotted key requires `register_with_fqdn`. Value: `{ip, role, image, hardware_capabilities?, config_patches?}`; role ∈ {controlplane, worker} and the controlplane count must be **odd** (etcd quorum); `image` must be a key in `images`; `hardware_capabilities` (default `[]`) are keys in `hardware_capabilities`; `config_patches` are per-node, applied AFTER the module-generated capability patch (so a raw patch overrides a generated `machine.kernel.modules`/`sysctls`/`nodeLabels` value — and its *content* is not parsed, so reserved-label enforcement on that vector is the downstream Kyverno rule, not tofu). |
| `register_with_fqdn` | bool | `false` | Sets `machine.kubelet.registerWithFQDN`. Talos splits a dotted hostname at the first dot and registers only the SHORT hostname with Kubernetes by default — so dotted node keys are rejected unless this is on. |
| `images` | map(object) | — | Per base-image: `{architecture("amd64"\|"arm64"), cpu_vendor("intel"\|"amd"\|"arm"), extensions(baseline — every node of the image), extra_kernel_args(schematic boot args, unioned with the node's profile args), overlay?}`. At least one image required. |
| `hardware_capabilities` | map(object) | `{}` | Consumer composites: `{requires_features, provisioning_profiles, emits_label}`. `emits_label` MUST be `platform.io/hardware-capability.*`. A provisioned `requires_features` atom must be satisfied by a listed profile and vice-versa (symmetry, both directions, plan-time-checked). |
| `config_patches` | list(string) | `[]` | machine-config patches applied to all nodes |
| `controlplane_config_patches` | list(string) | `[]` | patches for controlplane nodes only |
| `worker_config_patches` | list(string) | `[]` | patches for worker nodes only |
| `cluster_health_timeout` | string | `"10m"` | max wait for `data.talos_cluster_health` (etcd quorum, nodes Ready, apiserver reachable). `apply` blocks until then. |
| `pod_cidr` | list(string) | Talos default `/16` | pod CIDR(s) → Talos `podSubnets` AND Cilium IPAM/masquerade/native-routing. v4+v6 when `dual_stack`. |
| `service_cidr` | list(string) | Talos default `/12` | service CIDR(s) → Talos `serviceSubnets`. |
| `dual_stack` | bool | `false` | IPv4/IPv6 dual-stack (enables Cilium `ipv6`). |
| `allow_scheduling_on_controlplanes` | bool | `false` | remove the control-plane taint (single-node / edge). |
| `deploy_cilium` | bool | `true` | deliver Cilium as a controlplane `inlineManifest` seed AND disable the Talos default CNI (`cni.name: none`) + kube-proxy. Opt-out keeps Flannel / a caller-supplied CNI. |
| `cilium_chart_version` | string | `"1.20.0"` | cilium Helm chart version. **SEED knob** (inlineManifests are create-only), not an upgrade knob. |
| `cilium_chart_repository` | string | `"https://helm.cilium.io"` | Helm repo for the cilium chart (override for a private mirror / air-gap). |
| `cilium_namespace` | string | `"kube-system"` | namespace Cilium renders into. |
| `cilium_values_override` | string | `""` | consumer Helm values merged on the floor + computed values (long tail: Hubble, L2/BGP, bpf). |
| `cilium_routing_mode` | string | `"tunnel"` | `tunnel` / `native`. Install-time-fixed. |
| `cilium_native_routing_cidr` | string | `""` | `ipv4NativeRoutingCIDR` for native mode; empty = first `pod_cidr`. |
| `cilium_kube_proxy_replacement` | bool | `true` | Cilium kube-proxy replacement (also sets Talos `proxy.disabled`). |
| `cilium_mtu` | number | `0` | datapath MTU (0 = chart auto). |
| `cilium_encryption` | object | `{type="none"}` | `type` ∈ {none, wireguard, ipsec}. ipsec requires `cilium_ipsec_key`. |
| `cilium_ipsec_key` | string (sensitive) | `""` | IPsec PSK seeded as the `cilium-ipsec-keys` Secret; required for `type=ipsec` (wireguard is keyless). Lands in (encrypted) state. |
| `cilium_gateway_api` | bool | `true` | enable the Cilium **gateway controller** (operator creates the GatewayClass once CRDs exist). The CRDs are NOT seeded by default — apply them via GitOps (Day-1), or opt into bootstrap seeding below. Controller errors harmlessly until CRDs land; CNI unaffected. |
| `cilium_gateway_api_crds_url` | string | `""` (no boot seed) | **OPT-IN** bootstrap seeding of the Gateway API CRDs via `cluster.extraManifests`. Empty = CRDs are a Day-1 GitOps concern (air-gap-safe). Set to the GW-API **v1.6.1 standard** bundle URL (or an internal mirror) for a connected cluster — Cilium 1.20 requires v1.6.1 at a minimum, and TLSRoute is in the standard channel as of v1.6.1. Use the **experimental** bundle only if you carry pre-existing `v1alpha2` TLSRoute objects. ⚠️ a failed fetch crashloops Talos' ExtraManifestController and blocks clean bootstrap. |
| `cilium_agent_metrics` | bool | `false` | enable Cilium **agent** Prometheus metrics (`prometheus.enabled`). Default off. |
| `cilium_operator_metrics` | bool | `false` | enable Cilium **operator** Prometheus metrics (`operator.prometheus.enabled`). Default off. Note: the upstream chart's OWN default for this value is already `true`, so the rendered `cilium-config` ConfigMap's `operator-prometheus-serve-addr` key is present regardless of this toggle — it does not discriminate at the render layer (a pre-existing chart-default fact, not introduced by this input). |
| `cilium_hubble_enabled` | bool | `false` | enable Hubble flow/metrics observability. **Forces `hubble.tls.enabled=false`** (metrics-only scope — no Relay/UI; the Hubble metrics endpoint is independent of observer-API TLS since Cilium 1.16). Default off. |
| `cilium_hubble_metrics` | list(string) | `[]` | Hubble metrics to export (`hubble.metrics.enabled`), e.g. `["dns", "drop", "tcp"]`. Scrape wiring (ServiceMonitor/PodMonitor) stays consumer-side. An empty list with `cilium_hubble_enabled=true` is a valid **half-on** state (server on, no metrics exported). |
| `cilium_self_management` | bool | `false` | **opt-in**: emit a Cilium ArgoCD `Application` (module OUTPUT only — see `cilium_self_management_app` — never applied by the module) as the Day-2 delivery path. Requires `deploy_argocd=true` AND `deploy_cilium=true`. **HARD-REJECTED at plan time** while `cilium_values_override` is non-empty — see the Cilium Self-Management section below. |
| `cilium_self_management_project` | string | `"default"` | ArgoCD `AppProject` the emitted Application targets. Default `"default"` (the always-present permissive project) — scope to a dedicated project for hardening (see below). |
| `deploy_argocd` | bool | `true` | deliver ArgoCD as a controlplane `inlineManifest`. Requires `sops_age_key` when true. |
| `sops_age_key` | string (sensitive) | `""` | age private key (`keys.txt`) for the ArgoCD **ksops** repoServer, seeded as the `sops-age-key` Secret. **Required** when `deploy_argocd = true`. Lands in (encrypted) state. |
| `argocd_namespace` | string | `"argocd"` | namespace for the bootstrap ArgoCD install |
| `argocd_chart_version` | string | `"9.4.5"` | `argo-cd` Helm chart version (argoproj.github.io/argo-helm) |
| `argocd_values_override` | string | `""` | full replacement of the bootstrap Helm values (YAML). Empty = the shipped `helm/argocd-values.yaml` (slim, ksops). |
| `cert_approver_provider_regex` | string | `".*"` | `postfinance/kubelet-csr-approver` `PROVIDER_REGEX` — regex every kubelet-serving CSR's **SAN DNS name** must additionally match. Match the **full DNS SAN string**, which may be an FQDN (e.g. `node-1.internal.example.com`), not just the bare node name — a pattern too restrictive to match the actual SAN (e.g. `^node-[0-9]+$` against an FQDN SAN) denies those CSRs. `^node-.*$` is a safe permissive form. **SEED knob** (create-only). The always-on per-node DNS-SAN hostname-prefix binding applies regardless. Validated: non-empty/non-whitespace (empty crashes the approver; whitespace-only denies all), compiles, no `---`, no newline (protects the split-based audit outputs). |
| `cert_approver_provider_ip_prefixes` | list(string) | `["0.0.0.0/0", "::/0"]` | `PROVIDER_IP_PREFIXES` — CIDRs a CSR's IP SANs must fall within. Default is the **safe floor** (all IPs); **never `[]`** (an empty set denies every serving CSR). Tighten to node subnets for an IP-SAN-to-subnet binding. **SEED knob.** Every entry must be a valid CIDR. |
| `cert_approver_replicas` | number | `1` | approver Deployment replica count (`>= 1`). `> 1` derives leader-election + a namespaced `coordination.k8s.io/leases` Role/RoleBinding so the HA config is coherent; `1` keeps least privilege (no leases rule). **SEED knob.** |

**Patch precedence — two passes.** *Generation pass* (baked into the machine
config by `data.talos_machine_configuration`): all-nodes (`config_patches`) then
role (`controlplane`/`worker_config_patches`). *Apply pass* (strategic-merge
overlay, later wins): module hostname + install.image, then the
**module-generated capability patch** (`machine.kernel.modules`/`sysctls`/`nodeLabels`
composed from the node's `hardware_capabilities`), then node
(`node.config_patches`), then `base_cni_patch` strictly last. So a raw node patch
overrides a generated field (Talos applies it later) — this override is **silent**
(the module does not parse raw patch content; a plan-time overlap warning is a
documented follow-up, so a raw patch that drops a generated kernel module while
the node keeps its provisioning label is a known caveat). A node/raw patch can
also override `machine.install.image` — the module always selects the
non-secureboot `urls.installer`, so the module itself never emits a SecureBoot
installer. Patch *content* is the caller's responsibility: a SecureBoot string in
this repo's `tofu/**` is caught by `hard-constraints-check`, but a consumer's own
root/patch files (and schematic-level secureboot toggles the URL grep cannot see)
are outside the base gate — enforcing the constraint there is the consumer
overlay's job.

## Outputs

| Name | Sensitive | Description |
|---|---|---|
| `kubeconfig` | yes | admin kubeconfig (raw YAML) |
| `talosconfig` | yes | talosctl client config (raw YAML) |
| `client_configuration` | yes | Talos client cert bundle for chaining |
| `cluster_endpoint` | no | echoed API endpoint |
| `controlplane_ips` | no | controlplane node IPs |
| `schematic_ids` | no | Image-Factory schematic ID per distinct content-hash (identical nodes share one) |
| `installer_images` | no | resolved `metal-installer` image URL per node hostname (was per-class; the upgrade task reads it from tfplan JSON) |
| `node_schematic_hashes` | no | per-node content-hash of the composed schematic (dedup audit) |
| `distinct_schematic_count` | no | number of distinct schematics after content-hash dedup |
| `talos_install_version` | no | effective installer version |
| `cluster_health` | no | `"healthy (…)"` — references `data.talos_cluster_health`, so any consumer reading it blocks until the cluster is online |
| `cilium_self_management_app` | no | the emitted Cilium ArgoCD `Application` manifest (raw YAML string) when `cilium_self_management=true`; `""` otherwise. Module OUTPUT only — never applied by the module (see the Cilium Self-Management section below). Secret-free (no `cilium_values_override` term). |

Audit-shaped outputs. These exist as binding points for the composition
regression suite (`tests/composition.tftest.hcl`, via `task tofu:test` —
network-bound, not part of `task tofu:ci`); they are secret-free and safe to
read. Full semantics live in each output's `description` in
[`outputs.tf`](outputs.tf).

| Name | Sensitive | Description |
|---|---|---|
| `argocd_namespace_labels` | no | PSA floor + recommended labels the argocd namespace seed bakes |
| `cert_approver_namespace_labels` | no | PSA-restricted floor + labels of the cert-approver namespace seed |
| `cert_approver_seeded` | no | red-green binding: cert-approver seed wired into the controlplane patch list |
| `kubelet_serving_cert_rotation` | no | per-role booleans: rotation patch present in each role's patch list |
| `kubelet_rotation_setting` | no | decoded rotation patch — proves the mechanism is `machine.kubelet.extraConfig.serverTLSBootstrap`, not the deprecated `--rotate-server-certificates` flag |
| `cert_approver_approve_resource_names` | no | RBAC scope of the vendored approver's `approve` verb — must equal `["kubernetes.io/kubelet-serving"]`, never `["*"]` |
| `cert_approver_seed_missing_labels` | no | recommended-label gaps across the vendored seed manifest — must be empty |
| `cert_approver_rbac_rules` | no | raw decoded ClusterRole rule objects (inspection companion); INVARIANT at 3 signer-scoped rules. The binding closure is `cert_approver_clusterrole_signature` + `cert_approver_clusterrolebinding_targets` |
| `cert_approver_clusterrole_signature` | no | normalized per-rule signature (apiGroups+resources+VERBS+resourceNames) of the ClusterRole — the composition suite asserts the exact set, so a re-vendor adding a verb (`sign`), widening apiGroups, or dropping the signer scope turns red |
| `cilium_seed_observability_markers` | no | booleans decoded from the FROZEN bootstrap seed render (not a second Helm render), keyed `agent_metrics`/`operator_metrics`/`hubble`/`hubble_metrics`. `agent_metrics`, `hubble`, and `hubble_metrics` genuinely discriminate their respective toggles; `operator_metrics` is **audit-only** (see the `cilium_operator_metrics` input row — the upstream chart's own default makes this key always present at the render layer). `{}` when `deploy_cilium=false`. |
| `cert_approver_clusterrolebinding_targets` | no | every ClusterRoleBinding as {role, subjects} — the suite asserts exactly one (approver SA → the scoped ClusterRole), so a second binding (e.g. → cluster-admin) or a repointed roleRef turns red |
| `cert_approver_leaderelection_role_rules` | no | decoded namespaced leader-election Role rules (`coordination.k8s.io/leases` + events) — empty at `replicas:1` (least privilege), populated only at `replicas > 1` |
| `cert_approver_pod_security_context` | no | decoded pod/container securityContext — restricted-PSA regression guard (runAsNonRoot, drop ALL, readOnlyRootFilesystem, seccomp RuntimeDefault) |
| `cert_approver_env` | no | decoded `PROVIDER_*` / `BYPASS_DNS_RESOLUTION` env — red-green binding that the `substrate.cert_approver.*` config flows through to the seed |
| `cert_approver_container_args` | no | decoded container args of the rendered approver — binds the HA conditional (`-leader-election` present only when `replicas > 1`) |
| `cert_approver_replicas` | no | decoded replica count of the rendered approver Deployment — binds the consumer-settable `replicas` knob (default 1) |
| `controlplane_base_is_prefix_of_final` | no | asserts the sensitive argocd/cilium seeds are only appended after the non-sensitive base patch list, never reordered before it |

## Versions: schema-pin vs install-pin (Day-2 pattern)

Two distinct versions:

- **`talos_version`** — the **machine-config schema** the cluster was
  bootstrapped against. Fixed for the lifetime of the cluster.
- **`talos_install_version`** — the **installer-image tag** rendered into
  `machine.install.image` and the Image-Factory installer URL. What's actually
  running. Bump it to roll an OS upgrade.

For an OS upgrade: bump `talos_install_version`, `tofu plan -out tfplan.bin &&
tofu show -json tfplan.bin > tfplan.json` (new installer URL + `schematic_id`
per node flow through), then a consumer Taskfile target reads `tfplan.json` and
runs `talosctl upgrade --image …:<version>` idempotently per node, and finally
`tofu apply` updates state. Tofu owns the declarative state; the consumer
Taskfile owns the imperative talosctl execution; both read the same tfplan-JSON.

## ArgoCD delivery + health gate

ArgoCD is **Layer-1 substrate** in the platform's C4 layer model, not a Day-2
app — so the module seeds it (chart rendered locally into an inlineManifest). There is **no**
`helm_release`/`kubernetes_*` apply against a computed kubeconfig (that
chicken-and-egg anti-pattern is avoided): the chart is rendered **locally** with
`data.helm_template` and baked into the controlplane machine config as
`cluster.inlineManifests`. Three manifests in apply order:

1. the `argocd` **namespace**,
2. a `sops-age-key` **Secret** (`stringData."keys.txt" = var.sops_age_key`) so
   the bootstrap ArgoCD **ksops** repoServer can decrypt SOPS manifests
   (ADR-0023 class B), and
3. the rendered **ArgoCD manifest** itself.

Talos applies inlineManifests once at bootstrap and never reconciles them again,
so the seed is intentionally **minimal** (`helm/argocd-values.yaml`): server
`ClusterIP` + `insecure`, the ksops initContainer. The steady-state (TLS cert
via a `ClusterIssuer` that doesn't exist yet at bootstrap, RBAC, OIDC, the
app-of-apps) is owned by **ArgoCD self-management** in the consumer repo.
`argocd_values_override` is **merged** on top of the shipped values (not a
wholesale replace). `argocd_chart_version` is a **seed-only** knob — bumping it
after bootstrap only re-renders the machine config, it does not upgrade a
running ArgoCD (that is the self-management's job).

**CRDs are NOT in the inlineManifest.** The three ArgoCD CRDs
(Application/ApplicationSet/AppProject) render to ~1.8 MB — far over the Talos
inlineManifest budget (the app render is ~109 KB). So the module applies the
CRDs via `kubectl apply --server-side` (a `null_resource`, gated on the health
check) using the module's kubeconfig; server-side apply also avoids the >262 KB
client-side last-applied-config annotation limit the ApplicationSet CRD trips.
**This needs `kubectl` on the apply host** (a workstation has it via devbox; a
Crossplane provider-terraform runner must ship it). The ArgoCD app (in the
inlineManifest) crash-loops for the few seconds until the CRDs land, then
recovers.

**Why `kubectl` and not a Terraform provider apply?** (Decided in #104.) A
`hashicorp/kubernetes` `kubernetes_manifest` apply needs API access at *plan*
time — but on a first apply the cluster does not exist yet, so it cannot
bootstrap itself. A third-party `kubectl_manifest` provider works but is a worse
footprint for a substrate module (third-party provider + ~1.8 MB of state bloat).
The `kubectl` host dependency is therefore a deliberate, accepted trade — every
apply host must ship `kubectl`, including the Crossplane provider-terraform runner
image. See the `adr-0006-opentofu-cluster-lifecycle.md` 2026-06-03 amendment.

> The `sops_age_key` lands in Tofu state and in the controlplane machine config
> — both already sensitive (state holds PKI; machine config is a secret). But it
> is a **cross-cutting master key** (decrypts *all* SOPS secrets): whoever reads
> a controlplane node's machine config holds it — a conscious, larger blast
> radius. **Rotation** requires a machine-config re-apply (`tofu apply` with the
> new key); the inlineManifest Secret never reconciles on its own. The backend
> **must** be encrypted. Set `deploy_argocd = false` to wire ArgoCD another way;
> then `sops_age_key` is not required.

**Health gate.** `data.talos_cluster_health` blocks `tofu apply` after bootstrap
until etcd has quorum, every node is Ready and the apiserver answers (up to
`cluster_health_timeout`, default `10m`). It checks **cluster reachability, not
the ArgoCD rollout** — it exists so the apiserver is up before the CRD apply and
before credentials are emitted, not to assert ArgoCD is Ready. The
`kubeconfig`/`talosconfig`/`cluster_health` outputs `depends_on` it, so a
consumer that writes those into secret storage only ever receives credentials
for a cluster that is genuinely **online**.

**Cilium convergence — done.** Under the three-pillars model
(Talos + Cilium + ArgoCD), Cilium now follows the same local-render →
inlineManifest pattern as ArgoCD (`deploy_cilium`, default true): the module
disables the Talos default CNI + kube-proxy and bakes a locally-rendered Cilium
chart into the controlplane `cluster.inlineManifests` as a create-only SEED. The
former consumer-side `cluster.extraManifests`-URL recipe is obsolete. See
[`knowledge/decisions/0007-cluster-yaml-sot.md`](../../../knowledge/decisions/0007-cluster-yaml-sot.md). Install-time
Cilium config rides the typed `cilium_*` inputs + `cilium_values_override`;
runtime-mutable config (Hubble, L2/BGP) is Day-2 Cilium self-management.

## Cilium observability + self-management

**Observability (default off).** `cilium_agent_metrics`, `cilium_operator_metrics`,
`cilium_hubble_enabled` + `cilium_hubble_metrics` are first-class typed inputs
layered into the SAME computed-values map the bootstrap seed and the emitted
self-management `Application` (below) both derive from — a single observability
data-flow, no divergent layers. `cilium_hubble_enabled=true` forces
`hubble.tls.enabled=false` (metrics-only scope; no Relay/UI): the Hubble metrics
scrape endpoint (`hubble-metrics` Service, `:9965`) is independent of the
observer-API TLS setting at the pinned chart version. An empty `cilium_hubble_metrics`
with `cilium_hubble_enabled=true` is a valid **half-on** state — the Hubble
server runs but exports no metrics. `cilium_operator_metrics` does not
discriminate the rendered `cilium-config` ConfigMap (see the input row above);
`cilium_agent_metrics` and `cilium_hubble_enabled` do.

**Self-management (opt-in, `cilium_self_management`).** When enabled, the module
emits a rendered Cilium ArgoCD `Application` manifest as the
`cilium_self_management_app` OUTPUT — the module never applies it (no
`kubectl`, no live-apply resource: AGENTS.md §Hard Constraints forbids the
module directly applying ArgoCD-managed resources). Consumer pattern: a one-line
`local_file` resource in the consumer's own root writing the output to disk,
committed to the consumer's GitOps repo, so the consumer's existing ArgoCD
adopts steady-state Cilium management. The consumer owns **exactly one** Cilium
`Application` — mutual-exclusivity with the bootstrap seed's inlineManifest
resources (the seed becomes the pre-adoption floor, not a second manager). The
emitted manifest carries **no `syncPolicy`** — the consumer controls sync
timing, since enabling Hubble triggers a graceful-restart-gated DaemonSet roll.
Requires **OpenTofu ≥ 1.9** (cross-variable `validation` blocks).

**Coupling + guard.** `cilium_self_management` requires `deploy_argocd=true` AND
`deploy_cilium=true` (self-management hands the Day-2 config off from the
module-delivered seed to the consumer's ArgoCD — there is nothing to hand off
otherwise). Separately, the emitted `valuesObject` does **NOT** inherit
`cilium_values_override` — the module **HARD-REJECTS** `cilium_self_management=true`
while `cilium_values_override` is non-empty at plan time: a seed-active
datapath-critical override (BGP control-plane, L2 announcements, bpf tuning)
would otherwise be silently **DROPPED** the moment ArgoCD adopts Cilium.
Migrate the override into your own Cilium `Application` first, then empty
`cilium_values_override` in the SoT to enable self-management.

**Bootstrap-window datapath gap (accepted trade-off, no code fix).** The guard
above and the module's create-only seed (`terraform_data.cilium_render`,
`ignore_changes=[input]`) interact in two ways that are in tension and must both
be understood: (a) while `cilium_values_override` stays set in the SoT, the
guard blocks `cilium_self_management` outright — you cannot self-manage with a
seed-active override still declared; (b) once you empty
`cilium_values_override` to enable self-management, a **future** fresh bootstrap
or a `-replace` re-seed of the frozen render brings a node up with
**plain-floor Cilium only** (no BGP/L2/bpf) until ArgoCD's first sync adopts and
re-applies the override via the self-managed `Application` — a bootstrap-window
datapath gap on BGP/L2 clusters. This is the mirror image of the existing
re-bootstrapped-node caveat (a stale seed that still carries a since-migrated
override): one state has a gap on the seed side, the other has a gap on the
migration side. There is no code fix for either; plan around the window on
BGP-dependent clusters (e.g. hold reboots until ArgoCD sync is confirmed).

**`spec.project` posture.** Defaults to `"default"` (the always-present
permissive AppProject) so the feature works out of the box. **Strongly
recommended hardening**: set `cilium_self_management_project` to a
consumer-created, scoped `AppProject` that grants destination namespace
`kube-system` at `https://kubernetes.default.svc`, plus Cilium's cluster-scoped
resources (its CRDs, ClusterRoles, ClusterRoleBindings) in
`clusterResourceWhitelist` — without that whitelist, the adopted `Application`
is inert/degraded under a scoped project.

**Supply-chain note.** The emitted `targetRevision` is
`var.cilium_chart_version` — a mutable tag, no digest/cosign pin. Unlike the
frozen, render-once bootstrap seed, the self-managed `Application` **re-pulls**
the chart on every ArgoCD reconcile, a broader repeated-fetch attack surface.
Point `cilium_chart_repository` only at a trusted source.

**Chart-version-skew + ArgoCD-adoption caveat.** `cilium_chart_version` is a
seed-only knob for the bootstrap render; once self-management is adopted,
bumping it re-renders the emitted `Application`'s `targetRevision` and ArgoCD
performs the upgrade — the module itself never upgrades a running Cilium. The
**first sync that adopts** the seed-created Cilium resources into the emitted
`Application` may trigger managed-fields reconciliation and an agent restart —
an inherent seed→GitOps takeover behavior, not a bug, and not avoidable in code.

## Notes

- etcd is bootstrapped on exactly one controlplane: the one with the
  **lowest node name** (`sort()` over controlplane keys). This is a stable
  key — re-declaring `nodes` in a different order after bootstrap does not move
  the bootstrap target. The same holds for every Talos-facing list the module
  emits (`cluster_health.*`, the talosconfig endpoints/nodes,
  `output.controlplane_ips`): each is a projection of `var.nodes` ordered by node
  name, so declaration order is never observable.
- Per-node module-injected config is the hostname, the composed installer image,
  and the generated capability patch (kernel modules / sysctls / nodeLabels).
  Everything else cluster-specific comes from the caller's patches.
- **The patch escape hatch cuts both ways.** Caller patches are applied AFTER the
  module's own, and the module does not parse their content. So a per-node
  `config_patches` entry carrying a `HostnameConfig` (or `machine.network.hostname`)
  overrides the key-derived hostname, and a patch setting
  `machine.kubelet.registerWithFQDN` overrides `register_with_fqdn` in either
  direction. The node-key validations cannot see that, and no CI gate does — if
  you use the escape hatch on these two fields, the declared name and the live
  name diverge, and every state address, `installer_images` key and `talosctl`
  target stays keyed on a name no machine carries. The typed inputs are the
  supported surface.
- **Growing a control plane can move the bootstrap target.** It is the
  lowest-named controlplane, so ADDING one whose name sorts below the incumbent
  repoints `talos_machine_bootstrap` — which must not be re-created on a running
  cluster. Name new controlplanes so they sort above the incumbent, or move the
  state entry deliberately. The odd-count rule makes multi-node additions the
  normal shape, so check the plan for a `talos_machine_bootstrap` replacement
  before applying.
- The installer image is always the non-SecureBoot `metal-installer` (the
  SecureBoot installer variant is forbidden per the base `AGENTS.md` Hard
  Constraint — boot loops). ARM SBC images use `architecture = "arm64"` + an
  `overlay`; the platform stays `metal`.
- **Greenfield by default; adopting a running cluster needs `tofu import`.**
  The module *generates* `talos_machine_secrets`, so a naive apply against a
  live cluster would regenerate PKI and re-bootstrap etcd. To adopt an
  already-running cluster without re-bootstrapping, import
  `talos_machine_secrets.this` (from your existing `secrets.yaml`) and
  `talos_machine_bootstrap.this` before the first apply — full runbook in
  [`UPGRADING.md` §Adopting an already-running cluster](../../../UPGRADING.md#adopting-an-already-running-cluster-no-re-bootstrap).
  Reproducible proof scripts: [`test/`](test/README.md).

## Related

- [`knowledge/decisions/0006-opentofu-cluster-lifecycle.md`](../../../knowledge/decisions/0006-opentofu-cluster-lifecycle.md) — why OpenTofu replaced the Makefile/5-axis path, and the consequences.
- [`Taskfile.yml`](../../../Taskfile.yml) — `task tofu:ci` validates this module (fmt-check + validate + lint).
