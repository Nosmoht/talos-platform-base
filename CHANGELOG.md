# Changelog

This file follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- **OpenSpec adopted as the behavioral-requirements surface**
  (`knowledge/decisions/0015-openspec-adoption.md`). `openspec/specs/`
  carries specs for the 14 enumerated substrate capabilities (backfilled
  from the implementation by explicit owner decision); future behavior
  changes travel as spec deltas via `openspec/changes/`. New `spec:*`
  task namespace (`validate` incl. bite-check + source-partition assert,
  `check-regen`, `check-staleness`, `install-cli`, `update`),
  `docs:lint`/`docs:install-cli`, and `dev:verify-pins`; `docs-lint.yml`
  now runs exactly these Taskfile targets, so the local validation chain
  equals the remote one (pins live in `.tool-versions`, the Taskfile
  vars block, and — for the npm-distributed tools — `package.json` +
  `package-lock.json` with integrity hashes). The OCI tarball payload is
  unchanged — `openspec/` and the tool trees stay outside the allowlist.
- **Spec staleness gate, CI-enforced**: a PR whose diff touches a spec's
  `primary` source without touching the owning spec fails
  `docs-lint.yml` (`task spec:check-staleness`,
  `scripts/check-spec-staleness.py`). Escape for verified
  no-behavior-change diffs: the `Spec-Impact: none` trailer on every
  commit touching the file (per-commit scope), judged by the PR
  reviewer.

### Fixed

- **conftest ArgoCD policy — chart-omission evasion hardened**
  (`policies/conftest/argocd.rego`): every Application source must set
  `repoURL` and be explicitly classifiable (`chart`, `path`, `ref`, or a
  `plugin` block); a `helm:` block requires `chart` or `path` (a
  throwaway `ref` no longer dodges classification); and the literal
  floating markers (`latest`, `*`, `HEAD`) are denied as
  `targetRevision` on EVERY source independent of classification.
  Previously a source omitting `chart` fell through to the weaker
  git-source rules and skipped all Helm pinning checks; the textual
  chart-omission rule that could never fire (dead code) is removed.
  Disclosed residual: a chart-less source carrying `path` is classified
  as a git source — helm-vs-git repoURL discrimination is not
  mechanically decidable, and the floating deny catches only the literal
  markers; a mutable branch/tag name on a git-classified source stays a
  review concern. The denies are bound red-green by a committed negative
  fixture in `task gitops:validate`.
- **Duplicate hardware-feature ids are now rejected**:
  `scripts/lint-hardware-features.sh` gained a mechanical duplicate-id
  gate; the former schema-level `uniqueItemProperties` keyword (an
  AJV-only extension that `check-jsonschema` silently ignores) is
  removed from `schemas/hardware-features.schema.json`.
- **Version patterns fully anchored** in `schemas/cluster.schema.json`
  and the mirrored `tofu/modules/talos-cluster` validations:
  `talos.version`, `talos.install_version`, and `kubernetes.version` now
  reject trailing text after the PATCH segment (a `-`/`+` pre-release or
  build suffix stays accepted). **Consumer note (validation
  tightening):** values the former start-anchored patterns accepted —
  for example `v1.13.0.4` or `v1.13.0_hardened` — are now rejected at
  lint and plan time; such values never resolved to a valid Talos/Kubernetes
  release, but a consumer carrying one must fix it before upgrading.
  Bound red-green by `schemas/fixtures/cluster.invalid.yaml` (CI) and
  the offline `tests/input-validation.tftest.hcl` suite.
- **OCI publish membership gate is fail-closed**: a missing
  `.ci-oci-tarball-expected.txt` now aborts the publication instead of
  skipping the diff with a notice (parity with
  `task supply-chain:oci-allowlist`).
- **Bootstrap manifests carry the full recommended label set**: both
  `kubernetes/bootstrap/argocd/*.tmpl` templates gained
  `app.kubernetes.io/version`, set to a label-safe form of the rendered
  `target_revision` (sanitized/truncated — a slash-bearing branch name
  stays valid; `spec.source.targetRevision` keeps the raw value).

### Changed

- **The base now commits tool-generated AI artifacts**
  (`knowledge/decisions/0014-ship-ai-tool-artifacts.md`): the OpenSpec
  skill/command trees for Claude Code and Codex are committed
  (regenerable via `task spec:update`); operator scratch under
  `.claude/` stays gitignored via selective negation. Hand-authored
  harness primitives remain external. This reverses the former
  "ships no `.claude/` tree" policy in `CLAUDE.md`/`AGENTS.md`.

## v4.0.0 — 2026-07-11

### Changed

- **Documentation replaced by an Open Knowledge Format (OKF v0.1) bundle at
  `knowledge/` — the `docs/` tree is deleted (BREAKING for path consumers).**
  All prose documentation was regenerated from repository source (or, for
  decision records and project docs, migrated with per-claim verification)
  into `knowledge/` — architecture, reference, workflows, `decisions/`
  (the 13 ADRs, MADR frontmatter mapped to OKF), glossary. Entry point:
  `knowledge/index.md`. `openknowledge validate` (link-target raised to
  error via `knowledge/openknowledge.toml`) plus an offline lychee
  link-resolution pass gate the bundle in `docs-lint.yml` and locally via
  `task knowledge:validate`.
- **Machine-consumed contracts relocated out of `docs/` (BREAKING — OCI
  tarball layout changed).** `docs/platform-hardware-features.yaml` →
  `platform-hardware-features.yaml` (repo root);
  `docs/schemas/*` → `schemas/*`; `docs/primitive-contract.md` →
  `contracts/primitive-contract.md`. Both JSON Schema `$id` URLs updated
  accordingly. Consumers vendoring the tarball must repoint the two moved
  member paths; external harnesses reading the primitive contract at its
  hardcoded `docs/` path must repoint to `contracts/`. Migration table:
  `UPGRADING.md` §v4.0.0.

### Added

- **`knowledge:*` task namespace + pinned validation toolchain.**
  `task knowledge:validate` (OKF validate + offline link check),
  `task knowledge:new` (concept scaffold), `task knowledge:install-cli`
  (sha256-verified install of `openknowledge` 0.5.0 + `lychee` 0.24.2,
  pinned in `.tool-versions` and mirrored in `docs-lint.yml`).

## v3.0.0 — 2026-07-01

<!-- Backfilled 2026-07-11: these entries accrued under "Unreleased" and were
     released as v3.0.0, but the heading was never renamed — which is also why
     the v3.0.0 GitHub Release fell back to auto-generated notes. -->

### Added

