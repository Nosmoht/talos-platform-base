---
status: accepted
id: base:cluster-yaml-sot
date: 2026-06-06
deciders:
  - Thomas Krahn
consulted: []
informed: []
supersedes: []
related:
  - base:opentofu-cluster-lifecycle
  - base:substrate-only-base
---

# ADR: Module-delivered Cilium + `cluster.yaml` as the declarative cluster SoT

## Context and Problem Statement

Two defects surfaced after the OpenTofu cluster-lifecycle cutover
([`adr-opentofu-cluster-lifecycle.md`](adr-opentofu-cluster-lifecycle.md)):

1. **The base delivered Flannel, not Cilium.** The `tofu/modules/talos-cluster`
   module — the sole cluster-lifecycle path — generated the Talos machine config
   without ever setting `cluster.network.cni.name: none`. Talos' default CNI is
   Flannel, so a fresh cluster came up on Flannel. The module delivered **ArgoCD**
   as a `cluster.inlineManifests` seed (`deploy_argocd`) but Cilium nowhere — the
   "Cilium/ArgoCD asymmetry" the OpenTofu ADR flagged as "temporary and tracked"
   but never tracked. Under the three co-equal pillars (Talos + Cilium + ArgoCD),
   the CNI pillar is the *most* fundamental: without a CNI no pod starts, including
   ArgoCD's own.

2. **The cluster's desired state lived in HCL.** The OpenTofu cutover put the
   cluster definition (nodes, classes, versions) in the consumer's OpenTofu root —
   HCL. That makes a tool's language the Source-of-Truth. The platform intent is
   that a declarative `cluster.yaml` is the SoT and tooling (tofu) is the executor.

## Decision

**1. The module delivers Cilium and disables the Talos default CNI.** Mirroring
`deploy_argocd`, a new `deploy_cilium` (default `true`) renders the Cilium chart
locally with `data.helm_template` and bakes it into the controlplane
`cluster.inlineManifests` as a bootstrap **seed**. When enabled, the module injects
`cluster.network.cni.name: none` + `cluster.proxy.disabled: true` into the base
machine config (both roles), so Flannel and kube-proxy never come up. The opt-out
shape is `deploy_cilium = false`.

**2. The seed carries the cluster's install-time Cilium config; it is not a frozen
floor.** Talos applies inlineManifests **create-only** (it never edits a resource it
created), so the seed is a one-time render: `cilium_chart_version` is a SEED knob,
not an upgrade knob (parity with `argocd_chart_version`). Install-time-fixed settings
(routing mode, encryption, kube-proxy replacement, MTU, pod CIDR) MUST be in the
per-cluster seed. The base ships a minimal, cluster-agnostic **default** values floor
(`helm/cilium-values.yaml`); the module layers the typed `cilium_*` inputs on top, and
the consumer override (`cilium_values_override`) carries the long tail (Hubble,
L2/BGP, bpf). Runtime-mutable Cilium config is OPTIONAL Day-2 self-management — it is
**not** load-bearing for cluster correctness.

**3. `cluster.yaml` is the declarative cluster SoT, on the tofu engine.** The cluster
definition (identity, versions, nodes, classes, substrate) is declared in
`cluster.yaml`; the consumer's OpenTofu root is a thin `yamldecode` shim that maps it
onto the module's existing typed, validated variable interface. tofu remains the
executor, not the SoT — this restores the YAML SoT the cutover removed, on top of the
cutover's engine. This **corrects** the OpenTofu ADR's "node/class definitions live in
the consumer's OpenTofu root" stance: that stays true at the *mechanism* layer (the
module's typed interface), but the *human-edited SoT* is `cluster.yaml`.

**4. First-class fields for the common + irreversible + foot-gun set; escape hatches
for the long tail.** `pod_cidr`/`service_cidr` (fed to BOTH Talos subnets AND Cilium,
removing the silent strict-mode-CIDR coupling), `dual_stack`,
`allow_scheduling_on_controlplanes`, and `substrate.cilium.{routing_mode, encryption,
gateway_api, kube_proxy_replacement, mtu, chart_repository}` are typed fields. The long
tail (BGP peering CRs, SR-IOV/Multus device config, per-interface VIP) stays in
`config_patches` / `cilium_values_override`, which are inside the SoT — just untyped
(right-altitude: do not type every Talos/Cilium knob).

**5. Secrets never enter `cluster.yaml`.** `sops_age_key` (ArgoCD ksops) and the new
`cilium_ipsec_key` (only for `encryption.type = ipsec`; wireguard is keyless) are
supplied via tfvar/env and seeded as Secret inlineManifests. The schema has no slot
for either — structural, not merely documented.

