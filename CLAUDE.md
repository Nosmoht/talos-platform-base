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
Cluster-specific details (nodes, IPs, network topology, hardware) are defined in `.claude/environment.yaml`.
See `.claude/environment.example.yaml` for the schema. Software versions are pinned in `talos/versions.mk`.
- External ingress: ingress-front macvlan (stable MAC `02:42:c0:a8:02:46`, IP `192.168.2.70`) → nginx L4 upstream via net1 (macvlan) to remote worker nodes → embedded Envoy on hostNetwork (ports 80/443); Cilium `envoy.enabled: false` + `gatewayAPI.hostNetwork.enabled: true`; see `docs/postmortem-gateway-403-hairpin.md`
- Storage: LINSTOR/Piraeus Operator CSI (piraeus-datastore namespace), DRBD replication, NVMe nodes selected via NFD label `feature.node.kubernetes.io/storage-nvme.present=true`
- Runtime: gVisor available as containerd runtime handler (all nodes)
- Encryption: Cilium WireGuard strict mode (all inter-node pod traffic encrypted, PodCIDR `10.244.0.0/16`)
- Observability: Hubble dynamic flow export (dropped flows + DNS flows to `/var/run/cilium/hubble/`)
- Policy enforcement: Kyverno PNI policies in Enforce mode (namespace contract, reserved labels, capability validation)
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
- **Stale schematic IDs**: Editing `talos/talos-factory-schematic*.yaml` without re-running `make -C talos schematics` leaves `.schematic-ids.mk` stale — upgrades use the wrong image (missing boot params/extensions). `make -C talos validate-schematics` detects drift; `upgrade-*` Makefile targets run it automatically
- `talosctl apply-config --dry-run` fails via VIP — use explicit `-e <node-ip>` endpoint
- Always use `talosctl -n <ip> -e <ip>` when VIP or default endpoints may be down
- `talosctl apply-config` with unchanged config is a no-op
- `kubectl delete pod` on static pods only recreates mirror pod — real container keeps running
- kube-apiserver `$(POD_IP)` env var frozen at container creation; survives kubelet restarts
- `talosctl service etcd restart` NOT supported — etcd can't be restarted via API
- Stuck "shutting down" nodes (D-state on DRBD): only fixable with physical power cycle
- **Upgrade sequence lock stuck on CSI unmount**: DRBD CSI volumes in D-state during `unmountPodMounts` phase deadlock the upgrade with no API recovery — `talosctl reboot`, `upgrade --force`, and `reset` all fail with "locked"; only fixable with physical power cycle. Mitigate by running `kubectl drain <node> --delete-emptydir-data --ignore-daemonsets --timeout=120s` before `talosctl upgrade` on DRBD nodes
- Etcd member removed: `talosctl reset --system-labels-to-wipe EPHEMERAL --reboot --graceful=false`
- Learner promotion automatic (~1-2 min) after EPHEMERAL reset
- Maintenance mode `--insecure` only supports: `version`, `get disks`, `apply-config`
- `talosctl disks` deprecated — use `get disks`, `get systemdisk`, `get discoveredvolumes`
- **Cilium deployed via Talos `extraManifests`** (controlplane patch → GitHub raw URL) — reconcile drift with `make -C talos upgrade-k8s`, NOT `kubectl apply`
- **`extraManifests` does NOT garbage-collect**: removing resources from `cilium.yaml` does NOT delete them from the cluster after `upgrade-k8s` — orphans must be `kubectl delete`d manually
- **Apply Talos configs BEFORE `upgrade-k8s`**: `talosctl upgrade-k8s` reads extraManifests URLs from the LIVE node machine config. If you change the cache-bust URL in `controlplane.yaml` and `gen-configs`, you MUST `talosctl apply-config` to all CP nodes first — otherwise `upgrade-k8s` downloads from the old cached URL
- `talosctl upgrade-k8s` requires `-n <node-ip> -e <node-ip>` — `--endpoint` is a different flag (proxy endpoint)
- **`upgrade-k8s` does NOT reliably update existing ConfigMaps or create new resources**: When adding new ConfigMaps (e.g., `cilium-flowlog-config`) or adding keys to existing ones (e.g., `enable-wireguard` in `cilium-config`), `upgrade-k8s` shows "no changes" and skips them. Workaround: extract the resource from the rendered manifest with `yq` and `kubectl apply --server-side --force-conflicts --field-manager=talos -f -`, then restart the DaemonSet
- **`hubble-generate-certs` Job blocks `upgrade-k8s`**: The Job has a hash-based name (`hubble-generate-certs-b36ef54b9b`); if it already exists from a previous run, `upgrade-k8s` fails with immutable field error. Delete all matching Jobs before running: `kubectl delete job -n kube-system -l k8s-app=hubble-generate-certs`

