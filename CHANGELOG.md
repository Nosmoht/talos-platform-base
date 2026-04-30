# Changelog

## v0.1.1 — 2026-05-01

Hotfix release. Corrects documentation defects shipped in v0.1.0;
configures repo-level safeguards (branch protection, secret-scanning
push-protection); restores commit + tag signing discipline. No
source-tree change to `talos/patches/worker-pi.yaml`: the
`platform.io/pi-reserved` taint key shipped in v0.1.0 is correct for
base (the `homelab.io/` namespace is literal cluster-specific and does
not belong in base).

### Breaking changes from v0.1.0

- **`talos/patches/worker-pi.yaml`** — In v0.1.0 the kubelet
  `registerWithTaints` key was generalised from `homelab.io/pi-reserved`
  to `platform.io/pi-reserved`. Consumer cluster repos that previously
  shipped a `pi-public-ingress` Deployment (or any pod) tolerating
  `homelab.io/pi-reserved` MUST update the toleration to
  `platform.io/pi-reserved` during base-adoption. Failure to migrate
  results in pod unschedulability on Pi/edge nodes.

  This is the only known breaking change introduced by base
  de-homelab-ification. The talos-homelab-cluster consumer-repo
  creation plan (Plan #3) is responsible for performing the migration
  during repo creation.

### Documentation fixes

- `README.md` "What this provides": replaced an inaccurate Helm-bases
  bullet that listed 5 phantom components (MinIO, Strimzi, CloudNativePG,
  Redis, Omada Controller — none of which exist as
  `kubernetes/base/infrastructure/<x>/` directories) and omitted 5 real
  components (cert-approver, external-secrets, kubevirt, multus-cni,
  platform-network-interface). New list enumerates the actual 22.
- `README.md` repo-structure block: corrected `# 24 cluster-agnostic
  Helm-base components` → `# 22 …`.
- `CHANGELOG.md` (this entry's parent): the v0.1.0 entry's
  "Components" bullet claimed "24 Helm-base infrastructure components" —
  see this entry's amendment of the v0.1.0 known-issues sub-section.
- `LICENSE`: prepended `Copyright 2026 Thomas Krahn` above the
  Apache-2.0 standard text.
- `docs/claude-code-guide.md:107`: removed a `node-04 to node-05`
  homelab example; replaced with `<source-node> to <target-node>`.

### Repo hygiene

- Branch protection enabled on `main` with required status checks
  (`validate`, `Secret Scan (gitleaks)`, plus `Hard Constraints Check`
  if it gates PRs in this repo) and `enforce_admins=false` initially.
  Flip to `true` after one real PR proves the gate; tracked separately.
- Secret-scanning + push-protection enabled at repo level via
  `gh api PATCH /repos/.../security_and_analysis`.
- All v0.1.1 commits + the `v0.1.1` tag are SSH-signed (regression from
  v0.1.0 where `-c commit.gpgsign=false` was used and the tag was
  unsigned).

### OCI consumption note

If you pulled `ghcr.io/nosmoht/talos-platform-base:latest` before
2026-05-01, run `oras pull ghcr.io/nosmoht/talos-platform-base:latest`
with cleared local cache (`rm -rf ~/.config/oras/cache`) to refresh
the digest mapping to v0.1.1.

### Source-of-truth vs OCI inconsistency note

The OCI artifact for v0.1.0 (digest `sha256:dfc0b8fd2728...`) ships
the original CHANGELOG.md without the post-hoc "Known issues in v0.1.0"
section below. The known-issues amendment lives in source-of-truth
`main` (this file) and the v0.1.0 GitHub release-page body. v0.2.0
onward will not need this caveat.

---

## v0.1.0 — 2026-04-30

Initial release. Snapshot of `Nosmoht/Talos-Homelab` `main` at commit
`041e339283df45c4e876a1c18af8f213b4940fa2` (post-Phase-1.5), filtered to
retain only cluster-agnostic content per
`docs/adr-multi-repo-platform-split.md`.

### Components

- 22 Helm-base infrastructure components (see `kubernetes/base/infrastructure/`).
  Note: v0.1.0 shipped this bullet as "24" — corrected in v0.1.1. See
  Known issues in v0.1.0 below.
- Talos machine-config patches: common, controlplane (without extraManifests),
  drbd, worker-{gpu,gvisor,kubevirt,pi}, cluster.yaml.tmpl
- Talos Makefile with multi-cluster generation (`cluster.yaml` driven, `ENV=`
  override for multi-cluster checkouts)
- ArgoCD bootstrap templates (parameterized via envsubst)
- conftest policies (k8s.rego, argocd.rego)
- gitops-validate + hard-constraints-check CI workflows
- Cluster-agnostic helper scripts (kustomize discovery + render, conftest,
  SOPS verification, MCP wrapper, cilium-bootstrap render, codex-config
  placeholder check, MCP-config portability check, issue-state)

### Removed from source

- All homelab-specific overlays (`kubernetes/overlays/homelab/`)
- All per-node Talos config inputs (`talos/nodes/`, schematics, talosconfig,
  encrypted secrets bundle)
- The cluster-specific `pi-firewall.yaml` Talos patch and the
  `pi-public-ingress` topology
- Homelab-specific docs (hardware analyses, cilium-debug logs, ADRs for
  Pi-public-ingress / FritzBox / ingress-front, postmortems, runbooks,
  upgrade reports)
- Homelab-specific scripts (`configure-sg3428-via-omada-api.sh`,
  `discover_argocd_apps.sh`, `run_trivy.sh`)
- Homelab-specific workflows (`skill-frontmatter-check.yml`,
  `sysctl-baseline-check.yml`)
- `.claude/`, `.codex/`, `Plans/` (tooling dirs, not platform content;
  Claude-Code-specific primitives ship via the `kube-agent-harness` plugin)
- Trivy ignore-list (`.trivyignore.yaml`) — scoped to cluster overlay paths
  that don't exist in base
- `package.json`/`package-lock.json` — Talos-Homelab-specific dev tooling

### Mutated post-filter

- `talos/patches/controlplane.yaml`: `extraManifests:` block removed (consumer
  cluster repos layer their own controlplane patch with cluster-specific
  Cilium-bootstrap URL)
- `kubernetes/bootstrap/cilium/extras.yaml`: `homelab-gateway-config` →
  `cluster-gateway-config`
- `kubernetes/bootstrap/argocd/namespace.yaml`: `instance: homelab` →
  `instance: argocd`, `part-of: homelab` → `part-of: gitops`
- `Makefile`: dropped `argocd-oidc` and `migrate-cluster-yaml`; added
  `init-cluster-yaml`; `grafana-dashboards-check` now uses `OVERLAY_PATH`
  resolved from `cluster.yaml`; `validate-gitops` no longer references
  the dropped `run_trivy.sh` and `discover_argocd_apps.sh` scripts
- `AGENTS.md`, `CLAUDE.md`, `README.md`, `kubernetes/AGENTS.md`: rewritten
  for platform-base perspective (no homelab specifics; no `.claude/rules/`
  references; consumer-cluster-pinning guidance)

### Added

- `LICENSE` (Apache-2.0)
- `CHANGELOG.md` (this file)
- `.github/workflows/oci-publish.yml` — publishes the OCI artifact to
  `ghcr.io/<owner>/talos-platform-base:<tag>` and tags `:latest` on every
  `v*` tag push

### Known issues in v0.1.0

The following defects shipped in v0.1.0 and are documented here for
honest disclosure. v0.1.1 corrects D3, D4, D5, D6, D7, D8 and documents
D9; v0.1.2 closes D1; v0.2.0 closes D2.

- **D1 — CI is empty-green.** `gitops-validate.yml` "validate" job
  reported success on initial main push because
  `scripts/discover_kustomize_targets.sh` skips `kubernetes/base/*` and
  no overlays exist in this repo. Zero files were rendered, kubeconformed,
  or conftest-tested. CI extension is deferred to v0.1.2.
- **D2 — 12 of 22 base components have empty or missing
  `kustomization.yaml`** (alloy, argocd, cert-approver,
  kube-prometheus-stack, kyverno, local-path-provisioner, loki,
  metrics-server, node-feature-discovery, nvidia-device-plugin, tetragon,
  vault-config-operator, vault-operator). They render only as
  inputs-only Helm-values consumed by overlays. Restoration to
  standalone-renderable is tracked for v0.2.0.
- **D3 — All v0.1.0 commits unsigned.** `-c commit.gpgsign=false` was
  inadvertently applied during the post-filter cleanup commit; filter-repo
  also regenerated SHAs without preserving signatures. v0.1.1 onward
  signs commits + tags.
- **D4 — Component-list inaccuracies.** README/AGENTS/CHANGELOG claimed
  "24 Helm-base components"; actual is 22. README "What this provides"
  listed 5 phantom components and omitted 5 real ones. Corrected in
  v0.1.1.
- **D5 — No branch protection on `main`.** AGENTS.md asserted
  `gitleaks` and `hard-constraints-check` were "required PR checks" —
  they were not configured. v0.1.1 enables protection.
- **D6 — Tag v0.1.0 unsigned** (`git tag -a`, not `-as`). v0.1.1 onward
  uses `-as`.
- **D7 — LICENSE Apache-2.0 dumped without copyright holder.**
  v0.1.1 prepends `Copyright 2026 Thomas Krahn`.
- **D8 — `docs/claude-code-guide.md:107` retained `node-04 to node-05`
  homelab example.** Sanitised in v0.1.1.
- **D9 — Breaking taint-key change vs the only known consumer.**
  Documented as a breaking change in v0.1.1 CHANGELOG. Resolution is
  consumer-side migration, not base-revert: `homelab.io/pi-reserved` is
  literal cluster-specific and does not belong in base.

Additional Talos-surface defects identified during review that are
deferred to the v0.1.2 plan with their own dedicated review cycle:

- BOOTSTRAP_NODE bootstrap-rebuild footgun (`talos/Makefile:290`):
  re-running `make bootstrap` against a partially-replaced control
  plane could destroy etcd quorum.
- WORKER_NODES empty-list silent partial-apply: malformed
  `cluster.yaml` with empty `workers:` produces no error.
- `IP_<name>` Make-variable map fragility on Make-special characters in
  `cluster.yaml` `name:` values; no input-validation contract.
- Consumer overlay layering invariant unenforced: `gen-configs` succeeds
  with base-only patches and produces a Cilium-less Talos config.
