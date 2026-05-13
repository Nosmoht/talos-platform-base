# Architecture

This document is the [C4-model][c4] **System Context** (Level 1) and
**Container** (Level 2) view of `talos-platform-base`. For
component-level (L3) detail of the capability-first network surface, see
[`docs/capability-architecture.md`](docs/capability-architecture.md);
for individual decisions, see the [ADR set](docs/) (`adr-*.md`).

[c4]: https://c4model.com/

> **Reading order:** READ THIS FIRST if you are new. Then dive into
> ADRs for decisions, the cookbook for recipes, the capability
> reference for the catalogue.

## L1 — System Context

```mermaid
%%{init: { "theme": "neutral" } }%%
flowchart TB
  subgraph Authors["People"]
    BC[Base Contributors]
    CC[Consumer-Cluster Authors]
  end

  subgraph Outside["Outside platform-base"]
    GHCR[(GHCR<br/>OCI registry)]
    SBX[Sigstore / Cosign<br/>+ SLSA attestor]
    ArgoCD[ArgoCD<br/>in target cluster]
    Talos[Talos Linux nodes<br/>in target cluster]
    Cons[Consumer cluster repo<br/>e.g. talos-homelab-cluster]
  end

  Base[[talos-platform-base<br/>this repository]]

  BC -->|PRs| Base
  Base -->|"tag push triggers<br/>oci-publish.yml"| GHCR
  Base -->|sign + attest| SBX
  GHCR -->|"oras pull<br/>vendored to vendor/base/"| Cons
  CC -->|"pins .base-version"| Cons
  Cons -->|"Multi-Source<br/>Application"| ArgoCD
  Base -->|"Multi-Source<br/>Application source"| ArgoCD
  ArgoCD -->|"reconciles<br/>manifests"| Talos
```

### Roles

- **Base contributors** push code, version tags trigger OCI publish.
- **GHCR** stores the immutable OCI artifact (`ghcr.io/<owner>/talos-platform-base:<tag>`).
- **Sigstore / cosign** sign each artifact keyless via GitHub OIDC; SLSA build provenance is attached.
- **Consumer-cluster authors** maintain a separate repo that pins a `.base-version`, vendors via `oras pull`, and overlays cluster-specific values.
- **ArgoCD** runs in the target cluster and reconciles a Multi-Source Application that references *both* repos.
- **Talos Linux nodes** receive machine-config and Kubernetes workloads.

## L2 — Container View (base internals)

```mermaid
%%{init: { "theme": "neutral" } }%%
flowchart LR
  subgraph Base["talos-platform-base"]
    direction TB
    Make[Makefile<br/>validate-gitops<br/>validate-kyverno-policies]
    Boot["kubernetes/bootstrap/<br/>(parameterized templates)"]
    Infra["kubernetes/base/infrastructure/<br/>22 standalone-renderable components<br/>(12 Helm-based, 10 resources-only)"]
    Talos["talos/<br/>machine-config patches +<br/>cluster.yaml-driven Makefile"]
    Pol["policies/<br/>conftest Rego"]
    Scripts["scripts/<br/>render + lint helpers"]
    Docs["docs/<br/>ADRs + reference"]
    CI[".github/workflows/<br/>gitops-validate<br/>oci-publish<br/>hard-constraints-check"]
    Reg["PNI capability registry<br/>(ConfigMap, sync-wave -2)"]
    Pol2["7 Kyverno ClusterPolicies<br/>pni-contract-enforce<br/>pni-reserved-labels-enforce<br/>pni-reserved-annotations-enforce<br/>pni-capability-validation-enforce<br/>pni-instanced-suffix-required (audit)<br/>external-httproute-hostnames-enforce<br/>vault-ca-distribution"]
    CCNP["16 static CCNPs<br/>capability-selector"]

    Reg -.->|"data source for"| Pol2
    Reg -.->|"data source for"| CCNP
    Infra ---> Reg
    Infra ---> Pol2
    Infra ---> CCNP
    Make --> Pol
    Make --> Infra
    CI --> Make
  end
```

### Subsystems

| Subsystem | Purpose | Key files |
|---|---|---|
| `kubernetes/base/infrastructure/` | 22 cluster-agnostic Helm-base components, each renderable in isolation | `<comp>/{application,kustomization,namespace,values}.yaml` |
| `kubernetes/bootstrap/` | parameterized ArgoCD + Cilium bootstrap templates (envsubst) | `argocd/*.tmpl`, `cilium/extras.yaml` |
| Platform Network Interface (PNI) | capability-first contract — registry, admission policies, CCNPs | `kubernetes/base/infrastructure/platform-network-interface/` |
| `talos/` | machine-config patches + multi-cluster generation Makefile | `patches/*`, `cluster.yaml.tmpl` |
| `policies/` | conftest Rego — capability sunset, label hygiene | `policies/conftest/*` |
| Validation pipeline | kustomize render + conftest + kubeconform + Kyverno-CLI | `scripts/`, `Makefile`, `.github/workflows/gitops-validate.yml` |
| OCI publish | cosign keyless + SLSA attestation + immutable GHCR tag | `.github/workflows/oci-publish.yml` |

## Key flows

### Tagged release → consumer cluster

```mermaid
sequenceDiagram
  participant Maintainer
  participant GitHub
  participant CI as oci-publish.yml
  participant GHCR
  participant Sigstore
  participant Consumer as Consumer repo CI
  participant Cluster as Live cluster ArgoCD

  Maintainer->>GitHub: git tag v0.2.0 && git push --tags
  GitHub->>CI: trigger
  CI->>GHCR: push :v0.2.0 (immutable)
  CI->>Sigstore: cosign sign + attest provenance
  Consumer->>GHCR: cosign verify + oras pull → vendor/base/
  Consumer->>Cluster: Multi-Source Application sees new tag
  Cluster->>Cluster: ArgoCD reconciles, applies merged manifests
```

See [`docs/oci-artifact-verification.md`](docs/oci-artifact-verification.md)
for the verification recipe.

### Capability admission

```mermaid
sequenceDiagram
  participant Author as Consumer manifest author
  participant K8s as kube-apiserver
  participant Kyverno
  participant Reg as PNI registry ConfigMap

  Author->>K8s: kubectl apply namespace.yaml<br/>(consume.cnpg-postgres.team-foo)
  K8s->>Kyverno: admission webhook
  Kyverno->>Reg: lookup cnpg-postgres
  alt cap exists, instanced=true, suffix present
    Kyverno-->>K8s: allow
  else cap exists, instanced=true, suffix missing
    Kyverno-->>K8s: allow + PolicyReport (audit-mode advisory)
  else cap does not exist
    Kyverno-->>K8s: deny (pni-capability-validation-enforce)
  end
```

## Sync-wave order

```text
-2  PNI registry ConfigMap         (admitted before policies)
-1  ArgoCD AppProjects             (RBAC boundary)
 0  Infrastructure components      (cert-manager, kyverno, …)
 1  Apps (workload-layer)
```

## What this is NOT

- Not a runnable cluster — no node IPs, no SOPS secrets, no OIDC issuers.
- Not a library/SDK — no API users.
- Not an end-user product — the audience is operators and contributors.

Those concerns live in:

- **Consumer cluster repos** for cluster identity, secrets, overlays.
- **Application repos** for workload manifests.

## See also

- [`docs/README.md`](docs/README.md) — full documentation index (Diátaxis-organised)
- [`docs/capability-architecture.md`](docs/capability-architecture.md) — L3 detail on PNI capabilities
- [`AGENTS.md`](AGENTS.md) — tool-agnostic SOT (canonical for agents)
