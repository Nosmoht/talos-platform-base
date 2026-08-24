---
type: decision
title: "ADR: Kubelet serving-cert rotation as substrate default + cert-approver as a Talos seed"
description: "Enables kubelet serving-cert rotation by default on all nodes and delivers cert-approver as an unconditional, digest-pinned Talos controlplane inlineManifest seed."
status: stable
id: base:kubelet-serving-cert-rotation
decided: "2026-06-30T00:00:00Z"
deciders:
  - platform-maintainer
supersedes: []
# Partially superseded by 0019 (§D2 approver identity + seed mechanism only; D1
# rotation stands) — recorded via the dated in-body banner + 0019's `supersedes`,
# per the 0003/0004 partial-supersession convention (status stays stable; a
# populated superseded_by is reserved for FULL supersession, cf. 0005/0008).
superseded_by: []
related:
  - base:substrate-only-base
  - base:substrate-hard-constraints
  - base:namespace-ownership-rendered-manifests
  - base:opentofu-cluster-lifecycle
tags: [adr, talos]
---

# ADR: Kubelet serving-cert rotation as substrate default + cert-approver as a Talos seed

> [2026-07-17 partial supersession] **§D2 is superseded in part by
> [0019-postfinance-kubelet-csr-approver.md](./0019-postfinance-kubelet-csr-approver.md).**
> The **approver identity** (alex1989hu → postfinance/kubelet-csr-approver
> v1.2.14) and the **seed mechanism** (static `file()` vendored raw manifest →
> chart-rendered `templatefile()`-parameterized manifest at
> `manifests/kubelet-csr-approver.yaml`, namespace renamed to
> `kubelet-csr-approver`) are replaced, and the SAN-to-node-binding **stance**
> flips: ADR-0019 ships a per-node DNS-SAN binding **default-on** (plus a
> three-knob `substrate.cert_approver` config surface), rather than delegating
> the whole binding to consumer Kyverno as §Security below does. **§D1 (kubelet
> serving-cert rotation default-on) STANDS unchanged**, as do the still-holding
> §D2 sub-decisions ADR-0019 preserves: the unconditional seed, namespace
> sole-ownership ([ADR-0002](./0002-namespace-ownership-rendered-manifests.md)),
> restricted-PSA namespace, the six recommended labels, controlplane
> tolerations, and the `approve` verb signer-scoped to
> `kubernetes.io/kubelet-serving` only. Read the two ADRs together: everything
> below about the **alex1989hu** approver identity, the raw-manifest seed
> pattern, the metrics port 9090, and the "SAN-to-node binding is a consumer
> Kyverno obligation" residual reflects the superseded §D2; ADR-0019 is
> authoritative on those points.

## Context and Problem Statement

Two coupled facts make the pre-existing state incoherent:

1. The base shipped `cert-approver`
   (`alex1989hu/kubelet-serving-cert-approver`) as substrate, but only as an
   **idle namespace stub** under `kubernetes/base/infrastructure/cert-approver/`
   (namespace + `kustomization.yaml` + `values.yaml`). The actual
   Deployment/RBAC had to be wired by each consumer via a Multi-Source ArgoCD
   Application referencing the upstream `deploy/standalone`.
2. Kubelet **serving-cert rotation was never enabled** (`serverTLSBootstrap`
   absent everywhere in the repo). Without it the kubelet self-signs its serving
   certificate and submits no `kubernetes.io/kubelet-serving` CSR — so
   cert-approver had nothing to approve. cert-approver was dead weight.

