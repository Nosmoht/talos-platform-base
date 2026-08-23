---
type: reference
title: Task Runner Surface
description: Complete go-task target inventory with per-task purpose, preconditions, and the Makefile deprecation stub behavior.
tags: [go-task, tooling, validation]
generated: { by: human:nosmoht, at: "2026-08-23T00:00:00Z" }
verified:
  - { by: human:nosmoht, at: "2026-08-23T00:00:00Z" }
sources:
  - resource: Taskfile.yml
  - resource: Makefile
  - resource: package.json
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
  `MCP_TALOS_VERSION: 1.1.0`). Unlike the pins below these are asserted
  against nothing, so the values are restated here.
- Knowledge-bundle tool pins (`OPENKNOWLEDGE_VERSION`, `LYCHEE_VERSION`) plus
  their per-platform sha256 checksums are Taskfile vars, kept in sync with
  `.tool-versions` by `task dev:verify-pins`. The npm-distributed pins (`openspec`,
  `markdownlint-cli`) live in `package.json` + `package-lock.json`
  (integrity-hashed) instead of Taskfile vars.

## `tofu:*` — OpenTofu cluster-lifecycle module validation

| Task | Purpose |
| --- | --- |
| `tofu:fmt` | Rewrite all `tofu/` files to canonical format (mutating). |
| `tofu:fmt:check` | Verify `tofu/` formatting; CI-safe, non-mutating (`-check -diff`). |
| `tofu:validate` | `tofu init -backend=false` + `tofu validate` per tofu dir (modules + examples). |
| `tofu:lint` | `tflint --chdir=.` per tofu dir (modules + examples). |
| `tofu:docs` | Regenerate a module README's terraform-docs block — **refuses today**: no module README carries `BEGIN_TF_DOCS` markers, so their Inputs/Outputs tables are hand-maintained and must be edited by hand. Running `terraform-docs --output-mode inject` against a marker-less README appends a second, competing generated table set instead of updating one (verified, terraform-docs v0.22.0; [ADR-0015](../decisions/0015-openspec-adoption.md) correction). |
| `tofu:check:readme-parity` | CI fence: every `variables.tf` variable and `outputs.tf` output of a module appears in that module's hand-maintained README table (see `tofu:docs` for why those tables are hand-maintained). Scope limit: name-level parity in the `.tf` → README direction only — a README row for a deleted declaration, or stale prose on a surviving row, is not caught. Runs `scripts/check-module-readme-parity.sh`. |
| `tofu:lint:yaml` | yamllint (relaxed) + markdownlint over `tofu/` — advisory (`\|\| true`). |
| `tofu:check:render-determinism` | CI fence: Cilium/ArgoCD/CRD helm renders must use frozen `terraform_data` (`ignore_changes`), not live `data.helm_template`. Runs `scripts/check-render-determinism.sh`. |
| `tofu:check:kubeconfig-endpoint-regen` | CI fence: `talos_cluster_kubeconfig.this` keeps its `replace_triggered_by` wiring to the `terraform_data.kubeconfig_endpoint_marker` resource (whose `input` is `var.cluster_endpoint`), so a changed endpoint still forces kubeconfig regeneration (issue #186). Static, resource-scoped grep — no provider, no network. Runs `scripts/check-kubeconfig-endpoint-regen.sh`. |
| `tofu:check:node-projection-wiring` | CI fence: the five Talos boundary arguments (`talos_client_configuration.{endpoints,nodes}`, `talos_cluster_health.{control_plane_nodes,worker_nodes,endpoints}`) stay bound to their intended `nodes.tf` projections, and `talos_machine_configuration_apply` keeps iterating `local.nodes_checked` so the duplicate-IP guard stays in the dependency chain (issue #204). The offline fixture omits `main.tf`, so no `tofu test` can see this wiring. Static, block-scoped, awk+POSIX-grep — no provider, no network, no GNU-grep dependency. Runs `scripts/check-node-projection-wiring.sh`. |
| `tofu:check:shim-key-parity` | CI fence: every key of every CLOSED `substrate` object in `schemas/cluster.schema.json` is actually read by the worked example's shim (`tofu/modules/talos-cluster/examples/complete/main.tf`). The shim reads `cluster.yaml` through `try()`, which is total — a key it never reads, or reads misspelled, silently resolves to the module default while lint, `validate`, `plan` and the whole test suite stay green. Scope limit: closed objects only (`substrate.argocd` declares no key set; sections outside `substrate` restructure their data in the shim). Requires `jq`. Runs `scripts/check-shim-key-parity.sh`. |
| `tofu:test` | `tofu test` — the full suite, including the node-capability composition regression tests. **Network-dependent** (resolves the live Image Factory), so deliberately NOT part of `tofu:ci`. Superset of `tofu:test:offline`. |
| `tofu:test:offline` | The offline subset of `tofu:test`: the predicate-only catalog contract, the conflict guards, input validation, the consumer image-kernel-arg oracles (schematic re-image / no-re-image, issue #169), and the kubeconfig-endpoint-marker regression (issue #186 — the `terraform_data` marker tracks `var.cluster_endpoint`). Each points at a `tests/fixtures/*` stand-in module that symlinks the real code under test and declares no providers — a pure plan over `terraform_data`, so no network. Part of `tofu:ci`. |
| `tofu:ci` | Aggregate: `fmt:check` + `validate` + `lint` + `check:render-determinism` + `check:readme-parity` + `check:kubeconfig-endpoint-regen` + `check:node-projection-wiring` + `check:shim-key-parity` + `test:offline` — mirrors CI, stays offline. |

Both `tofu:validate` and `tofu:lint` exclude `tests/fixtures/**`: those are
test inputs exercised via `tofu test` (`run { module }`), partial stand-in
modules rather than standalone modules.

## `gitops:*` — manifest validation + rendered-manifests pipeline

| Task | Purpose |
| --- | --- |
| `gitops:validate` | Full pipeline: kustomize-target discovery → safe render → SOPS check → conftest → kubeconform → conftest bite-check → ArgoCD substrate invariants → `scripts/check-bootstrap-render.sh`. Stage detail in [manifest pipeline](manifest-pipeline.md). |
| `gitops:render-component` | Stage-1 (helm template) + Stage-2 (kustomize build) render of one component. Usage: `task gitops:render-component COMPONENT=<name>`; fails with usage text when `COMPONENT` is unset. |
| `gitops:render-all` | Render every component under `kubernetes/substrate/` that has a `chart.lock.yaml`; exits 0 with a notice when none exist. |
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
| `bootstrap:render-root` | Render the App-of-Apps root manifests (root-project + root-application) from `cluster.yaml` into `kubernetes/bootstrap/argocd/_out/`, with no cluster contact — a cluster-free dry-run. Usage: `task bootstrap:render-root [ENV=cluster.yaml]`. Field-level contract (which fields, the `main` default, the value guards) is normative in `openspec/specs/argocd-day-zero-bootstrap/`, asserted by `task bootstrap:check-render`. |
| `bootstrap:argocd` | Render the root templates from `cluster.yaml`, wait for the Application/AppProject CRDs to exist and become `Established` and for `deployment/argocd-server` to be available, then `kubectl apply` root-project and root-application. Usage: `task bootstrap:argocd [ENV=cluster.yaml]`. |
| `bootstrap:check-render` | CI gate: assert `bootstrap:render-root`'s output satisfies the `argocd-day-zero-bootstrap` spec scenarios, offline (`yq` + `envsubst` only, no cluster contact). Contract: `openspec/specs/argocd-day-zero-bootstrap/`. |
| `bootstrap:argocd-password` | Print the initial ArgoCD admin password from the `argocd-initial-admin-secret` Secret (rotate after first login). |

Details of the render → apply path (`bootstrap:render-root`, `bootstrap:check-render`, `bootstrap:argocd`):

- **Preconditions (`bootstrap:argocd` only — the render and check tasks need
  no cluster):** `deploy_argocd=true` and a completed `tofu apply` (the
  module seeds ArgoCD and applies its CRDs server-side), plus a working
  `kubectl` context. A persistent CRD `NotFound` means the apply did not
  finish its CRD step; recovery command:
  `tofu apply -replace=null_resource.argocd_crds[0]`.
- **Input subset:** the `bootstrap:render-root` dependency reads a narrow
  bootstrap-identity subset of the `ENV` file and renders
  `kubernetes/bootstrap/argocd/*.tmpl` into `kubernetes/bootstrap/argocd/_out/`.
  Which fields, the `main` default, and the guards that reject a value before
  it reaches a manifest are normative in
  `openspec/specs/argocd-day-zero-bootstrap/` and asserted by
  `task bootstrap:check-render` — not restated here, so this inventory cannot
  drift from them.

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
| `knowledge:validate` | Validate the `knowledge/` OKF bundle: `openknowledge validate --spec 0.2` (with the four binding rules from `knowledge/.openknowledge.toml`: `link-target`, `rule-catalog`, `"okf-0.2-metadata"` — quoted, or TOML reads it as a dotted key and drops the whole config — and `okf-version`; `markdown-syntax` stays at warn). `--spec` is pinned rather than left at the CLI default of `latest`, so the gate's meaning is a property of this repo rather than of the installed binary plus an offline intra-repo link-resolution pass (`lychee --offline`) over the bundle, root Markdown files, `contracts/`, and the two `tofu/modules/talos-cluster` READMEs. Runs `scripts/check-knowledge-gate-bite.sh` then `scripts/check-bundle-policy.sh` first, so a config the CLI cannot find fails the gate instead of silently degrading every raise to a warning, and the checker itself is proven to still discriminate. Invoked directly by `docs-lint.yml`. Precondition: `openknowledge` must report exactly the pinned version — the target refuses to run otherwise (`task knowledge:install-cli`). |
| `knowledge:rules-apply` | Regenerate the Open Knowledge Maintenance block in `AGENTS.md` from `knowledge/rules/` via `openknowledge prompt rules apply`. The block is a managed region between `openknowledge:rules` markers; run this after changing a rule document rather than hand-editing `AGENTS.md`. |
| `knowledge:rules-check` | Fail if the `AGENTS.md` managed block drifted from what `knowledge/rules/` currently renders — hand-edited, stale, or missing a configured rule. Asserts every rule in `OK_RULES` reached the block, so a rule that silently fails to render is caught rather than passing as a smaller-but-consistent block. Invoked by `docs-lint.yml`. |
| `knowledge:new` | Scaffold a new concept file with the bundle's frontmatter convention (usage: `task knowledge:new FILE=reference/foo.md TYPE=reference`). |
| `knowledge:install-cli` | Download the pinned, checksum-verified `openknowledge` + `lychee` release binaries for the host platform into `~/.local/bin`. |

## `spec:*` — OpenSpec behavioral specs

Not the same tool as `knowledge:*` — `openspec` validates the behavioral
capability specs under `openspec/`; `openknowledge` validates the OKF
bundle. See `knowledge/workflows/spec-driven-development.md`.

| Task | Purpose |
| --- | --- |
| `spec:validate` | Strict `openspec validate` over `openspec/`, a bite-check (a committed malformed fixture must fail validation, run against a temp copy), the `spec_lib` parser self-test (`scripts/test/test_spec_lib.py`), the staleness-gate merge-attribution bite-check (`scripts/check-staleness-gate-bite.sh`: six scenarios over a throwaway fixture repo, controls first; skips loudly on git < 2.38), the source-ownership partition assert (`scripts/check-spec-partition.py`: exclusivity + completeness over the enumerated universe per ADR-0015), and an offline `lychee` pass. Run verbatim by `docs-lint.yml`. Precondition: `task spec:install-cli` + `task knowledge:install-cli` (lychee). |
| `spec:install-cli` | Install the lockfile-pinned `openspec` CLI: shared `npm ci --ignore-scripts` (integrity-verified via `package-lock.json`) + `~/.local/bin` symlink. Precondition: `npm`. |
| `spec:check-regen` | Regeneration parity: whole-tree delta after `openspec update --force` must be empty — the committed tool trees equal the pinned generator's output (parity only, not benignity). Run verbatim by `docs-lint.yml`. Overwrites uncommitted edits inside the generated trees. |
| `spec:check-staleness` | Staleness gate: fail when the diff against `BASE` (default `origin/main`) touches a spec's `primary` source without touching the owning spec (`scripts/check-spec-staleness.py`; fragment-keyed sources fire at fragment granularity, fail-closed on unresolvable fragments). Escape for verified no-behavior-change diffs: `Spec-Impact: none` trailer in the BODY of every commit that CONTRIBUTED to the file — a base-sync merge does not count as one; attribution rule and its two failure directions: [spec-driven-development](../workflows/spec-driven-development.md). Run by `docs-lint.yml` on PRs. |
| `spec:update` | Regenerate the committed OpenSpec tool integrations (`.claude/`, `.codex/`) after a CLI upgrade; fails when the regeneration emitted paths `.gitignore` still ignores (delta-based gate). Regenerated diffs are security-relevant review surface (ADR-0014). |

## `docs:*` — repo-wide markdown lint

| Task | Purpose |
| --- | --- |
| `docs:lint` | `markdownlint` over the whole repo with `.markdownlintignore`. Run verbatim by `docs-lint.yml`. Precondition: `task docs:install-cli`. |
| `docs:install-cli` | Install the lockfile-pinned `markdownlint-cli`: shared `npm ci --ignore-scripts` + `~/.local/bin` symlink. |

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
| `dev:verify-pins` | Assert the Taskfile `vars:` pins (openknowledge, lychee) and the `package.json` pins (openspec, markdownlint-cli) agree with `.tool-versions`, and that every `package-lock.json`-resolved package points at the official `registry.npmjs.org` (supply-chain provenance guard). Run verbatim by `docs-lint.yml`. |

Deliberately absent from this table: `dev:npm-ci`, declared `internal: true` in `Taskfile.yml` and therefore hidden from `task --list` — the live inventory this page mirrors. It is the shared `npm ci --ignore-scripts` step that `docs:install-cli` and `spec:install-cli` both declare as a dependency (`deps: [dev:npm-ci]`). `Deliberately absent from this table:` is a fixed lead-in marker: the planned inventory-parity fence (issue #200) will read a table's exemption list from a note carrying this exact lead-in, naming the exempt tasks as the backticked task names that follow it in the same paragraph.

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
