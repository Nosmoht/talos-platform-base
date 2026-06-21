# Repository Guidelines — `talos-platform-base`

## Repository Purpose

This is the cluster-agnostic platform base for the Talos-on-Kubernetes
deployment family. It provides Helm-base manifests, Talos machine-config
patches, ArgoCD bootstrap templates, and the validation pipeline that any
consumer cluster repo builds upon via OCI-artifact consumption.

It is **NOT a runnable cluster**. It does NOT contain cluster identity, node
IPs, secrets, or environment-specific overrides. Those live in consumer
cluster repos that pin a specific tag of this base.

**Platform layering (base / apps / consumer).** The platform is layered and
the boundary is binary. `talos-platform-base` is the **substrate** — the
cluster-agnostic floor every cluster needs. Its core is three **co-equal
pillars: Talos + Cilium + ArgoCD**; the GitOps engine (ArgoCD) is as
constitutive as the OS (Talos) and the CNI (Cilium), **not** a Day-2 app.
`cert-approver` is the only addition, present solely as Talos boot-necessity
glue (no CSR auto-approval → no bootable cluster), not a fourth pillar.
Because ArgoCD is core substrate it is delivered as part of standing the
cluster up — **opt-out, never an opt-in Day-2 add-on**; classifying
ArgoCD-bootstrap as Day-2 is a scoping error. `talos-platform-apps` is the
**central catalog**: every platform
component that is *not* substrate lives there as independently versioned,
signed OCI artifacts. Consumer cluster repos **compose** — they pin a base
tag for the substrate and serve themselves from the apps catalog by
referencing exactly the OCI components they need. Routing rule: if it is not
substrate, it belongs in the apps catalog, never in base. See
[`docs/adr-substrate-only-base.md`](docs/adr-substrate-only-base.md) and the
platform layer model (`talos-platform-docs` ADR-0009).

## Project Structure & Module Organization

- `kubernetes/base/infrastructure/`: base Helm values and namespace/kustomization manifests per infrastructure component.
- `kubernetes/bootstrap/argocd/`: parameterized bootstrap templates (`*.tmpl`) consumed by `make argocd-bootstrap`.
- `kubernetes/bootstrap/cilium/`: reference Cilium Helm values + `extras.yaml` (GatewayClass) for optional Day-2 self-management. Cilium itself is delivered by the `talos-cluster` module as a controlplane `inlineManifest` seed (`deploy_cilium`); the former consumer-side render path is retired.
- `tofu/modules/talos-cluster/`: the OpenTofu module that is the sole Talos cluster-lifecycle path (machine secrets, per-node composed Image-Factory installer — content-hash-deduped, config apply, bootstrap, kubeconfig). Backend- and identity-agnostic; called by a consumer-side OpenTofu root that is a thin `yamldecode` shim over the declarative `cluster.yaml` SoT. See [`docs/adr-opentofu-cluster-lifecycle.md`](docs/adr-opentofu-cluster-lifecycle.md) and [`docs/adr-cluster-yaml-sot.md`](docs/adr-cluster-yaml-sot.md).
- `policies/`: conftest Rego policies for kustomize-rendered manifests.
- `scripts/`: cluster-agnostic validation, render and helper scripts.
- `docs/`: platform-base reference docs. See [`docs/README.md`](docs/README.md) for the navigable map (architecture, contract cookbook, ADRs, workflow refs).

## Build, Test, and Development Commands

