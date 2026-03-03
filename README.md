# Talos Homelab Migration

Talos-based Kubernetes homelab with ArgoCD GitOps, Cilium Gateway API, and Piraeus/LINSTOR storage.

## First-Time Claude Code Setup

To use Claude Code effectively in this repository, complete the local setup once:

1. Install required CLI tools (`gh`, `node`, `kubectl`, `talosctl`, `sops`, `yq`, `jq`).
2. Configure access:
   - `gh auth login`
   - `export KUBECONFIG=/tmp/homelab-kubeconfig`
3. Ensure MCP prerequisites are installed (GitHub and Kubernetes MCP servers).

Detailed instructions are in [`.claude/mcp/SETUP.md`](.claude/mcp/SETUP.md).

## Current Bootstrap Flow

1. Provision Talos nodes and generate/apply machine configs from `talos/`.
2. Install ArgoCD bootstrap components:
   - `kubernetes/bootstrap/argocd/namespace.yaml`
   - `kubernetes/bootstrap/argocd/root-project.yaml`
   - `kubernetes/bootstrap/argocd/root-application.yaml`
3. ArgoCD reconciles `kubernetes/overlays/homelab` (projects, infra apps, app overlays).

## Source of Truth

- Kubernetes manifests: `kubernetes/`
- Talos machine config sources: `talos/patches/`, `talos/nodes/`
- Operational docs: `docs/`

## Notes

- `kubelet-serving-cert-approver` and `metrics-server` are managed by ArgoCD (not Talos `extraManifests`).
- Gateway API is used instead of Ingress.
