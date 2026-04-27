# ADR: Multi-Repo Platform Split for Multi-Cluster Reuse

**Status**: Proposed (review pending)
**Date**: 2026-04-27
**Supersedes**: implicit single-repo assumption in #66, #67, #84

## Context

This repository began as a single-cluster homelab GitOps tree. With the addition
of a second cluster (`office-lab`, corporate site, internal-only, 3 control-plane
+ 4 worker, no GPU, no WAN edge), the single-overlay / single-repo model becomes
insufficient:

1. Cluster identity (IPs, FQDNs, OIDC issuers, SOPS keys) is hardcoded in
   56+ files across `kubernetes/overlays/homelab/**`, making add-cluster a
   copy-paste exercise that drifts over time.
2. Tooling (28 skills, 6 agents, 7 hooks, 9 scripts) lives in `.claude/**`
   of this repo, but should be reused across both clusters without manual sync.
3. Issues #66 (cross-cluster trust model) and #67 (multi-cluster service
   consumption / PNI evolution) require an explicit federation model before
   further architectural commitment.

## Decision

Split the platform into **three logically distinct repositories**, with the
existing repo evolving into the base layer and history preserved via
`git filter-repo`:

| Repo (target name) | Owner | Visibility | Contents |
|---|---|---|---|
| **`talos-platform-base`** (current Talos-Homelab repo, renamed) | Nosmoht | personal | Talos templates, Cilium/Piraeus/KubeVirt/Kyverno/cert-manager Helm bases, ArgoCD bootstrap (parameterized), AGENTS.md core constraints. NO cluster identity. |
| **`kube-agent-harness`** (existing private repo, reused as plugin) | devobagmbh | private | `.claude/{skills,agents,rules,references,hooks}` extracted from current repo + existing harness content. Acts as Claude-Code plugin for both cluster repos. |
| **`talos-homelab-cluster`** (new repo via filter-repo) | Nosmoht | personal | `kubernetes/overlays/homelab/**`, `talos/nodes/`, `.claude/environment.yaml`, homelab-specific ADRs. Consumes base + plugin. |
| **`talos-office-lab-cluster`** (new repo, scaffold from template) | corporate / devobagmbh | private | Office-lab cluster identity. Consumes base + plugin. |