- `make init-cluster-yaml`: copies `cluster.yaml.example` to `cluster.yaml` (gitignored) — the declarative cluster Source-of-Truth (identity, versions, endpoint, network, nodes, images, hardware-capabilities, machine-config patches, substrate). `make argocd-bootstrap` reads only the bootstrap-identity subset (`cluster.{name,overlay,target_revision}` + `repo.url`); the consumer's OpenTofu root is a thin `yamldecode` shim that maps the full file onto the `tofu/modules/talos-cluster` typed interface. tofu is the executor, not the SoT. See [`docs/adr-cluster-yaml-sot.md`](docs/adr-cluster-yaml-sot.md).
- `make validate-gitops`: kustomize-render + SOPS check + conftest + kubeconform across all rendered manifests.
- `make validate-kyverno-policies`: server-side validation of base Kyverno ClusterPolicies (PNI contract, reserved-labels, vault-ca-distribution, capability-validation).
- `make mcp-install` / `make mcp-verify`: install and verify MCP server binaries.
- `task ci` (devbox): `tofu fmt -check` + `tofu validate` + `tflint` over the `tofu/` cluster-lifecycle module and its examples.
- **The `make` ↔ `task` split is intentional — do not migrate `make`→`task`.** `task` (devbox) covers `tofu/`; `make` covers GitOps / Kyverno / bootstrap / MCP. Per [`docs/adr-task-runner-consolidation.md`](docs/adr-task-runner-consolidation.md) the `Makefile` dissolves *with* the substrate-only split (`docs/adr-substrate-only-base.md`): its component render-and-validate / Kyverno targets exit with their components at Phase-3 ablation, and the surviving targets fold into the Taskfile then. **The ArgoCD bootstrap targets are a separate, immediate case** — ArgoCD is already module-delivered (`inlineManifest`), so `make argocd-install` / `argocd-bootstrap` are dead; the double-install is fixed **now** under #113, not deferred to Phase 3. (devbox declares `go-task`, not `gnumake`; the `gnumake` bridge for still-live `make` targets is also #113.)

This base is consumed by cluster repos via OCI artifact (`oras pull
ghcr.io/nosmoht/talos-platform-base:<tag>`) into a gitignored `vendor/base/`
directory; live ArgoCD reconciliation uses a Multi-Source Application
referencing both the cluster repo and this base.

## Coding Style & Naming Conventions

- YAML with 2-space indentation; keep keys and list nesting consistent with existing manifests.
- One component per directory (`.../component/{application.yaml,kustomization.yaml,values.yaml}`).
- Conventional Commit style with subsystem scope (`fix(cilium): …`, `chore(talos): …`).
- Component directory name must equal the ArgoCD Application name (`kube-prometheus-stack/`, not `monitoring/`).

## Testing Guidelines

- This repo has no live cluster. Validation is manifest-render and policy focused.
- Required before opening a PR:
  - `make validate-gitops`
  - `make validate-kyverno-policies`
  - `kubectl kustomize kubernetes/base/infrastructure/<component>/` for any touched component
- Live runtime verification belongs in consumer cluster repos.

## Commit & Pull Request Guidelines

- Follow Conventional Commit style: `type(scope): short imperative summary`.
- Keep commits focused and logically grouped.
- PRs include: what changed and why, impacted components, validation steps run, breaking-change notes (Helm-value defaults that downstream consumers need to be aware of).
- A breaking change to base Helm values requires bumping the next OCI tag's MAJOR version per CHANGELOG.

## Codex CLI Operating Rules (Important)

- This file (`AGENTS.md`) is the canonical source of truth.
- Never `kubectl apply` ArgoCD-managed resources for rollout; commit to git and let consumer ArgoCD reconcile.
- Direct-apply exception: bootstrap content under `kubernetes/bootstrap/`.
- Keep secret material out of base — there is no `*.sops.yaml` in this repo.

## Platform Network Interface (PNI) — v2 Capability-First Contract

PNI is the platform's tenant-network contract. The architecture is
**capability-first**: capabilities are the stable interface, tools are
swappable implementations. Trust is **namespace-anchored**: a pod's
`capability-provider.<cap>` claim is valid only if its namespace declares
the matching `provide.<cap>` label. There is no central tool-signature
whitelist.

Authoritative refs:

