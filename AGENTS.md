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
`cert-approver` is the only addition, present solely as Talos serving-cert glue:
it approves the `kubernetes.io/kubelet-serving` CSRs the base's default-on kubelet
serving-cert rotation triggers (client-kubelet CSRs auto-approve, so the cluster
boots without it; metrics-server / `kubectl logs|exec|top` need it). The approver
is `postfinance/kubelet-csr-approver` — tunable per-cluster via
`substrate.cert_approver.*` (two security knobs + `replicas`) and carrying an
always-on per-node DNS-SAN binding. Delivered as a controlplane `inlineManifest`
seed (`knowledge/decisions/0019-postfinance-kubelet-csr-approver.md`, superseding
ADR-0013 §D2; the seed pattern + rotation default-on remain
`knowledge/decisions/0013-kubelet-serving-cert-rotation.md`), not a fourth pillar.
Because ArgoCD is core substrate it is delivered as part of standing the
cluster up — **opt-out, never an opt-in Day-2 add-on**; classifying
ArgoCD-bootstrap as Day-2 is a scoping error. `talos-platform-apps` is the
**central catalog**: every platform
component that is *not* substrate lives there as independently versioned,
signed OCI artifacts. Consumer cluster repos **compose** — they pin a base
tag for the substrate and serve themselves from the apps catalog by
referencing exactly the OCI components they need. Routing rule: if it is not
substrate, it belongs in the apps catalog, never in base. See
[`knowledge/decisions/0004-substrate-only-base.md`](knowledge/decisions/0004-substrate-only-base.md) and the
platform layer model (recorded in the platform architecture decision records).

## Project Structure & Module Organization

- `kubernetes/substrate/`: base Helm values and namespace/kustomization manifests per infrastructure component.
- `kubernetes/bootstrap/argocd/`: parameterized bootstrap templates (`*.tmpl`) consumed by `task bootstrap:argocd`.
- `kubernetes/bootstrap/cilium/`: reference Cilium Helm values + `extras.yaml` (GatewayClass) for optional Day-2 self-management. Cilium itself is delivered by the `talos-cluster` module as a controlplane `inlineManifest` seed (`deploy_cilium`); the former consumer-side render path is retired.
- `tofu/modules/talos-cluster/`: the OpenTofu module that is the sole Talos cluster-lifecycle path (machine secrets, per-node composed Image-Factory installer — content-hash-deduped, config apply, bootstrap, kubeconfig). Backend- and identity-agnostic; called by a consumer-side OpenTofu root that is a thin `yamldecode` shim over the declarative `cluster.yaml` SoT. See [`knowledge/decisions/0006-opentofu-cluster-lifecycle.md`](knowledge/decisions/0006-opentofu-cluster-lifecycle.md) and [`knowledge/decisions/0007-cluster-yaml-sot.md`](knowledge/decisions/0007-cluster-yaml-sot.md).
- `policies/`: conftest Rego policies for kustomize-rendered manifests.
- `openspec/`: behavioral-requirements source of truth (OpenSpec) — one spec per substrate capability under `specs/`, change proposals under `changes/`. See §Spec-Driven Development.
- `scripts/`: cluster-agnostic validation, render and helper scripts.
- `knowledge/`: the OKF v0.1 knowledge bundle — architecture, reference, workflows, decision records (ADRs), glossary. Entry point: [`knowledge/index.md`](knowledge/index.md). Contracts a consumer parses live outside the bundle: `schemas/`, `contracts/`, `platform-hardware-features.yaml` (repo root); the bundle itself ships in no release artifact (`.ci-oci-tarball-include.txt`). `knowledge/rules/` is a narrow carve-out for contracts the bundle's own tooling reads: `openknowledge` renders them into this file's Open Knowledge Maintenance block.

## Build, Test, and Development Commands

