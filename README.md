# talos-platform-base

Cluster-agnostic GitOps platform base for Talos-on-Kubernetes deployments.

This base ships a **capability-first Platform Network Interface (PNI)**: every
cross-namespace path is mediated by a capability identifier (`monitoring-scrape`,
`tls-issuance`, `cnpg-postgres.<inst>`, …). Tools are swappable implementations
of capabilities; trust is namespace-anchored. See
[capability-architecture.md](docs/capability-architecture.md) for the overview
and [pni-cookbook.md](docs/pni-cookbook.md) for concrete recipes.

## What this provides

- Talos machine-config patches (control-plane without `extraManifests`, common, drbd, worker-{gpu,gvisor,kubevirt,pi})
- Talos `Makefile` with `cluster.yaml`-driven multi-cluster config generation
- 22 standalone-renderable infrastructure components under `kubernetes/base/infrastructure/`:
  - **18 Helm-based** (chart pinned via `chart.lock.yaml` or rendered via `values.yaml`):
    alloy, argocd, cert-approver, cert-manager, dex, external-secrets,
    kube-prometheus-stack, kyverno, local-path-provisioner, loki, metrics-server,
    node-feature-discovery, nvidia-dcgm-exporter, nvidia-device-plugin,
    piraeus-operator, tetragon, vault-config-operator, vault-operator
  - **4 resources-only** (plain Kubernetes manifests, no Helm):
    kubevirt, kubevirt-cdi, multus-cni, platform-network-interface
- Cilium Helm values + `extras.yaml` under `kubernetes/bootstrap/cilium/` (the
  consumer-side cluster repo renders `cilium.yaml` via `make cilium-bootstrap`)
- Parameterized ArgoCD bootstrap (`root-application.yaml.tmpl`, `root-project.yaml.tmpl`)
- conftest policies, `validate-gitops` pipeline, hard-constraints checks
- Pre-commit hooks for secret-scan (gitleaks); consumer-side adds SOPS pre-commit

All 22 components are standalone-renderable via
`kubectl kustomize --enable-helm kubernetes/base/infrastructure/<comp>/`.
The set is frozen in `.ci-renderable-components.txt` and verified at every
PR via the gitops-validate workflow's set-based predicate.

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
2. A consumer-owned bootstrap step that runs
   `oras pull ghcr.io/nosmoht/talos-platform-base:<v>` into a gitignored
   `vendor/base/` directory — typically a small shell script in the
   consumer repo's `scripts/`, since each consumer owns its own pin and
   vendor-path conventions. See
   [`docs/tutorial-first-consumer-cluster.md`](./docs/tutorial-first-consumer-cluster.md)
   for a worked example.
3. ArgoCD Multi-Source Application manifests with `spec.sources[]`
   listing both the cluster repo and this base repo

See: [ADR — Multi-Repo Platform Split](./docs/adr-multi-repo-platform-split.md).

## Repository structure

```text
.
├── Makefile                              # base-side validation + MCP install
├── kubernetes/
│   ├── base/infrastructure/<comp>/       # 22 components (12 Helm-based, 10 resources-only)
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

## Documentation

**Start here** (in reading order):

| Doc | Audience | Purpose |
|---|---|---|
| [`ARCHITECTURE.md`](ARCHITECTURE.md) | new contributors | C4 L1/L2 view + key flows |
| [`AGENTS.md`](AGENTS.md) | agentic tools, hard-constraint reviewers | Tool-agnostic SOT — hard constraints, validation, PNI |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | anyone opening a PR | scope, conventional commits, PR checks |
| [`docs/capability-architecture.md`](docs/capability-architecture.md) | consumer authors, operators | Why capability-first — namespace-anchored trust, instance scoping |
| [`docs/pni-cookbook.md`](docs/pni-cookbook.md) | manifest authors | Concrete recipes for consuming + producing capabilities |
| [`docs/tutorial-first-consumer-cluster.md`](docs/tutorial-first-consumer-cluster.md) | new contributors | 30-min walk-through: vendor + verify + render |

**Full index:** [`docs/README.md`](docs/README.md) is the single source of truth
for the Diátaxis-organised documentation set (tutorial / how-to / reference /
explanation). All other documentation files (ADRs, capability reference, render
pipeline, OCI verification, MCP setup, glossary, issue workflow, harness-plugin
integration, …) are listed there. Refer to it for everything not in the table
above.

## License

Apache-2.0. See [LICENSE](./LICENSE).