- [ADR — Capability Producer/Consumer Symmetry](docs/adr-capability-producer-consumer-symmetry.md) — design decision, alternatives, consequences
- [`docs/capability-architecture.md`](docs/capability-architecture.md) — architecture overview + enforcement summary
- [`docs/pni-cookbook.md`](docs/pni-cookbook.md) — how-to recipes (consumer/producer manifests)
- [`docs/capability-reference.md`](docs/capability-reference.md) — per-capability catalogue (auto-generated; do not hand-edit)
- Registry source of truth: `kubernetes/base/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml`

### Five label/annotation sites per capability

| Site | Key | Reserved | Set by |
|---|---|---|---|
| Producer Namespace | `platform.io/provide.<cap>[.<inst>]: "true"` | yes | base manifests (RBAC-gated) |
| Producer Pod | `platform.io/capability-provider.<cap>[.<inst>]: "true"` | yes | producer Helm `podLabels` |
| Producer Service | annotations `platform.io/capability-endpoint.<cap>[.<inst>]: <port-name>` and `platform.io/capability-protocol.<cap>[.<inst>]: <wire>` | yes | producer Helm `service.annotations` — discovery semantics only (not used by CCNP `endpointSelector`); tenant-set forgery on Services denied by `pni-reserved-annotations-enforce` |
| Consumer Namespace | `platform.io/consume.<cap>[.<inst>]: "true"` | no | consumer manifests |
| Consumer Pod | `platform.io/capability-consumer.<cap>[.<inst>]: "true"` | no | consumer Helm `podLabels` |

`<inst>` suffix is mandatory for capabilities marked `instanced: true` in
the registry (`vault-secrets`, `cnpg-postgres`, `redis-managed`,
`rabbitmq-managed`, `kafka-managed`, `s3-object`). Audit-mode policy
`pni-instanced-suffix-required-audit` flags missing suffixes via
PolicyReport without blocking.

Namespace contract also carries:

- `platform.io/network-interface-version: v1`
- `platform.io/network-profile: restricted|managed|privileged`

### Reserved-label rule

Reserved keys MUST NOT appear on tenant-owned resources. Concretely:

- `platform.io/provide.*` — settable only by base manifests (RBAC).
- `platform.io/capability-provider.*` — settable on a workload only if its namespace carries the matching `provide.*` (namespace-anchored rule in `kyverno-clusterpolicy-pni-reserved-labels-enforce.yaml`).
- `platform.io/capability-endpoint.*` / `capability-protocol.*` on a Service — settable only by producer charts (admission policy `pni-reserved-annotations-enforce`).
- `platform.io/hardware-feature.*` (Layer-C atomic) — settable only by Talos `machine.nodeLabels` or a Layer-C discovery relay. Tenant forgery on Pods / Namespaces / Services denied by the `reserved-layer-c-hardware-labels` rule in `kyverno-clusterpolicy-pni-reserved-labels-enforce.yaml`. Catalogue: `docs/platform-hardware-features.yaml`.
- `platform.io/hardware-capability.*` (Layer-C composite, downstream-defined) — settable only by Talos `machine.nodeLabels`. Composite capability ids are NOT base-shipped; consumer cluster repos declare them per the composite-capability convention in `docs/adr-three-layer-capability-architecture.md` §Composite capability convention. Same enforcement rule as above.
- Legacy keys still forbidden everywhere: `platform.io/provider`, `platform.io/managed-by`, `platform.io/capability`.

Upstream-owned label namespaces are governed by **convention, not by base policy**:

- `feature.node.kubernetes.io/*` — owned by the NFD chart (NFD discovers hardware features and emits labels in its own namespace). The base does NOT relabel, proxy, or duplicate NFD-emitted labels into `platform.io/hardware-feature.*`. Both namespaces coexist; consumers choose which to reference for which decision.
- `nvidia.com/*` — owned by the NVIDIA device plugin (vendor namespace = package name). Same coexistence convention.

### Capability-first selectors

