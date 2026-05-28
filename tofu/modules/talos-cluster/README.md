# Module `talos-cluster`

Turns a set of PXE-booted Talos **maintenance-mode** nodes into a bootstrapped
Kubernetes cluster, and returns the admin `kubeconfig` + `talosconfig`.

This is the single Talos provisioning module used by **both** bootstrap stages
(ADR-0003): the Stage-0 workstation root and the Stage-1 Crossplane
`tf.Workspace` call it with the identical variable contract. It is
**backend-agnostic** — it contains no `terraform { backend ... }` block; the
caller supplies the state backend (ADR-0006: local+encrypted for Stage 0,
DS720+ Garage S3 for Stage 1).

## Scope

In scope:

- Generate cluster PKI / machine secrets.
- Render controlplane + worker machine configs (with k8s/Talos version + caller patches).
- Apply config to each node, bootstrap etcd on the first controlplane.
- Output `kubeconfig` and `talosconfig`.

Out of scope (handled elsewhere):

- Hardware provisioning + PXE boot → `lifecycle/ipxe` + DHCP `next-server`.
- Cluster identity (node IPs, endpoint, install disk, registry mirrors) → caller via variables/patches.
- Day-2 platform components (Cilium, ArgoCD, …) → Crossplane Composition steps / ArgoCD.

Precondition: every node in `var.nodes` is reachable on the Talos API port,
i.e. already booted into Talos maintenance mode.

## What's in scope

| Stage | Module-managed |
|---|---|
| Day-1: cluster PKI | `talos_machine_secrets` |
| Day-1: machine config (per role) | `data.talos_machine_configuration` |
| Day-1: per-class installer image | `talos_image_factory_extensions_versions` → `talos_image_factory_schematic` → `talos_image_factory_urls` |
| Day-1: apply config to each node | `talos_machine_configuration_apply` (per-node hostname + install.image patch) |
| Day-1: etcd bootstrap | `talos_machine_bootstrap` (first controlplane only) |
| Day-1: kubeconfig + talosconfig | `talos_cluster_kubeconfig` + `data.talos_client_configuration` |
| **Day-2: Talos OS upgrade** | Bumping `talos_version` re-renders machine configs AND the per-class installer image from the Image Factory; `talos_machine_configuration_apply` rolls them out. |
| **Day-2: Extension changes** | Edit `extensions` map → schematic ID changes → installer image URL changes → `machine_configuration_apply` re-rolls nodes of the affected class. |

Most of the declarative lifecycle is in scope: one `tofu apply` reconciles
Talos version, system extensions and config patches. **One Day-2 op stays
out-of-band**: Kubernetes version upgrades. The `siderolabs/talos` provider
does not ship a `talos_cluster_kubernetes_upgrade` resource yet, so K8s
bumps are run with `talosctl upgrade-k8s --to <version>` against the
cluster. Bumping `kubernetes_version` in `cluster.yaml` keeps the
machine-config in sync; the actual rolling upgrade is the talosctl command.
This is a tracked follow-up for when the provider exposes the upgrade as
a resource.

## Usage

```hcl
module "dhq" {
  source = "git::https://github.com/Nosmoht/talos-platform-base.git//tofu/modules/talos-cluster?ref=v0.5.0"

  cluster_name       = "dhq"
  talos_version      = "v1.13.0"
  kubernetes_version = "v1.36.0"
  cluster_endpoint   = "https://dhq.devoba.de:6443"

  nodes = [
    { hostname = "dhq-cp-1", ip = "10.0.10.11", role = "controlplane", class = "standard" },
    { hostname = "dhq-w-1",  ip = "10.0.10.21", role = "worker",       class = "standard" },
    { hostname = "dhq-gpu-1", ip = "10.0.10.31", role = "worker",      class = "gpu" },
  ]

  # Image-Factory extensions per node class. Empty list = default installer.
  extensions = {
    standard = ["siderolabs/qemu-guest-agent"]
    gpu      = ["siderolabs/nvidia-container-toolkit", "siderolabs/nonfree-kmod-nvidia"]
    pi       = []
  }

  # Cluster-specific machine-config patches (install disk, registry mirrors, …)
  config_patches = [
    file("${path.module}/patches/install-disk.yaml"),
  ]
}
```

The caller is responsible for the `provider "talos" {}` block and the backend
configuration. Example Stage-0 root `versions.tf`:

