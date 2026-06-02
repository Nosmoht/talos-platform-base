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

## Links

- PR #82 (reopened) — the implementation.
- [adr-substrate-only-base.md](adr-substrate-only-base.md) — the substrate-only boundary this module respects.
- [tofu/modules/talos-cluster/README.md](../tofu/modules/talos-cluster/README.md) — module contract.
