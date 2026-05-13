# Repository Guidelines — `talos-platform-base`

## Repository Purpose

This is the cluster-agnostic platform base for the Talos-on-Kubernetes
deployment family. It provides Helm-base manifests, Talos machine-config
patches, ArgoCD bootstrap templates, and the validation pipeline that any
consumer cluster repo (e.g. `talos-homelab-cluster`, future
`talos-office-lab-cluster`) builds upon via OCI-artifact consumption.

It is **NOT a runnable cluster**. It does NOT contain cluster identity, node
IPs, secrets, or environment-specific overrides. Those live in consumer
cluster repos that pin a specific tag of this base.

## Project Structure & Module Organization

- `kubernetes/base/infrastructure/`: base Helm values and namespace/kustomization manifests per infrastructure component.
- `kubernetes/bootstrap/argocd/`: parameterized bootstrap templates (`*.tmpl`) consumed by `make argocd-bootstrap`.
- `kubernetes/bootstrap/cilium/`: base Cilium Helm values and `extras.yaml` (rendered cilium.yaml is cluster-side).
- `talos/`: Talos machine config inputs (`patches/`), Makefile with `cluster.yaml`-driven multi-cluster generation.
- `policies/`: conftest Rego policies for kustomize-rendered manifests.
- `scripts/`: cluster-agnostic validation, render and helper scripts.
- `docs/`: platform-base reference docs. See [`docs/README.md`](docs/README.md) for the navigable map (architecture, contract cookbook, ADRs, workflow refs).

## Build, Test, and Development Commands

- `make init-cluster-yaml`: copies `cluster.yaml.example` to `cluster.yaml` (gitignored) for local validation.
- `make validate-gitops`: kustomize-render + SOPS check + conftest + kubeconform across all rendered manifests.
- `make validate-kyverno-policies`: server-side validation of base Kyverno ClusterPolicies (PNI contract, reserved-labels, vault-ca-distribution, capability-validation).
- `make mcp-install` / `make mcp-verify`: install and verify MCP server binaries.
- `make -C talos gen-configs`: generates Talos node configs from `cluster.yaml` (consumer-side; needs `talos/nodes/` from a consumer repo).

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
| Producer Service | annotations `platform.io/capability-endpoint.<cap>[.<inst>]: <port-name>` and `platform.io/capability-protocol.<cap>[.<inst>]: <wire>` | yes | producer Helm `service.annotations` (discovery only — not enforced) |
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
- Legacy keys still forbidden everywhere: `platform.io/provider`, `platform.io/managed-by`, `platform.io/capability`.

### Capability-first selectors

CCNPs use `capability-provider.<cap>` and `capability-consumer.<cap>`
selectors, never tool-name labels. A Prometheus → Victoria-Metrics or
Loki → Victoria-Logs swap is a label move on the producer pod template,
not a CCNP edit.

Exception: cluster-singleton plumbing without a capability fit
(e.g. `kube-dns` in `monitoring-dns-visibility`) keeps the tool selector
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
- For Talos config changes:
  - `make -C talos gen-configs ENV=<consumer-cluster.yaml>` (in a consumer-repo checkout)

---

## Hard Constraints

These are universal cluster invariants. CLAUDE.md imports this file via
`@AGENTS.md`. Both tools treat this section as canonical. Do NOT relax these
without repo-maintainer approval.

- **No SecureBoot** — `metal-installer-secureboot` causes boot loops; always use `metal-installer`
- **No `debugfs=off`** — causes "failed to create root filesystem" boot loop in Talos
- **Gateway API only** — no `kind: Ingress` or Ingress controllers; use HTTPRoute/TLSRoute
- **EndpointSlices only** — `kind: Endpoints` deprecated since Kubernetes v1.33.0; use `EndpointSlice`
- **Commit and push every successful tested change immediately** — do not batch at end of session
- **NEVER `kubectl apply` ArgoCD-managed resources** — commit to git, push, let ArgoCD sync; only exception: one-time bootstrap AppProjects (`kubernetes/bootstrap/`)
- **Kubernetes recommended labels on all resources** — `app.kubernetes.io/{name,instance,version,component,part-of,managed-by}`
- **File naming conventions** — `cnp-<component>.yaml`, `ccnp-<description>.yaml`; component dirs must match ArgoCD Application name
- **PNI first** for consumer-to-platform connectivity — do not begin with ad-hoc CNPs for managed platform services
- **Capability selectors only** for new CCNPs — never `app.kubernetes.io/name: <tool>`; selector MUST be `capability-provider.<cap>` or `capability-consumer.<cap>`. Documented plumbing exceptions are explicitly named in the file header.
- **Namespace-anchored producer trust** — every component setting `capability-provider.<cap>` on its pod template MUST also ship its own `namespace.yaml` carrying `platform.io/provide.<cap>: "true"`. No kube-system exemptions; relocate to a dedicated namespace instead.

## Key Terms

- **PNI** — Platform Network Interface: Kyverno+Cilium contract for capability-mediated access. v2 = capability-first, namespace-anchored, instance-aware (see ADR).
- **Capability** — stable, tool-agnostic identifier for a platform service (`monitoring-scrape`, `tls-issuance`, `cnpg-postgres`, …). Registry: `capability-registry-configmap.yaml`.
- **Instanced capability** — capability whose data plane is partitioned per tenant (`cnpg-postgres.<cluster>`, `vault-secrets.<mount>`); requires the `<inst>` label suffix.
- **Producer/Consumer symmetry** — for every capability, five sites carry the contract (namespace, pod, service annotation × producer/consumer). See AGENTS.md §PNI table.
- **Namespace-anchored trust** — `capability-provider.<cap>` on a pod is valid iff its namespace carries `provide.<cap>: "true"`. No central tool-signature whitelist.
- **AppProject** — ArgoCD RBAC boundary scoping repos/namespaces an Application can deploy to.
- **Sync-wave** — ArgoCD annotation for deploy order: `-1` (AppProjects) → `0` (infra) → `1` (apps).
- **Schematic** — Talos Image Factory spec embedding system extensions into installer images. Cluster-side input lives in consumer repo's `talos/talos-factory-schematic*.yaml`.
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

This base ships no `.claude/rules/`. Domain rules are part of the
`kube-agent-harness` Claude Code plugin. Consumer cluster repos either install
the plugin or copy the relevant rules into their own `.claude/rules/`
directory. See the harness repo for the rule catalogue.

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
2. **No auto-subagent dispatch**: Subagents (when shipped via the harness plugin) run only on explicit request.
3. **No `paths:` rule auto-loading**: read the relevant rule file from the harness plugin (or consumer repo's `.claude/rules/`) on demand.
4. **`--no-verify` bypass is possible locally**: Required PR checks (`gitleaks` CLI in `gitops-validate.yml`, `hard-constraints-check`) block merge server-side.