- `task cluster:init-yaml`: copies `cluster.yaml.example` to `cluster.yaml` (gitignored) — the declarative cluster Source-of-Truth (identity, versions, endpoint, network, nodes, images, hardware-capabilities, machine-config patches, substrate). `task bootstrap:argocd` reads only the bootstrap-identity subset (`cluster.{name,overlay,target_revision}` + `repo.url`); the consumer's OpenTofu root is a thin `yamldecode` shim that maps the full file onto the `tofu/modules/talos-cluster` typed interface. tofu is the executor, not the SoT. See [`knowledge/decisions/0007-cluster-yaml-sot.md`](knowledge/decisions/0007-cluster-yaml-sot.md).
- `task gitops:validate`: kustomize-render + SOPS check + conftest + kubeconform + ArgoCD substrate invariants across all rendered manifests.
- `task mcp:install` / `task mcp:verify`: install and verify MCP server binaries.
- `task tofu:ci` (devbox): `tofu fmt -check` + `tofu validate` + `tflint` + render-determinism fence over the `tofu/` cluster-lifecycle module and its examples.
- **go-task is the single runner — the `Makefile` was retired at v3.0.0.** Every former `make` target folds into a namespaced task in `Taskfile.yml`: `tofu:*` (OpenTofu validation), `gitops:*` (`validate`, `render-component`, `render-all`, `verify-rendered`), `bootstrap:*` (`argocd`, `argocd-password`), `cluster:init-yaml`, `supply-chain:oci-allowlist`, `mcp:*`, `dev:*`. Run `task --list` for the full set. A `Makefile` deprecation stub remains for one release cycle: any `make <target>` prints the migration mapping and exits non-zero. `chart-pull` and `grafana-dashboards-check` were dropped (no replacement). Decision: [`knowledge/decisions/0012-makefile-retirement.md`](knowledge/decisions/0012-makefile-retirement.md) (supersedes [`knowledge/decisions/0008-task-runner-consolidation.md`](knowledge/decisions/0008-task-runner-consolidation.md)).

This base is consumed by cluster repos via OCI artifact (`oras pull
ghcr.io/nosmoht/talos-platform-base:<tag>`) into a gitignored `vendor/base/`
directory; live ArgoCD reconciliation uses a Multi-Source Application
referencing both the cluster repo and this base.

## Coding Style & Naming Conventions

- YAML with 2-space indentation; keep keys and list nesting consistent with existing manifests.
- One component per directory (`.../component/{application.yaml,kustomization.yaml,values.yaml}`).
- Conventional Commit style with subsystem scope (`fix(cilium): …`, `chore(talos): …`).
- Component directory name must equal the ArgoCD Application name — exact match, no abbreviation or synonym.

## Testing Guidelines

- This repo has no live cluster. Validation is manifest-render and policy focused.
- Required before opening a PR:
  - `task gitops:validate`
  - `task spec:validate` when `openspec/` or a spec's `primary` source changed
  - `kubectl kustomize kubernetes/substrate/<component>/` for any touched component
- Live runtime verification belongs in consumer cluster repos.

## Commit & Pull Request Guidelines

- Follow Conventional Commit style: `type(scope): short imperative summary`.
- Keep commits focused and logically grouped.
- PRs include: what changed and why, impacted components, validation steps run, breaking-change notes (Helm-value defaults that downstream consumers need to be aware of).
- A breaking change to base Helm values requires bumping the next OCI tag's MAJOR version per CHANGELOG.

<!-- markdownlint-disable MD032 -->
<!-- openknowledge:rules:start -->
## Open Knowledge Maintenance

This project has an Open Knowledge wiki at `knowledge`.

This block is managed by `openknowledge prompt rules apply`.

Before relevant work:
- Read `knowledge/index.md` and follow only links relevant to the task.
- Treat the wiki as durable project memory, not as a scratchpad.
- If the wiki is missing, stale, or wrong, say so instead of inventing facts.

Enabled rules:
- docs: Keep docs in sync with implementation.
- decisions: Record important decisions.
- schemas: Document APIs, data models, configs, and contracts.
- talos-base-bundle: Repo-specific bundle conventions on top of the built-in maintenance rules.

Docs rules:
- When behavior, APIs, commands, configs, or examples change, update the matching docs in the same task.
- Preserve source anchors or citations when docs depend on implementation details.
- Keep docs focused on shipped behavior; label planned work clearly.