- **Cilium Gateway API honors Service `appProtocol: kubernetes.io/h2c` (#132, #133).**
  `gatewayAPI.enableAppProtocol: true` is now set in the computed Gateway-API
  Helm layer, gated on `var.cilium_gateway_api`, and the rendered `argocd-server`
  Service advertises `appProtocol: kubernetes.io/h2c` on its http (80) port (the
  https/443 port is untouched). This lets the Cilium Gateway route argocd's gRPC
  (CLI/UI API) over h2c instead of de-framing it to HTTP/1.1 — which argocd
  answers with 404. **Versioning: this is a MINOR, not a MAJOR, change.** It is
  additive and gated: `enableAppProtocol` is a no-op until a Service opts in via
  `appProtocol`, and post-v2.0.0 only `argocd` renders a Service in the substrate,
  so there is no base-side blast radius beyond argocd.
- **Existing-cluster caveat (Day-2).** The Cilium config is delivered by a frozen
  `terraform_data.cilium_render` seed (`lifecycle.ignore_changes`), so on an
  already-seeded cluster `tofu plan` shows **no diff** for it — a merge looks live
  while Cilium's behavior is unchanged until a forced re-render/re-seed. Confirm
  the running state with
  `kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.enable-gateway-api-app-protocol}'`
  (expect `"true"`). See UPGRADING.md.
- **Kubelet serving-cert rotation is default-on for every cluster + cert-approver
  is now a base-delivered substrate seed (adr-0013).** The `tofu/modules/talos-cluster`
  module injects `machine.kubelet.extraConfig.serverTLSBootstrap: true` on ALL nodes
  (the non-deprecated KubeletConfiguration field, not the deprecated
  `--rotate-server-certificates` flag), placed FIRST so a consumer can opt out via
  `config_patches`. cert-approver (`alex1989hu/kubelet-serving-cert-approver` v0.11.0,
  image digest-pinned) ships as a controlplane `inlineManifest` seed (namespace +
  signer-restricted RBAC + restricted-PSA Deployment), replacing the former
  namespace-only `kubernetes/base/infrastructure/cert-approver/` stub — no consumer
  wiring of the upstream remote. Net effect: trusted kubelet serving certs
  out-of-the-box (metrics-server / `kubectl logs|exec|top` without
  `--kubelet-insecure-tls`). SAN-to-node CSR validation is a documented
  consumer-cluster Kyverno defense-in-depth obligation (the base ships no admission
  policy).

### Changed — BREAKING

- **cert-approver relocated from a `kubernetes/base/infrastructure/` component to a
  Talos controlplane `inlineManifest` seed (adr-0013); kubelet serving-cert rotation
  default-on.** Existing-cluster impact: adopting this tag re-pushes machine config
  (reconciled) → rotation turns on and kubelets emit `kubernetes.io/kubelet-serving`
  CSRs, but the create-only approver seed does NOT land on an already-bootstrapped
  cluster → rotation-on-without-approver unless the approver is ensured present. See
  UPGRADING.md `v3.0.0` for the required migration (incl. double-management resolution
  for consumers who already wired the upstream approver Application).
  `.ci-renderable-components.txt` is now `argocd` only.

- **Single task runner — the `Makefile` is retired; go-task is the only runner
  (#113).** Every former `make <target>` folds into a namespaced task in
  `Taskfile.yml`: `tofu:*` (OpenTofu validation — the CI-invoked `task tofu:ci`
  / `task tofu:test`), `gitops:*` (`validate`, `render-component`, `render-all`,
  `verify-rendered`), `bootstrap:*` (`argocd`, `argocd-password`),
  `cluster:init-yaml`, `supply-chain:oci-allowlist`, `mcp:*`, `dev:*`. Run
  `task --list` for the full set. `chart-pull` and `grafana-dashboards-check`
  are **dropped** with no replacement (the former is a `helm pull` + `shasum`
  one-liner; the latter scanned a consumer overlay path absent in the base).
  `devbox.json` gains `yq-go` + `gettext` + `ripgrep` (not `gnumake`). A `Makefile`
  deprecation stub remains for one release cycle: any `make <target>` prints the
  migration mapping and exits non-zero. **Contributor / consumer impact:**
  day-zero runbooks or scripts invoking `make <target>` must switch to
  `task <target>`. Decision:
  [`docs/adr-makefile-retirement.md`](docs/adr-makefile-retirement.md)
  (supersedes [`docs/adr-task-runner-consolidation.md`](docs/adr-task-runner-consolidation.md)).

- **Day-zero bootstrap decoupled from the ArgoCD helm double-install (#113).**
  ArgoCD is delivered as a Talos `inlineManifest` seed by the
  `tofu/modules/talos-cluster` module (`deploy_argocd`, default true) since
  #102, but the bootstrap path still helm-installed it on top — a
  double-install. The redundant helm install is **removed**; `tofu apply` seeds
  the ArgoCD controller, namespace, and CRDs, and the consumer day-zero runs
  only `task bootstrap:argocd` to apply the consumer-identity App-of-Apps root
  (root-project + root-application), which the module does **not** deliver.
  Skipping `task bootstrap:argocd` yields a healthy-looking but inert cluster.
  `task bootstrap:argocd` now waits for both root CRDs (`applications`,
  `appprojects`) to establish and for argocd-server to become available before
  applying the root, restoring the cross-exec-context ordering barrier the
  removed step provided. See [`docs/day-zero-pattern.md`](docs/day-zero-pattern.md)
  and UPGRADING.md.

### Fixed

- **Module-seeded `argocd` namespace now carries the PSA floor + recommended
  labels itself (#113).** With `kubernetes/bootstrap/argocd/namespace.yaml`
  retired, the module is the sole creator of the `argocd` namespace; the
  create-only `inlineManifest` seed now sets `pod-security.kubernetes.io/enforce:
  baseline` (+ audit/warn restricted) and the six `app.kubernetes.io/*`
  recommended labels (AGENTS.md §Hard Constraints), so the namespace is never
  delivered PSA-unenforced. A `tofu test` run asserts the floor + labels
  (red-green bound to the seed bytes).

## v2.0.0 — 2026-06-22

### Changed — BREAKING

- **Substrate-only base (next MAJOR / v2.0.0).** All non-substrate components
  were removed from `kubernetes/base/infrastructure/` — it now ships only
  `argocd` + `cert-approver`. The PNI / capability-first network-trust contract
  dissolved from the base (per [`docs/adr-substrate-only-base.md`](docs/adr-substrate-only-base.md))
  into apps-CI Conftest + consumer-cluster Kyverno. Every other platform
  component (monitoring, vault, cert-manager, nvidia, kubevirt, loki, dex,
  multus, piraeus, tetragon, external-secrets, …) now lives in the
  `talos-platform-apps` catalog as signed OCI artifacts; consumers re-source
  them from there via a Multi-Source Application. `make validate-kyverno-policies`,
  the Layer-A capability-index scripts/docs, and the PNI ADRs were removed. The
  Layer-C hardware-features registry + node-capability composition stay (the
  `tofu/modules/talos-cluster` module depends on them). See UPGRADING.md.
- **ArgoCD `server.certificate` disabled by default (substrate self-containment).**
  The substrate `argocd` no longer renders a `cert-manager.io/v1 Certificate`
  (`server.certificate.enabled: false`) — with cert-manager removed from the base
  it would otherwise render against an absent CRD/issuer. argocd-server already
  runs `server.insecure=true` (serves plaintext at the pod; terminate TLS at your
  gateway/ingress). Consumers fronting ArgoCD with cert-manager-issued TLS
  re-enable `server.certificate` in a values overlay and provide the issuer
  (and set `server.insecure=false` for pod-served TLS). See UPGRADING.md.
- **talos-cluster: `var.classes` / `node.class` removed (#135).** Use
  `var.images` + `var.hardware_capabilities` and `node.image` +
  `node.hardware_capabilities`. A node sits on one base `image` and holds a SET
  of composable `hardware_capabilities` resolved via a base-owned
  provisioning-profile catalog — no more hand-authored monolithic classes. The
  `installer_images` output is now keyed by hostname (was per class). Nodes whose
  kernel-arg provisioning is corrected (for example, IOMMU) re-image once. See UPGRADING.md
  and [`docs/adr-node-capability-composition.md`](docs/adr-node-capability-composition.md).

### Added

- **Render-determinism regression fence (`scripts/check-render-determinism.sh`, wired into
  `task ci`).** Derives every helm render from the module and asserts each is consumed only
  via its frozen `terraform_data` (per-resource `ignore_changes`), and that CRD renders
  carry `triggers_replace` — so the #123 decoupling cannot silently regress.

### Changed

- **Releases are now conventional-commit-driven (semantic-release + approval
  gate).** A push to `main` computes the next version from the commit history
  and, on one manual approval in the `release` GitHub Environment, tags it; the
  existing signed-OCI publish (`oci-publish.yml`) runs unchanged on the tag push.
  A commit-lint check gates PR titles. **Contributor impact:** a MAJOR bump now
  requires a real `BREAKING CHANGE:` footer (or `type!:`) — prose `**BREAKING**`
  in a body is not recognised. `CHANGELOG.md` stays human-curated; the
  auto-generated GitHub Release notes are the canonical per-release record. See
  [`docs/release-automation.md`](docs/release-automation.md).

### Fixed

- **talos-cluster: inlineManifest + ArgoCD-CRD renders frozen in state, decoupled from
  `talos_machine_configuration_apply` (#123).** `data.helm_template.{cilium,argocd,argocd_crds}`
  are re-evaluated every plan and are not byte-stable (Sprig `genCA` at template time;
  helm-provider ordering). Consumed directly, every `tofu plan` / Crossplane reconcile
  re-pushed a fresh machineConfig — constant drift plus a self-eviction risk on single-node
  control planes. Each render is now captured once via `terraform_data` with
  `lifecycle { ignore_changes = [input] }`; the ArgoCD-CRD render additionally carries
  `triggers_replace` (a Day-2 kubectl convergence that must re-apply on an intended chart/
  version bump). Completes the structural half #122/v1.2.0 left open (which fixed only the
  Hubble default trigger). No interface change; empty-render postconditions added so a
  partial render is not frozen.

## v1.2.0 — 2026-06-11

### Changed

- **Cilium seed: Hubble disabled by default (`hubble.enabled: false`).** The
  Cilium chart's default `hubble.tls.auto.method=helm` regenerates the Hubble CA
  + server TLS on every `helm template` render, making the Cilium inlineManifest
  seed — and thus the rendered Talos machineConfig — non-deterministic: every
  `tofu plan` produced a new `machine_configuration` hash, so every apply / in-
  cluster Crossplane reconcile re-pushed machineConfig to the node. **BREAKING**
  for consumers who relied on seed-default Hubble: Hubble is now Day-2 — re-enable
  via `cilium_values_override` (`hubble.enabled: true`; prefer
  `tls.auto.method=cronJob` to keep the render deterministic) or Cilium ArgoCD
  self-management. **Partial fix (Refs #121, default trigger only):** the
  structural coupling — a live `data.helm_template` consumed by
  `talos_machine_configuration_apply` with no `lifecycle { ignore_changes }`,
  affecting both the Cilium and ArgoCD renders — is unaddressed; a future chart
  bump / override can reproduce the drift. Tracked in #123.

## v1.1.0 — 2026-06-07

### Removed

- **Consumer-side Cilium render path retired.** `scripts/render-cilium-bootstrap.sh`
  is deleted — the `talos-cluster` module delivers Cilium as a controlplane
  `inlineManifest` seed (since `v1.0.0`), so the render → `cluster.extraManifests`-URL
  recipe is obsolete. The deleted script is dropped from the OCI tarball allowlist
  (`.ci-oci-tarball-{include,expected}.txt`) and the `oci-publish.yml` renderer
  exec-bit check is removed with it. `kubernetes/bootstrap/cilium/{values,extras}.yaml`
  stay in the repo **and** in the OCI artifact as the Cilium values / GatewayClass
  reference (only the dead script leaves the artifact). **Migration:** a consumer that
  still invoked the renderer adopts the module-delivered Cilium seed (`deploy_cilium`,
  default `true`); the reference values are unchanged.

### Changed

- **Module plan-time validation hardened.**
  - `dual_stack` is now guarded **bidirectionally**: `dual_stack = true` requires
    `pod_cidr` AND `service_cidr` to each carry an IPv4 and an IPv6 CIDR, and
    `dual_stack = false` requires each to be IPv4-only. Previously a single-family
    CIDR with `dual_stack = true` — and the reverse, a v6 CIDR with
    `dual_stack = false` — both silently mismatched Talos (which carries the full
    subnet list) against the Cilium seed (which enables ipv6 only on the flag).
  - `pod_cidr`/`service_cidr` entries are now CIDR-format-validated (`cidrhost`),
    rejecting malformed values at `tofu validate` time.
  - `sops_age_key` must now start with `AGE-SECRET-KEY-1` (not merely `!= ""`), and
    the complete example root drops the `sops_age_key` default so a copied example
    cannot silently `tofu apply` a non-functional ksops key — it must supply a real
    key via `TF_VAR_sops_age_key`.
- **Cilium-delivery docs corrected** to describe the module `inlineManifest` seed
  (`day-zero-pattern.md` Layer-1, `AGENTS.md`, `kubernetes/AGENTS.md`) instead of the
  retired render path.

### Fixed

- **`talos-cluster` bakes the exact declared extension set (#119).** The
  `officialExtensions` comprehension resolved names from the
  `talos_image_factory_extensions_versions` data source, whose `filters.names`
  matches by **substring/prefix** — so a class declaring `siderolabs/gvisor`
  also pulled in `siderolabs/gvisor-debug`. Resolved names are now intersected
  with the declared set, and a `precondition` fails loudly when a declared
  extension does not resolve **exactly** (non-canonical / typo input), instead
  of silently baking a partial or empty set. Because the Image Factory schematic
  ID is a SHA256 over the whole schematic, the prior behaviour silently changed
  the content-addressed ID and the installed extension set on every gvisor-class
  node. Closes #118.
- **Adoption-proof harness runs on bash 3.2 (#117).**
  `test/run-adoption-proof.sh` aborted under `set -u` on macOS's default
  `/bin/bash` (3.2) before the first import, because a bare `"${PT[@]}"` over an
  empty array is an unbound-variable error pre-bash-4.4. The pass-through tofu
  flags now use the empty-safe `${PASSTHRU[@]+"${PASSTHRU[@]}"}` idiom at all
  three call sites; the dead `PT` mirror is removed. Closes #116.

## v1.0.0 — 2026-06-06

### Changed — BREAKING

- **`talos-cluster` module delivers Cilium as the CNI and disables the Talos
  default Flannel (`deploy_cilium` defaults to `true`).** Cilium is Layer-1
  substrate (Talos + Cilium + ArgoCD); the module now disables the bundled CNI
  (`cluster.network.cni.name: none`) + kube-proxy and bakes a locally-rendered
  Cilium chart into the controlplane `cluster.inlineManifests` as a create-only
  bootstrap **seed** — the same `data.helm_template` → inlineManifest pattern as
  ArgoCD (`cilium_chart_version` is a SEED knob, not an upgrade knob). A fresh
  cluster therefore comes up on Cilium, **not Flannel**. `cni:none` is applied in
  both the config-generation and per-node apply passes, so a caller patch cannot
  resurrect Flannel. New inputs: `deploy_cilium`, `cilium_chart_version`,
  `cilium_chart_repository`, `cilium_namespace`, `cilium_values_override`,
  `cilium_routing_mode`, `cilium_native_routing_cidr`, `cilium_kube_proxy_replacement`,
  `cilium_mtu`, `cilium_encryption` (`none|wireguard|ipsec`), `cilium_ipsec_key`
  (sensitive), `cilium_gateway_api`, `cilium_gateway_api_crds_url`, plus first-class
  `pod_cidr`, `service_cidr` (fed to BOTH Talos subnets AND Cilium), `dual_stack`,
  and `allow_scheduling_on_controlplanes`. The base ships a minimal,
  cluster-agnostic Cilium floor (`helm/cilium-values.yaml`); per-cluster install-time
  config rides the typed inputs + `cilium_values_override`. Decision + validation:
  `docs/adr-cluster-yaml-sot.md`.

  **BREAKING — migration:** a caller that previously relied on the Talos-default
  Flannel plus its own `cluster.extraManifests`-URL Cilium recipe must either adopt
  the module-delivered Cilium (drop the extraManifests recipe) or set
  `deploy_cilium = false` to keep the prior behaviour. Next OCI tag is a MAJOR bump.

- **`cluster.yaml` is now the full declarative cluster Source-of-Truth.** It
  carries the complete cluster definition (identity, Talos/Kubernetes versions,
  endpoint, pod/service CIDR, dual-stack, scheduling, nodes, classes,
  machine-config patches, and the `substrate.{cilium,argocd}` config). The
  consumer's OpenTofu root becomes a thin `yamldecode` shim that maps the file
  onto the `talos-cluster` module's typed interface — tofu is the executor, not
  the SoT. Machine-config patches are declared as structured YAML maps (the shim
  `yamlencode`s them onto the module's `list(string)` interface). Secrets
  (`sops_age_key`, `cilium_ipsec_key`) have no slot in `cluster.yaml`; they are
  supplied via tfvar/env. `cluster.yaml.example` and the
  `tofu/modules/talos-cluster/examples/complete` root are rebuilt to this shape.
  Realizes `docs/adr-cluster-yaml-sot.md` decision 3; corrects the OpenTofu-cutover
  ADR's "node/class definitions live in the consumer's OpenTofu root" stance.

  **BREAKING — migration:** the `cluster.yaml` schema and the consumer
  OpenTofu-root shape change. A consumer on the post-#82 slim `cluster.yaml`
  re-expands it to the full schema and replaces its hand-written HCL root with the
  thin `yamldecode` shim (see the rebuilt complete example). Next OCI tag is a
  MAJOR bump.

### Added

- **Cilium Gateway API controller** enabled by default (`cilium_gateway_api`),
  satisfying the "Gateway API only" Hard Constraint at the mechanism layer. The
  Gateway API CRDs (Cilium 1.19 → Gateway API v1.4.1 standard channel) are a Day-1
  GitOps / apps-catalog concern by default; bootstrap seeding via
  `cluster.extraManifests` is **opt-in** (`cilium_gateway_api_crds_url`), because a
  failed `extraManifests` fetch is not graceful (it crashloops Talos'
  ExtraManifestController and blocks clean bootstrap).
- **Plan-time guards** in the module: a SecureBoot-installer substring guard over
  all caller `config_patches` (the no-SecureBoot Hard Constraint, in code — a
  consumer's patches escape the repo's `tofu/**` CI grep) and a clear
  undefined-`node.class` failure.

### Fixed

- **OCI release tarball now ships the module `helm/` values dir**
  (`argocd-values.yaml`, `cilium-values.yaml`). The allowlist previously omitted
  it, so a consumer using the published OCI artifact as the tofu module source hit
  a file-not-found at plan time for both ArgoCD and Cilium. The `git::` source path
  was unaffected.

## v0.8.0 — 2026-06-03

### Changed — BREAKING

- **`talos-cluster` module delivers ArgoCD as a Talos `inlineManifest`
  (`deploy_argocd` defaults to `true`).** ArgoCD is Layer-1 substrate in the C4
  layer model (Talos + Cilium + ArgoCD = three co-equal substrate pillars), so
  the module now seeds the bootstrap install: the `argo-cd` chart is rendered
  locally via `data.helm_template` (new `hashicorp/helm` provider, used for
  rendering **only** — no `helm_release`/apply against a computed kubeconfig) and
  baked into the controlplane `cluster.inlineManifests` as namespace →
  `sops-age-key` Secret (for the ksops repoServer) → ArgoCD app. The three
  ArgoCD CRDs (~1.8 MB) are too large for an inlineManifest, so the module
  applies them via `kubectl` server-side after the health gate (new
  `hashicorp/local` + `hashicorp/null` providers; requires `kubectl` on the
  apply host). New inputs: `deploy_argocd` (default `true`), `sops_age_key`
  (sensitive, **required** when `deploy_argocd`), `argocd_namespace`,
  `argocd_chart_version` (seed-only), `argocd_values_override` (merged, not
  replaced). Steady state (TLS cert, RBAC, OIDC, app-of-apps) is ArgoCD
  self-management in the consumer repo.

  **BREAKING — migration:** existing callers must either set
  `deploy_argocd = false` to keep prior behaviour, or supply `sops_age_key`
  (else `tofu plan` hard-fails on the precondition). The default-`true` is the
  correct Vision statement (ArgoCD is constitutive), so this is a deliberate
  breaking change, not an additive one.

- **Module waits until the cluster is healthy.** `data.talos_cluster_health`
  blocks `tofu apply` after bootstrap until etcd quorum + nodes Ready + apiserver
  reachable (new `cluster_health_timeout`, default `10m`). The
  `kubeconfig`/`talosconfig` outputs and a new `cluster_health` output
  `depends_on` it, so credentials are only emitted for an online cluster. NOTE:
  the gate verifies cluster reachability, NOT the ArgoCD rollout.

## v0.7.0 — 2026-06-02

### Changed — BREAKING

- **OpenTofu module is the sole Talos cluster-lifecycle path.** The entire
  `talos/Makefile.lib` + `argv-print.sh` + 5-axis `cluster.yaml` generator is
  removed and replaced by the `tofu/modules/talos-cluster` OpenTofu module
  (machine secrets → per-class Image-Factory installer → machine config → apply
  → bootstrap → kubeconfig). Node roles are `controlplane`/`worker` only;
  hardware specialisation is a per-node `class` selecting an Image-Factory +
  patch profile (`architecture` incl. arm64/SBC `overlay`, `extensions`,
  `config_patches`); per-node `config_patches` carry genuinely per-node values
  (for example, NIC binding). `cluster.yaml` is slimmed to the ArgoCD-bootstrap identity
  (`cluster.{name,overlay,target_revision}` + `repo.url`); Talos node/class
  definitions move to the consumer's OpenTofu root. Local tooling is pinned via
  devbox; `task ci` (fmt-check + validate + lint) is the validation entrypoint
  and a new `tofu-validate` CI workflow enforces it. Decision + consequences:
  [`docs/adr-opentofu-cluster-lifecycle.md`](docs/adr-opentofu-cluster-lifecycle.md).
  **Migration:** see [`UPGRADING.md`](UPGRADING.md). Adopting an already-running
  cluster (PKI import, no re-bootstrap) is a tracked follow-up — the module is
  greenfield-safe today.

### Removed

- `talos/` in full (`Makefile.lib`, `scripts/*`, `patches/*`, `schemas/`,
  `test/`, `versions.mk`, RELEASE-NOTES-v0.5.x/v0.6.0, `AGENTS.md`), the
  `.github/workflows/role-patches-canonical.yml` workflow, and the 5-axis
  sections of `cluster.yaml`. The `EMIT=content` shared-render-artifact work
  (`adr-shared-render-artifact.md`) is superseded — the OpenTofu provider
  renders machine config directly, so the cross-frontend render bridge is no
  longer needed.

- **`feat(oci): ship Cilium recipe + inputs in OCI artifact (symmetric to
  Talos)`** — the OCI tarball now also carries
  `kubernetes/bootstrap/cilium/{extras,values}.yaml` and
  `scripts/render-cilium-bootstrap.sh`, mirroring the existing `talos/`
  surface. Additive only: no render-mechanic, schema, or Consumer-side
  change; a consumer cluster continues consuming Cilium via Git
  Multi-Source. Closes #84.

- **Repo-wide shellcheck gate** — adds `shellcheck -S warning` over all
  tracked `*.sh` to both pre-commit (local hook, `repo: local`) and CI
  (`gitops-validate.yml` `shellcheck` job, parallel to `secret-scan`).
  Fixes the two pre-existing findings: SC2034 (unused `src` in
  `scripts/render-capability-index.sh:309`) and SC2038 (`find|xargs`
  replaced with `-exec sh -c … +` in `scripts/verify-rendered.sh:19–21`).
  Both fixes are behavior-preserving; enumeration output is byte-identical.
  Closes #94.

- **`feat(cilium): render script accepts CILIUM_VALUES_OVERLAY + CILIUM_OUTPUT_FILE for Consumer overrides`**
  — `scripts/render-cilium-bootstrap.sh` gains two optional env vars; Helm `-f`
  list-replace caveat documented in the script header. Additive only; overlay-unset
  render is byte-identical. Closes #85.

Next release is the v1.0.0 substrate split per
[`docs/adr-substrate-only-base.md`](docs/adr-substrate-only-base.md).

## v0.6.0 — 2026-05-28

This is the coordinated MAJOR release that turns the v0.5.x 5-axis
preview into the only supported `cluster.yaml` path and folds the
remaining PNI policy name/behaviour cleanup. Engineering rationale per
item lives in [`talos/RELEASE-NOTES-v0.6.0.md`](talos/RELEASE-NOTES-v0.6.0.md);
consumer migration recipe in [`UPGRADING.md` §`v0.6.0`](UPGRADING.md).
The substrate split (PNI + 19 other components move to a new
`talos-platform-apps` repo) is **not** in this release — see
[`docs/adr-substrate-only-base.md`](docs/adr-substrate-only-base.md)
for the v1.0.0 plan.

### Changed (breaking)

- **Cluster identity field renames** — `cluster.api_vip` →
  `cluster.vip`; `cluster.gateway_vip` removed. A cluster has exactly
  one Kubernetes API VIP; Gateway / LoadBalancer VIPs belong with the
  respective Gateway-API manifests, not cluster identity.
- **NTP servers as a list** — `cluster.ntp_server` (string) →
  `cluster.ntp_servers` (array, minItems 1, per-element charset
  validation). Single-NTP was a SPOF: outage → clock drift → etcd
  cert validation failure. Talos `machine.time.servers` is natively
  a list; ≥2 servers now recommended for redundancy.
- **`hardware-platforms.nvidia-gpu-node` removed.** Axis 4 names the
  CPU mainboard / chassis class only. GPU presence is captured on
  Axis 5 via the `gpu-nvidia` capability; the Axis-4 entry was a
  duplicate contract. GPU nodes now declare
  `hardware-platform: intel-generic` plus capability `gpu-nvidia`.
- **gVisor removed from `hardware-capabilities`.** Workload-runtime-class
  labels (`platform.io/gvisor`) are not hardware predicates
  per ADR Three-Layer §D7. `worker-gvisor.yaml` now lives in
  `roles.<role>.patches[]` per the slot ladder in
  `talos/AGENTS.md §Patch slots`. `translate-legacy-cluster-yaml.sh`
  no longer emits a `gvisor` entry in the rendered
  `hardware-capabilities` block.
- **`hardware_capabilities` underscore alias removed.** The v0.5.4
  grace-window alias is gone from the schema, `argv-print.sh`, and
  `validate-schematics.sh`. Use canonical kebab-case
  `hardware-capabilities` everywhere. Schema's `required` list now
  hard-includes the kebab field; underscore-only documents fail with
  `'hardware-capabilities' is a required property`.
- **`hardware-capabilities[*].patches[].file` is now auto-composed.**
  Was declarative-only in v0.5.x. `argv-print.sh` emits cap-patches
  as `--config-patch` after role-patches (later-wins per talosctl
  merge semantics). Audit for accidental duplication with
  `roles.<role>.patches[]` — the same patch listed in both is
  emitted twice (harmless for identical content; cap wins on
  divergence).
- **Legacy `talos/Makefile` deleted** — the 439-LOC pattern-rule
  generator is gone. Consumers MUST include
  `$(BASE_DIR)/Makefile.lib` from their `talos/Makefile`.
- **Kyverno ClusterPolicies renamed (PNI name/behaviour cleanup).**
  Two policies that were missed by the v0.5.0 rename (#40):
  `pni-capability-validation-audit` →
  `pni-capability-validation-enforce`;
  `pni-reserved-labels-audit` → `pni-reserved-labels-enforce`.
  Rule names, validation messages, and behaviour unchanged. File
  names already matched the new policy names — only the
  `metadata.name` field was renamed. Migration is identical to the
  v0.5.0 `pni-contract` rename.

### Added

- **`talos/RELEASE-NOTES-v0.6.0.md`** — engineering rationale per
  breaking change above.
- **`UPGRADING.md §v0.6.0`** — consumer migration recipe (nine steps,
  in order).

### Added (Layer-A / Layer-C work, pre-cutover)

- **Layer-A entry classification (issue #62).** New required `kind:`
  field on every entry in `docs/platform-capability-index.yaml` —
  enum `tool-capability | network-primitive`. Four entries
  reclassified as `network-primitive` (`internet-egress`,
  `controlplane-egress`, `gateway-backend`, `external-gateway-routes`)
  per the Round-2 layer-audit
  (`.work/issues/layer-audit/cleanup-scope.md` Q1) — these have
  legitimately empty `composition[]` because the Cilium/Kyverno rule
  itself IS the dataplane. The remaining 32 entries are
  `tool-capability`. Hybrid case: `s3-object` keeps `kind:
  tool-capability` (has `minio-operator` real tool); its `external-s3`
  implementation gains a per-impl `external_network_attachment: true`
  flag. Mechanism decision recorded in
  `.work/issues/p5-network-primitives-lift/decision.md`.
  `scripts/lint-capability-index.sh` enforces the kind enum + per-impl
  flag; `scripts/check-capability-index-refs.sh` skips the
  empty-composition violation for `kind: network-primitive` entries.
  `scripts/render-capability-index.sh` surfaces `kind:` in the summary
  table and per-entry header. `docs/capability-architecture.md` gains
  a "Layer A entries: tool-capability vs network-primitive"
  subsection.

- **Three-Layer Capability Architecture (issue #61).** New ADR
  `docs/adr-three-layer-capability-architecture.md` (status: accepted)
  supersedes the Two-Layer ADR. Introduces **Layer C — Hardware Features
  Registry** at `docs/platform-hardware-features.yaml` with 7 atomic
  feature entries (`nvidia-gpu`, `vt-x-or-amd-v`, `kvm-kernel-module`,
  `drbd-kernel-module`, `local-nvme-block-device`, `iommu-enabled`,
  `ebpf-capable-kernel`) plus draft-2020-12 JSON Schema at
  `docs/schemas/hardware-features.schema.json`. Six Layer-A entries
  (`gpu-runtime`, `vm-runtime`, `block-storage-replicated`,
  `block-storage-local`, `secondary-network-attachment`,
  `cluster-provisioning`) gain `requires_hardware_features[]` referencing
  Layer-C ids. `node-feature-discovery` removed from
  `gpu-runtime.composition[]` (Layer-C producer-tooling, not Layer-A);
  `gpu-runtime.independence_test.alt_impls_exist` stays `false` (entry
  is NVIDIA-pinned by name + contract + `requires_hardware_features`;
  AMD ROCm / Intel Gaudi are sibling Layer-A capabilities, not
  alt-impls of this entry); `independent_lifecycle` re-evaluated to
  `true` post-NFD-removal (device-plugin and DCGM-exporter have
  separate version trains).
- **Composite Capability Convention.** ADR §Composite capability
  convention documents the CNCF-Platforms-White-Paper two-tier model:
  Layer C holds atomic features; composite capabilities (for example,
  `compute-virt`, `compute-gpu-nvidia`) are downstream-defined in
  consumer `cluster.yaml` `hardware-capabilities:` blocks via
  `requires_features[]`. Composite labels emit
  `platform.io/hardware-capability.<cap>=true` via Talos
  `machine.nodeLabels`. The base ships no composite-capability registry.
- **`scripts/lint-hardware-features.sh`** — sibling lint script that
  validates `docs/platform-hardware-features.yaml` against the JSON
  Schema (uses `check-jsonschema`; falls back to `uvx` for local dev).
- **`scripts/render-capability-index.sh`** extended to dispatch to
  Layer A + Layer C rendering. New `--layer {a,c,all}` flag (default
  `all`); `--check` verifies both rendered MD files.
- **`scripts/check-capability-index-refs.sh`** extended with Layer-C
  resolution (`requires_hardware_features[]` ids must resolve to Layer-C
  registry) and orphan-infra-dir advisory detection (`WARN:
  orphan-infra-dir <path>` for dirs under
  `kubernetes/base/infrastructure/` not referenced by any Layer-A
  composition[] and not in the Layer-C producer-tooling allow-list).
- **CI job `capability-index-check`** reordered: Layer-C schema lint
  runs before Layer-A refs-check (ordering matters — Layer-A
  cross-references depend on Layer-C ids resolving). Job renamed to
  `Capability-index validation (Layer A + Layer C)`.
- **Kyverno ClusterPolicy `pni-reserved-labels-enforce`** extended with
  new rule `reserved-layer-c-hardware-labels`: denies tenant-set
  `platform.io/hardware-feature.*` and `platform.io/hardware-capability.*`
  labels on standard-workload kinds (Pod, Deployment, StatefulSet,
  DaemonSet, ReplicaSet, ReplicationController, Job, CronJob, Service,
  Namespace), checking BOTH the resource's own `metadata.labels` AND
  workload-template paths (`spec.template.metadata.labels`,
  `spec.jobTemplate.spec.template.metadata.labels`). Closes the
  controller-mediated propagation attack surface identified in Round-1
  team-red review (`.work/reviews/r1/team-red.md` CRITICAL). Per-CRD
  enforcement (KubeVirt `VirtualMachine`, CNPG `Cluster`, and other
  consumer-installed CRDs) is out-of-scope and tracked as a follow-up
  issue per ADR §Enforcement scope (intentional limits).

### Changed

- **`AGENTS.md` §"Reserved-label rule"** extended for Layer C: the two
  new namespaces (`platform.io/hardware-feature.*`,
  `platform.io/hardware-capability.*`) are documented; upstream-owned
  namespaces (`feature.node.kubernetes.io/*`, `nvidia.com/*`) are
  documented as convention-not-policy.
- **`ARCHITECTURE.md`** updated to reference the three-layer model
  (replacing the two-layer description) and to link to the new ADR.
- **`docs/capability-architecture.md`** gains a "Where this document
  sits in the three-layer model" section explicitly naming Layer C
  alongside Layer A and Layer B.
- **`docs/README.md`** index updated: links to
  `platform-capability-index.md` (Layer A), `platform-hardware-features.md`
  (Layer C), and the new Three-Layer ADR; the Two-Layer ADR entry is
  marked superseded.
- **`docs/adr-two-layer-capability-architecture.md`** frontmatter
  flipped to `status: superseded` with `superseded_by:
  adr-three-layer-capability-architecture.md`. Body preserved verbatim
  for decision history; a top-of-document blockquote calls out the
  supersession.

### Changed (pre-existing)

- **README.md surfaces the Day-Zero invariant in the lead section.**
  One paragraph between "Why this exists" and "The idea" names the
  load-bearing rule ("the base ships Talos plus the minimum needed for
  ArgoCD to take over; everything else is GitOps-reconciled") and
  links to `docs/day-zero-pattern.md`. Prevents the reader from having
  to reconstruct the pattern from `ARCHITECTURE.md`, `AGENTS.md`, and
  the root `Makefile`.
- **README.md rewritten around the repo's vision (#58).** Reorganised
  from a feature-listing into a problem-and-answer narrative: why this
  base exists (three pain points: per-cluster drift, tool lock-in via
  network policy, vendor-the-tarball trust), the idea that closes each
  pain (immutable OCI artifact, capability-first PNI, cosign + SLSA +
  SBOM), what consumers receive, how to consume it (Day-0 vendor +
  Day-2 ArgoCD Multi-Source stanza), how to verify it before vendoring,
  honest status (single maintainer, pre-1.0, first consumer
  established), and a routing table to the rest of the docs. Body now
  matches the Talos / Crossplane / FluxCD pattern for operator-audience
  base repos; component listings, validation-command reference, and
  full structure tree moved to `ARCHITECTURE.md` / `CONTRIBUTING.md` /
  `docs/` where they belong.

### Added

- **Day-Zero pattern explanation (`docs/day-zero-pattern.md`).** Single
  canonical write-up of the three-layer bootstrap path: Talos (OS +
  bundled Kubernetes + Cilium CNI via `extraManifests`) → ArgoCD
  self-bootstrap (the five `kubectl apply` / `helm` invocations
  contained behind `make argocd-bootstrap`, each with a stated
  reason) → ArgoCD-reconciled day-two (the 22 components under
  `kubernetes/base/infrastructure/`, sync-wave -2 / -1 / 0 / 1
  ordering preserved). Includes the canonical end-to-end command
  sequence a consumer-cluster operator runs, plus the explicit
  statement that nothing outside the documented bootstrap exceptions
  may be `kubectl apply`-ed. Linked from `docs/README.md §Explanation`
  and from the tutorial's *Where to go next* table.
- **Human-maintained component dependency graph
  (`docs/component-dependencies.md`).** Mermaid graph of cross-component
  edges in `kubernetes/base/infrastructure/`. Hard edges sourced from
  `values.yaml` service-DNS references, `ClusterIssuer` names, and
  CRD producer / consumer relationships; soft edges sourced from
  ADR-documented namespace co-tenancy and App-of-Apps deploy
  provenance. PNI `provide.<cap>` / `consume.<cap>` labels are
  deliberately **not** the source — they are an admission contract,
  not a dependency declaration. `CONTRIBUTING.md` mandates an update
  on component add / remove / rename or service-DNS / Issuer
  cross-reference changes. A render-script-based approach was
  evaluated via multi-perspective review and an empirical research
  pass and rejected as overengineering at the current scale
  (22 components, 3 documented cross-references) per CNCF Platforms
  White Paper TVP guidance; re-evaluate when cross-reference count
  exceeds ~50.
- **Vale prose linter + Google Developer Documentation Style (#57).**
  `.vale.ini` configures Vale 3.14.2 with the Google style package,
  scoped to root-level Markdown files (`README`, `ARCHITECTURE`,
  `AGENTS`, `CONTRIBUTING`, `SECURITY`, `MAINTAINERS`, `UPGRADING`,
  `CHANGELOG`). Conservative initial ruleset: opts out of Headings,
  EmDash, LyHyphens, Spelling, Units, WordList, Will, Acronyms (each
  with a documented reason); enforces `Latin`, `Periods`, `Quotes`,
  `Slang`, `We`, plus `Vale.Avoid` and `Vale.Repetition`. New `vale`
  CI workflow (pinned by SHA per Scorecard convention) blocks on
  every error.
  Spec: [vale.sh](https://vale.sh) +
  [Google Developer Docs Style](https://developers.google.com/style).
- **arc42 narrative scaffolding in ARCHITECTURE.md (#56).** Adds arc42
  sections 1 (Introduction & Goals), 2 (Architecture Constraints), 4
  (Solution Strategy), 10 (Quality Requirements), 11 (Risks &
  Technical Debt), 12 (Glossary) around the existing C4 L1+L2 views.
  arc42 §5 (Building Block View) and §6 (Runtime View) remain covered
  by C4 L2 and "Key flows"; §9 (Architecture Decisions) is the ADR
  set. Spec: [arc42.org](https://arc42.org/).
- **MADR 3.0 frontmatter on every ADR (#55).** All four ADRs migrated
  from plain-Markdown `**Status:** …` / `**Date:** …` headers to
  structured YAML frontmatter (`status`, `date`, `deciders`,
  `consulted`, `informed`, `supersedes`, `related`). New
  [`docs/adr-template.md`](docs/adr-template.md) is the source for
  future ADRs. Spec:
  [MADR 3.0](https://adr.github.io/madr/) ([adr.github.io](https://adr.github.io)).
- **OpenSSF Best Practices self-assessment (#54).** New
  [`docs/openssf-best-practices.md`](docs/openssf-best-practices.md)
  maps every Passing-level criterion to a load-bearing artefact in
  this repo (Apache-2.0 + REUSE for licensing, cosign + SLSA + SBOM
  for secure release, `SECURITY.md` + `security.txt` for vulnerability
  reporting, conftest + kubeconform for static analysis). External
  enrolment at <https://www.bestpractices.dev> is a manual maintainer
  step; the badge appears in README only after the project ID is
  assigned. Spec:
  [bestpractices.dev/criteria/0](https://www.bestpractices.dev/criteria/0).
- **OpenSSF Scorecard CI workflow + README badge (#53).** Weekly
  scheduled supply-chain risk analysis via
  `ossf/scorecard-action@v2.4.3` (SHA-pinned). SARIF results uploaded
  to GitHub code-scanning + published to the public OpenSSF Scorecard
  API at `api.scorecard.dev`. The README badge reflects the latest
  scheduled run. Spec:
  [github.com/ossf/scorecard](https://github.com/ossf/scorecard).
- **CycloneDX 1.6 SBOM attached to every OCI artifact (#52).** Generated
  by Syft via `anchore/sbom-action@v0.17.9` during the publish workflow
  and attached as a cosign attestation (`--type cyclonedx`) keyed to the
  OCI artifact digest. Consumers verify via
  `cosign verify-attestation --type cyclonedx …` (see
  [`docs/oci-artifact-verification.md`](docs/oci-artifact-verification.md)
  step 3). Spec: [CycloneDX 1.6](https://cyclonedx.org/specification/overview/).
- **REUSE 3.3 licensing compliance (#51).** `REUSE.toml` + `LICENSES/`
  layout with aggregate Apache-2.0 annotation; `LicenseRef-UpstreamHelm`
  marks rendered Helm output (project does not own the copyright). New
  `reuse-compliance` CI job enforces compliance on every PR.
- **RFC 9116 `.well-known/security.txt` (#50).** Machine-readable
  security contact metadata complementing `SECURITY.md`. Indexed by
  OpenSSF Scorecard and security scanners.

## v0.5.0 — 2026-05-18

> This release bundles four concurrent work streams: (a) the
> capability-first v2 refactor (PRs B / C / D / E), (b) the documentation
> overhaul (root-level OSS-hygiene files + Diátaxis-organised `docs/`),
> (c) the late-cycle PNI policy rename (#40), and (d) the
> production-readiness wave that makes the base consumable by a second
> cluster (#31 cluster-agnostic refactor, #33 Layer-A validation tooling,
> #35 per-component READMEs).

### Added

- **PNI policy rename (#40).** `ClusterPolicy/pni-contract-audit` is now
  named `pni-contract-enforce`, matching its filename and its
  `validationFailureAction: Enforce` semantics. Rule names and validation
  messages are unchanged. See [`UPGRADING.md` §v0.5.0](UPGRADING.md) for
  the consumer-side migration steps.
- **Layer-A capability-index validation tooling (#33).**
  - `scripts/lint-capability-index.sh` — schema lint (required fields,
    kebab-case ids, ISO-8601 dates, enum validity for stability /
    deployment_topology / swap_class / implementation status). Uses
    `yq has()` instead of `// "missing"` to distinguish a missing field
    from an explicit `false` boolean.
  - `scripts/check-capability-index-refs.sh` — cross-reference check:
    `composition[]` resolves to a `kubernetes/base/infrastructure/<comp>/`
    directory or is marked external; `replaced_by` / `split_into` /
    `composed_of` resolve to Layer A ids; `pni_capability_id` is null or
    resolves to a Layer B id.
  - `scripts/render-capability-index.sh` — deterministic, idempotent
    YAML → Markdown renderer. `--check` mode for CI drift detection.
  - `scripts/test/capability-index-broken-fixture.yaml` — negative-test
    fixture (lint must exit non-zero on it).
  - `docs/platform-capability-index.md` — committed render of the
    802-line YAML source.
  - `.github/workflows/gitops-validate.yml` — new `capability-index-check`
    CI job runs all four checks (positive, negative-test, refs, render
    drift).
  - `docs/adr-two-layer-capability-architecture.md` — status promoted
    from `proposed` to `accepted` now that the two-artifact invariant
    (Layer A id-set ⊇ Layer B id-set; cross-references resolve;
    generated MD matches YAML) is mechanically enforced across PRs.
- **Per-component READMEs (#35).** All 22 directories under
  `kubernetes/base/infrastructure/<comp>/` now ship a README answering:
  what the component is for (one sentence), upstream chart + pinned
  version, declared PNI capabilities (provider + consumer), repo-specific
  Helm-value overrides, and known upgrade gotchas.
  `scripts/render-component-readmes.sh` is the deterministic generator
  with hand-curated Purpose + Gotchas maps and auto-extracted chart /
  namespace / PNI / values fields. bash 3.2 compatible (uses case-
  statement functions, not associative arrays).
- **Root-level OSS-hygiene documents.**
  - `ARCHITECTURE.md` — root-level C4 L1/L2 architecture document with
    Mermaid diagrams (System Context, Container view, release flow,
    capability-admission flow).
  - `SECURITY.md` — disclosure channel, supported-versions matrix,
    supply-chain (cosign + SLSA + immutable tags), threat-model summary,
    in/out-of-scope table, hardening notes.
  - `CONTRIBUTING.md` — scope, conventional-commits, PR expectations,
    capability-first design rules, file-placement rules, sensitive-data
    policy.
  - `MAINTAINERS.md` — active maintainer list + decision authority.
  - `CODEOWNERS` — review routing per path.
  - `UPGRADING.md` — cumulative migration guide for OCI-vendored
    consumers; per-tag template for future MAJOR/MINOR notes; pending-
    sunset table (`storage-csi`, `monitoring-scrape-provider`).
- **Diátaxis-organised `docs/` set.**
  - `docs/README.md` — Diátaxis-organised doc index.
  - `docs/capability-architecture.md` — canonical architecture
    explanation for the capability-first v2 contract.
  - `docs/pni-cookbook.md` — concrete consumer + producer + CCNP recipes.
  - `docs/tutorial-first-consumer-cluster.md` — Diátaxis tutorial
    quadrant (vendor + verify + render).
  - `docs/harness-plugin-integration.md` — specification of what the
    harness plugin should provide for the v2 contract;
    explicit rationale why this base ships no `.claude/`.
- **Lint + CI for docs.** `.markdownlint.yaml` + `.markdownlintignore` +
  CI gate in `.github/workflows/docs-lint.yml` (markdownlint + auto-
  regen freshness check on `docs/capability-reference.md`).
- **PNI policy — instanced-suffix audit (PR D).**
  `kyverno-clusterpolicy-pni-instanced-suffix-required.yaml` — new
  audit-mode ClusterPolicy that emits a PolicyReport advisory when a
  namespace declares bare `platform.io/consume.<cap>` for a capability
  marked `instanced: true` in the PNI registry. Audit-mode by
  intentional design: per-instance enforcement (generate+mutate) is
  consumer-overlay responsibility, not base. The advisory signals the
  vocabulary smell without blocking platform-internal consumers
  (`cert-manager`, `external-secrets`) whose specific Vault KV mount
  is overlay-configured.
- **Producer pod labels on operator pods (PR C).**
  - `vault-operator` (bank-vaults): pod retains
    `capability-provider.monitoring-scrape`. No `admission-webhook`
    label — bank-vaults vault-operator does NOT ship a
    ValidatingAdmissionWebhook (verified by grep of chart templates).
  - `vault-config-operator` (Red Hat): pod gains
    `capability-provider.{admission-webhook,monitoring-scrape}` via a
    kustomize strategic-merge patch. The upstream chart does NOT expose
    a `podLabels` value (hardcoded selectorLabels helper), so the patch
    is the right altitude.
  - `piraeus-operator`: pod gains
    `capability-provider.{admission-webhook,monitoring-scrape}` via the
    base `values.yaml`. NOTE: the base ships only `namespace.yaml` for
    piraeus-operator; the consumer overlay deploys the Helm chart and
    must merge the base `values.yaml` into the release.
- **Namespace trust anchors (PR C).**
  - `vault` namespace (declared by both vault-operator and
    vault-config-operator): adds `provide.admission-webhook`. The two
    `namespace.yaml` files are kept identical so whichever ArgoCD app
    applies last produces a consistent label set.
  - `piraeus-datastore` namespace: adds
    `provide.{admission-webhook,monitoring-scrape}`.
- **Producer-side labels on 4 components (PR B).**
  - `cert-manager`: webhook pod and Service carry
    `capability-provider.tls-issuance` + endpoint/protocol annotations;
    controller pod carries `capability-provider.monitoring-scrape`;
    `cert-manager` namespace carries `provide.{tls-issuance,monitoring-scrape}`.
  - `loki` (SimpleScalable write tier): write pods and Service carry
    `capability-provider.logging-ship` + endpoint/protocol annotations;
    `monitoring` namespace (declared by loki + kube-prometheus-stack)
    carries `provide.{logging-ship,monitoring-scrape}`.
  - `metrics-server` (relocated, see Changed): pod and Service carry
    `capability-provider.{hpa-metrics,monitoring-scrape}` + endpoint/
    protocol annotations; `metrics-server` namespace carries
    `provide.{hpa-metrics,monitoring-scrape}`.
  - `local-path-provisioner`: pod carries
    `capability-provider.block-storage-local` (set in base values.yaml);
    consumer overlay must host the deployment in a dedicated
    `local-path-storage` namespace carrying
    `provide.block-storage-local: "true"` (documented in values.yaml).
- **Existing-producer namespace-label migration (PR B).**
  - `vault` namespace: `provide.monitoring-scrape`.
  - `external-secrets` namespace: `provide.monitoring-scrape`.

- **Root-level OSS-hygiene documents.**
  - `ARCHITECTURE.md` — root-level C4 L1/L2 architecture document with
    Mermaid diagrams (System Context, Container view, release flow,
    capability-admission flow).
  - `SECURITY.md` — disclosure channel, supported-versions matrix,
    supply-chain (cosign + SLSA + immutable tags), threat-model summary,
    in/out-of-scope table, hardening notes.
  - `CONTRIBUTING.md` — scope, conventional-commits, PR expectations,
    capability-first design rules, file-placement rules, sensitive-data
    policy.
  - `MAINTAINERS.md` — active maintainer list + decision authority.
  - `CODEOWNERS` — review routing per path.
  - `UPGRADING.md` — cumulative migration guide for OCI-vendored
    consumers; per-tag template for future MAJOR/MINOR notes; pending-
    sunset table (`storage-csi`, `monitoring-scrape-provider`).
- **Diátaxis-organised `docs/` set.**
  - `docs/README.md` — Diátaxis-organised doc index.
  - `docs/capability-architecture.md` — canonical architecture
    explanation for the capability-first v2 contract.
  - `docs/pni-cookbook.md` — concrete consumer + producer + CCNP recipes.
  - `docs/tutorial-first-consumer-cluster.md` — Diátaxis tutorial
    quadrant (vendor + verify + render).
  - `docs/harness-plugin-integration.md` — specification of what the
    harness plugin should provide for the v2 contract;
    explicit rationale why this base ships no `.claude/`.
- **Lint + CI for docs.** `.markdownlint.yaml` + `.markdownlintignore` +
  CI gate in `.github/workflows/docs-lint.yml` (markdownlint + auto-
  regen freshness check on `docs/capability-reference.md`).
- **PNI policy — instanced-suffix audit (PR D).**
  `kyverno-clusterpolicy-pni-instanced-suffix-required.yaml` — new
  audit-mode ClusterPolicy that emits a PolicyReport advisory when a
  namespace declares bare `platform.io/consume.<cap>` for a capability
  marked `instanced: true` in the PNI registry. Audit-mode by
  intentional design: per-instance enforcement (generate+mutate) is
  consumer-overlay responsibility, not base. The advisory signals the
  vocabulary smell without blocking platform-internal consumers
  (`cert-manager`, `external-secrets`) whose specific Vault KV mount
  is overlay-configured.
- **Producer pod labels on operator pods (PR C).**
  - `vault-operator` (bank-vaults): pod retains
    `capability-provider.monitoring-scrape`. No `admission-webhook`
    label — bank-vaults vault-operator does NOT ship a
    ValidatingAdmissionWebhook (verified by grep of chart templates).
  - `vault-config-operator` (Red Hat): pod gains
    `capability-provider.{admission-webhook,monitoring-scrape}` via a
    kustomize strategic-merge patch. The upstream chart does NOT expose
    a `podLabels` value (hardcoded selectorLabels helper), so the patch
    is the right altitude.
  - `piraeus-operator`: pod gains
    `capability-provider.{admission-webhook,monitoring-scrape}` via the
    base `values.yaml`. NOTE: the base ships only `namespace.yaml` for
    piraeus-operator; the consumer overlay deploys the Helm chart and
    must merge the base `values.yaml` into the release.
- **Namespace trust anchors (PR C).**
  - `vault` namespace (declared by both vault-operator and
    vault-config-operator): adds `provide.admission-webhook`. The two
    `namespace.yaml` files are kept identical so whichever ArgoCD app
    applies last produces a consistent label set.
  - `piraeus-datastore` namespace: adds
    `provide.{admission-webhook,monitoring-scrape}`.
- **Producer-side labels on 4 components (PR B).**
  - `cert-manager`: webhook pod and Service carry
    `capability-provider.tls-issuance` + endpoint/protocol annotations;
    controller pod carries `capability-provider.monitoring-scrape`;
    `cert-manager` namespace carries `provide.{tls-issuance,monitoring-scrape}`.
  - `loki` (SimpleScalable write tier): write pods and Service carry
    `capability-provider.logging-ship` + endpoint/protocol annotations;
    `monitoring` namespace (declared by loki + kube-prometheus-stack)
    carries `provide.{logging-ship,monitoring-scrape}`.
  - `metrics-server` (relocated, see Changed): pod and Service carry
    `capability-provider.{hpa-metrics,monitoring-scrape}` + endpoint/
    protocol annotations; `metrics-server` namespace carries
    `provide.{hpa-metrics,monitoring-scrape}`.
  - `local-path-provisioner`: pod carries
    `capability-provider.block-storage-local` (set in base values.yaml);
    consumer overlay must host the deployment in a dedicated
    `local-path-storage` namespace carrying
    `provide.block-storage-local: "true"` (documented in values.yaml).
- **Existing-producer namespace-label migration (PR B).**
  - `vault` namespace: `provide.monitoring-scrape`.
  - `external-secrets` namespace: `provide.monitoring-scrape`.

### Changed

- **Cluster-agnostic refactor (#31, PR #44).** Every reference to a
  specific consumer-cluster repo name has
  been removed from the live documentation surface: `README.md` "How
  consumers use this," `AGENTS.md` "Repository Purpose," the
  `ARCHITECTURE.md` L1 System-Context diagram, `docs/mcp-setup.md`
  install hint, and the `cert-manager/kustomization.yaml` comment now
  speak only about generic "consumer cluster repos." The cluster-
  agnostic invariant is now visible in the docs, not just in the
  filesystem. `CHANGELOG.md` deliberately retains the historical
  references as per-release record; the rewrite scope is current
  architecture only.
- **ADR `docs/adr-multi-repo-platform-split.md` rewritten cluster-
  agnostic.** The ADR now describes the three repo *roles* (platform
  base, Claude-Code harness, consumer cluster repo) without naming
  individual repos. The phase-by-phase migration plan (Phases 1, 1.5,
  2, 3A, 3B) is dropped — every phase is long complete and the
  per-release history lives in this CHANGELOG. Net: 343 → 174 lines.
- **AGENTS.md / CLAUDE.md / README.md / .gitignore — capability-first v2 docs.**
  - `AGENTS.md` §"Platform Network Interface (PNI) Rules" rewritten to v2:
    capability-first vocabulary (5-site producer/consumer table),
    namespace-anchored trust, instanced suffix, reserved-label rule,
    out-of-scope note (per-instance enforcement is consumer-overlay
    scope).
  - `AGENTS.md` §"Hard Constraints" gains two v2-specific invariants:
    capability-selectors only for new CCNPs, namespace-anchored producer
    trust.
  - `AGENTS.md` §"Key Terms" expanded with capability, instanced
    capability, producer/consumer symmetry, namespace-anchored trust.
  - `CLAUDE.md` §"Context Architecture" gains a "Knowledge Map" pointing
    at the new docs.
  - `README.md` adds a capability-first pitch in the lead and a
    comprehensive doc-map table.
  - `.gitignore` adds `.claude/` (harness runtime dir) and `.work/`
    (harness scratchpad) — both runtime artefacts, never committed.
- **CCNP selector switched from tool-name to capability (PR E).**
  - `ccnp-pni-monitoring-scrape-consumer-egress.yaml` source selector
    rewritten from `app.kubernetes.io/name: prometheus` (tool-selector)
    to `platform.io/capability-consumer.monitoring-scrape: "true"`
    (capability-selector). A Prometheus → Victoria-Metrics swap is now
    a label move on the consumer pod, not a CCNP edit.
  - `kube-prometheus-stack` values.yaml:
    `prometheus.prometheusSpec.podMetadata.labels` gains
    `platform.io/capability-consumer.monitoring-scrape: "true"` so the
    new CCNP source selector matches the Prometheus pod.
- **BREAKING — `metrics-server` relocated from `kube-system` to dedicated
  `metrics-server` namespace (PR B).** Consumer overlays that referenced
  `kube-system/metrics-server` directly (ServiceMonitor targets, manual
  kubectl wiring) must update to `metrics-server/metrics-server`. The
  `v1beta1.metrics.k8s.io` APIService is re-pointed automatically; HPA
  and `kubectl top` survive the change after one ArgoCD reconcile
  (~10–30s gap during the prune-and-replace window).
- **BREAKING — `pni-reserved-labels-audit` ClusterPolicy refactored (PR B).**
  The hardcoded `app.kubernetes.io/component: rabbitmq` and
  `redis_setup_type` trust signatures are removed. Trust now derives
  from a single namespace-anchored rule that requires
  `platform.io/provide.<cap>[.<inst>]: "true"` on the workload's
  namespace. Consumer overlays that currently deploy broker pods
  (RabbitmqCluster, RedisFailover, CnpgCluster instances) carrying
  `platform.io/capability-provider.<cap>.<instance>` MUST ensure the
  hosting namespace carries the matching `provide.<cap>.<instance>`
  label. Without that label, broker pods will be denied at admission
  after upgrade. The Kyverno generate-policies that automate this for
  CRD-managed instances ship in PR D; for the PR B → PR D gap, consumer
  overlays must add the namespace labels by hand.
- **ADR extensions (decision-grade record).**
  - ADR `adr-capability-producer-consumer-symmetry.md` extended with
    §"Per-instance enforcement is consumer-overlay responsibility"
    (PR D). Verification documented: the base ships only operators for
    instanced capabilities; data-plane instances (CNPG `Cluster`,
    `RabbitmqCluster`, `RedisFailover`, `Kafka`, `Vault` server,
    `LinstorCluster`) are consumer-overlay-deployed. Shipping
    speculative generate/mutate for tools the base does not deploy
    would violate the right-altitude principle.
  - ADR `adr-capability-producer-consumer-symmetry.md` extended with
    §"Namespace-anchored producer trust" (PR B) — locks the invariant
    that trust derives from namespace labels and that kube-system
    residents must be relocated, not exempted.

### Removed

- **BREAKING — Tool-name CCNPs for non-base-deployed operators (PR E).**
  - `ccnp-pni-cnpg-operator-dataplane-egress.yaml`. The CCNP used
    hardcoded tool-name selectors (`app.kubernetes.io/name:
    cloudnative-pg`, `cnpg.io/cluster`) and referenced an operator
    (cloudnative-pg in the `cnpg-system` namespace) that the base does
    NOT deploy. Tool-specific operator→broker CCNPs belong with the
    tool — consumer overlays that deploy CNPG must ship their own copy
    (cap-selector form recommended for tool-swap resilience).
  - `ccnp-pni-strimzi-operator-dataplane-egress.yaml`. Same rationale —
    the `strimzi-cluster-operator` is not base-deployed; the
    tool-specific operator-dataplane CCNP belongs in the consumer
    overlay that owns Strimzi.
- **Docs cleanup.**
  - `docs/claude-code-guide.md` — described a `.claude/` skill set that
    does not exist in this base. Inconsistent with `CLAUDE.md` policy
    ("this base ships no `.claude/` directory").
  - `docs/claude-code-stack-audit.md` — internal audit log of a
    *different* repository that was historically copied here.

### Notes (out-of-scope deliberate decisions; for context, not Changelog history)

- **PR E — deliberately kept.**
  `ccnp-pni-monitoring-dns-visibility.yaml` uses namespace-scoped source
  and tool-name target (`k8s-app: kube-dns`). kube-dns is a
  cluster-singleton; this is plumbing, not a capability binding.
  `ccnp-pni-{redis,rabbitmq}-operator-dataplane-egress.yaml` use
  capability-selectors, so they are tool-agnostic substrate even though
  the base does not deploy redis/rabbitmq operators.
- **PR D — verified scope.** Kyverno generate/mutate policies for
  `cnpg-postgres`, `redis-managed`, `rabbitmq-managed`, `kafka-managed`,
  `s3-object`, and per-instance generate/mutate for `vault-secrets`
  remain consumer-overlay scope.
- **PR C — deferred to PR D.** LINSTOR controller / satellite pods
  (created dynamically by piraeus-operator from a `LinstorCluster` CR)
  require a Kyverno mutate-policy to label operator-managed pods at
  admission. Per-instance scoping for `vault-secrets` KV mounts is
  likewise PR D scope.

## v0.1.0 — 2026-05-01

Initial release of `talos-platform-base`. Cluster-agnostic snapshot
extracted from a private upstream cluster repository, filtered to
retain only cluster-agnostic content per
`docs/adr-multi-repo-platform-split.md`, then post-cleanup-mutated to
remove residual cluster-specificity and add release machinery.

### Components (22 standalone-renderable)

All 22 base infrastructure components are standalone-renderable via
`kubectl kustomize --enable-helm kubernetes/base/infrastructure/<comp>/`.
The CI pipeline asserts this against `.ci-renderable-components.txt` —
a frozen ground-truth set; any drift between rendered components and
listed components fails the gate.

| Component | Pattern | Output |
| --- | --- | --- |
| alloy | helm (Grafana 1.6.0) | namespace + chart manifests (monitoring) |
| argocd | helm (argoproj 9.4.5) | namespace + chart manifests (argocd) |
| cert-approver | resources only | namespace (kubelet-serving-cert-approver). Upstream is kustomize-from-git; consumer adds via Application CR. |
| cert-manager | resources only | namespace (cert-manager) |
| dex | resources only | namespace (dex) |
| external-secrets | resources only | (existing pattern preserved) |
| kube-prometheus-stack | helm (prometheus-community 81.6.1) | namespace + chart manifests (monitoring) |
| kubevirt | resources only | (existing pattern preserved) |
| kubevirt-cdi | resources only | (existing pattern preserved) |
| kyverno | helm (kyverno 3.7.1) | namespace + chart manifests (kyverno) |
| local-path-provisioner | empty resources | (no-op render). Upstream is helm-from-git path; consumer adds via Application CR multi-source. |
| loki | helm (Grafana 6.53.0) | namespace + chart manifests (monitoring) |
| metrics-server | helm (kubernetes-sigs 3.12.2) | chart manifests (kube-system, no namespace declared) |
| multus-cni | resources only | crd + rbac + daemonset (kube-system) |
| node-feature-discovery | helm (kubernetes-sigs 0.17.4) | namespace + chart manifests (node-feature-discovery) |
| nvidia-dcgm-exporter | resources only | namespace (nvidia-dcgm-exporter, monitoring) |
| nvidia-device-plugin | helm (nvidia 0.17.4) | chart manifests (kube-system, no namespace declared) |
| piraeus-operator | resources only | namespace (piraeus-datastore) |
| platform-network-interface | resources only | PNI Kyverno policies + capability CCNPs |
| tetragon | helm (Cilium 1.6.1) | namespace + chart manifests (tetragon) |
| vault-config-operator | helm (redhat-cop v0.8.38) | namespace + chart manifests (vault) |
| vault-operator | helm (bank-vaults 1.23.4 OCI) | namespace + chart manifests (vault) |

### Talos artefacts

- Machine-config patches: common, controlplane (no extraManifests — consumer overlay supplies the URL list), drbd, worker-{gpu,gvisor,kubevirt,pi}, cluster.yaml.tmpl
- `talos/Makefile` with `cluster.yaml`-driven multi-cluster generation, including:
  - **CP_NODES non-empty guard**: errors if `cluster.yaml` parse yields no control-plane entries (catches yq-2>/dev/null silent failures).
  - **WORKER_NODES non-empty guard**: errors if `workers:` is empty (gpu_workers/pi_nodes remain optional).
  - **Node-name input validation**: rejects names with whitespace, `$`, `:`, `=`, `#`, `*` — these break the `IP_<name>` Make-variable map.
  - **Bootstrap rebuild guard**: refuses `make bootstrap` if `talosctl etcd members` returns members on the target node, requiring `BOOTSTRAP_FORCE=1` to override (prevents accidental quorum-destroying re-bootstrap).
  - **Bootstrap-node resolution**: `BOOTSTRAP_NODE := $(firstword $(CP_NODES))` reads from `cluster.yaml` instead of hardcoding a name.

### CI / repo hygiene

- `.github/workflows/gitops-validate.yml` — kustomize-render + kubeconform + conftest + Kyverno-policy validation; **set-based predicate against `.ci-renderable-components.txt`** to catch membership drift.
- `.github/workflows/hard-constraints-check.yml` — server-side enforcement of §Hard Constraints (no Ingress, no Endpoints).
- `.github/workflows/oci-publish.yml` — publishes the OCI artifact to `ghcr.io/nosmoht/talos-platform-base:<tag>` (and `:latest`) on every `v*` tag push.
- `.pre-commit-config.yaml` — codex-config + MCP-portability checks + gitleaks. SOPS hooks deferred to consumer (no `*.sops.yaml` in base).
- Branch protection on `main` (configured via `gh api PUT`): required status checks `validate` + `Secret Scan (gitleaks)`, `enforce_admins=false` initially.
- Repo-level secret-scanning + push-protection: enabled.
- All commits + the `v0.1.0` tag are SSH-signed.

### Release machinery

- `LICENSE` (Apache-2.0)
- `CHANGELOG.md` (this file)

### Removed from the upstream source

- All cluster-specific kustomize overlays
- All per-node Talos config inputs (per-node config, schematics, talosconfig, encrypted secrets bundle)
- Cluster-specific Talos patches and node-topology definitions
- Cluster-specific docs (hardware analyses, debug logs, environment-specific ADRs, postmortems, runbooks, upgrade reports)
- Cluster-specific operational scripts
- Cluster-specific CI workflows
- `.claude/`, `.codex/`, `Plans/` (tooling dirs; Claude-Code-specific primitives ship via the harness plugin)
- `.sops.yaml` (contained the upstream cluster's age recipient — cluster-specific identifier; would have created a cross-cluster privilege-escalation path if a different consumer adopted base and committed `*.sops.yaml`)
- Trivy ignore-list (`.trivyignore.yaml`) — scoped to cluster overlay paths
- Cluster-specific dev tooling (`package.json`/`package-lock.json`)

### Mutated post-filter

- `talos/patches/controlplane.yaml`: `extraManifests:` block removed. Consumer cluster repos layer their own controlplane patch with the appropriate Cilium-bootstrap URL (which carries cluster-specific Hubble TLS certificates).
- `talos/patches/worker-pi.yaml`: `registerWithTaints[].key` generalised from a cluster-specific label namespace to `platform.io/pi-reserved`. **Breaking change** for any consumer's public-ingress deployment if/when adopted; migration is consumer-side. A cluster-specific label namespace does not belong in base.
- `kubernetes/bootstrap/cilium/extras.yaml`: gateway-config name generalised to `cluster-gateway-config`.
- `kubernetes/bootstrap/argocd/namespace.yaml`: `instance`/`part-of` labels generalised to `argocd`/`gitops`.
- `Makefile`: dropped `argocd-oidc` and `migrate-cluster-yaml`; added `init-cluster-yaml`; `grafana-dashboards-check` now uses `OVERLAY_PATH` resolved from `cluster.yaml`; `validate-gitops` no longer references the dropped scripts.
- `AGENTS.md`, `CLAUDE.md`, `README.md`, `kubernetes/AGENTS.md`: rewritten for platform-base perspective.
- `docs/claude-code-guide.md`: per-node example references generalised to `<source-node>`/`<target-node>`. *(File removed in the docs-cleanup PR — see Unreleased section.)*
- `LICENSE`: prepended an Apache-2.0 copyright header.

### Added (post-cleanup)

- `kubernetes/base/infrastructure/<comp>/kustomization.yaml` for the 12 previously inputs-only components (alloy, argocd, cert-approver, kube-prometheus-stack, kyverno, local-path-provisioner, loki, metrics-server, node-feature-discovery, nvidia-device-plugin, tetragon, vault-config-operator, vault-operator). Where applicable, `helmCharts:` references the upstream chart with version pinned to the value used in the upstream source as of the source-state pin.
- `kubernetes/base/infrastructure/<comp>/namespace.yaml` for components whose target namespace is non-system (alloy, argocd, cert-approver, kube-prometheus-stack, kyverno, loki, node-feature-discovery, tetragon, vault-config-operator, vault-operator). System-namespace components (kube-system targeted: local-path-provisioner, metrics-server, nvidia-device-plugin) deliberately do not declare a namespace.
- `.ci-renderable-components.txt` — frozen ground-truth set of standalone-renderable base components.

### Known limitations

- `cert-approver` and `local-path-provisioner` cannot use `helmCharts:` in their base `kustomization.yaml` because their upstream distributions are kustomize-from-git (cert-approver: `github.com/alex1989hu/kubelet-serving-cert-approver, path: deploy/standalone, ref: v0.10.3`) and helm-from-git (local-path-provisioner: `github.com/rancher/local-path-provisioner, path: deploy/chart/local-path-provisioner, ref: v0.0.34`) — neither pattern is supported by `kustomize helmCharts:`. Consumer cluster repos add the upstream chart/kustomization via their ArgoCD Application CR's source spec.
- The 9 "resources only" components (cert-manager, dex, external-secrets, kubevirt, kubevirt-cdi, multus-cni, nvidia-dcgm-exporter, piraeus-operator, platform-network-interface) do not currently use `helmCharts:` in their base kustomization. Folding helmCharts: for these, where applicable, is tracked as a future v0.x evolution and is not a v0.1.0 acceptance criterion.

### Source-state pin

The base was extracted from a pinned commit of a private upstream cluster
repository. The upstream repository is **never modified** by base creation or
maintenance work; this is verified at every release-time gate via SHA
equality between captured pre-state and observed post-state.
