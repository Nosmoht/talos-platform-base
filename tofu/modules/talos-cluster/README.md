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
- **Deliver ArgoCD** as a Talos `cluster.inlineManifest` (Layer-1 substrate, C4 layer model) — opt-out via `deploy_argocd = false`.
- Output `kubeconfig` and `talosconfig`.

Out of scope (caller / elsewhere):

- Hardware provisioning + PXE boot (DHCP `next-server`, iPXE).
- Cluster identity (node IPs, endpoint, NTP, install disk, registry mirrors) → caller via variables/patches.
- Day-2 platform components (Cilium, cert-manager, …) and **ArgoCD steady-state** (RBAC, OIDC, TLS cert, app-of-apps) → ArgoCD GitOps self-management. The module only seeds the *bootstrap* ArgoCD install.
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
| Day-1: ArgoCD bootstrap | `data.helm_template.argocd` rendered into `cluster.inlineManifests` (namespace → `sops-age-key` Secret for ksops → ArgoCD manifest). Opt-out: `deploy_argocd = false`. |
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
app — so the module seeds it, exactly like KPS renders Cilium. There is **no**
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
`ClusterIP` + `insecure`, CRDs install+keep, the ksops initContainer. The
steady-state (TLS cert via a `ClusterIssuer` that doesn't exist yet at
bootstrap, RBAC, OIDC, the app-of-apps) is owned by **ArgoCD self-management**
in the consumer repo. Override the whole values blob with
`argocd_values_override` if a cluster needs a different bootstrap shape.

> The `sops_age_key` lands in Tofu state and in the controlplane machine config
> — both are already sensitive (state holds PKI; machine config is a secret).
> The chosen backend **must** be encrypted regardless. Set `deploy_argocd =
> false` for a cluster that wires ArgoCD some other way; then `sops_age_key` is
> not required.

**Health gate.** `data.talos_cluster_health` blocks `tofu apply` after bootstrap
until etcd has quorum, every node is Ready and the apiserver answers (up to
`cluster_health_timeout`, default `10m`). Without it, `apply` would return the
instant the bootstrap call is *issued* — long before the apiserver is reachable
or ArgoCD's pods exist. The `kubeconfig`/`talosconfig`/`cluster_health` outputs
`depends_on` it, so a consumer that writes those into secret storage only ever
receives credentials for a cluster that is genuinely **online**.

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
