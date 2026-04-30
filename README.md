# talos-platform-base

Cluster-agnostic GitOps platform base for Talos-on-Kubernetes deployments.

## What this provides

- Talos machine-config patches (control-plane without `extraManifests`, common, drbd, worker-{gpu,gvisor,kubevirt,pi})
- Talos `Makefile` with `cluster.yaml`-driven multi-cluster config generation
- Helm bases for ArgoCD, Cilium, Piraeus, Kyverno, cert-manager, vault, dex,
  kube-prometheus-stack, alloy, loki, NFD, KubeVirt-CDI, Tetragon, MinIO,
  Strimzi, CloudNativePG, Redis, Local-Path Provisioner, Metrics Server,
  NVIDIA-DCGM, NVIDIA Device Plugin, Omada Controller (parameterized)
- Parameterized ArgoCD bootstrap (`root-application.yaml.tmpl`, `root-project.yaml.tmpl`)
- conftest policies, `validate-gitops` pipeline, hard-constraints checks
- Pre-commit hooks for SOPS encryption + secret-scan (consumer-side)

## What this does NOT provide

- Cluster identity (IPs, FQDNs, OIDC issuers)
- Per-node configurations
- SOPS-encrypted secrets
- Environment overrides (Helm value overrides, kustomize patches)
- Live ArgoCD or live cluster

Those live in **consumer cluster repos**.

## How consumers use this

Consumer cluster repos (e.g. `talos-homelab-cluster`, future
`talos-office-lab-cluster`) pin a specific tag of this base via:

1. A one-line `.base-version` file (e.g. `v0.1.0`)
2. A `scripts/bootstrap-base.sh` that runs `oras pull
   ghcr.io/nosmoht/talos-platform-base:<v>` into a gitignored
   `vendor/base/` directory
3. ArgoCD Multi-Source Application manifests with `spec.sources[]`
   listing both the cluster repo and this base repo

See: [ADR — Multi-Repo Platform Split](./docs/adr-multi-repo-platform-split.md).

## Repository structure

```
.
├── Makefile                              # base-side validation + MCP install
├── kubernetes/
│   ├── base/infrastructure/<comp>/       # 24 cluster-agnostic Helm-base components
│   └── bootstrap/
│       ├── argocd/                       # parameterized templates (envsubst)
│       └── cilium/                       # base Helm values for cilium.yaml render
├── talos/
│   ├── Makefile                          # cluster.yaml-driven multi-cluster
│   ├── patches/                          # common, controlplane (no extraManifests),
│   │                                     # drbd, worker-{gpu,gvisor,kubevirt,pi},
│   │                                     # cluster.yaml.tmpl
│   └── versions.mk
├── policies/                             # conftest Rego (k8s, argocd)
├── scripts/                              # cluster-agnostic helpers
├── cluster.yaml.example                  # cluster identity schema (placeholders)
├── AGENTS.md                             # canonical SOT for tooling agents
├── CLAUDE.md                             # Claude-Code-specific addenda
└── docs/                                 # base reference docs
```

## Versioning

Tags follow `vMAJOR.MINOR.PATCH`. Each tag triggers a GitHub Action that
publishes the OCI artifact to `ghcr.io/nosmoht/talos-platform-base:<tag>`
(and `:latest`).

Breaking changes bump MAJOR. New components or new patch options bump MINOR.
Helm-base value-default changes that are not breaking bump PATCH.

## Local validation

```bash
cp cluster.yaml.example cluster.yaml      # fill in placeholders for testing
make validate-gitops
make validate-kyverno-policies
```

Live cluster validation runs in consumer cluster repos.

## License

Apache-2.0. See [LICENSE](./LICENSE).
