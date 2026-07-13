---
type: reference
title: Task Runner Surface
description: Complete go-task target inventory with per-task purpose, preconditions, and the Makefile deprecation stub behavior.
tags: [go-task, tooling, validation]
timestamp: 2026-07-13
sources:
  - Taskfile.yml
  - Makefile
---

# Task Runner Surface

go-task is the **single task runner** for this repository since v3.0.0 — the
Makefile was retired (see [Makefile retirement](../decisions/0012-makefile-retirement.md)).
Every former `make` target folds into a namespaced task in `Taskfile.yml`.
Run `task --list` for the live inventory; `task` with no arguments (the
`default` task) prints the same list.

Conventions declared in `Taskfile.yml`:

- `silent: true` — only the commands themselves write to the console, not
  their invocation echo (mirrors the apps-catalog repo).
- `ENV: cluster.yaml` — the declarative cluster SoT consumed by the
  `bootstrap:*` namespace; override per invocation with
  `task bootstrap:argocd ENV=other.yaml`.
- MCP server versions are pinned as Taskfile vars
  (`MCP_GITHUB_VERSION: 0.33.0`, `MCP_K8S_VERSION: 0.0.60`,
  `MCP_TALOS_VERSION: 1.1.0`).
- Knowledge-bundle tool pins (`OPENKNOWLEDGE_VERSION: 0.5.0`,
  `LYCHEE_VERSION: 0.24.2`) plus their per-platform sha256 checksums are
  Taskfile vars, kept in sync with `.tool-versions` and the
  `docs-lint.yml` workflow env.

## `tofu:*` — OpenTofu cluster-lifecycle module validation

| Task | Purpose |
| --- | --- |
| `tofu:fmt` | Rewrite all `tofu/` files to canonical format (mutating). |
| `tofu:fmt:check` | Verify `tofu/` formatting; CI-safe, non-mutating (`-check -diff`). |
| `tofu:validate` | `tofu init -backend=false` + `tofu validate` per tofu dir (modules + examples). |
| `tofu:lint` | `tflint --chdir=.` per tofu dir (modules + examples). |
| `tofu:docs` | Regenerate module README input/output tables via terraform-docs. |
| `tofu:lint:yaml` | yamllint (relaxed) + markdownlint over `tofu/` — advisory (`\|\| true`). |
| `tofu:check:render-determinism` | CI fence: Cilium/ArgoCD/CRD helm renders must use frozen `terraform_data` (`ignore_changes`), not live `data.helm_template`. Runs `scripts/check-render-determinism.sh`. |
| `tofu:test` | `tofu test` — node-capability composition regression suite. **Network-dependent** (resolves the live Image Factory), so deliberately NOT part of `tofu:ci`. |
| `tofu:ci` | Aggregate: `fmt:check` + `validate` + `lint` + `check:render-determinism` — mirrors CI, stays offline. |

Both `tofu:validate` and `tofu:lint` exclude `tests/fixtures/**`: those are
test inputs exercised via `tofu test` (`run { module }`), partial stand-in
modules rather than standalone modules.

## `gitops:*` — manifest validation + rendered-manifests pipeline

| Task | Purpose |
| --- | --- |
| `gitops:validate` | Full pipeline: kustomize-target discovery → safe render → SOPS check → conftest → kubeconform → ArgoCD substrate invariants. Stage detail in [manifest pipeline](manifest-pipeline.md). |
| `gitops:render-component` | Stage-1 (helm template) + Stage-2 (kustomize build) render of one component. Usage: `task gitops:render-component COMPONENT=<name>`; fails with usage text when `COMPONENT` is unset. |
| `gitops:render-all` | Render every component under `kubernetes/base/infrastructure/` that has a `chart.lock.yaml`; exits 0 with a notice when none exist. |
| `gitops:verify-rendered` | Re-render all components and fail if the committed `_rendered/` tree drifts (`scripts/verify-rendered.sh`). |