## ArgoCD Pattern
- App-of-apps: single root Application manages all child apps, projects, and resources
- Bootstrap: `make argocd-bootstrap` (Helm install + root AppProject + root app); ArgoCD self-manages after
- Sync-wave ordering: projects(-1) → infrastructure(0) → apps(1)
- Root app uses `root-bootstrap` AppProject (least-privilege); gateway-api is its own Application (project: infrastructure, sync-wave: 4, dest: default ns)
- Bootstrap cilium manifest (`kubernetes/bootstrap/cilium/cilium.yaml`) includes GatewayClass — reconcile with `make -C talos upgrade-k8s` (re-applies extraManifests)
- Full patterns in `.claude/rules/kubernetes-gitops.md` — do NOT re-explore, read the rule

## ArgoCD Operations — Gotchas
- **Immutable selector on chart upgrade**: Helm chart upgrades changing Deployment `spec.selector.matchLabels` require deleting the Deployment (and often Service) first — Kubernetes rejects selector patches; also check Service selector for stale labels from three-way merge
- **Exhausted auto-sync retries**: When retries exhaust for a fixed revision, ArgoCD stops ("will not retry"); clear `/status/operationState` via patch then refresh to allow fresh auto-sync
- **Stale revision in auto-sync retries**: Auto-sync locks to the git revision at the time it started; pushing fixes won't help until retries exhaust. Fix: `argocd app terminate-op <app>` then clear `/status/operationState` via patch — this is less disruptive than restarting the application-controller pod
- **SharedResourceWarning (Namespace)**: When upstream sources include a Namespace resource, don't also define it in root app — use `spec.source.kustomize.patches` on the child Application to add PSA/homelab labels instead
- **OCI Helm repos in ArgoCD**: Use `repoURL: ghcr.io/<org>/<repo>` (no `oci://` prefix), `chart: <name>`. AppProject `sourceRepos` needs glob pattern: `ghcr.io/<org>/<repo>*`
- **Hook Job completed but operationState stuck**: If a hook Job completes and is deleted (DeletePolicy) before ArgoCD observes completion, sync hangs. Clear `/status/operationState` via patch then refresh
- **AppProject permission can block valid app syncs**: If an app shows `one or more synchronization tasks are not valid`, inspect denied kinds in Application status and add them to the owning AppProject `spec.clusterResourceWhitelist` in Git (then sync `root`). Example needed here: `cilium.io/CiliumClusterwideNetworkPolicy` for `infrastructure` project.
- **Do not stop at `OutOfSync` label-only checks**: Always check `status.operationState.message` and per-resource sync results to find the first hard blocker.
- **Multus DaemonSet `prune: false`**: Multus has `prune: false` (safety — orphaned CNI config blocks pod creation). Changing init containers (e.g., adding CNI plugins) won't take effect until `kubectl rollout restart daemonset kube-multus-ds -n kube-system`
- **Gateway `Programmed: False` blocks root app sync**: Cilium bug #42786 causes Gateway to show `Programmed: False` with hostNetwork (ClusterIP Service gets no addresses). ArgoCD treats this as unhealthy and blocks sync at the Gateway's sync-wave. Fix: add `argocd.argoproj.io/sync-options: SkipHealthCheck=true` annotation on the Gateway resource
- **Removing `commonAnnotations` drops sync-wave from raw resources**: When extracting raw resources from a kustomization that used `commonAnnotations` for sync-wave, the individual resources lose their wave and default to wave 0. Either add per-resource `argocd.argoproj.io/sync-wave` annotations or move resources into a child Application
- **Migrating resources between ArgoCD Applications**: When transferring resource ownership from one Application to another, add `argocd.argoproj.io/sync-options: Prune=false` to the resources before removing them from the old Application's kustomization. Otherwise `prune: true` deletes them before the new Application recreates them, causing an outage window

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
- **`cilium.l7policy` filter applies to ALL eBPF identity-marked traffic** — not just TPROXY-redirected traffic. Any pod traffic via eth0 (Cilium CNI) gets identity-marked by eBPF. Only external LAN traffic (entering via physical NIC, no eBPF marking) bypasses the filter. This is why macvlan (net1) to remote nodes works but eth0 to the same host does not.
- **Embedded Envoy needs `NET_BIND_SERVICE` + `keepCapNetBindService`** — for hostNetwork Gateway ports 80/443. Both must be set: `NET_BIND_SERVICE` in `securityContext.capabilities.ciliumAgent` AND `envoy.securityContext.capabilities.keepCapNetBindService: true`. Silent failure without either — no error, no LISTEN socket.
- **"Per-Gateway Deployments" do NOT exist in Cilium 1.19** — Gateway listeners are CiliumEnvoyConfig with `nodeSelector`, processed by embedded Envoy in matching cilium-agent pods. No Deployment is created.
- **kube-vip does NOT provide virtual MAC** — uses node's real MAC via gratuitous ARP (same as Cilium L2 announcements). Only keepalived `use_vmac` provides RFC 5798 virtual MAC (`00:00:5e:00:01:{VRID}`)
- `fromEntities: ["ingress"]` matches Cilium's `reserved:ingress` identity (ID 8) for Gateway API backend pods
- **kube-apiserver port after DNAT**: `toEntities: ["kube-apiserver"]` with `port: "443"` won't work — Cilium kube-proxy replacement DNATs ClusterIP 10.96.0.1:443 → endpoint:6443 before policy evaluation. Use `port: "6443"` in CNP egress rules
- **K8s NetworkPolicy + CiliumNetworkPolicy AND semantics**: When both policy types select the same pod, traffic must be allowed by BOTH. Don't use K8s default-deny NetworkPolicy alongside CiliumNetworkPolicies — per-component CNPs already create implicit default-deny for selected endpoints
- **ArgoCD hook jobs and CNPs**: Helm chart hook Jobs (e.g. admission-create/patch) run BEFORE resources are synced — CNPs in `resources/` can't unblock them. Ensure CNP endpointSelectors cover hook job pod labels, and apply CNP fixes live when debugging chicken-and-egg
- **hostNetwork pods (e.g. linstor-csi-node) have host identity** — don't write CNPs for them; their traffic to other pods appears as `fromEntities: ["host"]`
- **Cross-namespace Prometheus scraping** — when adding CNPs to a new namespace with ServiceMonitors, also add egress rule in `cnp-prometheus.yaml` for the target namespace/ports
- **Prefer identity/capability-based selectors over namespace name allowlists** — model connectivity through PNI capabilities and provider/consumer identities, not one-off namespace tuples
- **CCNP on namespaces without existing CNPs activates implicit default-deny** — adding a PNI capability label to a namespace that has no CiliumNetworkPolicy/CiliumClusterwideNetworkPolicy selecting its pods will activate Cilium's implicit default-deny for those pods; do not opt in `privileged` namespaces (e.g. `argocd`) without shipping a full CNP set first
- **Gateway-backend `toPorts` must use container ports (post-DNAT)** — Cilium evaluates `toPorts` after kube-proxy DNAT; use the pod's container port (e.g. `8080` for ArgoCD), not the Service port (e.g. `80`)
- **DRBD satellite mesh uses port range 7000-7999** — LINSTOR assigns per-resource; use Cilium `endPort` for ranges
- **WireGuard strict mode `cidr: ""` causes fatal crash** — Cilium agent dies with `Cannot parse CIDR from --encryption-strict-egress-cidr option: no '/'`. Always set explicit PodCIDR (`10.244.0.0/16`) or omit the field from Helm values entirely (but Helm renders empty string by default, so set it explicitly)
- **WireGuard `allowRemoteNodeIdentities: true` required for hostNetwork pods** — `linstor-csi-node` and other hostNetwork pods use `reserved:remote-node` identity for cross-node traffic; setting `false` breaks DRBD replication and CSI volume mounts
- **WireGuard does NOT encrypt macvlan (external ingress) traffic** — traffic entering via physical NIC (ingress-front → nginx → remote worker) is outside Cilium's datapath; only pod-to-pod traffic through eth0/cilium_wg0 is encrypted
- **WireGuard two-pass deployment**: Enable with `strictMode.enabled: false` first, verify all tunnels (7 peers per node), then enable strict mode. Rolling restart with strict mode ON causes traffic blackhole between restarted (WireGuard ON) and not-yet-restarted (WireGuard OFF) nodes
- **Hubble dynamic export `includeFilters` uses proto field names** — correct: `verdict: [DROPPED]`, `protocol: [DNS]`. Incorrect: `fields: [{name: verdict, values: [DROPPED]}]` (the `fields` wrapper is NOT valid FlowFilter proto format despite appearing in some docs)
- **Hubble dynamic export config is hot-reloadable** — updating the `cilium-flowlog-config` ConfigMap triggers automatic reconfiguration without pod restart (agent logs: `Configuring Hubble event exporter`)
- **Debugging policy drops**: Use `hubble observe --from-ip <pod-ip>` for reliable drop visibility — `cilium-dbg monitor --type drop` can miss drops. Cilium CLI inside agent pods is `cilium-dbg`, not `cilium`
- After pushing changes, force ArgoCD refresh: `kubectl annotate application <app> -n argocd argocd.argoproj.io/refresh=hard --overwrite`

