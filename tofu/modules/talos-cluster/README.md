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

## Usage

```hcl
module "dhq" {
  source = "git::https://github.com/Nosmoht/talos-platform-base.git//tofu/modules/talos-cluster?ref=v0.5.0"

  cluster_name       = "dhq"
  talos_version      = "v1.13.0"
  kubernetes_version = "v1.36.0"
  cluster_endpoint   = "https://dhq.devoba.de:6443"

  nodes = [
    { hostname = "dhq-cp-1", ip = "10.0.10.11", role = "controlplane" },
    { hostname = "dhq-w-1", ip = "10.0.10.21", role = "worker" },
    { hostname = "dhq-w-2", ip = "10.0.10.22", role = "worker" },
  ]

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
| `talos_version` | string | — | v-prefixed semver, e.g. `v1.13.0` |
| `kubernetes_version` | string | — | v-prefixed semver, e.g. `v1.36.0` |
| `cluster_endpoint` | string | — | `https://…:6443` API endpoint / VIP |
| `nodes` | list(object) | — | `{hostname, ip, role}`, role ∈ {controlplane, worker} |
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

## Notes

- etcd is bootstrapped on the **first** controlplane in `nodes` only; input
  order is significant and preserved.
- The only node-specific config the module injects is the hostname patch.
  Everything cluster-specific comes from the caller's patches.

## Related ADRs

- [ADR-0003 — Bootstrap Staging](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0003-bootstrap-staging.md)
- [ADR-0006 — TF-State Management](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0006-tf-state-management.md)
- [ADR-0004 — Cluster-Lifecycle-Tooling](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0004-cluster-lifecycle-tooling.md)
