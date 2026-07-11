---
type: reference
title: cluster.yaml — Declarative Cluster SoT
description: Shape, consumers, secret-handling rules, and lint gate of the declarative cluster.yaml Source-of-Truth a consumer cluster maintains.
tags: [cluster-yaml, sot, schema, bootstrap]
timestamp: 2026-07-11
sources:
  - cluster.yaml.example
  - schemas/cluster.schema.json
  - scripts/lint-cluster-yaml.sh
  - schemas/fixtures/cluster.invalid.yaml
  - Taskfile.yml
  - tofu/modules/talos-cluster/examples/complete/main.tf
  - .github/workflows/gitops-validate.yml
---

# cluster.yaml — Declarative Cluster SoT

`cluster.yaml` is the declarative Source-of-Truth for a consumer cluster: the
YAML document IS the cluster definition (identity, versions, network, images,
capabilities, nodes, machine-config patches, substrate knobs). OpenTofu is the
executor, not the SoT — the consumer's root module is a thin `yamldecode` shim
that maps this file onto the typed interface of the
[talos-cluster module](talos-cluster-module.md). The base ships only
`cluster.yaml.example`; the real `cluster.yaml` is gitignored at the base and
committed in consumer repos per repo convention.

Seeding: `task cluster:init-yaml` copies `cluster.yaml.example` to
`cluster.yaml` if (and only if) it does not already exist.

## Two consumers, two subsets

1. **`task bootstrap:argocd`** reads only the **bootstrap-identity subset**,
   extracted with `yq` in the internal `bootstrap:render-root` task:
   `.cluster.name`, `.cluster.overlay`,
   `.cluster.target_revision // "main"`, and `.repo.url`. The values are
   `envsubst`-rendered into the App-of-Apps root templates under
   `kubernetes/bootstrap/argocd/` (any value containing `$` is rejected as
   unsafe for `envsubst`). The file is selected via the Taskfile `ENV`
   variable (default `cluster.yaml`; override per invocation with
   `task bootstrap:argocd ENV=other.yaml`).
2. **The consumer OpenTofu root** reads the **full file**. The worked shim is
   `tofu/modules/talos-cluster/examples/complete/main.tf`: it `yamldecode`s
   the file, re-encodes the structured patch maps (`config_patches`,
   `controlplane_config_patches`, `worker_config_patches`, per-node
   `config_patches`) into the YAML strings the module interface takes, and
   maps `cluster.*`, `talos.*`, `kubernetes.version`, `images`,
   `hardware-capabilities`, `nodes`, and `substrate.{cilium,argocd}` onto the
   module variables, applying the module defaults via `try()` for omitted
   keys.

## Schema shape

`schemas/cluster.schema.json` (JSON Schema draft 2020-12) validates the file.
It mirrors the module's variable validations for the structured surface and is
closed at the root (`additionalProperties: false`).

- Required top-level keys: `cluster`, `repo`, `talos`, `kubernetes`,
  `images`, `nodes`.
- `cluster`: requires `name` (lowercase RFC-1123 label pattern) and
  `endpoint` (`^https://`); optional `overlay`, `target_revision` (the
  bootstrap-identity fields), `pod_cidr` / `service_cidr` (arrays,
  `minItems: 1`), `dual_stack`, `allow_scheduling_on_controlplanes`.
- `talos`: requires `version` (v-prefixed semver — the schema pin); optional
  `install_version` (empty or v-prefixed semver).
- `kubernetes`: requires `version` (v-prefixed semver).
- `images`: object with `minProperties: 1`; each image requires `cpu_vendor`
  (`intel|amd|arm`), optional `architecture` (`amd64|arm64`), `extensions`,
  and a nullable SBC `overlay` (requires `name` + `image` when present).
- `hardware-capabilities`: optional map; each entry requires `emits_label`
  matching `^platform\.io/hardware-capability\.` and optionally carries
  `requires_features` and `provisioning_profiles`.
- `nodes`: array, `minItems: 1`; each node requires `hostname`, `ip`,
  `role` (enum `controlplane|worker`), `image`; optional
  `hardware_capabilities` and free-form `config_patches`.
- `config_patches` / `controlplane_config_patches` /
  `worker_config_patches`: arrays of free-form objects. Patch **content** is
  deliberately not schema-validated — structural validity is Talos' concern
  at apply time, and secret-leak risk in free-form blocks is gitleaks'
  concern, not the schema's.
- `substrate`: closed object (`additionalProperties: false`) with exactly two
  loosely-typed members, `cilium` and `argocd` — a typo'd sibling key (e.g.
  `argo_cd:`) fails lint instead of being silently dropped by the shim.
  cert-approver is always-on substrate with no cluster.yaml knob.

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

## What must never be in it

Secrets have **no schema slot** — they are structurally excluded, not merely
discouraged:

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

## Lint gate

`scripts/lint-cluster-yaml.sh` validates a cluster.yaml against the schema
using `check-jsonschema` (PATH binary preferred, `uvx` fallback), always
passing `--default-filetype yaml` because the default target
`cluster.yaml.example` does not end in `.yaml`.

- Usage: `scripts/lint-cluster-yaml.sh [file]` — no argument lints
  `cluster.yaml.example`; consumer repos point it at their committed
  `cluster.yaml`.
- Exit codes: `0` pass, `1` at least one schema violation, `2`
  environment/argument error (file or schema missing, no runner on PATH).
- On success it prints a summary line with node and image counts (via `yq`,
  best-effort).

CI wires the gate in the `hardware-features-check` job of
`.github/workflows/gitops-validate.yml`:

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