## Macvlan + Cilium eBPF Interaction Gotchas
- **Macvlan bridge mode blocks same-host pod↔host traffic** — kernel limitation; pod cannot reach its own node's LAN IP via net1 (macvlan). Traffic to remote LAN hosts works fine.
- **Pod routing table conflict**: `192.168.2.0/24 dev net1` takes precedence over Cilium eth0 default route for all LAN traffic. Adding a `/32` host route via eth0 requires `NET_ADMIN` capability, which violates `baseline` Pod Security Admission.
- **Proxy traffic must go via macvlan to REMOTE nodes** to bypass eBPF identity marking. The ingress-front nginx uses a static upstream with all worker node LAN IPs; the local node's IP fails silently (macvlan bridge isolation) and nginx upstream failover routes to a remote node where traffic arrives as external LAN traffic (no eBPF, no L7 filter).
- **ConfigMap subPath mounts are read-only** — cannot `sed -i` for runtime config templating. Use init container + emptyDir pattern if dynamic substitution is needed.
- **Stable MAC is a general L2 networking requirement** (not router-specific) — VIP MAC changes on failover orphan port forwarding rules, cause ARP cache staleness (1-20+ min), and disrupt device tracking on any router/switch

## Kyverno Validation
- After editing Kyverno `ClusterPolicy` manifests, run `make validate-kyverno-policies` before commit to catch invalid variable/JMESPath expressions via server-side dry-run.

