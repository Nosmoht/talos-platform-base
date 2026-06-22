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
- `kubernetes/bootstrap/argocd/`: parameterized bootstrap templates (`*.tmpl`) consumed by `task bootstrap:argocd`.
- `kubernetes/bootstrap/cilium/`: reference Cilium Helm values + `extras.yaml` (GatewayClass) for optional Day-2 self-management. Cilium itself is delivered by the `talos-cluster` module as a controlplane `inlineManifest` seed (`deploy_cilium`); the former consumer-side render path is retired.
- `tofu/modules/talos-cluster/`: the OpenTofu module that is the sole Talos cluster-lifecycle path (machine secrets, per-node composed Image-Factory installer — content-hash-deduped, config apply, bootstrap, kubeconfig). Backend- and identity-agnostic; called by a consumer-side OpenTofu root that is a thin `yamldecode` shim over the declarative `cluster.yaml` SoT. See [`docs/adr-opentofu-cluster-lifecycle.md`](docs/adr-opentofu-cluster-lifecycle.md) and [`docs/adr-cluster-yaml-sot.md`](docs/adr-cluster-yaml-sot.md).
- `policies/`: conftest Rego policies for kustomize-rendered manifests.
- `scripts/`: cluster-agnostic validation, render and helper scripts.
- `docs/`: platform-base reference docs. See [`docs/README.md`](docs/README.md) for the navigable map (architecture, contract cookbook, ADRs, workflow refs).

## Build, Test, and Development Commands

- `task cluster:init-yaml`: copies `cluster.yaml.example` to `cluster.yaml` (gitignored) — the declarative cluster Source-of-Truth (identity, versions, endpoint, network, nodes, images, hardware-capabilities, machine-config patches, substrate). `task bootstrap:argocd` reads only the bootstrap-identity subset (`cluster.{name,overlay,target_revision}` + `repo.url`); the consumer's OpenTofu root is a thin `yamldecode` shim that maps the full file onto the `tofu/modules/talos-cluster` typed interface. tofu is the executor, not the SoT. See [`docs/adr-cluster-yaml-sot.md`](docs/adr-cluster-yaml-sot.md).
- `task gitops:validate`: kustomize-render + SOPS check + conftest + kubeconform across all rendered manifests.
- `task mcp:install` / `task mcp:verify`: install and verify MCP server binaries.
- `task tofu:ci` (devbox): `tofu fmt -check` + `tofu validate` + `tflint` + render-determinism fence over the `tofu/` cluster-lifecycle module and its examples.
- **go-task is the single runner — the `Makefile` was retired at v3.0.0.** Every former `make` target folds into a namespaced task in `Taskfile.yml`: `tofu:*` (OpenTofu validation), `gitops:*` (`validate`, `render-component`, `render-all`, `verify-rendered`), `bootstrap:*` (`argocd`, `argocd-password`), `cluster:init-yaml`, `supply-chain:oci-allowlist`, `mcp:*`, `dev:*`. Run `task --list` for the full set. A `Makefile` deprecation stub remains for one release cycle: any `make <target>` prints the migration mapping and exits non-zero. `chart-pull` and `grafana-dashboards-check` were dropped (no replacement). Decision: [`docs/adr-makefile-retirement.md`](docs/adr-makefile-retirement.md) (supersedes [`docs/adr-task-runner-consolidation.md`](docs/adr-task-runner-consolidation.md)).

This base is consumed by cluster repos via OCI artifact (`oras pull
ghcr.io/nosmoht/talos-platform-base:<tag>`) into a gitignored `vendor/base/`
directory; live ArgoCD reconciliation uses a Multi-Source Application
referencing both the cluster repo and this base.

## Coding Style & Naming Conventions

- YAML with 2-space indentation; keep keys and list nesting consistent with existing manifests.
- One component per directory (`.../component/{application.yaml,kustomization.yaml,values.yaml}`).
- Conventional Commit style with subsystem scope (`fix(cilium): …`, `chore(talos): …`).
- Component directory name must equal the ArgoCD Application name (`cert-approver/`, not `csr-approver/`).

## Testing Guidelines

- This repo has no live cluster. Validation is manifest-render and policy focused.
- Required before opening a PR:
  - `task gitops:validate`
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

## Validation Checklist For Codex Changes

- For base/infrastructure changes:
  - `kubectl kustomize kubernetes/base/infrastructure/<component>/`
  - `task gitops:validate`
