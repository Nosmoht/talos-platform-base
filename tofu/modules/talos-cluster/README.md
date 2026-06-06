# Module `talos-cluster`

Turns a set of PXE-booted Talos **maintenance-mode** nodes into a bootstrapped
Kubernetes cluster, and returns the admin `kubeconfig` + `talosconfig`.

This is the substrate base's **only** Talos cluster-lifecycle path (it replaced
the former `talos/Makefile.lib` + 5-axis `cluster.yaml` generator — see
[`docs/adr-opentofu-cluster-lifecycle.md`](../../../docs/adr-opentofu-cluster-lifecycle.md)).
The module is **backend- and caller-agnostic**: it contains no
`terraform { backend ... }` block. A consumer cluster repo pulls the base as an
OCI artifact, supplies the `provider "talos"` block + an **encrypted** state
backend, and calls the module directly with a `tofu apply` from a workstation.
No higher-level orchestrator is required.

## Scope

In scope:

- Generate cluster PKI / machine secrets.
- Render controlplane + worker machine configs (k8s/Talos version + caller patches).
- Resolve a per-class Image-Factory installer image (extensions + architecture + optional SBC overlay).
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
| Day-1: per-class installer image | `talos_image_factory_extensions_versions` → `talos_image_factory_schematic` → `talos_image_factory_urls` (per-class `architecture` + optional `overlay`) |
| Day-1: apply config to each node | `talos_machine_configuration_apply` (hostname + install.image + class + node patches) |
| Day-1: etcd bootstrap | `talos_machine_bootstrap` (first controlplane only) |
| Day-1: kubeconfig + talosconfig | `talos_cluster_kubeconfig` + `data.talos_client_configuration` |
| Day-1: wait for healthy cluster | `data.talos_cluster_health` (blocks `apply` until etcd quorum + nodes Ready + apiserver reachable; gates the credential outputs) |
| Day-1: CNI + Cilium bootstrap | base machine config sets `cluster.network.cni.name: none` + `cluster.proxy.disabled: true` + pod/service subnets; `data.helm_template.cilium` (floor `helm/cilium-values.yaml` + typed `cilium_*` inputs + `cilium_values_override`) → controlplane `cluster.inlineManifests` seed (+ `cilium-ipsec-keys` Secret when `cilium_encryption.type = ipsec`). Opt-out: `deploy_cilium = false`. |
| Day-1: ArgoCD bootstrap | `data.helm_template.argocd` (app, no CRDs) → `cluster.inlineManifests` (namespace → `sops-age-key` Secret for ksops → ArgoCD app); the ~1.8 MB CRDs are applied via `kubectl` server-side post-health-gate (`null_resource`). Opt-out: `deploy_argocd = false`. |
| **Day-2: Talos OS upgrade** | Bumping `talos_install_version` re-renders the per-class installer image; `talos_machine_configuration_apply` rolls it out. |
| **Day-2: class changes** | Edit `classes` (extensions/overlay/patches) → schematic ID + installer URL change → `machine_configuration_apply` re-rolls nodes of that class. |

**One Day-2 op stays out-of-band**: Kubernetes version upgrades. The
`siderolabs/talos` provider ships no `talos_cluster_kubernetes_upgrade`
resource, so K8s bumps run with `talosctl upgrade-k8s --to <version>` against
the cluster. Bumping `kubernetes_version` keeps the machine-config in sync; the
rolling upgrade is the talosctl command. Tracked follow-up for when the provider
exposes it as a resource.

## Node roles vs classes

Kubernetes node **roles** are ONLY `controlplane` and `worker`. Hardware
specialisation — GPU, single-board-computer, storage — is **not** a role. It is
expressed via a node's **`class`**, which selects an Image-Factory + patch
profile from `var.classes`. This is what makes a heterogeneous, multi-arch
cluster (amd64 servers + an arm64 Raspberry Pi worker) expressible in one apply.

## Usage

```hcl
module "homelab" {
  source = "git::https://github.com/Nosmoht/talos-platform-base.git//tofu/modules/talos-cluster?ref=<tag>"

  cluster_name       = "homelab"
  talos_version      = "v1.12.6"
  kubernetes_version = "v1.35.0"
  cluster_endpoint   = "https://api.example:6443"

  nodes = [
    { hostname = "node-cp-1", ip = "192.0.2.11", role = "controlplane", class = "standard" },
    { hostname = "node-w-1", ip = "192.0.2.21", role = "worker", class = "kubevirt" },
    { hostname = "node-gpu-1", ip = "192.0.2.31", role = "worker", class = "gpu",
      config_patches = [file("${path.module}/patches/gpu-nic.yaml")] }, # per-node NIC binding
    { hostname = "node-pi-1", ip = "192.0.2.41", role = "worker", class = "pi" }, # arm64
  ]

  classes = {
    standard = { architecture = "amd64", extensions = ["siderolabs/drbd"] }
    kubevirt = {
      architecture   = "amd64"
      extensions     = ["siderolabs/drbd"]
      config_patches = [file("${path.module}/patches/kubevirt.yaml")] # whole class
    }
    gpu = {
      architecture = "amd64"
      extensions   = ["siderolabs/drbd", "siderolabs/nvidia-container-toolkit-lts"]
    }
    pi = {
      architecture = "arm64"
      extensions   = []
      overlay      = { name = "rpi_generic", image = "siderolabs/sbc-raspberrypi" }
    }
  }

  # Cluster-wide patches the caller owns (NTP, registry mirrors, install disk).
  config_patches = [file("${path.module}/patches/cluster-common.yaml")]
}
```

