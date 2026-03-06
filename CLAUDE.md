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

## Platform Network Interface (PNI) — Mandatory Workflow
- **Use PNI first for platform service connectivity** — do not start with ad-hoc per-namespace CNPs when integrating with managed platform components.
- **PNI contract for consumer namespaces**:
  - `platform.io/network-interface-version: v1`
  - `platform.io/network-profile: restricted|managed|privileged`
  - capability opt-in via `platform.io/consume.<capability>: "true"`
- **`network-profile` alone is never sufficient** for core service access; require explicit `consume.<capability>` labels.
- **Provider-reserved labels are platform-owned only** (never set in consumer manifests): `platform.io/provider`, `platform.io/managed-by`, `platform.io/capability`.
- **If a consumer refuses PNI**, they must ship and own self-managed CNP/KNP behavior and validation; document this explicitly in PR notes.
- **When adding new platform integrations**, update `docs/platform-network-interface.md` capability catalog and contract examples in the same change.
- **Keep policy ownership in infrastructure paths** (`kubernetes/overlays/homelab/infrastructure/...`); do not push operator-namespace policy ownership to consumer apps.

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
- **Cilium deployed via Talos `extraManifests`** (controlplane patch → GitHub raw URL) — reconcile drift with `make -C talos upgrade-k8s`, NOT `kubectl apply`
- `talosctl upgrade-k8s` requires `-n <node-ip> -e <node-ip>` — `--endpoint` is a different flag (proxy endpoint)

## ArgoCD Pattern
- App-of-apps: single root Application manages all child apps, projects, and resources
- Bootstrap: `make argocd-bootstrap` (Helm install + root AppProject + root app); ArgoCD self-manages after
- Sync-wave ordering: projects(-1) → infrastructure(0) → apps(1)
- Root app uses `root-bootstrap` AppProject (least-privilege); gateway-api resources are raw (no child Application)
- Bootstrap cilium manifest (`kubernetes/bootstrap/cilium/cilium.yaml`) includes GatewayClass — reconcile with `make -C talos upgrade-k8s` (re-applies extraManifests)
- Full patterns in `.claude/rules/kubernetes-gitops.md` — do NOT re-explore, read the rule

## ArgoCD Operations — Gotchas
- **Immutable selector on chart upgrade**: Helm chart upgrades changing Deployment `spec.selector.matchLabels` require deleting the Deployment (and often Service) first — Kubernetes rejects selector patches; also check Service selector for stale labels from three-way merge
- **Exhausted auto-sync retries**: When retries exhaust for a fixed revision, ArgoCD stops ("will not retry"); clear `/status/operationState` via patch then refresh to allow fresh auto-sync
- **Stale revision in auto-sync retries**: Auto-sync locks to the git revision at the time it started; pushing fixes won't help until retries exhaust. Restart the application-controller pod (`kubectl delete pod -n argocd -l app.kubernetes.io/component=application-controller`) to force re-resolution of branch HEAD
- **SharedResourceWarning (Namespace)**: When upstream sources include a Namespace resource, don't also define it in root app — use `spec.source.kustomize.patches` on the child Application to add PSA/homelab labels instead
- **OCI Helm repos in ArgoCD**: Use `repoURL: ghcr.io/<org>/<repo>` (no `oci://` prefix), `chart: <name>`. AppProject `sourceRepos` needs glob pattern: `ghcr.io/<org>/<repo>*`
- **Hook Job completed but operationState stuck**: If a hook Job completes and is deleted (DeletePolicy) before ArgoCD observes completion, sync hangs. Clear `/status/operationState` via patch then refresh
- **AppProject permission can block valid app syncs**: If an app shows `one or more synchronization tasks are not valid`, inspect denied kinds in Application status and add them to the owning AppProject `spec.clusterResourceWhitelist` in Git (then sync `root`). Example needed here: `cilium.io/CiliumClusterwideNetworkPolicy` for `infrastructure` project.
- **Do not stop at `OutOfSync` label-only checks**: Always check `status.operationState.message` and per-resource sync results to find the first hard blocker.

## Monitoring & Dashboard Gotchas
- **Kubernetes / Scheduler dashboard "No data" has two independent causes**:
  1. Scheduler not reachable: on Talos control planes, `kube-scheduler` may run with `--bind-address=127.0.0.1`; Prometheus scrapes on `:10259` then fail with `connection refused`.
  2. Dashboard query filtering: dashboard JSON may filter by `cluster="$cluster"` while metrics have no `cluster` label.