- For Talos cluster-lifecycle (`tofu/`) changes:
  - `task tofu:ci` (or `tofu fmt -check -recursive tofu/` + per-dir `tofu init -backend=false && tofu validate` + `tflint`)

---

## Hard Constraints

These are universal cluster invariants. CLAUDE.md imports this file via
`@AGENTS.md`. Both tools treat this section as canonical. Do NOT relax these
without repo-maintainer approval.

- **No SecureBoot** — `metal-installer-secureboot`, the bare `metal-secureboot`, and the Image-Factory `installer-secureboot` URL form all cause boot loops; always use the non-secureboot installer. The `tofu/modules/talos-cluster` module enforces this in code (selects `urls.installer`, never `urls.installer_secureboot`). CI gate: `hard-constraints-check.yml` greps `(metal-secureboot|installer-secureboot)` over `tofu/**`. Decision: [`docs/adr-substrate-hard-constraints.md`](docs/adr-substrate-hard-constraints.md).
- **No `debugfs=off`** — causes "failed to create root filesystem" boot loop in Talos (with Cilium). Decision: [`docs/adr-substrate-hard-constraints.md`](docs/adr-substrate-hard-constraints.md).
- **Gateway API only** — no `kind: Ingress` or Ingress controllers; use HTTPRoute/TLSRoute
- **EndpointSlices only** — `kind: Endpoints` deprecated since Kubernetes v1.33.0; use `EndpointSlice` (GA since v1.21). Decision: [`docs/adr-substrate-hard-constraints.md`](docs/adr-substrate-hard-constraints.md).
- **Commit and push every successful tested change immediately** — do not batch at end of session
- **NEVER `kubectl apply` ArgoCD-managed resources** — commit to git, push, let ArgoCD sync; only exception: one-time bootstrap AppProjects (`kubernetes/bootstrap/`)
- **Kubernetes recommended labels on all resources** — `app.kubernetes.io/{name,instance,version,component,part-of,managed-by}`
- **File naming conventions** — component dirs must match the ArgoCD Application name

## Key Terms

Curated subset for agent-context loading. Full definitions and the long
tail (Rendered Manifests Pattern, Right altitude, …) live in
[`docs/glossary.md`](docs/glossary.md); cite that file for terms not in
this list.

- **AppProject** — ArgoCD RBAC boundary scoping repos/namespaces an Application can deploy to.
- **Sync-wave** — ArgoCD annotation for deploy order: `-1` (AppProjects) → `0` (infra) → `1` (apps).
- **Schematic** — Talos Image Factory spec embedding system extensions (and optional SBC overlay) into installer images. Derived per node by the `tofu/modules/talos-cluster` module: the node's `image` (baseline `extensions` + `overlay` + `architecture`) unioned with the `extensions` + `extraKernelArgs` of the provisioning profiles its `hardware_capabilities` resolve to; content-hash-deduped so identical nodes share one schematic.
- **DRBD** — Distributed Replicated Block Device — LINSTOR replication layer for persistent storage (apps-catalog component).
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
PATH-resolved command names**. Run `task mcp:install` once after cloning to
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
- **Node capability composition** ([`docs/adr-node-capability-composition.md`](docs/adr-node-capability-composition.md)) — per-node provisioning is DECOUPLED from hardware detection; the per-node provisioning-profile catalog is base-owned/module-local (a consumer cannot redefine it). A consumer `emits_label` MUST land in `platform.io/hardware-capability.*`, never `hardware-feature.*` (Layer-C atomic, Talos-only). These are the mechanical anti-forgery / anti-override invariants a composing agent must honor; the Layer-C vocabulary lives in [`docs/adr-three-layer-capability-architecture.md`](docs/adr-three-layer-capability-architecture.md) and [`docs/platform-hardware-features.yaml`](docs/platform-hardware-features.yaml). Enforcement of the reserved Layer-C labels is consumer-cluster Kyverno (the base ships no admission policy).
- **Capability-layer model & PNI dissolution** ([talos-platform-docs ADR-0021](https://github.com/devobagmbh/talos-platform-docs/blob/main/adr/0021-capability-layer-model.md)) — capability = stable interface, tool = swappable implementation. The base-resident PNI / Layer-A network-trust surface **was removed** at the substrate-only ablation (v2.0.0): per [`docs/adr-substrate-only-base.md`](docs/adr-substrate-only-base.md) it dissolved into apps-CI Conftest + consumer-cluster Kyverno. Only the Layer-C hardware-feature/capability vocabulary (`base:three-layer-capability-architecture`) remains base-resident, because the `tofu/modules/talos-cluster` composition model depends on it.