## Validation

The schema + seed model were stress-tested before implementation against five diverse
consumer clusters (homelab kitchen-sink; minimal hardened cloud with IPsec + cloud LB;
all-arm64 single-node edge; air-gapped regulated; HPC with Multus + native routing +
BGP) and an adversarial `team-red` pass (verdict: **REWORK**). The convergent finding
drove decision 2: the original "minimal seed + everything Day-2" framing was wrong
because several Cilium settings are install-time-fixed under create-only inlineManifests,
and the "Day-2 self-management adopts the seed" mechanism was load-bearing and unbuilt
(a `helm template` seed has no Helm-release metadata for a later `helm upgrade` to adopt
cleanly). Decisions 2 and 4 are the correction.

## Consequences

- **Positive.** A fresh cluster comes up on Cilium, not Flannel. The Cilium/ArgoCD
  asymmetry is closed. The cluster SoT is declarative `cluster.yaml`, not HCL. The
  pod-CIDR foot-gun (Talos/Cilium divergence, silent strict-mode gap) is closed.
- **Breaking (MAJOR).** The base machine config now sets `cni.name: none` and delivers
  Cilium by default; the `cluster.yaml` schema and the consumer-root shape change.
- **Residual boundaries (stated, not solved):** full air-gap needs a self-hosted Image
  Factory host in addition to `chart_repository` overrides; SR-IOV/Multus node device
  config and control-plane VIP realization remain raw `config_patches`; reconfiguring an
  install-time-fixed Cilium setting after bootstrap requires a CNI re-bootstrap (a
  Talos/Cilium property, not a schema gap).
- **Replaces the consumer-side render path.** `scripts/render-cilium-bootstrap.sh` +
  the `cluster.extraManifests`-URL pattern become obsolete; the former full
  `kubernetes/bootstrap/cilium/values.yaml` is preserved as the reference for the
  optional Day-2 Cilium self-management follow-on.

## Implementation status

- **Done (this change):** decisions 1, 2, 4, 5 — `deploy_cilium`, `cni:none`
  (authoritative, last in the patch order so a stale caller `cni` patch cannot
  resurrect Flannel) + `proxy.disabled`, `data.helm_template.cilium` controlplane
  inlineManifest seed, vendored minimal `helm/cilium-values.yaml`, typed `cilium_*`
  + `pod_cidr`/`service_cidr`/`dual_stack`/`allow_scheduling_on_controlplanes`
  inputs, IPsec key Secret seeding. **Gateway API controller** enabled in the seed
  (`cilium_gateway_api` default `true`); the Cilium operator creates the GatewayClass
  at runtime once the Gateway API CRDs (v1.4.1 standard channel for Cilium 1.19)
  exist. The CRDs are NOT seeded at bootstrap by default — they are a Day-1
  GitOps / apps-catalog concern (the substrate/apps boundary, and air-gap-safe).
  Bootstrap seeding via `cluster.extraManifests` is OPT-IN (`cilium_gateway_api_crds_url`),
  because a failed `extraManifests` fetch is NOT graceful — Talos' ExtraManifestController
  crashloops and bootstrap does not complete cleanly (T1, Talos v1.10/v1.11 docs), so a
  github-URL default would make every cluster's bootstrap depend on github reachability.
  SecureBoot-installer guard (a substring HEURISTIC, not complete enforcement —
  schematic-level SecureBoot stays consumer-overlay) + clear undefined-class failure
  added as plan-time preconditions (a consumer's patches escape the repo's `tofu/**`
  CI grep). `cni:none` is re-applied in BOTH the generation and apply passes so a
  class/node patch cannot resurrect Flannel.
- **Pending follow-on:** decision 3 (the `cluster.yaml` full-SoT migration: schema,
  thin shim, example rebuild, AGENTS.md correction), the `render-cilium-bootstrap.sh`
  retirement, and chart/CRD digest pinning (both `cilium_chart_repository` and
  `cilium_gateway_api_crds_url` are tag/URL-pulled without a digest pin today).

## Links

- [adr-opentofu-cluster-lifecycle.md](adr-opentofu-cluster-lifecycle.md) — the engine
  this builds on; its "Cilium convergence — temporary" roadmap note is realized here.
- [adr-substrate-only-base.md](adr-substrate-only-base.md) — the substrate boundary
  (no secrets, no cluster identity in the base) this respects.
- `tofu/modules/talos-cluster/README.md` — module contract.