The Kubernetes built-in approver in kube-controller-manager auto-approves
`kubernetes.io/kube-apiserver-client-kubelet` CSRs (node-join / client certs) but
**never** `kubernetes.io/kubelet-serving` (verified: Kubernetes CSR reference).
So a cluster **boots** without cert-approver; what breaks without it — once
rotation is on — is metrics-server, `kubectl logs|exec|top` (they proxy to the
kubelet's HTTPS serving endpoint and reject an untrusted serving cert). This
corrects the earlier "no auto-approval → no bootable cluster" framing in
`adr-0004` / `component-dependencies.md`: the approver is a **serving-cert /
observability** prerequisite, not a boot prerequisite.

The requirement: serving-cert rotation should be **default-on for every cluster**
of this family, and cert-approver should be **fully part of the base** so the
resulting CSRs are approved out-of-the-box with no consumer wiring.

## Decision

### D1 — Kubelet serving-cert rotation default-on (all nodes, overridable)

The `tofu/modules/talos-cluster` module injects an all-nodes machine-config patch
enabling `machine.kubelet.extraConfig.serverTLSBootstrap: true`
(`local.base_kubelet_rotation_patch`), wired into **both** the controlplane and
worker `data.talos_machine_configuration` patch lists (the serving cert is per
kubelet). Placed FIRST (after `base_cluster_patch`, before `var.config_patches`)
so a consumer can opt out via `config_patches`, mirroring the overridable
`base_cluster_patch` precedent.

**Mechanism — non-deprecated path (repo directive: no deprecated options).** The
KubeletConfiguration field `serverTLSBootstrap` is used via `extraConfig`, NOT
the deprecated kubelet flag `--rotate-server-certificates` (passed via
`extraArgs`). The Talos metrics-server guide still shows the deprecated flag
form; this base deliberately uses the current field. `extraConfig` carries a
genuine bool (no `extraArgs` `map[string]string` string-quoting hazard).

### D2 — cert-approver as an unconditional Talos controlplane inlineManifest seed

cert-approver is delivered as a controlplane `cluster.inlineManifest` seed
(`local.cert_approver_controlplane_patch`), mirroring how Cilium and ArgoCD are
seeded — namespace (separate entry, first) + the vendored
ServiceAccount + signer-restricted ClusterRoles/Bindings + Deployment. The idle
`kubernetes/base/infrastructure/cert-approver/` stub is removed.

- **Unconditional (no toggle).** `cluster.schema.json`'s `substrate` block is
  `additionalProperties: false` with only `cilium`/`argocd` and states
  cert-approver is "always-on boot-glue with no cluster.yaml knobs". A
  `deploy_cert_approver` toggle would be unreachable from the `cluster.yaml` SoT
  (lint rejection on `substrate.cert_approver`), so cert-approver is always
  seeded. The schema description is updated from the stale "idle stub" reality to
  "seeded-always-on". A future opt-out, if ever needed, ships as a
  `substrate.cert_approver` schema addition + a gated local (deferred).
- **Vendored-static-manifest seed pattern.** alex1989hu ships raw YAML (no Helm
  chart), so the pinned upstream `deploy/standalone-install.yaml` (v0.11.0) is
  vendored at `tofu/modules/talos-cluster/manifests/cert-approver.yaml` and read
  via `file()`. This is a NEW seed pattern, distinct from the helm-render +
  `terraform_data` freeze pattern Cilium/ArgoCD use. The image is **digest-pinned**
  (`@sha256:f17017b5…1171c4`) and the file header records source URL + tag +
  upstream-file SHA256 + the modifications applied (namespace stripped, image
  pinned, `automountServiceAccountToken: true` set explicitly) so a re-vendor on
  the next version bump is reproducible and re-verifiable.
- **Namespace ownership (ADR-0002).** The seed is the **sole** owner of the
  `kubelet-serving-cert-approver` namespace — there is no steady-state
  Application, so there is no two-writer transfer like the argocd case; this is
  the *simplest* sole-owner shape, not a new exception. Seeded labels carry PSA
  **restricted** (single-replica controller, no host access),
  `managed-by: opentofu`, and the six recommended labels; the stale
  `platform.io/network-*` (PNI, dissolved at v2.0.0) labels of the old stub are
  dropped.

### Why cert-approver is substrate (rationale reconciliation)

Given the corrected mechanism (serving-cert, not boot), cert-approver's substrate
status rests on **coupling to the default-on rotation + boot-time presence**, not
on bootability: because D1 turns rotation on for every cluster, the approver must
be present from cluster stand-up to keep the Pending-CSR window short and
self-healing. It is substrate-by-coupling, delivered as a seed so it is present
at bootstrap with zero consumer wiring.

## Security model (Gate 1 — verified at source)

A `kubernetes.io/kubelet-serving` auto-approver is a privilege boundary (it mints
trusted serving identities). alex1989hu v0.11.0
`controller/certificatesigningrequest/helper.go::isRequestConform` (read at the
pinned tag) validates: `Subject.Organization == ["system:nodes"]`;
`CommonName` prefix `system:node:`; `csr.Spec.Username == CommonName` (binds the
cert identity to the authenticated node); no email/URI SANs; ≥1 DNS/IP SAN
present; key usages ⊆ {digital signature, server auth, key encipherment}.

**Known limitation (accepted, with compensating control):** it does **not**
validate that the requested DNS/IP **SANs belong to the requesting node**. A
node authenticated as `system:node:worker-1` (CN pinned to that name) could
obtain a serving cert whose SANs name another node or a control-plane address —
a MITM vector **if a node is already compromised**. postfinance/kubelet-csr-approver
closes this with `providerRegex` + `providerIpPrefixes` SAN allowlisting, but
those are **per-cluster** values and would break this base's cluster-agnostic,
fixed-seed model. Decision: keep alex1989hu (the Talos-recommended,
cluster-agnostic approver); the stronger SAN-to-node binding is a
**consumer-cluster Kyverno defense-in-depth obligation**, consistent with
ADR-0004 ("Apps owns the `kubelet-serving` vocabulary"; Kyverno admission lives
in consumer clusters). The base ships no admission policy (substrate-only).

RBAC is signer-restricted (verified): the `approve` verb on `signers` is scoped
to `resourceNames: ["kubernetes.io/kubelet-serving"]` — it cannot approve client
signers (no auth-as-node escalation). The Deployment satisfies restricted PSA
(`runAsNonRoot`, `drop: [ALL]`, `readOnlyRootFilesystem`, `seccompProfile:
RuntimeDefault`, uid/gid/fsGroup 65534).

## Consequences

**Positive:** rotation + a working approver out-of-the-box for every consumer;
trusted kubelet serving certs (metrics-server without `--kubelet-insecure-tls`);
no per-cluster approver wiring; cluster-agnostic.

**Neutral / trade-offs:**

- **Create-only seed.** Talos `inlineManifests` are applied once at bootstrap and
  are not reconciled. Upgrading the approver on a **running** cluster is therefore
  a manual in-cluster operation (`kubectl set image` / re-apply the vendored
  manifest) or a deliberate re-seed — **not** a plain `tofu apply` (which will not
  update an already-bootstrapped node's inlineManifest). New clusters get v0.11.0
  at bootstrap.

  > [2026-07-11 verification] The "applied once at bootstrap and are not
  > reconciled" premise was corrected post-merge (#157, commit 487f18e): Talos
  > re-applies `inlineManifests` on every machine-config apply and **creates**
  > any not-yet-existing manifest — "create-only" means an *existing* resource is
  > never updated or deleted, not that a new manifest is skipped on a running
  > cluster. The upgrade consequence stands (an already-existing approver is
  > never mutated by the seed, so approver upgrades stay manual), but the seed
  > itself does land on a running cluster via the config-apply reconcile. See
  > `UPGRADING.md` §"Kubelet serving-cert rotation default-on + cert-approver
  > seed".
- **Pending-CSR window + single replica.** The approver Pod is not Ready at the
  instant kubelets submit their first serving CSRs (it schedules after the API
  server + CNI are up). CSRs sit Pending briefly and are approved once the Pod is
  Ready (self-healing). `replicas: 1` — a down approver blocks new/rotating
  serving certs cluster-wide. A rolling OS upgrade / CP-node reboot
  (`talosctl upgrade`) **evicts the single (CP-resident) approver**, stalling any
  rotation in that window until it reschedules — time mass-rotation-affecting
  upgrades accordingly. The base ships no monitoring; consumers wire an alert on
  the count of Pending `kubernetes.io/kubelet-serving` CSRs (approver metrics on
  port 9090). A PodDisruptionBudget / second replica is out of scope here.
- **SAN-validation residual is now shipped default-on to every cluster — consumer
  Kyverno is a REQUIRED follow-up, not optional hardening.** Because D1 turns
  rotation on for every cluster and D2 ships the approver unconditionally + cluster-
  scoped, the SAN-to-node gap in §Security (a compromised node can mint a serving
  cert for arbitrary SANs) is live on every fresh cluster until the consumer adds
  the SAN-to-node Kyverno policy. For any multi-tenant / untrusted-node cluster
  this policy is a required post-adoption action (ADR-0004 places the
  `kubelet-serving` policy surface in consumer clusters; the base ships none). The
  §Wrong-if clause anticipates promoting it to a base-shipped policy.
- **Controlplane scheduling.** The approver Deployment tolerates control-plane
  taints (upstream manifest) so it schedules even on a single-controlplane
  cluster with `allow_scheduling_on_controlplanes = false`.
- **Existing-cluster migration (BREAKING — MAJOR OCI bump).** Adopting the new
  base tag on a running cluster re-pushes machine config (reconciled) → rotation
  turns on → serving CSRs are emitted, but the create-only approver seed does
  **not** land → rotation-on-without-approver. See `UPGRADING.md`: ensure the
  approver runs before/at the bump (keep the consumer's existing approver
  Application until the seed is confirmed, or apply the **complete upstream**
  manifest once — the vendored seed file is namespace-stripped, so a direct
  `kubectl apply` of it would fail), and resolve double-management by **removing**
  the consumer's Application (keeping it re-conflicts on the next CP-node join,
  which does receive the seed).

  > [2026-07-11 verification] Corrected by #157 (commit 487f18e): on a running,
  > already-bootstrapped cluster the approver seed **does** land automatically
  > via the config-apply reconcile — empirically confirmed on a live
  > single-node cluster (base v2.0.0 → v3.0.0: the approver pod came up and the
  > `kubernetes.io/kubelet-serving` CSRs reached `Approved,Issued` with no
  > manual step). `UPGRADING.md` now frames the one-time complete-upstream
  > `kubectl apply` as a *fallback* (for the rare Talos without
  > reconcile-on-change), not a required migration step; the double-management
  > guidance (remove a pre-existing consumer approver Application) still
  > applies.

## Validation

How will we know this decision is wrong, and what mechanical check confirms it
stays correct?

- **Mechanical (stays correct):** `tofu test`
  (`tests/composition.tftest.hcl::kubelet_serving_cert_rotation_and_cert_approver_seed`)
  asserts — bound red-green via module outputs — that the rotation patch is wired
  into BOTH the controlplane and worker patch lists, that it decodes to
  `serverTLSBootstrap = true` (and that the deprecated `extraArgs` flag is absent),
  that the cert-approver seed is wired into the controlplane list, that its
  namespace carries PSA `restricted` + the six recommended labels, and that the
  vendored ClusterRole's `approve` verb is resourceNames-scoped to **exactly**
  `[kubernetes.io/kubelet-serving]` (the scope, not mere signer-string presence —
  proven red-green by broadening to `["*"]`). `gitops-validate.yml` `cmp` gate keeps
  `infrastructure/` at `argocd` only.
  - **Binding residual (named, not hidden):** the controlplane rotation + seed
    checks assert membership in the *non-sensitive* `controlplane_base_patches`
    sub-list (a `contains()` over the full list would taint on the sops/ipsec seed
    Secrets and a non-sensitive output would be rejected). The
    `controlplane_base_is_prefix_of_final` assertion binds that the data source's
    actual list (`controlplane_machine_config_patches`) BEGINS with that sub-list,
    so the sub-list checks transitively cover the final list. The worker side binds
    the real list directly (no seeds, no sensitivity split).
  - **Opt-out (D2) residual:** the documented `serverTLSBootstrap: false`
    `config_patches` opt-out relies on the base patch being placed FIRST (consumer
    patch merges later, last-wins). The unit test binds placement, but the
    server-side strategic-merge *result* is a homelab predicate, not unit-provable.
- **Behavioral (only a live cluster proves it):** a homelab `tofu apply` —
  `kubectl get csr` shows `kubernetes.io/kubelet-serving` CSRs reaching
  `Approved,Issued` on controlplane AND worker nodes, and metrics-server functions
  without `--kubelet-insecure-tls`. The automated gates verify render/wiring, not
  behavior; the homelab apply is the required behavioral predicate for: (a) Talos
  v1.12.6 actually accepts `extraConfig.serverTLSBootstrap` and the kubelet emits
  the CSR; (b) the namespace inlineManifest applies before the namespaced
  SA/Deployment (intra-seed ordering — same pattern the argocd seed relies on, but
  Talos sequencing is not statically provable here); (c) the `config_patches`
  opt-out actually wins the server-side merge.
- **Wrong-if:** Talos removes/renames `extraConfig.serverTLSBootstrap` (revisit
  the field); a future upstream re-vendor broadens the approver's signer scope or
  drops node-identity validation (revisit the approver choice / add the consumer
  Kyverno mandate as base-shipped policy).

## Alternatives considered

- **`extraArgs.rotate-server-certificates` flag** (the Talos-doc form) — rejected:
  deprecated upstream kubelet flag; repo directive forbids deprecated options.
- **postfinance/kubelet-csr-approver** (stronger built-in SAN validation) —
  rejected: requires per-cluster `providerRegex`/`providerIpPrefixes`, breaking
  the cluster-agnostic fixed-seed model. SAN-to-node binding is pushed to
  consumer-cluster Kyverno instead.
- **Keep cert-approver as a rendered `infrastructure/` component** (complete the
  stub, consumer authors the Application) — rejected: leaves per-consumer wiring
  and a brief Pending window until the consumer's app-of-apps syncs; the seed is
  zero-wiring and present at bootstrap. (Seed + rendered component — the full
  argocd-style treatment — was also rejected as over-complex for a small, stable
  CSR approver.)
- **A `deploy_cert_approver` toggle** — rejected: unreachable from the
  `cluster.yaml` SoT (`substrate` is a closed schema); cert-approver is always-on
  boot-glue.

## References

- `tofu/modules/talos-cluster/main.tf` — `base_kubelet_rotation_patch`,
  `cert_approver_namespace_labels`, `cert_approver_controlplane_patch`,
  `controlplane_base_patches` (sensitivity split).
- `tofu/modules/talos-cluster/manifests/cert-approver.yaml` — vendored,
  digest-pinned upstream manifest (provenance in the file header).
- `tofu/modules/talos-cluster/tests/composition.tftest.hcl` — the red-green AC gate.
- [0004-substrate-only-base.md](./0004-substrate-only-base.md) — substrate-only thesis; the `infrastructure/`
  count invariant + disposition table were amended here for the cert-approver relocation.
- [0002-namespace-ownership-rendered-manifests.md](./0002-namespace-ownership-rendered-manifests.md) — namespace sole-owner model.
- Kubernetes CSR reference (`kubernetes.io/kubelet-serving` never auto-approved);
  alex1989hu/kubelet-serving-cert-approver `controller/certificatesigningrequest/helper.go` @ v0.11.0.