## Documentation
- All documentation in English (exception: `docs/kernel-tuning.md` is German, legacy)

## Operational Patterns
- **Upgrade planning:** Use `/plan-talos-upgrade` or `/plan-cilium-upgrade` — these skills include automated research and risk assessment steps. Do not skip these skills for ad-hoc upgrades.
- **Pre-operation review:** Before disruptive changes (upgrades, storage migration, network topology changes), invoke `platform-reliability-reviewer` with prefix "pre-operation:" for adversarial risk assessment.
- **Architecture decisions:** When evaluating alternatives, spawn `talos-sre` and `platform-reliability-reviewer` with the same question to get operational + reliability perspectives.
- **After incidents:** Update CLAUDE.md gotchas if the lesson is universal. Write a postmortem to `docs/` if the incident was complex. Keep `docs/` for record, CLAUDE.md for decision-making.

## Context Architecture
- Domain-specific knowledge in `.claude/rules/` — auto-loaded by path glob (not always-loaded)
- Rules: `talos-config.md`, `talos-nodes.md`, `talos-image-factory.md`, `kubernetes-gitops.md`, `cilium-gateway-api.md`, `argocd-operations.md`, `manifest-quality.md`, `talos-operations.md`
- Daily skills: `gitops-health-triage`, `talos-apply`, `talos-upgrade`, `cilium-policy-debug`, plus hardware/kernel skills under `.claude/skills/`
- Deprecated: `talos-node-maintenance` (superseded by `talos-apply` + `talos-upgrade`)
- Delegation agents: `gitops-operator`, `talos-sre`, `platform-reliability-reviewer` (supports pre-merge + pre-operation modes), `researcher` under `.claude/agents/`
- Scheduled checks: `talos-update-check` (weekly, Talos releases), `nvidia-extension-check` (weekly, Image Factory digest drift), `cilium-update-check` (weekly, Cilium stable releases)
- This CLAUDE.md kept minimal — only hard constraints, universal gotchas, and cluster overview
