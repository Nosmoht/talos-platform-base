# Homelab - Talos Kubernetes Cluster + ArgoCD GitOps

## Hard Constraints
- **Do NOT use SecureBoot (`metal-installer-secureboot`)** — causes boot loops; always use `metal-installer`
- **Do NOT use `debugfs=off`** kernel boot param — causes "failed to create root filesystem" boot loop
- **Use Gateway API, NOT Ingress** — no Ingress resources or Ingress controllers
- **Use EndpointSlices, NOT Endpoints** — Endpoints deprecated since Kubernetes v1.33.0
- **Commit and push every successful tested change immediately** — don't batch at end of session
- **NEVER `kubectl apply` ArgoCD-managed resources** — commit to git, push, let ArgoCD sync; only exception is one-time bootstrap of AppProjects (chicken-and-egg)
- **NEVER `kubectl apply` to deploy/rollout** — bootstrap manifests (`kubernetes/bootstrap/`) are the only exception

## Cluster Overview
- Talos v1.12.4, Kubernetes v1.35.0, Cilium v1.19.0 CNI
- Hardware: Lenovo ThinkCentre M910q (node-01..05), M920q (node-06), custom (node-gpu-01)
- 3 control plane nodes (node-01..03), 3 workers (node-04..06), 1 GPU worker (node-gpu-01)
- Network: 192.168.2.0/24, API VIP: 192.168.2.60, Gateway LB VIP: 192.168.2.70, gateway/DNS: 192.168.2.1
- External access: Fritz!Box → Raspberry Pi (192.168.2.200, DNAT+SNAT) → Cilium L2 VIP (192.168.2.70)
- L2 announcements: Cilium native (CiliumL2AnnouncementPolicy + CiliumLoadBalancerIPPool), NOT MetalLB
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
- App-of-apps: single root Application manages all child apps, projects, and resources
- Bootstrap: `make argocd-bootstrap` (Helm install + root AppProject + root app); ArgoCD self-manages after
- Sync-wave ordering: projects(-1) → infrastructure(0) → apps(1)
- Root app uses `root-bootstrap` AppProject (least-privilege); gateway-api resources are raw (no child Application)
- Bootstrap cilium manifest (`kubernetes/bootstrap/cilium/cilium.yaml`) includes GatewayClass — apply manually after changes
- Full patterns in `.claude/rules/kubernetes-gitops.md` — do NOT re-explore, read the rule

## Documentation
- All documentation in English (exception: `docs/kernel-tuning.md` is German, legacy)

## Context Architecture
- Domain-specific knowledge in `.claude/rules/` — auto-loaded by path glob (not always-loaded)
- Rules: `talos-config.md`, `talos-nodes.md`, `talos-image-factory.md`, `kubernetes-gitops.md`, `cilium-gateway-api.md`
- This CLAUDE.md kept minimal — only hard constraints, universal gotchas, and cluster overview