A runnable-shaped `tofu validate` fixture covering this exact topology lives in
[`examples/homelab/`](examples/homelab).

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
| `nodes` | list(object) | — | `{hostname, ip, role, class?, config_patches?}`; role ∈ {controlplane, worker}; `class` defaults to `"standard"` and must be a key in `classes`; `config_patches` are per-node (highest precedence). |
| `classes` | map(object) | `{ standard = { architecture = "amd64" } }` | Per-class profile: `{architecture("amd64"\|"arm64"), extensions, overlay?, config_patches}`. The `"standard"` class is mandatory. |
| `config_patches` | list(string) | `[]` | machine-config patches applied to all nodes |
| `controlplane_config_patches` | list(string) | `[]` | patches for controlplane nodes only |
| `worker_config_patches` | list(string) | `[]` | patches for worker nodes only |
| `cluster_health_timeout` | string | `"10m"` | max wait for `data.talos_cluster_health` (etcd quorum, nodes Ready, apiserver reachable). `apply` blocks until then. |
| `pod_cidr` | list(string) | Talos default `/16` | pod CIDR(s) → Talos `podSubnets` AND Cilium IPAM/masquerade/native-routing. v4+v6 when `dual_stack`. |
| `service_cidr` | list(string) | Talos default `/12` | service CIDR(s) → Talos `serviceSubnets`. |
| `dual_stack` | bool | `false` | IPv4/IPv6 dual-stack (enables Cilium `ipv6`). |
| `allow_scheduling_on_controlplanes` | bool | `false` | remove the control-plane taint (single-node / edge). |
| `deploy_cilium` | bool | `true` | deliver Cilium as a controlplane `inlineManifest` seed AND disable the Talos default CNI (`cni.name: none`) + kube-proxy. Opt-out keeps Flannel / a caller-supplied CNI. |
| `cilium_chart_version` | string | `"1.19.4"` | cilium Helm chart version. **SEED knob** (inlineManifests are create-only), not an upgrade knob. |
| `cilium_chart_repository` | string | `"https://helm.cilium.io"` | Helm repo for the cilium chart (override for a private mirror / air-gap). |
| `cilium_namespace` | string | `"kube-system"` | namespace Cilium renders into. |
| `cilium_values_override` | string | `""` | consumer Helm values merged on the floor + computed values (long tail: Hubble, L2/BGP, bpf). |
| `cilium_routing_mode` | string | `"tunnel"` | `tunnel` \| `native`. Install-time-fixed. |
| `cilium_native_routing_cidr` | string | `""` | `ipv4NativeRoutingCIDR` for native mode; empty = first `pod_cidr`. |
| `cilium_kube_proxy_replacement` | bool | `true` | Cilium kube-proxy replacement (also sets Talos `proxy.disabled`). |
| `cilium_mtu` | number | `0` | datapath MTU (0 = chart auto). |
| `cilium_encryption` | object | `{type="none"}` | `type` ∈ {none, wireguard, ipsec}. ipsec requires `cilium_ipsec_key`. |
| `cilium_ipsec_key` | string (sensitive) | `""` | IPsec PSK seeded as the `cilium-ipsec-keys` Secret; required for `type=ipsec` (wireguard is keyless). Lands in (encrypted) state. |
| `cilium_gateway_api` | bool | `true` | enable Cilium Gateway API: renders the gateway controller AND seeds the Gateway API CRDs via `extraManifests`. Satisfies the "Gateway API only" Hard Constraint out of the box. |
| `cilium_gateway_api_crds_url` | string | GW-API v1.4.1 standard bundle | Gateway API CRD manifest URL seeded via `cluster.extraManifests` (fetched at boot, retried). Override for an air-gap mirror or the experimental channel (TLSRoute). |
| `deploy_argocd` | bool | `true` | deliver ArgoCD as a controlplane `inlineManifest`. Requires `sops_age_key` when true. |
| `sops_age_key` | string (sensitive) | `""` | age private key (`keys.txt`) for the ArgoCD **ksops** repoServer, seeded as the `sops-age-key` Secret. **Required** when `deploy_argocd = true`. Lands in (encrypted) state. |
| `argocd_namespace` | string | `"argocd"` | namespace for the bootstrap ArgoCD install |
| `argocd_chart_version` | string | `"9.4.5"` | `argo-cd` Helm chart version (argoproj.github.io/argo-helm) |
| `argocd_values_override` | string | `""` | full replacement of the bootstrap Helm values (YAML). Empty = the shipped `helm/argocd-values.yaml` (slim, ksops). |

