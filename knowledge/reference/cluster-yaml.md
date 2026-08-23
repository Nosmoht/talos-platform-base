---
type: reference
title: cluster.yaml — Declarative Cluster SoT
description: The two consumers of the declarative cluster.yaml Source-of-Truth, its secret-handling rules, and how CI wires the schema lint gate red-green.
tags: [cluster-yaml, sot, schema, bootstrap]
timestamp: 2026-08-14
sources:
  - resource: cluster.yaml.example
  # Kept despite the schema-shape section moving to openspec/specs/cluster-yaml-sot/:
  # the surviving prose still derives from this file (the deliberate absence of a
  # schema_version, the unvalidated patch content), so it is still the trigger
  # the bundle's re-verify rule needs — drop it and nothing tells a future
  # reader those claims went stale.
  - resource: schemas/cluster.schema.json
  - resource: scripts/lint-cluster-yaml.sh
  - resource: scripts/check-shim-key-parity.sh
  - resource: schemas/fixtures/cluster.invalid.yaml
  - resource: Taskfile.yml
  - resource: tofu/modules/talos-cluster/examples/complete/main.tf
  - resource: tofu/modules/talos-cluster/examples/complete/variables.tf
  - resource: .github/workflows/gitops-validate.yml
---

# cluster.yaml — Declarative Cluster SoT

`cluster.yaml` is the declarative Source-of-Truth for a consumer cluster: the
YAML document IS the cluster definition (identity, versions, network, images,
capabilities, nodes, machine-config patches, substrate knobs). OpenTofu is the
executor, not the SoT — the consumer's root module is a thin `yamldecode` shim
that maps this file onto the typed interface of the `talos-cluster` module
(normative in `openspec/specs/module-interface-contract/`;
`tofu/modules/talos-cluster/README.md` is the release-shipped copy of the
same interface). The base ships only `cluster.yaml.example`; the real
`cluster.yaml` is gitignored at the base and committed in consumer repos per
repo convention.

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
tail — registry mirrors, install disk, NTP, VIP — lives inside the SoT as raw
Talos patches in `config_patches`, just untyped. **Boot kernel command-line
args are the one exception**, and deliberately not routed through
`config_patches`: under the Talos v1.10+ UKI/systemd-boot default,
`machine.install.extraKernelArgs` is ignored (kernel args are embedded in the
UKI), so a `config_patches` entry targeting it silently no-ops. Boot kernel
args go to `images.<id>.extra_kernel_args` instead — the schematic sink that
actually reaches the UKI, and the input that re-images the node when changed
(issue #169).

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

Secrets have **no schema slot**, per `openspec/specs/cluster-yaml-sot/`
§"Requirement: Untyped escape hatches and structural secret exclusion" (which
itself names `knowledge/decisions/0007-cluster-yaml-sot.md` as normative for
why). Where they go instead:

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
   `schemas/fixtures/cluster.invalid.yaml` — valid in every respect except ten
   deliberate violations, each binding one schema rule owned by
   `openspec/specs/cluster-yaml-sot/` — must fail, and CI names all ten
   violations individually in the output. See the spec for the gate's exact
   pass/fail/error behavior. Relaxing any one of the ten rules in the schema
   turns this step red without affecting the other nine.
3. `tofu/modules/talos-cluster/examples/complete/cluster.yaml` is linted the
   same way (issue #169) — the module's worked example is otherwise reachable
   by no CI job.

## How CI binds the schema to the shim

Lint proves a `cluster.yaml` matches the schema. It does not prove the declared
value reaches the module: the shim reads the file through `try()`, which is
total, so a key the shim never reads — or reads misspelled — resolves to the
module default with no error anywhere. Schema lint passes, `tofu validate` and
`tofu plan` pass, and the module's own test suite never loads the shim.

`scripts/check-shim-key-parity.sh` closes that gap by asserting every key of
every CLOSED substrate object in the schema is actually read by
`tofu/modules/talos-cluster/examples/complete/main.tf`. It runs as
`task tofu:check:shim-key-parity`, is carried by `task tofu:ci`, and
`.github/workflows/tofu-validate.yml` lists `schemas/cluster.schema.json` among
its trigger paths so a schema-only widening — the diff shape that leaves a new
key unmapped — still runs it. Its scope is the closed objects only:
`substrate.argocd` is deliberately loosely typed and declares no key set to
bind, and the sections outside `substrate` restructure their data in the shim
(node and image maps go through for-expressions), so key-name presence is not
the right oracle for them.

## Worked references

- `cluster.yaml.example` — the commented minimal skeleton (RFC5737
  documentation IPs, platform-default CIDRs, empty capability map).
- `tofu/modules/talos-cluster/examples/complete/cluster.yaml` — a full mixed
  amd64 + arm64 topology exercising every field the shim reads (capability
  composition, per-node patches, role-tier patches, the
  `install_version` upgrade split, explicit substrate knobs).
- Decision record:
  [0007-cluster-yaml-sot](../decisions/0007-cluster-yaml-sot.md).