Precondition: the safe-render stage requires ripgrep (`rg`) on PATH for
ksops/SOPS-generator detection — it fails loudly (exit 2) rather than
silently treating directories as safe.

## `bootstrap:*` — consumer App-of-Apps root seed

ArgoCD itself (controller, namespace, CRDs) is delivered by
`tofu/modules/talos-cluster` as a Talos `inlineManifest` seed
(`deploy_argocd=true`) plus server-side-applied CRDs — **not** by these
tasks. `bootstrap:argocd` only seeds the consumer-identity App-of-Apps root
(root-project + root-application), which the module does not deliver.

| Task | Purpose |
| --- | --- |
| `bootstrap:argocd` | Render the root templates from `cluster.yaml`, wait for the Application/AppProject CRDs to exist and become `Established` and for `deployment/argocd-server` to be available, then `kubectl apply` root-project and root-application. Usage: `task bootstrap:argocd [ENV=cluster.yaml]`. |
| `bootstrap:argocd-password` | Print the initial ArgoCD admin password from the `argocd-initial-admin-secret` Secret (rotate after first login). |

Details of `bootstrap:argocd`:

- **Preconditions:** `deploy_argocd=true` and a completed `tofu apply` (the
  module seeds ArgoCD and applies its CRDs server-side), plus a working
  `kubectl` context. A persistent CRD `NotFound` means the apply did not
  finish its CRD step; recovery command:
  `tofu apply -replace=null_resource.argocd_crds[0]`.
- **Input subset:** an internal `bootstrap:render-root` dependency reads only
  `cluster.{name,overlay,target_revision}` (revision defaults to `main`) and
  `repo.url` from the `ENV` file, rejects any value containing `$` (unsafe
  for `envsubst`), and renders
  `kubernetes/bootstrap/argocd/*.tmpl` into `kubernetes/bootstrap/argocd/_out/`.

## `cluster:*` — declarative cluster SoT init

| Task | Purpose |
| --- | --- |
| `cluster:init-yaml` | Copy `cluster.yaml.example` to `cluster.yaml` (gitignored declarative SoT) if absent; no-op when the file already exists. |

## `supply-chain:*` — OCI artifact verification

| Task | Purpose |
| --- | --- |
| `supply-chain:oci-allowlist` | Build the OCI tarball locally from `.ci-oci-tarball-include.txt` and diff its sorted contents against `.ci-oci-tarball-expected.txt` (fail-closed allowlist). Run before pushing a tag to confirm the fixture matches actual contents. |

## `knowledge:*` — OKF knowledge bundle authoring + validation

| Task | Purpose |
| --- | --- |
| `knowledge:validate` | Validate the `knowledge/` OKF bundle: `openknowledge validate` (with the binding `link-target = "error"` rule from `knowledge/openknowledge.toml`) plus an offline intra-repo link-resolution pass (`lychee --offline`) over the bundle, root Markdown files, and `contracts/`. Mirrors the CI gates in `docs-lint.yml`. |
| `knowledge:new` | Scaffold a new concept file with the bundle's frontmatter convention (usage: `task knowledge:new FILE=reference/foo.md TYPE=reference`). |
| `knowledge:install-cli` | Download the pinned, checksum-verified `openknowledge` + `lychee` release binaries for the host platform into `~/.local/bin`. |

## `spec:*` — OpenSpec behavioral specs

Not the same tool as `knowledge:*` — `openspec` validates the behavioral
capability specs under `openspec/`; `openknowledge` validates the OKF
bundle. See `knowledge/workflows/spec-driven-development.md`.

