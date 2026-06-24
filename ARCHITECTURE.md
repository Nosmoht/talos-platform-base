# Architecture

This document is a hybrid **[C4][c4]** and **[arc42][arc42]** architecture
description:

- arc42 sections 1 (Introduction & Goals), 2 (Architecture Constraints),
  4 (Solution Strategy), 10 (Quality Requirements), 11 (Risks & Technical
  Debt), 12 (Glossary) — for the narrative scaffolding arc42 is strong at.
- C4 levels 1 (System Context) and 2 (Container) — for the structural
  diagrams C4 is strong at.

arc42 sections 5 (Building Block View) and 6 (Runtime View) are covered
by the C4 L2 and "Key flows" sections respectively; section 9
(Architecture Decisions) is covered by the [ADR set](docs/) (`adr-*.md`)
under MADR 3.0 frontmatter.

[c4]: https://c4model.com/
[arc42]: https://arc42.org/

> **Reading order:** READ THIS FIRST if you are new. Then dive into
> ADRs for decisions and the per-component docs for detail.

## 1. Introduction and Goals

`talos-platform-base` is the cluster-agnostic GitOps base of the
Talos-on-Kubernetes deployment family. Its job is to ship a versioned,
signed, attested OCI artifact that one or more consumer cluster repos
vendor and overlay with cluster-specific identity.

**Goals (in priority order):**

1. **Reusable across clusters.** A second cluster pins a tag and is
   bootstrappable without any base-repo edits.
2. **Supply-chain auditable.** Every artifact is signed (cosign keyless
   OIDC), provenance-attested (SLSA), and inventory-attested
   (CycloneDX 1.6 SBOM). Reproducible from `chart.lock.yaml` +
   `values.yaml`.
3. **No cluster identity inside.** No IPs, FQDNs, OIDC issuers, SOPS
   keys, or per-cluster secrets — those live in the consumer cluster
   repo.

**Audience:** platform operators and contributors maintaining one or
more Talos/Kubernetes clusters. NOT application developers; NOT
end-users; NOT marketing readers.

## 2. Architecture Constraints

The non-negotiable invariants. These are enforced by CI gates and
documented in [`AGENTS.md`](AGENTS.md) §"Hard Constraints" and
§"Tool-Agnostic Safety Invariants":

| Constraint | Why | Enforced by |
|---|---|---|
| No SecureBoot | `metal-installer-secureboot` causes Talos boot loops | `AGENTS.md` + reviewer-flagged at PR |
| No `debugfs=off` | causes "failed to create root filesystem" Talos boot loop | `AGENTS.md` |
| Gateway API only — no `kind: Ingress` | API-deprecated; consistent L7 model | `hard-constraints-check.yml` (CI required) |
| EndpointSlices only — no `kind: Endpoints` | deprecated since Kubernetes v1.33 | `hard-constraints-check.yml` (CI required) |
| Apache-2.0, REUSE 3.3 compliant | OSS hygiene + SBOM correctness | `reuse-compliance` CI job |

## 3. System scope — see L1 below

The arc42 §3 "System Scope and Context" maps directly onto the C4 L1
**System Context** view below — no duplication.

## 4. Solution Strategy

How the goals listed in §1 are achieved at the highest abstraction
level. Three architectural decisions do the load-bearing work; each is
captured in a separate ADR with MADR 3.0 frontmatter:

| Strategy | Realised by | ADR |
|---|---|---|
| **Goal 1** (reusable) — separate cluster identity from platform code | Three-role split: base / harness-plugin / consumer-cluster | [`adr-0001-multi-repo-platform-split.md`](docs/adr-0001-multi-repo-platform-split.md) |
| **Goal 2** (auditable) — every artifact carries cryptographic provenance | OCI artifact + cosign + SLSA + CycloneDX SBOM, all keyless OIDC | [`SECURITY.md`](SECURITY.md) §"Supply chain" + [`docs/oci-artifact-verification.md`](docs/oci-artifact-verification.md) |
| **Goal 3** (no cluster identity) — base is fully cluster-agnostic | Rendered manifests pattern + consumer-side overlays own namespace creation | [`adr-0002-namespace-ownership-rendered-manifests.md`](docs/adr-0002-namespace-ownership-rendered-manifests.md) |

