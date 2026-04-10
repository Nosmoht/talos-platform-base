# Talos Homelab

Talos-based Kubernetes homelab with ArgoCD GitOps, Cilium Gateway API, and Piraeus/LINSTOR storage.

## Start Here (Operator Checklist)

Read these in order before making changes:

1. This `README.md` (safety rules + workflow)
2. [`docs/day0-setup.md`](docs/day0-setup.md) (cluster bootstrap and architecture)
3. [`docs/day2-operations.md`](docs/day2-operations.md) (day-to-day operations and recovery)
4. [`docs/platform-network-interface.md`](docs/platform-network-interface.md) (consumer onboarding for managed network capabilities)
5. [`AGENTS.md`](AGENTS.md) (canonical cluster constraints and operational knowledge — used by Claude Code and Codex CLI)
   - **Prerequisite**: Enable GitHub Push Protection in repo Settings → Code security → Push protection
6. [`docs/claude-code-guide.md`](docs/claude-code-guide.md) (Claude Code skills, agents, and automation)

## Hard Safety Rules

- Do not `kubectl apply` ArgoCD-managed resources. Commit to git and let ArgoCD sync.
- Use Gateway API resources; do not introduce Ingress resources/controllers.
- Do not use `metal-installer-secureboot` for Talos images on this hardware.
- Do not add `debugfs=off` boot parameter (causes Talos boot failure).
- Keep secrets encrypted as `*.sops.yaml`; never commit plaintext secrets.
- Keep cluster bootstrap/platform secrets in SOPS; use Vault + External Secrets for customer runtime secrets.
- For Talos operations, prefer explicit node endpoint flags (`talosctl -n <ip> -e <ip>`).

## Repository Layout

- `kubernetes/base/infrastructure/`: shared Helm values/bases per component.
- `kubernetes/overlays/homelab/`: ArgoCD apps, overlay values, extra resources.
- `kubernetes/bootstrap/`: one-time bootstrap manifests (ArgoCD, Cilium).
- `talos/patches/`, `talos/nodes/`: Talos machine config sources.
- `talos/Makefile`: node install/apply/upgrade workflows.
- `docs/`: runbooks, reviews, tuning notes.

## First-Time Workstation Setup

Install required CLIs: `talosctl`, `kubectl`, `kubectl-linstor`, `make`, `sops`, `yq`, `jq`, `gh`, `helm`, `uv`.

Set cluster access:

```bash
talosctl -n 192.168.2.61 -e 192.168.2.61 kubeconfig --force /tmp/homelab-kubeconfig
export KUBECONFIG=/tmp/homelab-kubeconfig
gh auth login
```

Install git commit hooks (SOPS encryption guard + secret scanner):

```bash
make install-pre-commit
```

## Claude Code Assistance

This repository includes slash-command skills, delegation agents, and auto-loaded
context rules for Claude Code. Start a session in the repo root to use them.

Common commands:
- `/plan-talos-upgrade` / `/execute-talos-upgrade` — safe Talos version upgrades
- `/gitops-health-triage [app\|all]` — diagnose ArgoCD sync failures
- `/cilium-policy-debug [namespace/app]` — trace and fix connectivity drops

Full catalog: [`docs/claude-code-guide.md`](docs/claude-code-guide.md). For MCP server setup, see [`.claude/mcp/SETUP.md`](.claude/mcp/SETUP.md).

## Safe Change Workflow

For Kubernetes/GitOps changes:

```bash
# 1) Edit manifests in kubernetes/
# 2) Validate render
kubectl kustomize kubernetes/overlays/homelab
kubectl apply -k kubernetes/overlays/homelab --dry-run=client

# 3) Commit and push
git add <files>
git commit -m "fix(scope): summary"
git push

# 4) Verify ArgoCD reconciliation
kubectl -n argocd get applications
```

For Talos config changes:

```bash
# Dry-run regenerates configs automatically
make -C talos dry-run-node-01

# Apply runs the per-node dry-run first
make -C talos apply-node-01

# Use upgrade when Talos version, boot args, or extensions changed
make -C talos upgrade-node-01
```

## Current Bootstrap Flow

1. Provision Talos nodes and generate/apply machine configs from `talos/`.
2. Install ArgoCD bootstrap components:
   - `kubernetes/bootstrap/argocd/namespace.yaml`
   - `kubernetes/bootstrap/argocd/root-project.yaml`
   - `kubernetes/bootstrap/argocd/root-application.yaml`
3. ArgoCD reconciles `kubernetes/overlays/homelab` (projects, infra apps, app overlays).

## Common Mistakes to Avoid

- Applying Argo-managed manifests directly with `kubectl apply`.
- Making cluster-wide Talos changes without per-node dry-run and readiness checks.
- Forgetting DRBD implications before reboot-triggering operations.
- Mixing unrelated changes in one commit (Talos + app manifests + docs).

## GPU Node Scheduling Policy

- Keep a single scheduling taint on `node-gpu-01`: `nvidia.com/gpu=present:NoSchedule`.
- System addons that must run on every node (for example `alloy`, `loki-canary`, `node-feature-discovery`, GPU exporters/plugins) may tolerate only this GPU taint.
- Do not add `drbd.linbit.com/*` tolerations to non-LINBIT workloads.
- Keep LINBIT/Piraeus off the GPU node by LINSTOR node selection rules, not by widening tolerations.
- For new critical addons, prefer `priorityClassName: system-node-critical` (or `system-cluster-critical` where appropriate) plus the existing GPU toleration pattern.