| Task | Purpose |
| --- | --- |
| `spec:validate` | Strict `openspec validate` over `openspec/`, a bite-check (a committed malformed fixture must fail validation, run against a temp copy), the source-ownership partition assert (`scripts/check-spec-partition.py`: exclusivity + completeness over the enumerated universe per ADR-0015), and an offline `lychee` pass. Run verbatim by `docs-lint.yml`. Precondition: `task spec:install-cli` + `task knowledge:install-cli` (lychee). |
| `spec:check-regen` | Regeneration parity: whole-tree delta after `openspec update --force` must be empty — the committed tool trees equal the pinned generator's output (parity only, not benignity). Run verbatim by `docs-lint.yml`. Overwrites uncommitted edits inside the generated trees. |
| `spec:install-cli` | Install the pinned `openspec` CLI via npm with lifecycle scripts disabled (`--ignore-scripts`). Precondition: `npm`. |
| `spec:update` | Regenerate the committed OpenSpec tool integrations (`.claude/`, `.codex/`) after a CLI upgrade; fails when the regeneration emitted paths `.gitignore` still ignores (delta-based gate). Regenerated diffs are security-relevant review surface (ADR-0014). |

## `docs:*` — repo-wide markdown lint

| Task | Purpose |
| --- | --- |
| `docs:lint` | `markdownlint` over the whole repo with `.markdownlintignore`. Run verbatim by `docs-lint.yml`. Precondition: `task docs:install-cli`. |
| `docs:install-cli` | Install the pinned `markdownlint-cli` via npm with lifecycle scripts disabled. |

## `mcp:*` — MCP server binary management

| Task | Purpose |
| --- | --- |
| `mcp:install` | Install the three MCP server binaries per OS and symlink `scripts/mcp-github-wrapper.sh` as `~/.local/bin/mcp-github-wrapper`. |
| `mcp:verify` | Check all five binaries resolve on PATH (`gh`, `github-mcp-server`, `kubernetes-mcp-server`, `talos-mcp`, `mcp-github-wrapper`) and `gh auth token` succeeds; non-zero exit on any failure. |
| `mcp:uninstall` | Remove the wrapper symlink from `~/.local/bin` (leaves the binaries in place). |

`mcp:install` preconditions: `gh` always; on macOS `brew` (github + kubernetes
MCP servers) and `npm` (talos-mcp); on Linux `go` (github-mcp-server via
`go install`) and `npm` (kubernetes + talos MCP servers). Versions come from
the pinned Taskfile vars above. See the MCP setup workflow
([mcp-setup](../workflows/mcp-setup.md)).

## `dev:*` — contributor hygiene

| Task | Purpose |
| --- | --- |
| `dev:install-pre-commit` | `uvx pre-commit install` + one advisory run across the repo. |
| `dev:verify-tools` | Confirm installed binaries match the `.tool-versions` pins (`scripts/verify-tools.sh`). |
| `dev:verify-pins` | Assert the Taskfile `vars:` pins agree with `.tool-versions` (openknowledge, lychee, openspec, markdownlint). Run verbatim by `docs-lint.yml`. |

## Makefile deprecation stub

The tracked `Makefile` is a retirement stub kept for **one release cycle**:
any `make <target>` (including bare `make`) prints the migration mapping to
stderr and exits with code 2 — never runs a build. The printed mapping:

| Old `make` target | Replacement |
| --- | --- |
| `make validate-gitops` | `task gitops:validate` |
| `make render-component` | `task gitops:render-component COMPONENT=<name>` |
| `make render-all` | `task gitops:render-all` |
| `make verify-rendered` | `task gitops:verify-rendered` |
| `make argocd-bootstrap` | `task bootstrap:argocd` |
| `make argocd-password` | `task bootstrap:argocd-password` |
| `make init-cluster-yaml` | `task cluster:init-yaml` |
| `make oci-allowlist-check` | `task supply-chain:oci-allowlist` |
| `make mcp-install` | `task mcp:install` |
| `make mcp-verify` | `task mcp:verify` |
| `make mcp-uninstall` | `task mcp:uninstall` |
| `make install-pre-commit` | `task dev:install-pre-commit` |
| `make verify-tools` | `task dev:verify-tools` |

Removed with no replacement: `make chart-pull` and
`make grafana-dashboards-check`. Rationale and the supersession chain live in
[Makefile retirement](../decisions/0012-makefile-retirement.md).