**Patch precedence — two passes.** *Generation pass* (baked into the machine
config by `data.talos_machine_configuration`): all-nodes (`config_patches`) then
role (`controlplane`/`worker_config_patches`). *Apply pass* (strategic-merge
overlay, later wins): module hostname + install.image, then class
(`classes[class].config_patches`), then node (`node.config_patches`). A
class/node patch in the apply pass can override `machine.install.image` — the
module always selects the non-secureboot `urls.installer`, so the module itself
never emits a SecureBoot installer. Patch *content* is the caller's
responsibility: a SecureBoot string in this repo's `tofu/**` is caught by
`hard-constraints-check`, but a consumer's own root/patch files (and
schematic-level secureboot toggles the URL grep cannot see) are outside the base
gate — enforcing the constraint there is the consumer overlay's job.

## Outputs

| Name | Sensitive | Description |
|---|---|---|
| `kubeconfig` | yes | admin kubeconfig (raw YAML) |
| `talosconfig` | yes | talosctl client config (raw YAML) |
| `client_configuration` | yes | Talos client cert bundle for chaining |
| `cluster_endpoint` | no | echoed API endpoint |
| `controlplane_ips` | no | controlplane node IPs |
| `schematic_ids` | no | Image-Factory schematic ID per class |
| `installer_images` | no | resolved `metal-installer` image URL per class |
| `talos_install_version` | no | effective installer version |
| `cluster_health` | no | `"healthy (…)"` — references `data.talos_cluster_health`, so any consumer reading it blocks until the cluster is online |

## Versions: schema-pin vs install-pin (Day-2 pattern)

Two distinct versions:

- **`talos_version`** — the **machine-config schema** the cluster was
  bootstrapped against. Fixed for the lifetime of the cluster.
- **`talos_install_version`** — the **installer-image tag** rendered into
  `machine.install.image` and the Image-Factory installer URL. What's actually
  running. Bump it to roll an OS upgrade.

For an OS upgrade: bump `talos_install_version`, `tofu plan -out tfplan.bin &&
tofu show -json tfplan.bin > tfplan.json` (new installer URL + `schematic_id`
per class flow through), then a consumer Taskfile target reads `tfplan.json` and
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
image. See the `adr-opentofu-cluster-lifecycle.md` 2026-06-03 amendment.

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
[`docs/adr-cluster-yaml-sot.md`](../../../docs/adr-cluster-yaml-sot.md). Install-time
Cilium config rides the typed `cilium_*` inputs + `cilium_values_override`;
runtime-mutable config (Hubble, L2/BGP) is Day-2 Cilium self-management.

## Notes

- etcd is bootstrapped on exactly one controlplane: the one with the
  **lowest hostname** (`sort()` over controlplane hostnames). This is a stable
  key — reordering `nodes` after bootstrap does not move the bootstrap target.
- Per-node module-injected config is the hostname + class installer image.
  Everything else cluster-specific comes from the caller's patches.
- The installer image is always `metal-installer` (NEVER
  `metal-installer-secureboot`, per the base `AGENTS.md` Hard Constraint). ARM
  SBC classes use `architecture = "arm64"` + an `overlay`; the platform stays
  `metal`.
- **Greenfield by default; adopting a running cluster needs `tofu import`.**
  The module *generates* `talos_machine_secrets`, so a naive apply against a
  live cluster would regenerate PKI and re-bootstrap etcd. To adopt an
  already-running cluster without re-bootstrapping, import
  `talos_machine_secrets.this` (from your existing `secrets.yaml`) and
  `talos_machine_bootstrap.this` before the first apply — full runbook in
  [`UPGRADING.md` §Adopting an already-running cluster](../../../UPGRADING.md#adopting-an-already-running-cluster-no-re-bootstrap).
  Reproducible proof scripts: [`test/`](test/README.md).

## Related

- [`docs/adr-opentofu-cluster-lifecycle.md`](../../../docs/adr-opentofu-cluster-lifecycle.md) — why OpenTofu replaced the Makefile/5-axis path, and the consequences.
- [`Taskfile.yml`](../../../Taskfile.yml) — `task ci` validates this module (fmt-check + validate + lint).
