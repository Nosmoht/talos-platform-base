---
type: decision
title: "ADR: Module-delivered Cilium + `cluster.yaml` as the declarative cluster SoT"
description: "Delivers Cilium as a module inlineManifest seed (disabling the Talos default CNI) and makes cluster.yaml the declarative cluster Source-of-Truth, with the consumer's OpenTofu root as a thin yamldecode shim."
status: accepted
id: base:cluster-yaml-sot
timestamp: 2026-06-06
deciders:
  - platform-maintainer
supersedes: []
related:
  - base:opentofu-cluster-lifecycle
  - base:substrate-only-base
tags: [adr, talos]
---

# ADR: Module-delivered Cilium + `cluster.yaml` as the declarative cluster SoT

## Context and Problem Statement

Two defects surfaced after the OpenTofu cluster-lifecycle cutover
([`0006-opentofu-cluster-lifecycle.md`](./0006-opentofu-cluster-lifecycle.md)):

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

> [2026-07-11 verification] The *classes* named in this decision were removed by
> [`0009-node-capability-composition.md`](./0009-node-capability-composition.md):
> `cluster.yaml` today declares a per-node `image` plus a `hardware_capabilities`
> set, resolved against the `images:` / `hardware-capabilities:` catalogs —
> neither `schemas/cluster.schema.json` nor
> `tofu/modules/talos-cluster/variables.tf` defines a class. The SoT-on-a-
> `yamldecode`-shim decision itself is unchanged.

**4. First-class fields for the common + irreversible + foot-gun set; escape hatches
for the long tail.** `pod_cidr`/`service_cidr` (fed to BOTH Talos subnets AND Cilium,
removing the silent strict-mode-CIDR coupling), `dual_stack`,
`allow_scheduling_on_controlplanes`, and `substrate.cilium.{routing_mode, encryption,
gateway_api, kube_proxy_replacement, mtu, chart_repository}` are typed fields. The long
tail (BGP peering CRs, SR-IOV/Multus device config, per-interface VIP) stays in
`config_patches` / `cilium_values_override`, which are inside the SoT — just untyped
(right-altitude: do not type every Talos/Cilium knob).

**5. The two typed secret fields never enter `cluster.yaml`.** `sops_age_key`
(ArgoCD ksops) and `cilium_ipsec_key` (only for `encryption.type = ipsec`;
wireguard is keyless) are supplied via tfvar/env and seeded as Secret
inlineManifests. The schema has **no slot** for either — that exclusion is
structural, not merely documented. The free-form escape hatches inside the SoT
(`config_patches`, `substrate.{cilium,argocd}.values_override`) are a different
matter: they are unbounded passthrough rendered into the same secret-bearing
controlplane machine config, so a consumer *could* paste secret material into
them. That is **operator discipline backed by the `gitleaks` gate**, not a
structural guarantee — `cluster.yaml` is committed in consumer repos, so never
put secret material in an escape hatch. Only the two named keys are structurally
excluded.

## Validation

