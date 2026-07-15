---
type: reference
title: cluster.yaml — Declarative Cluster SoT
description: The two consumers of the declarative cluster.yaml Source-of-Truth, its secret-handling rules, and how CI wires the schema lint gate red-green.
tags: [cluster-yaml, sot, schema, bootstrap]
timestamp: 2026-07-15
sources:
  - cluster.yaml.example
  # Kept despite the schema-shape section moving to openspec/specs/cluster-yaml-sot/:
  # the surviving prose still derives from this file (the deliberate absence of a
  # schema_version, the unvalidated patch content, the structural exclusion of
  # secrets), so it is still the trigger the bundle's re-verify rule needs — drop
  # it and nothing tells a future reader those claims went stale.
  - schemas/cluster.schema.json
  - scripts/lint-cluster-yaml.sh
  - schemas/fixtures/cluster.invalid.yaml
  - Taskfile.yml
  - tofu/modules/talos-cluster/examples/complete/main.tf
  - tofu/modules/talos-cluster/examples/complete/variables.tf
  - .github/workflows/gitops-validate.yml
---

# cluster.yaml — Declarative Cluster SoT

`cluster.yaml` is the declarative Source-of-Truth for a consumer cluster: the
YAML document IS the cluster definition (identity, versions, network, images,
capabilities, nodes, machine-config patches, substrate knobs). OpenTofu is the
executor, not the SoT — the consumer's root module is a thin `yamldecode` shim
that maps this file onto the typed interface of the `talos-cluster` module
(interface tables in `tofu/modules/talos-cluster/README.md`). The base ships
only `cluster.yaml.example`; the real `cluster.yaml` is gitignored at the base
and committed in consumer repos per repo convention.

> **The file's shape is normative in the spec, not here.** Required keys, field
> types, patterns and the closed-root rule live in
> `openspec/specs/cluster-yaml-sot/`, derived from
> `schemas/cluster.schema.json`; the bootstrap-identity subset and the
> envsubst containment guards live in
> `openspec/specs/argocd-day-zero-bootstrap/` (SoT map:
> [ADR-0015](../decisions/0015-openspec-adoption.md)). This document carries
> only what those specs do not: why secrets have no slot and where they go
> instead, the authoring notes the schema cannot express, and how CI binds the
> lint gate.

Seeding: `task cluster:init-yaml` copies `cluster.yaml.example` to
`cluster.yaml` if (and only if) it does not already exist.

## Two consumers, two subsets

1. **`task bootstrap:argocd`** reads only the **bootstrap-identity subset** —
   four fields, extracted with `yq` in the `bootstrap:render-root`
   task and `envsubst`-rendered into the App-of-Apps root templates under
   `kubernetes/bootstrap/argocd/`. The subset and the two guards that keep a
   `cluster.yaml` value from expanding into anything but itself are normative
   in `openspec/specs/argocd-day-zero-bootstrap/`. The file is selected via
   the Taskfile `ENV` variable (default `cluster.yaml`; override per
   invocation with `task bootstrap:argocd ENV=other.yaml`).
2. **The consumer OpenTofu root** reads the **full file**. The worked shim is
   `tofu/modules/talos-cluster/examples/complete/main.tf`: it `yamldecode`s
   the file, re-encodes the structured patch maps (`config_patches`,
   `controlplane_config_patches`, `worker_config_patches`, per-node
   `config_patches`) into the YAML strings the module interface takes, and
   maps `cluster.*`, `talos.*`, `kubernetes.version`, `images`,
   `hardware-capabilities`, `nodes`, and `substrate.{cilium,argocd}` onto the
   module variables, applying the module defaults via `try()` for omitted
   keys.

## Authoring notes behind the schema's choices

The typed surface is deliberately limited to the common, irreversible, or
foot-gun-prone set (network CIDRs, versions, substrate toggles); the long
tail — registry mirrors, install disk, NTP, kernel args, VIP — lives inside
the SoT as raw Talos patches in `config_patches`, just untyped.

There is **no `schema_version` field by design**: the schema is versioned by
its `$id` plus the base OCI tag — a breaking shape change bumps the next tag's
MAJOR version, so the migration signal is the OCI tag, not an in-file field.

Structured YAML patch values that must reach Talos as strings must be quoted
(bare scalars like `30`, `on`, `no`, `0755` coerce to int/bool/octal and
re-encode wrong through the shim's `yamlencode`).

Patch **content** is deliberately not schema-validated — structural validity
is Talos' concern at apply time, and secret-leak risk in free-form blocks is
gitleaks' concern, not the schema's.

## What must never be in it

Secrets have **no schema slot** — they are structurally excluded, not merely
discouraged. Where they go instead:

- `sops_age_key` (ArgoCD ksops repoServer) → `TF_VAR_sops_age_key` /
  gitignored tfvars / SOPS.
- `cilium_ipsec_key` (only when `substrate.cilium.encryption.type: ipsec`) →
  `TF_VAR_cilium_ipsec_key` / gitignored tfvars / SOPS.

The example shim declares both as `sensitive` variables in
`tofu/modules/talos-cluster/examples/complete/variables.tf`; `sops_age_key`
deliberately has no default so a copied root cannot silently apply a
non-functional ksops key. The free-form escape hatches (`config_patches`,
`substrate.*.values_override`) are unbounded passthrough into the controlplane
machine config — never paste secret material into them; cluster.yaml is
committed in consumer repos and gitleaks is the backstop, not a substitute.

## How CI binds the lint gate

`scripts/lint-cluster-yaml.sh` validates a cluster.yaml against the schema
(behavior, arguments and exit codes are spec'd in
`openspec/specs/cluster-yaml-sot/`). CI wires it in the
`hardware-features-check` job of `.github/workflows/gitops-validate.yml`, and
the wiring is what makes the gate bite:

1. Positive step: `scripts/lint-cluster-yaml.sh cluster.yaml.example` must
   pass.
2. Negative (schema red-green) step: the intentionally invalid fixture
   `schemas/fixtures/cluster.invalid.yaml` — valid in every respect except
   one node carries `role: master`, which the `node.role` enum rejects —
   must fail with **exit code exactly 1**. Exit `0` fails CI ("malformed
   cluster.yaml fixture passed schema validation"); any other non-zero code
   also fails ("linter errored, did not reach a schema verdict"), so a broken
   toolchain cannot pass vacuously. Relaxing the role enum in the schema
   turns this step red.

## Worked references

- `cluster.yaml.example` — the commented minimal skeleton (RFC5737
  documentation IPs, platform-default CIDRs, empty capability map).
- `tofu/modules/talos-cluster/examples/complete/cluster.yaml` — a full mixed
  amd64 + arm64 topology exercising every field the shim reads (capability
  composition, per-node patches, role-tier patches, the
  `install_version` upgrade split, explicit substrate knobs).
- Decision record:
  [0007-cluster-yaml-sot](../decisions/0007-cluster-yaml-sot.md).