**Per-cluster trust model** (resolves #66): Each cluster is a self-rooted peer.
No shared CA, no shared SOPS key, no shared Vault. Per-cluster break-glass
kubeconfig.

**Per-cluster service consumption** (resolves #67): All capabilities are
cluster-local. The "shared platform service" class is intentionally empty.
PNI labels remain cluster-scoped.

**Codex CLI is no longer a primary support target for skills.** Claude Code's
plugin mechanism (project-level `claude plugin install` + global
`~/.claude/plugins/`) is the canonical distribution path. Codex users who want
skill access must clone `kube-agent-harness` separately and symlink — manual
fallback only.

## Consequences

### Positive
- Cluster identity isolation matches per-cluster security boundary (per-repo
  SOPS, per-repo CI access, per-repo PR review).
- Skills/agents update once → both clusters benefit.
- Adding cluster N+1 = scaffold from template + per-cluster repo; no base-repo
  edits.
- Aligns with industry GitOps-fleet patterns (Flux fleet-infra, ArgoCD
  ApplicationSet-of-cluster-repos).
- Resolves long-standing Issues #66 and #67 with a concrete trust + consumption
  decision.

### Negative
- 4 repos for 2 clusters = coordination overhead. Bumping a base component
  requires coordinated PRs across 3 repos.
- `git filter-repo` migration is a multi-hour one-way operation per repo. Not
  reversible without manual fixup.
- `kubernetes/base/` and `talos/patches/common.yaml` need a one-time cleanup
  pass to remove hardcoded homelab IPs before the base repo is truly
  cluster-agnostic.
- AGENTS.md / CLAUDE.md split requires careful import structure (host repo
  `@`-imports plugin docs).
- Codex CLI user experience for skills degrades to "manual symlink".

### Neutral / Out of scope
- ArgoCD ApplicationSet-of-clusters not adopted — each cluster runs its own
  ArgoCD pointing at its own repo. Manageable for ≤5 clusters.
- Service mesh federation explicitly NOT planned.
- Cross-cluster Vault/Dex/SSO explicitly NOT planned.
- Office-lab has no WAN edge by design (internal-only); the homelab's
  `pi-public-ingress` architecture is homelab-specific and stays in
  `talos-homelab-cluster`. No "shared edge ingress" capability across clusters.

## Migration Plan (Phases)

### Phase 1 — Base de-homelab-ification (in current repo, ~1.5–2 weeks)

**Scope (initial discovery via pre-merge review of this ADR):**
- `talos/patches/common.yaml` — NTP/gateway IPs.
- `talos/Makefile:1-21` — `CLUSTER_NAME`, `ENDPOINT`, IP_node-XX map.
- `kubernetes/base/infrastructure/argocd/values.yaml` — hardcoded ArgoCD FQDN.
- `kubernetes/base/infrastructure/alloy/values.yaml` — hardcoded `cluster = "homelab"` Loki label.
- `kubernetes/base/infrastructure/**/namespace.yaml` and PNI CCNP files — `instance: homelab`, `part-of: homelab` labels (~14 files).
- `kubernetes/bootstrap/argocd/root-application.yaml` — hardcoded `repoURL` and `path` (raw YAML, not a template).

**Parameterization mechanisms:**
- Talos Makefile: `CLUSTER ?= homelab`, `include clusters/$(CLUSTER).mk`. Default preserves current behaviour.
- ArgoCD root-application: render via `envsubst` or Make target generating the manifest from a template (`root-application.yaml.tmpl`) into a gitignored `_out/` path that `make argocd-bootstrap` applies. Template variables: `${REPO_URL}`, `${OVERLAY}`, `${CLUSTER_NAME}`. Document the mechanism in the Phase-1 sub-issue acceptance.
- Helm values cluster-specific tokens: extract into per-overlay `values-<cluster>.yaml` or kustomize `patchesStrategicMerge` overlays.
- Namespace labels: `instance:` and `part-of:` become per-overlay kustomize patches against base namespace manifests.

**Acceptance gate:** `grep -rn "homelab\|<homelab-mgmt-prefix>\|ntbc.io" kubernetes/base/ talos/Makefile` returns zero matches.

### Phase 2 — Plugin extraction (~1 week)

**Prerequisite spike (must complete before any history rewrite):**
- Verify Claude Code's plugin distribution schema actually supports: (a) `.claude/hooks/*.sh` registration through plugin install, (b) `paths:`-frontmatter rules with host-repo path resolution. If either is unsupported, hooks and `paths:`-rules stay per-host-repo (carve-out exception); only `paths:`-agnostic skills/agents/refs/rules ship in the plugin. Spike outcome documented in Phase-2 sub-issue.

**Migration steps:**
- `git filter-repo --path .claude/skills/ --path .claude/agents/ --path .claude/rules/ --path .claude/references/ --path .claude/hooks/` → integrate into `kube-agent-harness`. Resolve naming collisions with existing harness skills via explicit prefix rename map (e.g. `gitops-health-triage` → `homelab-gitops-health-triage` if duplicate).
- Replace `.claude/**` in current repo with plugin reference (`claude plugin install kube-agent-harness` or equivalent local marketplace).
- Update CLAUDE.md / AGENTS.md to document the new plugin source.

**Operational caveat:** `git filter-repo` rewrites SHA history. Open PRs and feature branches against `main` must be merged or closed in a 24-hour freeze window before each filter-repo run. The 4-week budget assumes one freeze per filter-repo (Phase 2 + Phase 3A = 2 freezes total).

### Phase 3 — Cluster split + office-lab scaffold (~2 weeks)

**3A: Homelab cluster repo split (history-preserving, with live-cluster cutover)**
- `git filter-repo --path kubernetes/overlays/homelab --path talos/nodes --path talos/patches/pi-firewall.yaml --path docs/adr-pi-sole-public-ingress.md ...` → new `talos-homelab-cluster` repo.
- **AppProject `sourceRepos` dual-listing**: every AppProject in the new repo lists BOTH `talos-platform-base.git` AND `talos-homelab-cluster.git` so multi-source Applications (kustomize + helm `$values`) keep working. Verified via `argocd app get` for all 34 applications post-cutover.
- **ArgoCD repoURL cutover sequence** (NOT a re-run of `argocd-bootstrap` — the root Application has `selfHeal: true, prune: true` which would race a fresh apply):
  1. Pause root Application (`kubectl patch application root -n argocd --type merge -p '{"spec":{"syncPolicy":{"automated":null}}}'`).
  2. `kubectl edit application root -n argocd` — change `spec.source.repoURL` and `spec.source.path` to new repo + path.
  3. `argocd app diff root` — must show zero drift.
  4. Resume automation by re-applying the root manifest with `automated.selfHeal: true`.
  5. Monitor for 24h before declaring stable.

**3B: Base repo rename**
- Rename `Nosmoht/Talos-Homelab` → `Nosmoht/talos-platform-base`. GitHub auto-redirects.
- README/AGENTS.md cleanup; remove cluster-specific overview.

**3C: Office-lab scaffold**
- New `talos-office-lab-cluster` repo from base + plugin templates.
- Deliver `docs/office-lab-network-brief.md` (network-admin briefing).

### Verification gate (Phase 3A done)

`argocd app diff` is necessary but **not sufficient** — it compares manifests, not running state. Phase 3A cutover must additionally verify these never-blip services with external runtime probes:

- **pi-public-ingress** — external `curl -I https://<homelab-public-fqdn>/` returns 200/302 before/during/after cutover.
- **ingress-front** — internal LAN curl against gateway VIP returns 200.
- **vault** — `kubectl -n vault exec ... vault status` reports unsealed throughout.
- **dex** — OIDC discovery endpoint returns 200, kubectl OIDC login still succeeds.
- **cert-manager** — `kubectl get clusterissuer -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}'` is `True True` for all issuers.
- **kube-prometheus-stack** — `up{job="..."}` query against Prometheus shows continuous scrape (no gap > 60s).
- **PreSync/PostSync hooks** in vault-config-operator and similar must not re-run unintentionally; check `kubectl get jobs -A` before/after for unexpected new job creations.

If any probe shows degradation > 60s, abort the cutover and roll back via `kubectl patch application root` to the old repoURL.

### Verification gate (Phase 3 done)
- Existing homelab cluster still reconciled by ArgoCD from new homelab-cluster repo (no production drift during migration).
- Office-lab can be brought up from base + plugin + new office-lab repo using the same workflow.

## Alternatives Considered

| Alternative | Why rejected |
|---|---|
| Multiple overlays in single repo (`overlays/homelab/`, `overlays/office-lab/`) | User explicitly judged unrealistic — too many homelab-specific concerns leak through cluster boundary; access control is per-repo on GitHub. |
| ArgoCD ApplicationSet-of-clusters in one repo | Same coupling concerns. ApplicationSet pattern works well at scale (≥10 clusters); for 2 clusters it's overkill and bundles unrelated trust domains. |
| Helm values branching per cluster | Doesn't address Talos node-config separation, doesn't address SOPS-key per-cluster, doesn't address PR-review boundary. |
| Keep monolith, defer multi-cluster | Postpones the problem; office-lab bringup blocks on this anyway. |

## References
- Issues: #66 (cross-cluster trust), #67 (multi-cluster service consumption),
  #84 (Claude harness primitives epic), #142 (closed — recent CI work that
  established the pattern of issue-driven changes)
- Memory: `feedback_harness_composition.md`, `feedback_harness_capability_driven.md`,
  `reference_harness_service_model.md`, `project_multi_repo_split_decided.md`
- External: ArgoCD ApplicationSet patterns
  (https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/),
  Flux fleet-infra reference architecture
  (https://github.com/fluxcd/flux2-multi-tenancy)