The schema + seed model were stress-tested before implementation against five diverse
consumer clusters (kitchen-sink; minimal hardened cloud with IPsec + cloud LB;
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

> [2026-07-11 verification] The "classes" in the schema enumeration below and the
> "undefined-class failure" precondition reflect the pre-ADR-0009 node model.
> `cluster.yaml.example` today carries `images:`, `hardware-capabilities:`, and
> per-node `image` / `hardware_capabilities` instead of `classes` (validated by
> `scripts/lint-cluster-yaml.sh` against `schemas/cluster.schema.json`);
> [`0009-node-capability-composition.md`](./0009-node-capability-composition.md)
> made that change.

- **Done — decision 3 (the `cluster.yaml` SoT migration), in the follow-on Arc-2
  commits:** `cluster.yaml.example` is the full declarative schema (identity,
  versions, endpoint, network, nodes, classes, machine-config patches, substrate);
  the `examples/complete` root is a thin `yamldecode` shim mapping it onto the typed
  interface (machine-config patches declared as structured YAML, `yamlencode`d by
  the shim); `AGENTS.md` + this ADR's parent (`base:opentofu-cluster-lifecycle`)
  corrected. Verified by `task tofu:ci` (fmt + validate + tflint) and `tofu plan` (19
  add / 0 error on the complete example).
- **Done — decisions 1, 2, 4, 5 (the Cilium-delivery change):** `deploy_cilium`, `cni:none`
  (authoritative, last in the patch order so a stale caller `cni` patch cannot
  resurrect Flannel) + `proxy.disabled`, `data.helm_template.cilium` controlplane
  inlineManifest seed, vendored minimal `helm/cilium-values.yaml`, the typed
  `cilium_*` / `pod_cidr` / `service_cidr` / `dual_stack` /
  `allow_scheduling_on_controlplanes` inputs, IPsec key Secret seeding. **Gateway API controller** enabled in the seed
  (`cilium_gateway_api` default `true`); the Cilium operator creates the GatewayClass
  at runtime once the Gateway API CRDs (v1.6.1 standard channel for Cilium 1.20 —
  TLSRoute joined the standard channel at v1.6.1) exist. The CRDs are NOT seeded at bootstrap by default — they are a Day-1
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
- **Done — Arc-3 residuals (this follow-on):** the obsolete
  `scripts/render-cilium-bootstrap.sh` render path is retired (the module's
  inlineManifest seed replaces it); the deleted script is dropped from the OCI
  tarball allowlist (`.ci-oci-tarball-{include,expected}.txt`) and its
  `oci-publish.yml` exec-bit check removed. `kubernetes/bootstrap/cilium/{values,extras}.yaml`
  stay BOTH in-repo AND in the OCI artifact as the Cilium values / GatewayClass
  reference (only the dead script leaves the artifact — no consumer-facing
  contract removal). The OCI tarball ships the module's `helm/` values dir (added
  in `v1.0.0`, commit `44ff918`). Cilium-delivery doc accuracy fixed
  (`day-zero-pattern.md` Layer-1, `AGENTS.md`, `kubernetes/AGENTS.md`).
  Module-validation hardening landed: (a) a **bidirectional** `dual_stack` ⟺
  CIDR-family cross-field precondition — `dual_stack = true` requires each of
  `pod_cidr`/`service_cidr` to carry a v4 AND a v6 entry, `dual_stack = false`
  requires each to be v4-only — so neither mismatch direction slips through (the
  Talos podSubnets carry the full list while the Cilium seed enables ipv6 only on
  the flag); (b) per-variable `cidrhost`-based CIDR-format validation on
  `pod_cidr`/`service_cidr` (rejects malformed entries at validate time, so the
  `":"`-marks-v6 family heuristic cannot misclassify garbage); (c) a
  `startswith("AGE-SECRET-KEY-1")` precondition on `sops_age_key`, AND the example
  root drops the `sops_age_key` default — a copied example must supply a real key
  via `TF_VAR_sops_age_key` (`tofu plan` requires it), so it cannot silently apply
  a non-functional ksops key. `tofu validate` (CI) does not evaluate preconditions,
  so it stays green without a key.
- **Known limitations of the Arc-3 guards (best-effort, by design — surfaced in
  Arc-3 review):** (a) the `dual_stack` guard inspects only the **typed** inputs;
  a raw `config_patches` override of `cluster.network.podSubnets` can still desync
  Talos from the Cilium seed — raw-patch correctness is consumer-overlay
  responsibility (parity with the SecureBoot substring guard; AGENTS.md "Out of
  scope for the base", ADR decision 4). (b) The guard checks IP-family **presence**,
  not count, so it does not enforce the Kubernetes one-CIDR-per-family dual-stack
  rule (Kubernetes/Talos reject a multi-same-family list at apply). (c) **IPv6-only
  single-stack is unsupported** and now hard-rejected at plan time (the Cilium seed
  couples `ipv6.enabled` to `dual_stack`); fail-fast replaces the previously-silent
  broken plan — adding a v6-only path is a separate feature, not a regression.
  (d) Module preconditions are **plan-time**, so the validate-only CI gate
  (`task tofu:ci`) does not exercise them — they protect `tofu plan`/`apply`, not
  `tofu validate` (a property shared by all of the module's preconditions).
- **Deferred — chart/CRD integrity pinning (a delivery-mechanism change, not a
  precondition).** Verified 2026-06: the Helm provider's `data.helm_template`
  exposes only `verify`/`keyring` (GPG provenance via `.prov` files), no
  sha256/digest argument; SHA256 digest pinning is OCI-registry-only and
  unavailable for a classic HTTP repo like `helm.cilium.io`. And `helm.cilium.io`
  publishes no provenance files (`cilium-1.19.4.prov` → HTTP 404; re-verified
  2026-08-12 at the 1.20.0 bump — `cilium-1.20.0.prov` is likewise HTTP 404), so
  even GPG `verify` is blocked at the source. Pinning chart integrity therefore requires
  consuming the chart from an OCI registry by digest (or self-mirroring with
  provenance) — beyond a module precondition. The building blocks already exist
  in-repo: `cilium_chart_repository` accepts a private OCI mirror, and the
  `oci-publish.yml` pipeline already captures, cosign-signs, and SLSA-attests the
  base artifact *by digest* — so the deferred work is "mirror the chart into an OCI
  registry and reference it by digest", not net-new infrastructure.
  `cilium_gateway_api_crds_url` is likewise an unpinned URL fetched by Talos
  `extraManifests` (no checksum verification in Talos). Both stay "point only at a
  trusted source" until a digest-capable delivery path is adopted.

## Links

- [0006-opentofu-cluster-lifecycle.md](./0006-opentofu-cluster-lifecycle.md) — the engine
  this builds on; its "Cilium convergence — temporary" roadmap note is realized here.
- [0004-substrate-only-base.md](./0004-substrate-only-base.md) — the substrate boundary
  (no secrets, no cluster identity in the base) this respects.
- `tofu/modules/talos-cluster/README.md` — module contract.
