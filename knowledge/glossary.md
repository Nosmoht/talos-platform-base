---
type: glossary
title: Glossary
description: Cross-domain vocabulary for the talos-platform-base substrate, its delivery pipeline, and its consumer contract.
tags: [glossary, vocabulary, platform]
generated: { by: human:nosmoht, at: "2026-09-04T00:00:00Z" }
verified:
  - { by: human:nosmoht, at: "2026-08-28T00:00:00Z" }
  - { by: human:nosmoht, at: "2026-07-17T00:00:00Z" }
sources:
  - resource: AGENTS.md
  - resource: Taskfile.yml
  - resource: tofu/modules/talos-cluster/variables.tf
  - resource: tofu/modules/talos-cluster/manifests/kubelet-csr-approver.yaml
  - resource: tofu/modules/talos-cluster/profiles.tf
  - resource: scripts/render-component.sh
  - resource: scripts/check-render-determinism.sh
  - resource: .github/workflows/oci-publish.yml
  - resource: .releaserc.json
  - resource: kubernetes/substrate/argocd/chart.lock.yaml
  - resource: cluster.yaml.example
---

# Glossary

Alphabetical vocabulary. Terms with a decision behind them link the decision
record; deep-dive pages are linked where they exist.

- **Allowlist tarball** — the fail-closed OCI content gate: the publish tarball
  is built strictly from the paths in `.ci-oci-tarball-include.txt` and its
  listing is diffed against `.ci-oci-tarball-expected.txt`; any divergence
  fails. Run locally via `task supply-chain:oci-allowlist`, enforced in
  `.github/workflows/oci-publish.yml`.
- **AppProject** — ArgoCD RBAC boundary scoping which repos and namespaces an
  Application may deploy to. The consumer root AppProject is seeded from
  `kubernetes/bootstrap/argocd/root-project.yaml.tmpl` by
  `task bootstrap:argocd`.
- **Apps catalog** — `talos-platform-apps`, the central catalog of every
  platform component that is *not* substrate, shipped as independently
  versioned signed OCI artifacts. Routing rule: not substrate → apps catalog,
  never base. See [0004-substrate-only-base](decisions/0004-substrate-only-base.md).
- **cert-approver** — single-purpose controller (**postfinance/kubelet-csr-approver**,
  namespace `kubelet-csr-approver`) seeded as a controlplane `inlineManifest`
  (`tofu/modules/talos-cluster/manifests/kubelet-csr-approver.yaml`, the
  postfinance Helm chart rendered at pin time then `templatefile()`-parameterized)
  that approves `kubernetes.io/kubelet-serving` CSRs triggered by the base's
  default-on kubelet serving-cert rotation; its RBAC `approve` verb is
  signer-scoped to exactly that signer, and it binds each CSR's DNS SAN to the
  requesting node by default. Exposes three `substrate.cert_approver` knobs
  (`provider_regex`, `provider_ip_prefixes`, `replicas`). Talos serving-cert
  glue, not a fourth pillar. See
  [0013-kubelet-serving-cert-rotation](decisions/0013-kubelet-serving-cert-rotation.md)
  and [0019-postfinance-kubelet-csr-approver](decisions/0019-postfinance-kubelet-csr-approver.md).
- **chart.lock.yaml** — per-component pin spec for the Rendered Manifests
  Pattern: chart repo/name/version plus `tgz_sha256` digest, release
  name/namespace/`includeCRDs`, and the values file. Read by
  `scripts/render-component.sh`.
- **cluster.yaml** — the declarative Source-of-Truth for a consumer cluster
  (identity, versions, network, images, hardware-capabilities, nodes, patches,
  substrate knobs). YAML is the SoT; OpenTofu is the executor via a thin
  `yamldecode` shim. Secrets have no slot in it. Schema:
  `schemas/cluster.schema.json`. See [0007-cluster-yaml-sot](decisions/0007-cluster-yaml-sot.md).
- **Conftest** — Rego policy checks (`policies/conftest/`) over
  kustomize-rendered manifests; part of `task gitops:validate`.
- **Consumer repo** — a cluster repo that composes the platform: pins a base
  tag (OCI artifact into gitignored `vendor/base/`), holds `cluster.yaml` and
  all cluster identity/secrets, and references apps-catalog components. Live
  runtime verification happens there, never in base.
- **Day-zero / Day-1 / Day-2** — delivery phases. Day-zero: baked into the
  bootstrap itself (`tofu apply` seeds Cilium, ArgoCD, cert-approver as
  Talos `inlineManifests`). Day-1: applied via GitOps once the cluster is up
  (e.g. Gateway API CRDs by default). Day-2: runtime-mutable self-management
  (chart upgrades, Hubble/L2/BGP config) owned by ArgoCD reconciliation.
- **DRBD** — Distributed Replicated Block Device, the LINSTOR replication
  layer (apps-catalog component). The base `drbd` provisioning profile bakes
  the `siderolabs/drbd` extension and kernel modules and provides the
  `drbd-kernel-module` atom.
- **Hard constraint** — universal cluster invariant codified in
  `AGENTS.md` §Hard Constraints (no SecureBoot installer, no `debugfs=off`,
  Gateway API only, EndpointSlices only, …), enforced server-side by the
  `hard-constraints-check` workflow on every PR (not currently in the
  branch-protection required-check set, which is `validate` +
  `Secret Scan (gitleaks)`). See
  [0011-substrate-hard-constraints](decisions/0011-substrate-hard-constraints.md).
- **Hardware capability** — consumer-defined composite in `cluster.yaml`
  (`requires_features` + `provisioning_profiles` + `emits_label` in the
  `platform.io/hardware-capability.*` namespace). A node holds a *set* of
  capabilities; roles stay `controlplane|worker`. See
  [capability-composition](architecture/capability-composition.md).
