# Homelab - Talos Kubernetes Cluster + ArgoCD GitOps

## Hard Constraints
- **Do NOT use SecureBoot (`metal-installer-secureboot`)** — causes boot loops; always use `metal-installer`
- **Do NOT use `debugfs=off`** kernel boot param — causes "failed to create root filesystem" boot loop
- **Use Gateway API, NOT Ingress** — no Ingress resources or Ingress controllers
- **Use EndpointSlices, NOT Endpoints** — Endpoints deprecated since Kubernetes v1.33.0
- **Commit and push every successful tested change immediately** — don't batch at end of session
- **NEVER `kubectl apply` ArgoCD-managed resources** — commit to git, push, let ArgoCD sync; only exception is one-time bootstrap of AppProjects (chicken-and-egg)
- **NEVER `kubectl apply` to deploy/rollout** — bootstrap manifests (`kubernetes/bootstrap/`) are the only exception
- **Use Kubernetes recommended labels** on all resources — `app.kubernetes.io/name`, `app.kubernetes.io/instance`, `app.kubernetes.io/version`, `app.kubernetes.io/component`, `app.kubernetes.io/part-of`, `app.kubernetes.io/managed-by` (per https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/)

## Cluster Overview
- Talos v1.12.4, Kubernetes v1.35.0, Cilium v1.19.0 CNI
- Hardware: Lenovo ThinkCentre M910q (node-01..05), M920q (node-06), custom (node-gpu-01)
- 3 control plane nodes (node-01..03), 3 workers (node-04..06), 1 GPU worker (node-gpu-01)
- Network: 192.168.2.0/24, API VIP: 192.168.2.60, Gateway LB VIP: 192.168.2.70, gateway/DNS: 192.168.2.1
- External access: Fritz!Box → Raspberry Pi (192.168.2.200, DNAT+SNAT) → Cilium L2 VIP (192.168.2.70)
- L2 announcements: Cilium native (CiliumL2AnnouncementPolicy + CiliumLoadBalancerIPPool), NOT MetalLB
- Storage: LINSTOR/Piraeus Operator CSI (piraeus-datastore namespace), DRBD replication, NVMe nodes selected via NFD label `feature.node.kubernetes.io/storage-nvme.present=true`
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
- **Cilium deployed via Talos `extraManifests`** (controlplane patch → GitHub raw URL) — reconcile drift with `make talos-upgrade-k8s`, NOT `kubectl apply`
- `talosctl upgrade-k8s` requires `-n <node-ip> -e <node-ip>` — `--endpoint` is a different flag (proxy endpoint)

## ArgoCD Pattern
- App-of-apps: single root Application manages all child apps, projects, and resources
- Bootstrap: `make argocd-bootstrap` (Helm install + root AppProject + root app); ArgoCD self-manages after
- Sync-wave ordering: projects(-1) → infrastructure(0) → apps(1)
- Root app uses `root-bootstrap` AppProject (least-privilege); gateway-api resources are raw (no child Application)
- Bootstrap cilium manifest (`kubernetes/bootstrap/cilium/cilium.yaml`) includes GatewayClass — reconcile with `make talos-upgrade-k8s` (re-applies extraManifests)
- Full patterns in `.claude/rules/kubernetes-gitops.md` — do NOT re-explore, read the rule

## ArgoCD Operations — Gotchas
- **Immutable selector on chart upgrade**: Helm chart upgrades changing Deployment `spec.selector.matchLabels` require deleting the Deployment (and often Service) first — Kubernetes rejects selector patches; also check Service selector for stale labels from three-way merge
- **Exhausted auto-sync retries**: When retries exhaust for a fixed revision, ArgoCD stops ("will not retry"); clear `/status/operationState` via patch then refresh to allow fresh auto-sync
- **Stale revision in auto-sync retries**: Auto-sync locks to the git revision at the time it started; pushing fixes won't help until retries exhaust. Restart the application-controller pod (`kubectl delete pod -n argocd -l app.kubernetes.io/component=application-controller`) to force re-resolution of branch HEAD
- **SharedResourceWarning (Namespace)**: When upstream sources include a Namespace resource, don't also define it in root app — use `spec.source.kustomize.patches` on the child Application to add PSA/homelab labels instead
- **OCI Helm repos in ArgoCD**: Use `repoURL: ghcr.io/<org>/<repo>` (no `oci://` prefix), `chart: <name>`. AppProject `sourceRepos` needs glob pattern: `ghcr.io/<org>/<repo>*`
- **Hook Job completed but operationState stuck**: If a hook Job completes and is deleted (DeletePolicy) before ArgoCD observes completion, sync hangs. Clear `/status/operationState` via patch then refresh

## Cilium NetworkPolicy Gotchas
- **Alertmanager mesh requires TCP + UDP on port 9094** — memberlist gossip protocol uses both; TCP-only CNP causes cluster split-brain
- **kube-prometheus-stack ServiceMonitors have sidecar ports** — alertmanager has `reloader-web:8080` (config-reloader), check `kubectl get servicemonitor <name> -o yaml` for all endpoint ports before writing CNPs
- `fromEntities: ["world"]` does NOT match Cilium's external Envoy proxy traffic — use `fromEntities: ["ingress"]` for Gateway API ingress
- Cilium external Envoy proxy (`external-envoy-proxy: true`) uses `reserved:ingress` identity (ID 8), not `world`
- **kube-apiserver port after DNAT**: `toEntities: ["kube-apiserver"]` with `port: "443"` won't work — Cilium kube-proxy replacement DNATs ClusterIP 10.96.0.1:443 → endpoint:6443 before policy evaluation. Use `port: "6443"` in CNP egress rules
- **K8s NetworkPolicy + CiliumNetworkPolicy AND semantics**: When both policy types select the same pod, traffic must be allowed by BOTH. Don't use K8s default-deny NetworkPolicy alongside CiliumNetworkPolicies — per-component CNPs already create implicit default-deny for selected endpoints
- **ArgoCD hook jobs and CNPs**: Helm chart hook Jobs (e.g. admission-create/patch) run BEFORE resources are synced — CNPs in `resources/` can't unblock them. Ensure CNP endpointSelectors cover hook job pod labels, and apply CNP fixes live when debugging chicken-and-egg
- **Debugging policy drops**: Use `hubble observe --from-ip <pod-ip>` for reliable drop visibility — `cilium-dbg monitor --type drop` can miss drops. Cilium CLI inside agent pods is `cilium-dbg`, not `cilium`
- After pushing changes, force ArgoCD refresh: `kubectl annotate application <app> -n argocd argocd.argoproj.io/refresh=hard --overwrite`

## Documentation
- All documentation in English (exception: `docs/kernel-tuning.md` is German, legacy)

## Context Architecture
- Domain-specific knowledge in `.claude/rules/` — auto-loaded by path glob (not always-loaded)
- Rules: `talos-config.md`, `talos-nodes.md`, `talos-image-factory.md`, `kubernetes-gitops.md`, `cilium-gateway-api.md`, `argocd-operations.md`, `manifest-quality.md`, `talos-operations.md`
- Daily skills: `gitops-health-triage`, `talos-node-maintenance`, `cilium-policy-debug`, plus hardware/kernel skills under `.claude/skills/`
- Delegation agents: `gitops-operator`, `talos-sre`, `platform-reliability-reviewer` under `.claude/agents/`
- This CLAUDE.md kept minimal — only hard constraints, universal gotchas, and cluster overview