CCNPs use `capability-provider.<cap>` and `capability-consumer.<cap>`
selectors, never tool-name labels. A Prometheus → Victoria-Metrics or
Loki → Victoria-Logs swap is a label move on the producer pod template,
not a CCNP edit.

Exception: cluster-singleton plumbing without a capability fit
(for example `kube-dns` in `monitoring-dns-visibility`) keeps the tool selector
and is explicitly documented as such.

### Out of scope for the base

The base ships the **vocabulary contract + advisory** only. Per-instance
generate/mutate Kyverno machinery (one CCNP per CR instance) is
**consumer-overlay responsibility** — the base does not deploy the
instance CRs (Vault server, CNPG `Cluster`, `RabbitmqCluster`,
`RedisFailover`, `Kafka`, `LinstorCluster`) so per-instance enforcement
is plugged in by the consumer overlay that deploys the tool.

## Validation Checklist For Codex Changes

- For base/infrastructure changes:
  - `kubectl kustomize kubernetes/base/infrastructure/<component>/`
  - `make validate-gitops`
- If editing Kyverno `ClusterPolicy` resources:
  - `make validate-kyverno-policies`
- For Talos cluster-lifecycle (`tofu/`) changes:
  - `task ci` (or `tofu fmt -check -recursive tofu/` + per-dir `tofu init -backend=false && tofu validate` + `tflint`)

---

## Hard Constraints

These are universal cluster invariants. CLAUDE.md imports this file via
`@AGENTS.md`. Both tools treat this section as canonical. Do NOT relax these
without repo-maintainer approval.

- **No SecureBoot** — `metal-installer-secureboot`, the bare `metal-secureboot`, and the Image-Factory `installer-secureboot` URL form all cause boot loops; always use the non-secureboot installer. The `tofu/modules/talos-cluster` module enforces this in code (selects `urls.installer`, never `urls.installer_secureboot`). CI gate: `hard-constraints-check.yml` greps `(metal-secureboot|installer-secureboot)` over `tofu/**`. Decision: [`docs/adr-substrate-hard-constraints.md`](docs/adr-substrate-hard-constraints.md).
- **No `debugfs=off`** — causes "failed to create root filesystem" boot loop in Talos. Decision: [`docs/adr-substrate-hard-constraints.md`](docs/adr-substrate-hard-constraints.md).
- **Gateway API only** — no `kind: Ingress` or Ingress controllers; use HTTPRoute/TLSRoute
- **EndpointSlices only** — `kind: Endpoints` deprecated since Kubernetes v1.33.0; use `EndpointSlice`. Decision: [`docs/adr-substrate-hard-constraints.md`](docs/adr-substrate-hard-constraints.md).
- **Commit and push every successful tested change immediately** — do not batch at end of session
- **NEVER `kubectl apply` ArgoCD-managed resources** — commit to git, push, let ArgoCD sync; only exception: one-time bootstrap AppProjects (`kubernetes/bootstrap/`)
- **Kubernetes recommended labels on all resources** — `app.kubernetes.io/{name,instance,version,component,part-of,managed-by}`
- **File naming conventions** — `cnp-<component>.yaml`, `ccnp-<description>.yaml`; component dirs must match ArgoCD Application name
- **PNI first** for consumer-to-platform connectivity — do not begin with ad-hoc CNPs for managed platform services
- **Capability selectors only** for new CCNPs — never `app.kubernetes.io/name: <tool>`; selector MUST be `capability-provider.<cap>` or `capability-consumer.<cap>`. Documented plumbing exceptions are explicitly named in the file header.
- **Namespace-anchored producer trust** — every component setting `capability-provider.<cap>` on its pod template MUST also ship its own `namespace.yaml` carrying `platform.io/provide.<cap>: "true"`. No kube-system exemptions; relocate to a dedicated namespace instead.

## Key Terms