Decisions rules:
- When a meaningful technical or product decision is made, record the context, options, chosen path, and tradeoffs.
- Link decisions to affected concepts, workflows, commands, systems, or source files.
- Do not rewrite decision history to hide old context; append clarifications or superseding decisions.

Schemas rules:
- Create or update concepts for APIs, schemas, tables, config keys, data models, and contracts when their source changes.
- Prefer source pointers over copying generated or code-derived truth into prose.
- Keep schema docs linked to the authoritative source files, specs, or systems.

Bundle Conventions rules:
- Use the closed `type` vocabulary: `architecture`, `reference`, `workflow`, `decision`, `glossary`, `project`, `Rule`. Add a new type by editing this list and `knowledge/index.md` in the same change. `Rule` is capitalized because the CLI requires that spelling, not as a naming pattern to copy.
- Set `timestamp` to the date of the last substantive verification, not the last typo fix, and keep `sources` pointing at the repo-relative paths the concept was derived from.
- Re-verify a concept when a change to one of its `sources` lands inside what the concept describes — not merely because a listed file was touched. A green validation run proves link and schema health, never freshness.
- Omit `sources` on `decision` concepts: an ADR records a decision rather than deriving from source files. Their field contract, including `status`, `id`, `deciders`, and `supersedes`, lives in `knowledge/decisions/index.md`.
- Link relatively inside the bundle, and cite anything outside it as an inline code span rather than a markdown link: `.openknowledge.toml` raises `link-target` to error, so an escaping link fails validation.
- Validate with `task knowledge:validate`, which runs `openknowledge validate` plus the offline link gate. Run `task knowledge:rules-check` as well after touching `knowledge/rules/`.
- Invoke `openknowledge` through the `knowledge:*` task targets, never bare: the version pin and the telemetry opt-out both live in `Taskfile.yml`, and a bare run skips both silently. Where a bare run is unavoidable, prefix it with `OPENKNOWLEDGE_TELEMETRY=off`.
- Record bundle changes in `knowledge/log.md`, one bullet per changed concept under today's date. User-facing changes belong in the root `CHANGELOG.md`. The two files have separate audiences and do not mirror each other.
- Regenerate the `AGENTS.md` managed block with `task knowledge:rules-apply` after changing this file. Hand-editing the block fails `task knowledge:rules-check`.

After wiki updates:
- Keep non-reserved Markdown files OKF-valid with YAML frontmatter and a non-empty `type`.
- Update `index.md` links when pages are added, moved, or removed.
- Update `log.md` when durable wiki knowledge changes.
- Run `openknowledge validate "knowledge"` before finishing.
<!-- openknowledge:rules:end -->
<!-- markdownlint-enable MD032 -->

## Codex CLI Operating Rules (Important)

- This file (`AGENTS.md`) is the canonical source of truth.
- Never `kubectl apply` ArgoCD-managed resources for rollout; commit to git and let consumer ArgoCD reconcile.
- Direct-apply exception: bootstrap content under `kubernetes/bootstrap/`.
- Keep secret material out of base — there is no `*.sops.yaml` in this repo.

## Validation Checklist For Codex Changes

- For base/infrastructure changes:
  - `kubectl kustomize kubernetes/substrate/<component>/`
  - `task gitops:validate`
- For Talos cluster-lifecycle (`tofu/`) changes:
  - `task tofu:ci` (or `tofu fmt -check -recursive tofu/` + per-dir `tofu init -backend=false && tofu validate` + `tflint`)

---

## Hard Constraints

These are universal cluster invariants. CLAUDE.md imports this file via
`@AGENTS.md`. Both tools treat this section as canonical. Do NOT relax these
without repo-maintainer approval.

