# Changelog

This file follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

> The Unreleased section bundles two concurrent work streams toward the
> next tag: (a) the capability-first v2 refactor (PRs B / C / D / E),
> and (b) the documentation overhaul (root-level OSS-hygiene files +
> Diátaxis-organised `docs/`). Per Keep a Changelog the two are merged
> here; provenance is preserved in the per-entry context.

### Added

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
    `kube-agent-harness` plugin should provide for the v2 contract;
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
    *different* repository (homelab) that was historically copied here.

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

Initial release of `talos-platform-base`. Cluster-agnostic snapshot of
`Nosmoht/Talos-Homelab` `main` at commit
`041e339283df45c4e876a1c18af8f213b4940fa2` (post-Phase-1.5), filtered to
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

- `LICENSE` (Apache-2.0, copyright 2026 Thomas Krahn)
- `CHANGELOG.md` (this file)

### Removed from the Talos-Homelab source

- All homelab-specific overlays (`kubernetes/overlays/homelab/`)
- All per-node Talos config inputs (`talos/nodes/`, schematics, talosconfig, encrypted secrets bundle)
- Cluster-specific `pi-firewall.yaml` Talos patch and the `pi-public-ingress` topology
- Homelab-specific docs (hardware analyses, cilium-debug logs, ADRs for Pi-public-ingress / FritzBox / ingress-front, postmortems, runbooks, upgrade reports)
- Homelab-specific scripts (`configure-sg3428-via-omada-api.sh`, `discover_argocd_apps.sh`, `run_trivy.sh`)
- Homelab-specific workflows (`skill-frontmatter-check.yml`, `sysctl-baseline-check.yml`)
- `.claude/`, `.codex/`, `Plans/` (tooling dirs; Claude-Code-specific primitives ship via the `kube-agent-harness` plugin)
- `.sops.yaml` (contained the Talos-Homelab age recipient — cluster-specific identifier; would have created a cross-cluster privilege-escalation path if a different consumer adopted base and committed `*.sops.yaml`)
- Trivy ignore-list (`.trivyignore.yaml`) — scoped to cluster overlay paths
- `package.json`/`package-lock.json` — Talos-Homelab-specific dev tooling

### Mutated post-filter

- `talos/patches/controlplane.yaml`: `extraManifests:` block removed. Consumer cluster repos layer their own controlplane patch with the appropriate Cilium-bootstrap URL (which carries cluster-specific Hubble TLS certificates).
- `talos/patches/worker-pi.yaml`: `registerWithTaints[].key` generalised from `homelab.io/pi-reserved` to `platform.io/pi-reserved`. **Breaking change** for Talos-Homelab consumer's `pi-public-ingress` deployment if/when adopted; migration is consumer-side. The `homelab.io/` namespace is literal cluster-specific and does not belong in base.
- `kubernetes/bootstrap/cilium/extras.yaml`: `homelab-gateway-config` → `cluster-gateway-config`.
- `kubernetes/bootstrap/argocd/namespace.yaml`: `instance: homelab` → `instance: argocd`, `part-of: homelab` → `part-of: gitops`.
- `Makefile`: dropped `argocd-oidc` and `migrate-cluster-yaml`; added `init-cluster-yaml`; `grafana-dashboards-check` now uses `OVERLAY_PATH` resolved from `cluster.yaml`; `validate-gitops` no longer references the dropped `run_trivy.sh` and `discover_argocd_apps.sh` scripts.
- `AGENTS.md`, `CLAUDE.md`, `README.md`, `kubernetes/AGENTS.md`: rewritten for platform-base perspective.
- `docs/claude-code-guide.md:107`: `node-04 to node-05` → `<source-node> to <target-node>`. *(File removed in the docs-cleanup PR — see Unreleased section.)*
- `LICENSE`: prepended `Copyright 2026 Thomas Krahn` above the Apache-2.0 standard text.

### Added (post-cleanup)

- `kubernetes/base/infrastructure/<comp>/kustomization.yaml` for the 12 previously inputs-only components (alloy, argocd, cert-approver, kube-prometheus-stack, kyverno, local-path-provisioner, loki, metrics-server, node-feature-discovery, nvidia-device-plugin, tetragon, vault-config-operator, vault-operator). Where applicable, `helmCharts:` references the upstream chart with version pinned to the value used in Talos-Homelab as of the source-state pin.
- `kubernetes/base/infrastructure/<comp>/namespace.yaml` for components whose target namespace is non-system (alloy, argocd, cert-approver, kube-prometheus-stack, kyverno, loki, node-feature-discovery, tetragon, vault-config-operator, vault-operator). System-namespace components (kube-system targeted: local-path-provisioner, metrics-server, nvidia-device-plugin) deliberately do not declare a namespace.
- `.ci-renderable-components.txt` — frozen ground-truth set of standalone-renderable base components.

### Known limitations

- `cert-approver` and `local-path-provisioner` cannot use `helmCharts:` in their base `kustomization.yaml` because their upstream distributions are kustomize-from-git (cert-approver: `github.com/alex1989hu/kubelet-serving-cert-approver, path: deploy/standalone, ref: v0.10.3`) and helm-from-git (local-path-provisioner: `github.com/rancher/local-path-provisioner, path: deploy/chart/local-path-provisioner, ref: v0.0.34`) — neither pattern is supported by `kustomize helmCharts:`. Consumer cluster repos add the upstream chart/kustomization via their ArgoCD Application CR's source spec.
- The 9 "resources only" components (cert-manager, dex, external-secrets, kubevirt, kubevirt-cdi, multus-cni, nvidia-dcgm-exporter, piraeus-operator, platform-network-interface) do not currently use `helmCharts:` in their base kustomization. Folding helmCharts: for these, where applicable, is tracked as a future v0.x evolution and is not a v0.1.0 acceptance criterion.

### Source-state pin

`Nosmoht/Talos-Homelab` `main` at commit `041e339283df45c4e876a1c18af8f213b4940fa2`.
The Talos-Homelab repository is **never modified** by base creation or
maintenance work; this is verified at every release-time gate via SHA
equality between captured pre-state and observed post-state.
