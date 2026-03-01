# Talos Homelab Migration

Talos-based Kubernetes homelab with ArgoCD GitOps, Cilium Gateway API, and Piraeus/LINSTOR storage.

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