- **No SecureBoot** — `metal-installer-secureboot`, the bare `metal-secureboot`, and the Image-Factory `installer-secureboot` URL form all cause boot loops; always use the non-secureboot installer. The `tofu/modules/talos-cluster` module enforces this in code (selects `urls.installer`, never `urls.installer_secureboot`). CI gate: `hard-constraints-check.yml` greps `(metal-secureboot|installer-secureboot)` over `tofu/**`. Decision: [`knowledge/decisions/0011-substrate-hard-constraints.md`](knowledge/decisions/0011-substrate-hard-constraints.md).
- **No `debugfs=off`** — causes "failed to create root filesystem" boot loop in Talos (with Cilium). Decision: [`knowledge/decisions/0011-substrate-hard-constraints.md`](knowledge/decisions/0011-substrate-hard-constraints.md).
- **Gateway API only** — no `kind: Ingress` or Ingress controllers; use HTTPRoute/TLSRoute
- **EndpointSlices only** — `kind: Endpoints` deprecated since Kubernetes v1.33.0; use `EndpointSlice` (GA since v1.21). Decision: [`knowledge/decisions/0011-substrate-hard-constraints.md`](knowledge/decisions/0011-substrate-hard-constraints.md).
- **Commit and push every successful tested change immediately** — do not batch at end of session
- **NEVER `kubectl apply` ArgoCD-managed resources** — commit to git, push, let ArgoCD sync; only exception: one-time bootstrap AppProjects (`kubernetes/bootstrap/`)
- **Kubernetes recommended labels on all resources** — `app.kubernetes.io/{name,instance,version,component,part-of,managed-by}`
- **File naming conventions** — component dirs must match the ArgoCD Application name

## Key Terms

Curated subset for agent-context loading. Full definitions and the long
tail (Rendered Manifests Pattern, Right altitude, …) live in
[`knowledge/glossary.md`](knowledge/glossary.md); cite that file for terms not in
this list.

- **AppProject** — ArgoCD RBAC boundary scoping repos/namespaces an Application can deploy to.
- **Sync-wave** — ArgoCD annotation for deploy order: `-1` (AppProjects) → `0` (infra) → `1` (apps).
- **Schematic** — Talos Image Factory spec embedding system extensions (and optional SBC overlay) into installer images. Derived per node by the `tofu/modules/talos-cluster` module: the node's `image` (baseline `extensions` + `extra_kernel_args` + `overlay` + `architecture`) unioned with the `extensions` + `extraKernelArgs` of the provisioning profiles its `hardware_capabilities` resolve to; content-hash-deduped so identical nodes share one schematic.
- **DRBD** — Distributed Replicated Block Device — LINSTOR replication layer for persistent storage (apps-catalog component).
- **Multi-Source Application** — ArgoCD Application with `spec.sources[base, cluster]` consuming this base alongside consumer cluster manifests.
- **OCI artifact** — versioned tarball of this base published to `ghcr.io/nosmoht/talos-platform-base:<tag>` on every git tag push; consumed via `oras pull`.

## Tool-Agnostic Safety Invariants

| Safety Gate | Enforced via | Fail Reason |
|---|---|---|
| AWS/GitHub tokens in any file | pre-commit `gitleaks` hook | Credential leak prevention |
| `git commit --no-verify` bypass | CI `gitleaks` CLI in `gitops-validate.yml` `secret-scan` job (required PR check) | Last backstop — blocks merge even if local hooks bypassed |
| Forbidden Kubernetes kinds (Ingress, Endpoints) | CI `hard-constraints-check.yml` on every PR (required branch-protection context `Hard Constraints`) | Server-side enforcement of §Hard Constraints |
| SOPS plaintext leak (consumer-side) | pre-commit + Claude Code PreToolUse hook (consumer repo) | Plaintext secrets must never reach git |

`*.sops.yaml` does not exist in this base repo. Consumer cluster repos add
their own SOPS gate via pre-commit.

## Domain Rules — On-Demand Reference

This base commits the OpenSpec-GENERATED tool integrations (the Claude Code
and Codex skill/command trees produced by `openspec init`/`openspec update`;
regenerable via `task spec:update` — see
[`knowledge/decisions/0014-ship-ai-tool-artifacts.md`](knowledge/decisions/0014-ship-ai-tool-artifacts.md)).
Never hand-edit those trees — the next regeneration overwrites them. It still
ships no hand-authored rules, hooks, or subagents; any domain rules come from
an external harness that an operator or consumer repo installs — verify a
rule file is present in the working repo before relying on it.

