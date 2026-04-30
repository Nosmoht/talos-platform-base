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
- `docs/`: platform-base reference docs (issue workflow, MCP setup, primitive contract, ADR for the multi-repo split).

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

## Platform Network Interface (PNI) Rules

PNI is the platform's tenant-network contract. Base ships only the generic
pattern (namespace/pod label conventions, Kyverno enforcement policies, the 18
capability CCNPs whose CIDR rules use IANA-reserved RFC1918 blocks as RFC-standard
"private network" exclusions). Consumer cluster overlays carry the only
cluster-specific value (`cluster-config-cm.yaml` with `external_hostname_pattern`).

- Default to PNI for consumer-to-platform connectivity.
- Consumer namespace contract (namespace-level labels):
  - `platform.io/network-interface-version: v1`
  - `platform.io/network-profile: restricted|managed|privileged`
  - explicit capability opt-in: `platform.io/consume.<capability>: "true"`
- Consumer pod contract (pod-level labels):
  - Every pod that consumes a PNI capability must carry `platform.io/capability-consumer.<capability>: "true"` on the pod template.
- Never set provider-reserved labels in consumer manifests: `platform.io/provider`, `platform.io/managed-by`, `platform.io/capability`.

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

## Key Terms

- **PNI** — Platform Network Interface: Kyverno-enforced namespace contract for platform service access. Base ships the pattern; consumer overlays carry environment-specific values.
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
