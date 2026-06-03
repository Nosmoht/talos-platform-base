---
status: accepted
date: 2026-06-02
deciders:
  - Thomas Krahn
consulted: []
informed: []
supersedes:
  - docs/adr-shared-render-artifact.md
related:
  - docs/adr-substrate-only-base.md
  - docs/adr-multi-repo-platform-split.md
---

# ADR: OpenTofu module is the sole Talos cluster-lifecycle path

## Context and Problem Statement

Through v0.6.0 the base shipped the Talos cluster lifecycle as a `make`
pipeline: `talos/Makefile.lib` + `talos/scripts/argv-print.sh` rendering a
5-axis `cluster.yaml` (role · arch · infrastructure-platform ·
hardware-platform · hardware-capabilities) into per-node `talosctl gen config`
argv. That path conflated Kubernetes node roles with hardware specialisation
(it modelled `gpu-worker` / `pi-worker` as *roles*), grew a bespoke
schematic-hash cache, a placeholder-substitution engine, and a Layer-C feature
registry — a large, base-specific imperative surface for what is fundamentally
declarative provisioning.

An earlier proposal to add an OpenTofu module alongside the `make` path (PR #82)
was rejected on scope grounds. That decision is now **reversed**: the OpenTofu
`talos-cluster` module replaces the `make`/5-axis path entirely, and the
`make` path is removed. The `siderolabs/talos` Terraform provider already does
declaratively (machine secrets, machine config, Image-Factory schematics,
config apply, etcd bootstrap, kubeconfig) what the bespoke scripts did
imperatively.

The generalised rationale behind this reversal — the recurring anti-pattern of
re-implementing a maintained declarative tool as bespoke base-local imperative
infrastructure, and a recognition checklist to catch it elsewhere — is recorded
in #99. This ADR is the concrete decision; #99 is the pattern it instantiates.

## Decision Drivers

- Kubernetes node roles are only `controlplane` and `worker`; hardware
  specialisation is not a role. The 5-axis schema encoded the wrong model.
- A declarative provider with upstream maintenance beats a base-local
  imperative generator (argv-print, schematic cache, placeholder engine).
- Reproducible, pinned local tooling (devbox) + a single task runner
  (go-task) over an ad-hoc `make` lifecycle.
- The base must stay substrate-only and identity-free
  ([adr-substrate-only-base.md](adr-substrate-only-base.md)); the module is
  backend- and identity-agnostic, so cluster identity stays consumer-side.

## Considered Options

1. **Keep the `make`/5-axis path; add OpenTofu additively** (the original PR #82
   shape) — two competing lifecycle paths.
2. **Replace the `make`/5-axis path with the OpenTofu module entirely** — one
   path; `make` lifecycle removed.
3. **Status quo** — keep `make`/5-axis only; reject OpenTofu (the prior
   decision).

## Decision Outcome

Chosen option: **Option 2 — replace entirely**, because two parallel lifecycle
paths is a duplicate-maintenance and drift hazard, and the declarative provider
subsumes the bespoke generator. This is a breaking change (MAJOR).

The module lives at `tofu/modules/talos-cluster/`. Node roles are
`controlplane` / `worker` only; hardware specialisation is a node `class` that
selects a per-class Image-Factory + patch profile (`architecture`,
`extensions`, optional SBC `overlay`, `config_patches`). Patches apply in two
passes: a generation pass (all-nodes, role — baked into the machine config) and
an apply-overlay pass (module install.image, class, node — later wins). devbox
pins the toolchain (OpenTofu, tflint, go-task, …) and a `Taskfile.yml` exposes
`fmt` / `validate` / `lint` / `ci`. The module selects the non-secureboot
`urls.installer` (so the module never emits a SecureBoot installer); the
`hard-constraints-check` CI gate scans this repo's `tofu/**`. Enforcing
no-SecureBoot in consumer-supplied root/patch files (and schematic-level
secureboot toggles) is the consumer overlay's responsibility — the same
substrate-only boundary the base applies to PNI instance enforcement.

### Consequences

- Positive: one declarative lifecycle path; correct role model
  (controlplane/worker only); multi-architecture clusters (amd64 servers + an
  arm64 Raspberry-Pi worker) expressible in one apply via per-class
  `architecture` + `overlay`; per-class and per-node patch heterogeneity
  supported; provider-maintained upgrade/extension reconciliation.
- Negative: breaking change for consumers — every consumer migrates its Talos
  node definitions out of `cluster.yaml` into an OpenTofu root that calls the
  module. `cluster.yaml` is slimmed to its ArgoCD-bootstrap identity
  (`cluster.{name,overlay,target_revision}` + `repo.url`); the 5-axis Talos
  sections are gone. NTP (formerly injected from `cluster.yaml`) is now a
  caller `config_patches` value. The Layer-C hardware-feature *validation*
  that `validate-schematics.sh` performed is dropped (the
  `docs/platform-hardware-features.yaml` catalogue stays — it is PNI
  Layer-C label vocabulary, independent of Talos config generation).
- Follow-up:
  - **Running-cluster PKI adoption.** The module *generates*
    `talos_machine_secrets` into state. Adopting an already-running cluster
    (whose PKI lives in a SOPS `secrets.yaml`) without re-bootstrapping is
    **not yet implemented** — tracked separately. The module is safe for
    greenfield clusters only until then.
  - **Consumer Stage-0 root.** Each consumer authors a root module
    (provider + encrypted backend + module call + `cluster.yaml`→variables
    mapping + per-node NIC rendering). Tracked in the consumer repo.
  - **Kubernetes upgrades** stay out-of-band (`talosctl upgrade-k8s`) until the
    provider ships an upgrade resource.

## Pros and Cons of the Options

### Option 1 — additive

- Pro: no breaking change; consumers migrate at leisure.
- Con: two lifecycle paths to maintain; drift and "which path is authoritative"
  ambiguity; the wrong (role-conflating) 5-axis model survives.

### Option 2 — replace (chosen)

- Pro: single authoritative declarative path; correct role model; smaller
  base-local surface.
- Con: breaking; needs a documented per-consumer migration and a
  not-yet-built PKI-adoption path for running clusters.

### Option 3 — status quo

- Pro: no work; no migration.
- Con: keeps the bespoke imperative generator and the wrong role model
  indefinitely.

## Validation

- CI `tofu-validate` (mirrors local `task ci`: `tofu fmt -check`, per-dir
  `tofu validate`, `tflint`) is green on every `tofu/**` change.
- `tofu/modules/talos-cluster/examples/homelab/` validates a mixed
  amd64 + arm64 topology (controlplane, kubevirt workers, GPU worker, arm64
  Raspberry-Pi worker) — the evidence that a real heterogeneous cluster is
  expressible.
- The Hard Constraint check holds: the module emits `metal-installer`
  (never `metal-installer-secureboot`); arm64 SBC classes use
  `architecture = "arm64"` + an overlay on the `metal` platform.
- This ADR is wrong if a consumer cannot express its cluster against the module
  without re-introducing a base-local generator. The first real consumer
  migration (homelab) is the test; the PKI-adoption follow-up is the known gap.

## Amendment — 2026-06-03: ArgoCD bootstrap delivery + cluster-health gate

The original outcome left **all** of Day-2 — including ArgoCD — to GitOps,
implicitly treating ArgoCD as a Day-2 app. The platform C4 layer model
(Level-2) instead places **ArgoCD in Layer-1 (substrate)**: it is the GitOps
engine that delivers every higher layer, so *something* has to seed it before
any GitOps can run. Two consumer-side options were possible — a Stage-1
Crossplane/orchestrator step, or the lifecycle module itself. Cleared with the
base maintainer, the decision is that **the `talos-cluster` module delivers the
ArgoCD bootstrap install**, because the module is already the one component that
holds the freshly-bootstrapped cluster's trust material and runs at exactly the
right moment (right after etcd bootstrap, before anything else exists).

**Mechanism (no new anti-pattern).** ArgoCD is rendered **locally** with
`data.helm_template` and baked into the controlplane `cluster.inlineManifests`.
Crucially this avoids the chicken-and-egg of a `helm_release`/`kubernetes_*`
apply against a kubeconfig that is itself a computed output of the same apply.
The seed is the namespace → `sops-age-key` Secret for the ksops repoServer →
the ArgoCD **app** (no CRDs) and is intentionally minimal. The three ArgoCD CRDs
render to ~1.8 MB — too large for an inlineManifest — so the module applies them
via `kubectl` **server-side** after the health gate (needs `kubectl` on the
apply host). The **steady-state** (TLS cert via a not-yet-existing
`ClusterIssuer`, RBAC, OIDC, the app-of-apps) remains ArgoCD **self-management**
in the consumer repo.

**CRD-apply mechanism — decided (#104).** Keeping the CRD apply *in the module*
via `kubectl` server-side (`null_resource` + `local-exec`) is an accepted,
deliberate choice over three alternatives. (1) A declarative `hashicorp/kubernetes`
`kubernetes_manifest` apply is ruled out: it requires API access at **plan** time,
but on a first apply the cluster does not exist yet — it cannot bootstrap itself.
(2) A third-party `kubectl_manifest` provider (`gavinbunney`/`alekc`) would work,
but trades a `kubectl` binary for a third-party provider dependency plus ~1.8 MB
of CRD state bloat — a worse footprint for a substrate module, not a better one.
(3) Moving the apply to the consumer's Stage-0 root keeps the module purely
declarative but scatters the trust-material handling the module already owns at
exactly the right moment. The accepted cost is a hard **`kubectl` host
dependency**: every apply host must ship it — a workstation via devbox, and the
Crossplane provider-terraform runner **image must include `kubectl`**.

**Not a boundary move — a correction.** This amendment does **not** move the
Layer-1/Day-2 line. ArgoCD was always Layer-1 (Talos + Cilium + ArgoCD = three
co-equal substrate pillars). The v0.7.0 lifecycle cutover over-scoped its
Talos-only focus and mis-classified the ArgoCD bootstrap as Day-2; this
amendment corrects that. *Bootstrap seed* is substrate; *everything ArgoCD
reconciles after that* is GitOps — as it always should have read.

**Substrate-only boundary preserved.** The base still ships **no secrets**: the
age key is the caller-supplied `sops_age_key` (sensitive, lands only in the
encrypted state + machine config, both already secret-bearing). `deploy_argocd`
defaults to `true` but is an **opt-out** — a consumer that seeds ArgoCD via a
Stage-1 orchestrator sets `deploy_argocd = false` and the module stays
ArgoCD-agnostic. No cluster identity enters the base.

**Cluster-health gate.** Independently, `data.talos_cluster_health` now blocks
`tofu apply` after bootstrap until etcd quorum + nodes Ready + apiserver
reachable (`cluster_health_timeout`, default `10m`). It gates **cluster
reachability, not the ArgoCD rollout** — its job is to ensure the apiserver is
up before the CRD `kubectl` apply runs and before credentials are emitted, not
to assert ArgoCD is Ready. Without it `apply` returned the instant the bootstrap
call was issued — before the apiserver answered. The credential outputs and the
new `cluster_health` output `depends_on` it, so downstream tooling only receives
credentials for a cluster that is genuinely online.

**Roadmap — Cilium convergence.** Under the three-pillars model, Cilium should
eventually follow the same local-render → inlineManifest pattern (today it ships
via the consumer's config_patches/recipe). The Cilium/ArgoCD asymmetry is
**temporary** and tracked, not a standing design choice.

This amendment is wrong if seeding ArgoCD from the lifecycle module forces
cluster identity or secrets into the base, or if a consumer cannot decline it.
Both are addressed (`sops_age_key` is caller-supplied; `deploy_argocd = false`
opts out). The narrower follow-up — whether the bootstrap-vs-steady-state split
holds once a real consumer self-manages ArgoCD's TLS/RBAC — is validated by the
first consumer (seeder).

## Links

- #99 — the generalised pattern this ADR instantiates (prefer maintained declarative tooling over bespoke imperative reinvention).
- PR #82 (reopened) — the implementation.
- [adr-substrate-only-base.md](adr-substrate-only-base.md) — the substrate-only boundary this module respects.
- [tofu/modules/talos-cluster/README.md](../tofu/modules/talos-cluster/README.md) — module contract.
