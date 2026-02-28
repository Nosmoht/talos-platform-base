# Homelab - Talos Kubernetes Cluster + ArgoCD GitOps

## Hard Constraints
- **Do NOT use SecureBoot (`metal-installer-secureboot`)** — causes boot loops; always use `metal-installer`
- **Do NOT use `debugfs=off`** kernel boot param — causes "failed to create root filesystem" boot loop
- **Use Gateway API, NOT Ingress** — no Ingress resources or Ingress controllers
- **Use EndpointSlices, NOT Endpoints** — Endpoints deprecated since Kubernetes v1.33.0

## Cluster Overview
- Talos v1.12.4, Kubernetes v1.35.0, Cilium v1.19.0 CNI
- Hardware: Lenovo ThinkCentre M910q (node-01..05), M920q (node-06), custom (node-gpu-01)
- 3 control plane nodes (node-01..03), 3 workers (node-04..06), 1 GPU worker (node-gpu-01)
- Network: 192.168.2.0/24, VIP: 192.168.2.60, gateway/DNS: 192.168.2.1
- Storage: LINSTOR/Piraeus Operator CSI (piraeus-datastore namespace), DRBD replication
- Runtime: gVisor available as containerd runtime handler (all nodes)
- GitOps: ArgoCD with Kustomize base/overlays, multi-cluster ready

## Required Tools
`talosctl`, `kubectl`, `kubectl linstor`, `make`, `sops` (AGE backend), `yq`, `curl`, `jq`

## Talos Config — Critical Rules
- Patches applied: `common.yaml` → role patch → node patch (later overrides scalars)
- `--config-patch` APPENDS arrays — don't duplicate entries across common and role patches
- Strategic merge on interfaces APPENDS arrays — doesn't merge by deviceSelector
- Install images injected via `--config-patch` from Makefile (not in patch files)
- `talos/secrets.yaml` is SOPS-encrypted; auto-decrypted during config generation

## Talos Operations — Universal Gotchas
- `talosctl apply-config --dry-run` fails via VIP — use explicit `-e <node-ip>` endpoint
- Always use `talosctl -n <ip> -e <ip>` when VIP or default endpoints may be down
- `talosctl apply-config` with unchanged config is a no-op
- `kubectl delete pod` on static pods only recreates mirror pod — real container keeps running
- kube-apiserver `$(POD_IP)` env var frozen at container creation; survives kubelet restarts
- `talosctl service etcd restart` NOT supported — etcd can't be restarted via API
- Stuck "shutting down" nodes (D-state on DRBD): only fixable with physical power cycle
- Etcd member removed: `talosctl reset --system-labels-to-wipe EPHEMERAL --reboot --graceful=false`
- Learner promotion automatic (~1-2 min) after EPHEMERAL reset
- Maintenance mode `--insecure` only supports: `version`, `get disks`, `apply-config`
- `talosctl disks` deprecated — use `get disks`, `get systemdisk`, `get discoveredvolumes`

## ArgoCD Pattern
- Bootstrap: `make argocd-bootstrap` (ArgoCD + AppProjects + Applications)
- Application CRs co-located in `overlays/homelab/infrastructure/<component>/application.yaml`
- Multi-source Helm with `$values` ref; AppProjects: `infrastructure` and `apps`

## Documentation
- All documentation in English (exception: `docs/kernel-tuning.md` is German, legacy)

## Context Architecture
- Domain-specific knowledge in `.claude/rules/` — auto-loaded by path glob (not always-loaded)
- Rules: `talos-config.md`, `talos-nodes.md`, `talos-image-factory.md`, `kubernetes-gitops.md`, `cilium-gateway-api.md`
- This CLAUDE.md kept minimal — only hard constraints, universal gotchas, and cluster overview