## Spec-Driven Development (OpenSpec)

`openspec/specs/` is the behavioral-requirements source of truth: one spec per
substrate capability, covering exactly the externally observable contracts
enumerated by the spec directories under `openspec/specs/` — never assume
unlisted behavior is spec'd
(repo-internal QA is documented in
`knowledge/`, not spec'd — scope principle in
[`knowledge/decisions/0015-openspec-adoption.md`](knowledge/decisions/0015-openspec-adoption.md)).
Normative constraints stay in §Hard Constraints and the ADRs; specs cite them
and describe observable outcomes.

- A change to platform behavior requires a spec delta via
  `openspec/changes/` (propose → apply → archive); direct edits to
  `openspec/specs/` are reserved for the one-time backfill.
- Validate locally with `task spec:validate` (+ `task spec:check-regen` for
  the tool trees, `task spec:check-staleness` for the ownership gate); CI
  (`docs-lint.yml`) runs exactly these Taskfile targets — the local and
  remote commands are identical (`spec:check-staleness` runs on PR events
  only).
- A PR touching a spec's `primary` source file (frontmatter `sources:`)
  updates the owning spec — CI-enforced by `task spec:check-staleness`;
  verified no-behavior-change diffs escape via the `Spec-Impact: none`
  trailer on EVERY commit that contributed to the file (per-commit scope;
  syncing your branch with `main` never voids the escape; the PR reviewer
  judges the claim).
- Full workflow incl. tool-pin upgrades:
  [`knowledge/workflows/spec-driven-development.md`](knowledge/workflows/spec-driven-development.md).
- Do not confuse the tools: `openspec` validates behavioral specs
  (`spec:*` tasks); `openknowledge` validates the `knowledge/` bundle
  (`knowledge:*` tasks).

## MCP Server Configuration

All three MCP servers (github, kubernetes-mcp-server, talos) use **bare
PATH-resolved command names**. Run `task mcp:install` once after cloning to
install the binaries and register the wrapper symlink. See `knowledge/workflows/mcp-setup.md`
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

See `knowledge/workflows/issue-lifecycle.md` for the full issue lifecycle.

## Issue-Interface

The tracker is GitHub Issues. This table declares the project-local command
implementing each tracker-agnostic vocabulary verb; agents dereference it at
runtime instead of assuming a host. State transitions go through
`scripts/issue-state.sh` — it encodes the guards, race handling, and label
hygiene that ad-hoc `gh issue edit` calls skip. Reads and comments go through
`gh` directly. Semantics of each transition (guards, exit codes, race
behavior): `knowledge/workflows/issue-lifecycle.md` and the script header.

### Required operations

| Operation | Command |
|---|---|
| `issue:read` | `gh issue view ${N} --json title,body,labels` |
| `issue:comment` | `gh issue comment ${N} --body-file -` |
| `issue:read-comments` | `gh issue view ${N} --json comments --jq '.comments[].body'` |
| `state:claim` | `scripts/issue-state.sh claim ${N}` |
| `state:handoff` | `scripts/issue-state.sh handoff ${N}` |
| `state:release` | `scripts/issue-state.sh release ${N}` |
| `state:block` | `scripts/issue-state.sh block ${N} "${REASON}"` |
| `state:close` | `gh pr merge ${PR_REF} --merge && scripts/issue-state.sh close ${N} --pr "${PR_REF}"` |
| `pr:open` | `gh pr create --fill` |
| `pr:list-by-branch` | `gh pr list --head "$(git rev-parse --abbrev-ref HEAD)" --json number --jq '.[0].number // empty'` |
| `pr:status` | `gh pr checks ${PR_NUMBER} --required` |

### Optional operations

| Operation | Command |
|---|---|
| `issue:list-ready` | `gh issue list --state open --label 'status: ready'` |
| `issue:label` | `gh issue edit ${N} --add-label "${LABEL}"` |
| `issue:unlabel` | `gh issue edit ${N} --remove-label "${LABEL}"` |
| `issue:close-as-wontfix` | `gh issue close ${N} --reason "not planned"` |
| `issue:create` | `gh issue create --title "${TITLE}" --body-file -` |