- **Hardware feature (Layer-C atom)** — atomic, tool-agnostic hardware
  predicate in the base-owned registry `platform-hardware-features.yaml`
  (schema `schemas/hardware-features.schema.json`), each with a
  `discovery_source` and node label key; provisioned atoms surface as
  `platform.io/hardware-feature.<id>` labels emitted only from base-controlled
  profile `provides`. See [0003-three-layer-capability-architecture](decisions/0003-three-layer-capability-architecture.md).
- **inlineManifest seed** — Talos `cluster.inlineManifests` delivery: the
  module renders a chart locally (`data.helm_template`) and bakes the result
  into the controlplane machine config, so it comes up with the bootstrap.
  Create-only — Talos never edits what it created — so `*_chart_version` is a
  seed knob, not an upgrade knob; steady-state ownership moves to GitOps.
- **kubeconform** — Kubernetes schema validation of rendered manifests; part
  of `task gitops:validate`.
- **Multi-Source Application** — ArgoCD Application with
  `spec.sources[base, cluster]` reconciling a consumer repo together with this
  base's OCI content.
- **OCI artifact** — versioned tarball of this base published to
  `ghcr.io/nosmoht/talos-platform-base:<tag>` on every tag push by
  `.github/workflows/oci-publish.yml`; cosign-signed (keyless OIDC) with SLSA
  provenance and a CycloneDX SBOM attestation; consumed via `oras pull`.
- **OKF / knowledge bundle** — this `knowledge/` tree (glossary, architecture,
  decisions, reference, workflows, project), versioned via the `okf_version`
  frontmatter in `index.md`; the agent- and human-facing knowledge layer
  regenerated from repo source.
- **Provisioning profile** — entry in the module-local catalog
  `tofu/modules/talos-cluster/profiles.tf` (`drbd`, `iommu`, `nvidia-lts`)
  binding `provides`/extensions/kernel args/modules/sysctls/vendor variants.
  Base-owned: consumers select by id but cannot redefine. See
  [0009-node-capability-composition](decisions/0009-node-capability-composition.md).
- **Render-determinism fence** — `scripts/check-render-determinism.sh`
  (wired into `task tofu:ci`): static guard asserting every
  `data.helm_template` render is read exactly once and consumed only through a
  frozen `terraform_data` with `ignore_changes = [input]` (CRD renders
  additionally `triggers_replace`), so non-byte-stable helm renders cannot
  re-push a fresh machineConfig every plan. The single read may be captured
  directly as the freeze's `input`, or sit in a `locals` block whose value the
  freeze captures — the second shape admits a pure transform between read and
  freeze, such as the ArgoCD CRD projection.
- **Rendered Manifests Pattern** — charts are rendered at build time, not in
  the cluster: `scripts/render-component.sh` runs helm template (Stage 1) +
  kustomize build (Stage 2) from `chart.lock.yaml` and commits the split
  output under `_rendered/` (`manifests.yaml` + `crds.yaml`); drift is caught
  by `task gitops:verify-rendered`. See
  [0002-namespace-ownership-rendered-manifests](decisions/0002-namespace-ownership-rendered-manifests.md)
  and [0005-shared-render-artifact](decisions/0005-shared-render-artifact.md).
- **Right altitude** — the lightest-sufficient form for an automation
  artifact (description → declaration → CLI line → shell helper → code); a
  selection heuristic from the external agent harness, not a base-shipped
  rule.
- **Schematic** — Talos Image Factory spec embedding system extensions,
  kernel args, and an optional SBC overlay into installer images. Derived per
  node by the module: the image's baseline `extensions` + `extra_kernel_args` +
  `overlay` unioned with the selected profiles' `extensions` + `extraKernelArgs`,
  content-hash-deduplicated so identical nodes share one schematic. See
  [capability-composition](architecture/capability-composition.md).
- **semantic-release** — the release automation configured in
  `.releaserc.json`: conventional-commit analysis on `main` and a `v${version}`
  tag, and nothing more. It carries no publish plugin, so the GitHub Release is
  created by `.github/workflows/oci-publish.yml`, which the tag push triggers.
- **SOPS (consumer-side only)** — secret encryption used exclusively in
  consumer repos; this base ships no `*.sops.yaml`. The module's
  `sops_age_key` input seeds the ArgoCD ksops repoServer so consumer secrets
  can decrypt.
- **Substrate** — the cluster-agnostic Layer-1 floor every cluster needs:
  the three co-equal pillars Talos + Cilium + ArgoCD (plus cert-approver as
  serving-cert glue), delivered by the `talos-cluster` module at bootstrap.
  ArgoCD delivery is opt-out, never a Day-2 add-on. See
  [0004-substrate-only-base](decisions/0004-substrate-only-base.md).
- **Sync-wave** — ArgoCD ordering annotation: `-1` (AppProjects) → `0`
  (infrastructure) → `1` (apps).
- **Task runner (go-task)** — `Taskfile.yml` is the single command runner
  (`tofu:*`, `gitops:*`, `bootstrap:*`, `cluster:*`, `supply-chain:*`,
  `mcp:*`, `dev:*`); the `Makefile` is a deprecation stub. See
  [0012-makefile-retirement](decisions/0012-makefile-retirement.md).
- **Tool-agnostic safety invariant** — a non-cluster-invariant safety rule
  (e.g. no credentials in committed files) enforced by scanning gates that
  work without any specific agent tooling: gitleaks pre-commit hook plus the
  CI `secret-scan` job as the `--no-verify` backstop.