Curated subset for agent-context loading. Full definitions and the long
tail (Reserved label, PolicyReport, Capability-selector, Rendered Manifests
Pattern, Right altitude, Two-layer capability vocabulary, …) live in
[`docs/glossary.md`](docs/glossary.md); cite that file for terms not in
this list.

- **PNI** — Platform Network Interface: Kyverno+Cilium contract for capability-mediated access. v2 = capability-first, namespace-anchored, instance-aware (see ADR).
- **Capability** — stable, tool-agnostic identifier for a platform service (`monitoring-scrape`, `tls-issuance`, `cnpg-postgres`, …). Registry: `capability-registry-configmap.yaml`.
- **Instanced capability** — capability whose data plane is partitioned per tenant (`cnpg-postgres.<cluster>`, `vault-secrets.<mount>`); requires the `<inst>` label suffix.
- **Producer/Consumer symmetry** — for every capability, five sites carry the contract (namespace, pod, service annotation × producer/consumer). See AGENTS.md §PNI table.
- **Namespace-anchored trust** — `capability-provider.<cap>` on a pod is valid iff its namespace carries `provide.<cap>: "true"`. No central tool-signature whitelist.
- **AppProject** — ArgoCD RBAC boundary scoping repos/namespaces an Application can deploy to.
- **Sync-wave** — ArgoCD annotation for deploy order: `-1` (AppProjects) → `0` (infra) → `1` (apps).
- **Schematic** — Talos Image Factory spec embedding system extensions (and optional SBC overlay) into installer images. Derived per node by the `tofu/modules/talos-cluster` module: the node's `image` (baseline `extensions` + `overlay` + `architecture`) unioned with the `extensions` + `extraKernelArgs` of the provisioning profiles its `hardware_capabilities` resolve to; content-hash-deduped so identical nodes share one schematic.
- **CCNP/CNP** — CiliumClusterwideNetworkPolicy / CiliumNetworkPolicy. Named `ccnp-*.yaml` / `cnp-*.yaml`.
- **DRBD** — Distributed Replicated Block Device — LINSTOR replication layer for persistent storage.
- **Multi-Source Application** — ArgoCD Application with `spec.sources[base, cluster]` consuming this base alongside consumer cluster manifests.
- **OCI artifact** — versioned tarball of this base published to `ghcr.io/nosmoht/talos-platform-base:<tag>` on every git tag push; consumed via `oras pull`.

## Tool-Agnostic Safety Invariants

| Safety Gate | Enforced via | Fail Reason |
|---|---|---|
| AWS/GitHub tokens in any file | pre-commit `gitleaks` hook | Credential leak prevention |
| `git commit --no-verify` bypass | CI `gitleaks` CLI in `gitops-validate.yml` `secret-scan` job (required PR check) | Last backstop — blocks merge even if local hooks bypassed |
| Forbidden Kubernetes kinds (Ingress, Endpoints) | CI `hard-constraints-check.yml` (required PR check) | Server-side enforcement of §Hard Constraints |
| SOPS plaintext leak (consumer-side) | pre-commit + Claude Code PreToolUse hook (consumer repo) | Plaintext secrets must never reach git |

`*.sops.yaml` does not exist in this base repo. Consumer cluster repos add
their own SOPS gate via pre-commit.

## Domain Rules — On-Demand Reference

This base ships no `.claude/rules/` and depends on none. Any domain rules come
from an external harness that an operator or consumer repo installs — verify a
rule file is present in the working repo before relying on it.

## MCP Server Configuration

All three MCP servers (github, kubernetes-mcp-server, talos) use **bare
PATH-resolved command names**. Run `make mcp-install` once after cloning to
install the binaries and register the wrapper symlink. See `docs/mcp-setup.md`
for full instructions.

`.mcp.json` (Claude Code) and consumer-side `.codex/config.toml` (Codex CLI)
both reference:

- `mcp-github-wrapper` — PATH-installed symlink pointing to `scripts/mcp-github-wrapper.sh`
- `kubernetes-mcp-server` — Homebrew (macOS) or npm binary
- `talos-mcp` — npm binary

The wrapper fetches the GitHub token from `gh auth token` at spawn time and
injects it only into the `github-mcp-server` child process — the token is
never exported to the shell environment.

## Session-Start Ritual

At session start, scan the GitHub Issues backlog. Use the `github` MCP server.

1. `mcp__github__list_issues(state="open", labels=["status: ready"])`
2. `mcp__github__list_issues(state="open", labels=["status: in-progress"])`
3. **Status gate**: only the `status: ready` label authorizes work to begin.

See `docs/issue-workflow.md` for the full issue lifecycle.

## Deltas vs Claude Code (For Codex CLI Users)

1. **No PreToolUse interception**: Tool-agnostic safety begins at `git commit` (pre-commit framework).
2. **No auto-subagent dispatch**: any subagents come from an externally installed harness (not this base) and run only on explicit request.
3. **No `paths:` rule auto-loading**: if an external harness or consumer repo provides rule files, read the relevant one on demand.
4. **`--no-verify` bypass is possible locally**: Required PR checks (`gitleaks` CLI in `gitops-validate.yml`, `hard-constraints-check`) block merge server-side.

## ADR-Abdeckung

Operative decisions an agent here must honor that the sections above do not yet spell out:

- **Namespace ownership** ([`docs/adr-namespace-ownership-rendered-manifests.md`](docs/adr-namespace-ownership-rendered-manifests.md)) — one Application owns each namespace (the component itself); a consumer `root` Application MUST NOT track platform (vendor-shipped) namespaces, and no `Prune=false` is set on a platform namespace. `argocd` is the only chicken-and-egg exception.
- **Signed-OCI producer obligation** (`talos-platform-docs` ADR-0009) — the base OCI artifact is cosign-signed (keyless OIDC), carries SLSA build provenance and a CycloneDX SBOM attestation, produced on every tag push by [`.github/workflows/oci-publish.yml`](.github/workflows/oci-publish.yml). Consumer-side verification is documented in [`docs/oci-artifact-verification.md`](docs/oci-artifact-verification.md). (The layer-model reference under §Repository Purpose covers *what* base produces; this is the supply-chain *how*.)
- **Policy-stack role split** (`talos-platform-docs` ADR-0018) — base ships the `pni-reserved-labels-enforce` Kyverno ClusterPolicy (validated by `make validate-kyverno-policies`); the Conftest-in-CI counterpart lives in `talos-platform-apps`, not here. The `policies/` Conftest in this repo is base-scoped.
- **Node capability composition** ([`docs/adr-node-capability-composition.md`](docs/adr-node-capability-composition.md)) — per-node provisioning is DECOUPLED from hardware detection; the per-node provisioning-profile catalog is base-owned/module-local (a consumer cannot redefine it). A consumer `emits_label` MUST land in `platform.io/hardware-capability.*`, never `hardware-feature.*` (Layer-C atomic, Talos-only). These are the mechanical anti-forgery / anti-override invariants a composing agent must honor — §PNI above states the resulting label rules; this names the decision behind them.
- **Capability-layer model & base→apps migration** ([talos-platform-docs ADR-0021](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0021-capability-layer-model.md)) — capability = stable interface, tool = swappable implementation; `base:three-layer-capability-architecture` realizes it for the substrate. The base-resident PNI / Layer-A surface (§PNI above) is **not permanent**: per [`docs/adr-substrate-only-base.md`](docs/adr-substrate-only-base.md) §Amendment 2026-06-03 it *dissolves* (not "moves to apps") into apps-CI Conftest + consumer-cluster Kyverno at Phase-3 ablation — do not treat the full base-resident capability/PNI surface as durable. (The original §Component Classification table routed PNI to apps as a *move*; the Amendment reclassified it as dissolve.)