`ci:status` is **not declared**: CI here is PR-attached (`gitops-validate.yml`,
`hard-constraints-check.yml`, `docs-lint.yml` all fire on pull-request events),
so `pr:status` is the CI-status verb and a branch-scoped equivalent would report
nothing. Consumers requiring push-triggered CI status degrade per their own
contract.

### Substitution conventions

- `${N}` — issue number (decimal, no leading `#`)
- `${PR_REF}` / `${PR_NUMBER}` — pull-request identifier
- `${REASON}` — block reason string
- `${TITLE}` — issue title
- `${LABEL}` — label name

## Deltas vs Claude Code (For Codex CLI Users)

1. **No PreToolUse interception**: Tool-agnostic safety begins at `git commit` (pre-commit framework).
2. **No auto-subagent dispatch**: any subagents come from an externally installed harness (not this base) and run only on explicit request.
3. **No `paths:` rule auto-loading**: if an external harness or consumer repo provides rule files, read the relevant one on demand.
4. **`--no-verify` bypass is possible locally**: Required PR checks (`gitleaks` CLI in `gitops-validate.yml`, `hard-constraints-check`) block merge server-side.
5. **OpenSpec invocation differs per tool**: Claude Code uses the `/opsx:*` slash commands from the committed `.claude/commands/` tree; Codex CLI uses its committed skill tree or drives the `openspec` CLI directly (`openspec --help`).

## ADR-Abdeckung

Operative decisions an agent here must honor that the sections above do not yet spell out:

- **Namespace ownership** ([`knowledge/decisions/0002-namespace-ownership-rendered-manifests.md`](knowledge/decisions/0002-namespace-ownership-rendered-manifests.md)) — one Application owns each namespace (the component itself); a consumer `root` Application MUST NOT track platform (vendor-shipped) namespaces, and no `Prune=false` is set on a platform namespace. `argocd` is the only chicken-and-egg exception.
- **Signed-OCI producer obligation** (per the platform architecture decision records) — the base OCI artifact is cosign-signed (keyless OIDC), carries SLSA build provenance and a CycloneDX SBOM attestation, produced on every tag push by [`.github/workflows/oci-publish.yml`](.github/workflows/oci-publish.yml). Consumer-side verification is documented in [`knowledge/workflows/verify-release.md`](knowledge/workflows/verify-release.md). (The layer-model reference under §Repository Purpose covers *what* base produces; this is the supply-chain *how*.)
- **Node capability composition** ([`knowledge/decisions/0009-node-capability-composition.md`](knowledge/decisions/0009-node-capability-composition.md)) — per-node provisioning is DECOUPLED from hardware detection; the per-node provisioning-profile catalog is base-owned/module-local (a consumer cannot redefine it). A consumer `emits_label` MUST land in `platform.io/hardware-capability.*`, never `hardware-feature.*` (Layer-C atomic, Talos-only). These are the mechanical anti-forgery / anti-override invariants a composing agent must honor; the Layer-C vocabulary lives in [`knowledge/decisions/0003-three-layer-capability-architecture.md`](knowledge/decisions/0003-three-layer-capability-architecture.md) and [`platform-hardware-features.yaml`](platform-hardware-features.yaml). Enforcement of the reserved Layer-C labels is consumer-cluster Kyverno (the base ships no admission policy).
- **Capability-layer model & PNI dissolution** (recorded in the platform architecture decision records) — capability = stable interface, tool = swappable implementation. The base-resident PNI / Layer-A network-trust surface **was removed** at the substrate-only ablation (v2.0.0): per [`knowledge/decisions/0004-substrate-only-base.md`](knowledge/decisions/0004-substrate-only-base.md) it dissolved into apps-CI Conftest + consumer-cluster Kyverno. Only the Layer-C hardware-feature/capability vocabulary (`base:three-layer-capability-architecture`) remains base-resident, because the `tofu/modules/talos-cluster` composition model depends on it.