```hcl
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    talos = { source = "siderolabs/talos", version = ">= 0.7.0, < 1.0.0" }
  }
  # Stage 0: local + encrypted (ADR-0006). Stage 1 supplies an s3 backend instead.
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
| `talos_version` | string | — | **Schema-pin**, v-prefixed semver (e.g. `v1.13.0`). Fixed at bootstrap; do NOT change. Drives `talos_machine_secrets` and `data.talos_machine_configuration`. |
| `talos_install_version` | string | `""` | **OS-version pin** — what's actually installed on the nodes. Defaults to `talos_version`. Bump for OS upgrades; `task talos:upgrade:cluster` reads it from tfplan JSON and runs `talosctl upgrade` per node. |
| `kubernetes_version` | string | — | v-prefixed semver, e.g. `v1.36.0`. Bump triggers out-of-band `talosctl upgrade-k8s` (taskfile). |
| `cluster_endpoint` | string | — | `https://…:6443` API endpoint / VIP |
| `nodes` | list(object) | — | `{hostname, ip, role, class?}`; role ∈ {controlplane, worker}; class defaults to `"standard"` and must exist in `extensions` |
| `extensions` | map(list(string)) | `{ standard = [], gpu = [], pi = [] }` | Image-Factory system extensions per node class. Empty list = default Talos installer. |
| `config_patches` | list(string) | `[]` | machine-config patches applied to all nodes |
| `controlplane_config_patches` | list(string) | `[]` | patches for controlplane nodes only |
| `worker_config_patches` | list(string) | `[]` | patches for worker nodes only |

## Outputs

| Name | Sensitive | Description |
|---|---|---|
| `kubeconfig` | yes | admin kubeconfig (raw YAML) |
| `talosconfig` | yes | talosctl client config (raw YAML) |
| `client_configuration` | yes | Talos client cert bundle for chaining |
| `cluster_endpoint` | no | echoed API endpoint |
| `controlplane_ips` | no | controlplane node IPs |
| `schematic_ids` | no | Image-Factory schematic ID per node class (audit + upgrade-task input via tfplan JSON) |
| `installer_images` | no | resolved `metal-installer` image URL per node class |
| `talos_install_version` | no | effective installer version (= `talos_install_version` or `talos_version` if unset) |

## Versions: schema-pin vs install-pin (Day-2-Pattern)

Inspired by `KPS/k8s.platform`. Two distinct versions:

- **`talos_version`** — the **machine-config schema** the cluster was bootstrapped against. Fixed for the lifetime of the cluster. Drives `talos_machine_secrets.talos_version`, `data.talos_machine_configuration.talos_version`.
- **`talos_install_version`** — the **installer-image tag** rendered into `machine.install.image` and into the Image-Factory installer URL. This is what's actually running on the nodes. Bump it to roll an OS upgrade.

For OS upgrades, the consumer-side workflow is:

1. Bump `cluster.yaml.talos.install_version` (e.g. `v1.13.0` → `v1.13.1`).
2. `tofu plan -out tfplan.bin && tofu show -json tfplan.bin > tfplan.json` — the new installer image URL and `schematic_id` per class flow through.
3. `task talos:upgrade:cluster` (consumer Taskfile) reads `tfplan.json`, iterates over the nodes, checks `talosctl version` against `tfplan.json:.variables.talos_install_version.value`, and runs `talosctl upgrade --image factory.talos.dev/installer/<schematic>:<version>` idempotently per node.
4. `tofu apply` afterwards updates the machine-config in state.

For Kubernetes upgrades, analogous: bump `cluster.yaml.kubernetes.version`, `task talos:upgrade:k8s` reads it from tfplan-JSON and runs `talosctl upgrade-k8s --to <version>` idempotently.

Tofu owns the declarative state (versions, schematics, machine-config); the consumer Taskfile owns the imperative talosctl execution. Both are driven by the same tfplan-JSON, so there's a single source of truth.

## Notes

- etcd is bootstrapped on the **first** controlplane in `nodes` only; input
  order is significant and preserved.
- The only node-specific config the module injects is the hostname patch.
  Everything cluster-specific comes from the caller's patches.

## Related ADRs

- [ADR-0003 — Bootstrap Staging](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0003-bootstrap-staging.md)
- [ADR-0006 — TF-State Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0006-tf-state-management.md)
- [ADR-0004 — Cluster-Lifecycle-Tooling](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0004-cluster-lifecycle-tooling.md)