- **Permanent scheduler metrics fix (Talos)**: set `cluster.scheduler.extraArgs.bind-address: 0.0.0.0` in `talos/patches/controlplane.yaml`, regenerate controlplane configs, apply to all control-plane nodes.
- **Permanent dashboard fix**: use a repo-managed dashboard JSON without `$cluster` variable/matchers; wire via `configMapGenerator` with `grafana_dashboard: "1"` and `disableNameSuffixHash: true`.
- **Verify scheduler observability quickly**:
  - `sum(up{job="kube-scheduler"})` should be `3` (for 3 control-plane nodes).
  - `count({__name__=~"scheduler_.*",job="kube-scheduler"})` should be non-zero.
- **Grafana sidecar import verification**: check `deploy/monitoring-grafana` container `grafana-sc-dashboard` logs for `Writing /tmp/dashboards/<dashboard>.json`.
- **Kustomize build in this repo needs ksops plugins**: use `kustomize build --enable-alpha-plugins --enable-exec ...` for local validation; default build fails with `external plugins disabled`.

## Cilium NetworkPolicy Gotchas
- **Alertmanager mesh requires TCP + UDP on port 9094** — memberlist gossip protocol uses both; TCP-only CNP causes cluster split-brain
- **kube-prometheus-stack ServiceMonitors have sidecar ports** — alertmanager has `reloader-web:8080` (config-reloader), check `kubectl get servicemonitor <name> -o yaml` for all endpoint ports before writing CNPs
- `fromEntities: ["world"]` does NOT match Cilium's external Envoy proxy traffic — use `fromEntities: ["ingress"]` for Gateway API ingress
- Cilium external Envoy proxy (`external-envoy-proxy: true`) uses `reserved:ingress` identity (ID 8), not `world`
- **kube-apiserver port after DNAT**: `toEntities: ["kube-apiserver"]` with `port: "443"` won't work — Cilium kube-proxy replacement DNATs ClusterIP 10.96.0.1:443 → endpoint:6443 before policy evaluation. Use `port: "6443"` in CNP egress rules
- **K8s NetworkPolicy + CiliumNetworkPolicy AND semantics**: When both policy types select the same pod, traffic must be allowed by BOTH. Don't use K8s default-deny NetworkPolicy alongside CiliumNetworkPolicies — per-component CNPs already create implicit default-deny for selected endpoints
- **ArgoCD hook jobs and CNPs**: Helm chart hook Jobs (e.g. admission-create/patch) run BEFORE resources are synced — CNPs in `resources/` can't unblock them. Ensure CNP endpointSelectors cover hook job pod labels, and apply CNP fixes live when debugging chicken-and-egg
- **hostNetwork pods (e.g. linstor-csi-node) have host identity** — don't write CNPs for them; their traffic to other pods appears as `fromEntities: ["host"]`
- **Cross-namespace Prometheus scraping** — when adding CNPs to a new namespace with ServiceMonitors, also add egress rule in `cnp-prometheus.yaml` for the target namespace/ports
- **Prefer identity/capability-based selectors over namespace name allowlists** — model connectivity through PNI capabilities and provider/consumer identities, not one-off namespace tuples
- **DRBD satellite mesh uses port range 7000-7999** — LINSTOR assigns per-resource; use Cilium `endPort` for ranges
- **Debugging policy drops**: Use `hubble observe --from-ip <pod-ip>` for reliable drop visibility — `cilium-dbg monitor --type drop` can miss drops. Cilium CLI inside agent pods is `cilium-dbg`, not `cilium`
- After pushing changes, force ArgoCD refresh: `kubectl annotate application <app> -n argocd argocd.argoproj.io/refresh=hard --overwrite`

## Kyverno Validation
- After editing Kyverno `ClusterPolicy` manifests, run `make validate-kyverno-policies` before commit to catch invalid variable/JMESPath expressions via server-side dry-run.

## Documentation
- All documentation in English (exception: `docs/kernel-tuning.md` is German, legacy)

## Context Architecture
- Domain-specific knowledge in `.claude/rules/` — auto-loaded by path glob (not always-loaded)
- Rules: `talos-config.md`, `talos-nodes.md`, `talos-image-factory.md`, `kubernetes-gitops.md`, `cilium-gateway-api.md`, `argocd-operations.md`, `manifest-quality.md`, `talos-operations.md`
- Daily skills: `gitops-health-triage`, `talos-node-maintenance`, `cilium-policy-debug`, plus hardware/kernel skills under `.claude/skills/`
- Delegation agents: `gitops-operator`, `talos-sre`, `platform-reliability-reviewer` under `.claude/agents/`
- This CLAUDE.md kept minimal — only hard constraints, universal gotchas, and cluster overview