A further decision — the substrate-only scope itself — keeps everything
above Talos + Cilium + ArgoCD (plus `cert-approver` boot glue) out of the
base; non-substrate components live in the
[`talos-platform-apps`](https://github.com/devobagmbh/talos-platform-apps)
catalog (see
[`docs/adr-0004-substrate-only-base.md`](docs/adr-0004-substrate-only-base.md)).

The one capability surface that *stays* in the substrate is **Layer C —
per-node hardware capability composition**, which decides which Talos
Image-Factory schematic each node receives. It is independent of the
dissolved network-trust contract:

- **Hardware Features Registry** (`docs/platform-hardware-features.yaml`,
  schema-validated against
  `docs/schemas/hardware-features.schema.json`): the catalogue of atomic
  hardware predicates (GPU, NVMe, IOMMU, SBC overlay, …) that a node's
  provisioning profiles compose into a schematic.

The decision is captured in
[`adr-0009-node-capability-composition.md`](docs/adr-0009-node-capability-composition.md)
and the broader layer model in
[`adr-0003-three-layer-capability-architecture.md`](docs/adr-0003-three-layer-capability-architecture.md).

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
    Cons[Consumer cluster repo]
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
    Make[Makefile<br/>validate-gitops<br/>argocd-bootstrap]
    Boot["kubernetes/bootstrap/<br/>(parameterized templates)"]
    Infra["kubernetes/base/infrastructure/<br/>substrate components<br/>(argocd, cert-approver)"]
    Talos["tofu/modules/talos-cluster/<br/>OpenTofu cluster-lifecycle module<br/>(per-class Image-Factory + bootstrap,<br/>Cilium + ArgoCD inlineManifest seeds)"]
    Pol["policies/<br/>conftest Rego"]
    Scripts["scripts/<br/>render + lint helpers"]
    Docs["docs/<br/>ADRs + reference"]
    CI[".github/workflows/<br/>gitops-validate<br/>oci-publish<br/>hard-constraints-check"]

    Make --> Pol
    Make --> Infra
    CI --> Make
  end
```

### Subsystems

| Subsystem | Purpose | Key files |
|---|---|---|
| `kubernetes/base/infrastructure/` | substrate components (`argocd`, `cert-approver`), each renderable in isolation | `<comp>/{application,kustomization,namespace,values}.yaml` |
| `kubernetes/bootstrap/` | parameterized ArgoCD + Cilium bootstrap templates (envsubst) | `argocd/*.tmpl`, `cilium/extras.yaml` |
| `tofu/modules/talos-cluster/` | OpenTofu cluster-lifecycle module — sole Talos provisioning path (per-class Image-Factory installer, Cilium + ArgoCD inlineManifest seeds, machine config, bootstrap, kubeconfig) | `*.tf`, `examples/homelab/` |
| `policies/` | conftest Rego — label hygiene over rendered manifests | `policies/conftest/*` |
| Validation pipeline | kustomize render + conftest + kubeconform | `scripts/`, `Makefile`, `.github/workflows/gitops-validate.yml` |
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

  Maintainer->>GitHub: git tag v1.0.0 && git push --tags
  GitHub->>CI: trigger
  CI->>GHCR: push :v1.0.0 (immutable)
  CI->>Sigstore: cosign sign + attest provenance
  Consumer->>GHCR: cosign verify + oras pull → vendor/base/
  Consumer->>Cluster: Multi-Source Application sees new tag
  Cluster->>Cluster: ArgoCD reconciles, applies merged manifests
```

See [`docs/oci-artifact-verification.md`](docs/oci-artifact-verification.md)
for the verification recipe.

## Sync-wave order

```text
-1  ArgoCD AppProjects             (RBAC boundary)
 0  Substrate components           (argocd, cert-approver)
 1  Apps (workload-layer, from the talos-platform-apps catalog)
```

## What this is NOT

- Not a runnable cluster — no node IPs, no SOPS secrets, no OIDC issuers.
- Not a library/SDK — no API users.
- Not an end-user product — the audience is operators and contributors.

Those concerns live in:

- **Consumer cluster repos** for cluster identity, secrets, overlays.
- **Application repos** for workload manifests.

## 10. Quality Requirements

The non-functional qualities the architecture optimises for. Each is
backed by a load-bearing mechanism in the repo today.

| Quality | Target | Mechanism |
|---|---|---|
| **Supply-chain integrity** | Every release verifiable to commit SHA via OIDC chain | cosign + SLSA + CycloneDX 1.6 SBOM in [`docs/oci-artifact-verification.md`](docs/oci-artifact-verification.md) |
| **Reproducibility** | `chart.lock.yaml` + `values.yaml` → identical rendered output | `verify-rendered.sh` (CI required); idempotent renderer |
| **Cluster-agnostic** | A second cluster pins a tag and bootstraps without base edits | `make day0` flow in consumer repo; `.base-version` pin; no IPs/FQDNs in base |
| **CI-required gates** | No broken main; no silent regression | conftest, kubeconform, REUSE lint, hard-constraints-check, hardware-features-check |
| **Multi-maintainer-ready** | New contributor can land a non-trivial change in ≤ 4 h human time | `CONTRIBUTING.md`, `MAINTAINERS.md`, per-component READMEs, MADR ADR template |
| **Operator-facing docs** | Audience is platform operators, not end-users — content is at operator altitude | Diátaxis-organised `docs/`; arc42 §1 explicitly excludes end-user audience |

## 11. Risks and Technical Debt

Honest accounting of where the architecture is fragile or in flight.
Each item is either tracked or has a documented mitigation; do not let
this list grow silently.

| Risk / debt | Severity | Mitigation / tracking |
|---|---|---|
| **Pre-release tags v0.2–v0.4 exist without GitHub Releases.** Consumers pinning to them get the OCI artifact but no human-readable changelog. | low | Documented in [`UPGRADING.md`](UPGRADING.md) §"Note on prior git tags"; v0.5.0 is the first canonical release |
| **OpenSSF Best Practices Badge not yet enrolled.** Self-assessment lives at [`docs/openssf-best-practices.md`](docs/openssf-best-practices.md); external enrolment is a manual step. | low | Will be addressed in a follow-up by the maintainer; badge appears in README only once project ID is assigned |
| **Multi-cluster reuse exercised against only one consumer (`talos-homelab-cluster`).** Second-consumer validation is desk-only. | medium | Issue #32 tracks an E2E Multi-Source demo against a second test cluster |
| **Single maintainer.** Bus factor = 1; review coverage on changes is human + automated gates, not multi-reviewer. | medium | OpenSSF Scorecard `Code-Review` check will score low by design; mitigated by aggressive CI gating and adversarial reviewer subagent dispatch on risky diffs |
| **`kubernetes/base/` tree duplicated in consumer repo (homelab) is a Phase-1.5 migration leftover.** | low | Tracked consumer-side; not a base-repo concern |
| **Vale prose linter** for prose-style consistency. | low | Done — configured in #57 (`.vale.ini` + `vale.yml` CI workflow) |

## 12. Glossary

The cross-domain vocabulary used in this document lives in
[`docs/glossary.md`](docs/glossary.md) (per Diátaxis "Reference"
quadrant). AGENTS.md §"Key Terms" carries the curated subset
auto-loaded into agent contexts.

## See also

- [`docs/README.md`](docs/README.md) — full documentation index (Diátaxis-organised)
- [`docs/adr-0004-substrate-only-base.md`](docs/adr-0004-substrate-only-base.md) — substrate / apps-catalog boundary
- [`docs/adr-0009-node-capability-composition.md`](docs/adr-0009-node-capability-composition.md) — Layer-C per-node hardware capability composition
- [`AGENTS.md`](AGENTS.md) — tool-agnostic SOT (canonical for agents)
- [`docs/openssf-best-practices.md`](docs/openssf-best-practices.md) — self-assessment against OpenSSF Passing-level criteria
