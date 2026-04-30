# Changelog

## v0.1.0 — 2026-04-30

Initial release. Snapshot of `Nosmoht/Talos-Homelab` `main` at commit
`041e339283df45c4e876a1c18af8f213b4940fa2` (post-Phase-1.5), filtered to
retain only cluster-agnostic content per
`docs/adr-multi-repo-platform-split.md`.

### Components

- 24 Helm-base infrastructure components (see `kubernetes/base/infrastructure/`)
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
