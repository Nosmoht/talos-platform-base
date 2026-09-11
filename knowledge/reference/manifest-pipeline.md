---
type: reference
title: Manifest Pipeline
description: How the rendered-manifests pattern is implemented — chart pinning, two-stage render, drift fences, and the gitops:validate pipeline with its CI mapping.
tags: [rendered-manifests, validation, ci, conftest]
generated: { by: human:nosmoht, at: "2026-09-02T00:00:00Z" }
sources:
  - resource: scripts/render-component.sh
  - resource: scripts/verify-rendered.sh
  - resource: scripts/render_kustomize_safe.sh
  - resource: scripts/discover_kustomize_targets.sh
  - resource: scripts/verify_sops_files.sh
  - resource: scripts/run_conftest.sh
  - resource: scripts/check-argocd-substrate-invariants.sh
  - resource: scripts/check-argocd-network-policy-invariants.sh
  - resource: scripts/check-argocd-network-policy-gate-bites.sh
  - resource: scripts/render-component-readmes.sh
  - resource: scripts/lint-cluster-yaml.sh
  - resource: policies/conftest/k8s.rego
  - resource: policies/conftest/argocd.rego
  - resource: Taskfile.yml
  - resource: .github/workflows/gitops-validate.yml
---

# Manifest Pipeline

The base ships Helm-based infrastructure components as **rendered, committed
YAML** (the Rendered Manifests Pattern): the render happens at authoring time
from a pinned, checksum-verified chart, the output lands in git under
`kubernetes/substrate/<component>/_rendered/`, and CI proves the
committed output is byte-reproducible from its inputs. What consumers and
ArgoCD see is plain reviewable YAML — no chart is templated at sync time, and
a hand-edit to committed output cannot ship silently because the drift gate
re-renders and diffs on every PR.

## Chart pin: `chart.lock.yaml`

Each Helm-based component directory carries a `chart.lock.yaml` that is the
single pin spec for its render (schema from `scripts/render-component.sh`):

```yaml
chart:
  repo: <https-or-oci-url>      # required
  name: <chart-name>            # required
  version: <semver-or-tag>      # required
  tgz_sha256: <hex>             # optional; verified if set, written if absent
release:
  name: <helm-release-name>     # required
  namespace: <k8s-namespace>    # required
  includeCRDs: true|false       # default true
values: <relative-path>         # default: values.yaml
```

Supply-chain posture: the pulled chart tarball is sha256-verified against
`chart.tgz_sha256`. A mismatch aborts the render (exit 3) — either the
upstream republished the same version (a security event) or the lock needs a
deliberate update. When the digest is absent, the script writes the observed
digest back into the lock, so the pin self-establishes on first render.

### What a chart bump obliges

Two review obligations attach to moving a pin. Neither is mechanically gated —
they are repo-internal QA, which is why they live here rather than in
`openspec/`; the observable half is a requirement of the
`module-interface-contract` spec.

- **`Spec-Impact: none` is not available for the variables file.** For a
  component the `talos-cluster` module also seeds, the module's declared default
  is the single source of truth for the pin, and the shipped examples leave the
  key unset — so moving the default changes what a fresh bootstrap seeds and what
  the steady-state render delivers. The escape is scoped to verified
  no-behaviour-change diffs, and the staleness gate cannot reach the render-side
  spec on its own, because the file describing the seed's contents is not the file
  a version bump touches. The delta belongs on the render or seed capability.
- **Re-verify what the module cannot check at plan time, and record it where an
  adopting consumer reads it.** The Kubernetes version range the new upstream
  version supports — `kubernetes_version` is a required module input the module
  never validates against the chart — and the upstream project's own upgrade
  notes for every version crossed. Same form and same reason as the Gateway-API
  CRD floor the module-interface spec attaches to `cilium_chart_version`: no gate
  compares a chart pin against an upstream support matrix, and a mechanical
  coupling remains desirable and unbuilt.

## Render stages (`task gitops:render-component COMPONENT=<name>`)

`scripts/render-component.sh <component>` runs per component:

1. **Pull** the pinned chart (`helm pull`, HTTPS or `oci://` repo forms) into
   a local `.helm-cache/`, then verify or write the sha256 digest.
2. **Stage 1 — `helm template`** with the component's `values.yaml`, the
   locked release name/namespace, and `--include-crds` when
   `release.includeCRDs` is true.
3. **Stage 2 — `kustomize build`** of the component's `_rendered-overlay/`
   (with `--load-restrictor=LoadRestrictionsNone`), applying the
   platform-base standard patches on top of the Helm output.
4. **CRD split**: the final stream is split by `kind` into
   `_rendered/manifests.yaml` (everything except CRDs) and
   `_rendered/crds.yaml` (CRDs only, written only when the chart ships any).
   The split exists for the two-Application pattern: a separate ArgoCD
   Application deploys the CRDs at sync-wave -5, ahead of the component
   itself. Trailing newlines are normalized to exactly one.

Exit codes: `0` success, `1` usage/missing input, `2` chart pull failed,
`3` sha256 mismatch, `4` helm template failed, `5` kustomize build failed.

Per-component layout (tracked vs intermediate, per the render script and
`.gitignore`):

```text
kubernetes/substrate/<component>/
├── chart.lock.yaml        # pin spec (committed)
├── values.yaml            # Stage-1 input: repo-wide defaults (committed)
├── kustomization.yaml     # validation entry point (committed)
├── namespace.yaml         # namespace + labels (committed)
├── _rendered-overlay/     # Stage-2 input: patches over Stage-1 (committed)
├── .render-stage1/        # Stage-1 intermediate (gitignored)
└── _rendered/             # Stage-2 output (committed)
    ├── manifests.yaml
    └── crds.yaml          # only when the chart ships CRDs
```

`.helm-cache/` (pulled chart tarballs) is likewise gitignored — it is
reproducible from `chart.lock.yaml` via the sha256 pin. Since the
substrate-only ablation, `argocd` is the base's only Helm-based component;
the pipeline itself is component-generic.

Determinism inputs: helm, kustomize, and yq versions are pinned in
`.tool-versions` (checked locally by `task dev:verify-tools` and in CI by a
drift step — see the CI mapping below). yq matters because multi-line block
scalar serialization differs across yq versions and would show up as render
drift.

`task gitops:render-all` runs the same script for every component that has a
`chart.lock.yaml`.

## Drift fence: `task gitops:verify-rendered`

`scripts/verify-rendered.sh` snapshots each component's committed
`_rendered/` tree, re-renders in place from the current `chart.lock.yaml` +
`values.yaml` + `_rendered-overlay/`, and diffs. Any drift or render failure
fails the run (exit 1 drift, exit 2 render failure) with the remediation
printed: re-run `task gitops:render-all` and commit, or fix the inputs. This
is the load-bearing guarantee that committed `_rendered/` YAML is
reproducible — CI runs it on every PR.

A sibling generator, `scripts/render-component-readmes.sh`, renders each
component's `README.md` (chart pin, namespace, top-level value overrides
auto-extracted; purpose and upgrade gotchas hand-curated in the script) for
the components listed in `.ci-renderable-components.txt`, with a `--check`
mode that fails on drift.

## `task gitops:validate` — stage by stage

The aggregate validation task chains the following gates
(`Taskfile.yml`, `gitops:validate`):

1. **Discovery** — `scripts/discover_kustomize_targets.sh` finds
   kustomization directories under `kubernetes/overlays/`,
   `kubernetes/bootstrap/`, and one-level-deep component dirs in
   `kubernetes/substrate/` (avoiding chart-internal
   kustomizations), excluding `.git/`, `knowledge/`, `vendor/`,
   `third_party/`, generated Talos output, and `resources/` subpaths. Output:
   `.work/kustomize-targets.txt`.
2. **Safe render** — `scripts/render_kustomize_safe.sh` classifies each
   target: directories whose kustomization references
   ksops/sops-generator/`viaduct.ai/v1`, or that contain a file with a
   top-level `sops:` key, are **skipped as unsafe** (rendering them would
   emit plaintext secrets); safe targets are rendered with
   `kustomize build --enable-helm` into `.work/rendered/`. Requires
   ripgrep — absent `rg` is a hard failure (exit 2) because the detection
   would otherwise fail open. Output list:
   `.work/kustomize-rendered-files.txt`.
3. **SOPS negative gate** — `scripts/verify_sops_files.sh` fails if ANY SOPS
   material exists in the base repo: filename match (`*.sops.yaml`,
   `*.sops.yml`, `*.sops.json`) or content match (top-level `sops:` key in
   any YAML). The gate is inverted on purpose: a validate-if-present form
   passed vacuously with zero SOPS files. Secret material belongs in
   consumer repos only.
4. **Conftest policies** — `scripts/run_conftest.sh` tests rendered files
   against `policies/conftest/` with two enforcement tiers:
   - **Rendered base components: informational only.** Findings print but do
     not gate, because rendered output inherits upstream chart defaults;
     consumer overlays apply cluster-specific hardening on top.
   - **ArgoCD Application CRs: enforced by design, currently unwired.** The
     enforced tier reads its file list from `.work/argocd-applications.txt`
     (the script's default), but no current local or CI invocation produces
     that file — both call `scripts/run_conftest.sh` with no arguments, and
     with the list absent the script prints a notice and skips the tier.
     Tracked as a follow-up to wire a producer for the list.
5. **Kubeconform** — `kubeconform -strict -ignore-missing-schemas` over every
   rendered file.
6. **Conftest bite-check** — the committed invalid Application fixture must
   trigger all three expected source-classification and pinning denials.
7. **ArgoCD substrate invariants** —
   `scripts/check-argocd-substrate-invariants.sh` (below).
8. **NetworkPolicy gate bite-check** —
   `scripts/check-argocd-network-policy-gate-bites.sh` mutates copies of the
   committed render and requires the exact-posture gate to reject selector,
   ingress, port, `policyTypes`, and policy-set drift.
9. **Bootstrap render contract** — `scripts/check-bootstrap-render.sh` binds
   the consumer bootstrap render to its OpenSpec scenarios.
10. **Cilium reference values** — `scripts/check-cilium-reference-values.py`
   checks the shipped Day-2 values against the pinned chart schema; an
   unreachable registry skips loudly rather than blocking unrelated work.

### Conftest policy content

- `policies/conftest/k8s.rego` (package `conftest.k8s`): denies workloads
  (Deployment/StatefulSet/DaemonSet outside `kube-system`) that enable
  `hostNetwork`, run privileged containers, or omit `resources`,
  `resources.requests`, or `resources.limits`.
- `policies/conftest/argocd.rego` (package `conftest.argocd`): for every
  ArgoCD `Application` — `spec.project`, `destination.namespace`, and
  `destination.server`/`name` must be set; Helm sources must set `repoURL`,
  `chart`, and an exact-semver `targetRevision` (floating `latest`/`*`
  denied); git sources must not target `HEAD`; automated sync requires
  `syncPolicy.retry.limit` (the `root` app exempt); only the
  `infrastructure` project may target `kube-system`. An optional warning for
  `main`/`master` git revisions exists but is disabled
  (`enable_git_main_warnings := false`).

### ArgoCD substrate invariants

`scripts/check-argocd-substrate-invariants.sh` guards the ArgoCD invariants
across the two render paths — the Day-0 bootstrap seed values
(`tofu/modules/talos-cluster/helm/argocd-values.yaml`) and the steady-state
self-management values (`kubernetes/substrate/argocd/values.yaml`)
— by rendering each fresh with the single pinned chart from the argocd
component's `chart.lock.yaml` (tarball sha256-verified, same posture as the
component render). I1–I3 and I6 are asserted against both paths; I4 and I5 are
steady-state-only; P compares the two pins:

- **I1** — no bundled-Dex resource: no rendered document carries the label
  `app.kubernetes.io/component=dex-server` nor the name
  `argocd-dex-server` (label anchor survives a `fullnameOverride`).
- **I2** — no ConfigMap has a `.data` key prefixed `server.dex.server`
  (every ConfigMap is scanned, not just `argocd-cmd-params-cm` by name, so a
  chart rename cannot make the check pass vacuously).
- **I3** — the `argocd-cm` ConfigMap has no `url` key. Scoped
  by ConfigMap name rather than by a blanket key sweep, because `url` is generic
  enough that other ConfigMaps carry it legitimately. `argocd-notifications-cm`'s
  `argocdUrl` is an accepted residual the chart's `default` function makes
  unclearable.
- **I4** (steady-state only) — `argocd-rbac-cm` carries no non-empty
  `policy.csv`: the substrate ships no identity. Steady-state-only by
  construction — the published component is what a consumer's overlay merges
  onto, so a principal shipped there becomes a standing grant in every consuming
  cluster. Asserted on emptiness rather than absence, because the chart emits
  the key unconditionally.
- **I5** (steady-state only) — `argocd-rbac-cm` carries no non-empty
  `policy.default`; unlike I4's named-subject policy, this would grant a role to
  every authenticated principal.
- **I6** — both renders carry the exact five-policy NetworkPolicy posture.
  `scripts/check-argocd-network-policy-invariants.sh` binds each component's
  selector, ingress peers and ports, and `policyTypes`; the server remains open
  for a consumer gateway while redis and repo-server remain restricted to their
  documented callers. It also binds `apiVersion` and `metadata.namespace` (a
  namespaced, group-scoped object enforces nothing outside `argocd`), rejects any
  higher-precedence policy kind the `kind` filter would otherwise miss, and
  cross-checks each named ingress port against the target workload's
  `containerPort` names — a rename there makes an allow rule match nothing while
  every policy document stays byte-identical. The steady-state side runs on the
  **kustomize-built** component as well as on the fresh helm render: the
  committed `_rendered/` tree is a file consumers vendor, so a hand edit to it or
  a regeneration through a changed `_rendered-overlay/` reaches them while the
  fresh-render check stays green, and `verify-rendered.sh` proves only that
  `_rendered/` is reproducible, not that what it reproduces satisfies I6. Unlike
  I1–I5 the invariant is positive, so a set that no longer matches is a violation
  (exit 3) rather than a render-shape error.
  `scripts/check-argocd-network-policy-gate-bites.sh` mutates the committed
  render and proves empty/wrong selectors, unsafe ingress drift, a missing policy,
  an added sixth, a namespace move, a foreign policy kind and a renamed
  `containerPort` are all rejected. `argocd-applicationset-controller` is
  deliberately unpoliced — the chart gates its policy on
  `applicationSet.{metrics,ingress,httproute}`, none of which the base enables,
  and an emitted policy would default-deny the webhook receiver.
- **P** — the module's Day-0 `argocd_chart_version` default equals the
  steady-state `chart.lock.yaml` version.

The name-scoped invariants (I3–I5) each run behind a **presence anchor**: a
negative assertion selecting a ConfigMap by name passes vacuously if the chart
renames or drops it, so the gate first requires exactly one such ConfigMap and
exits with a distinct render-shape code when that fails. I1/I2 need no anchor —
they sweep every document.

Beyond the shipped-values invariants, the gate also builds the worked consumer
overlay `kubernetes/examples/argocd-consumer-sso/` against an **unpatched
control build** and asserts the documented SSO wiring still applies: a merged
`url`, a parseable `oidc.config`, a non-empty `policy.csv`, no base-shipped
`.data` key lost to the patch, and `kubeconform -strict` on the result. The
control is what makes those assertions evidence rather than restatements. See
[argocd-sso-contract](argocd-sso-contract.md).

Consumer `argocd_values_override` input is out of scope — base CI cannot gate
what a consumer boots; consumer-cluster admission policy owns that.

## CI mapping: `gitops-validate.yml`

The workflow runs on every PR and on pushes to `main`, with these jobs:

| Job | What it runs |
| --- | --- |
| `validate` | Tool-version drift check (workflow env vs `.tool-versions` for kustomize, conftest, kubeconform, helm, yq) → pinned tool installs → `verify-rendered.sh` (drift gate) → `check-argocd-substrate-invariants.sh` → NetworkPolicy gate bite-check → Cilium reference-values schema check → discovery → safe render → **renderable-set fence** (rendered base-component set must equal the frozen `.ci-renderable-components.txt`) → kubeconform → `run_conftest.sh`; uploads `.work/` diagnostics on failure. |
| `hardware-features-check` | Layer-C registry schema lint (`scripts/lint-hardware-features.sh`), provisioning-catalog reference check, **cluster.yaml schema lint** (`scripts/lint-cluster-yaml.sh` against `schemas/cluster.schema.json`, targeting `cluster.yaml.example` and the module's worked example `tofu/modules/talos-cluster/examples/complete/cluster.yaml`), and a **red-green fixture step**: `schemas/fixtures/cluster.invalid.yaml` must be rejected with exit 1 specifically — exit 0 (fixture passed) and exit 2 (toolchain error, no schema verdict) both fail, so a broken linter cannot pass vacuously. |
| `reuse-compliance` | REUSE 3.3 lint — every file carries SPDX metadata; `_rendered/` upstream-chart output is marked `LicenseRef-UpstreamHelm`. |
| `secret-scan` | gitleaks over the full history with the pinned shared `.gitleaks.toml` — the server-side backstop against local `--no-verify` bypass. |
| `oci-allowlist-check` | Same fail-closed tarball diff as `task supply-chain:oci-allowlist`. |
| `shellcheck` | `shellcheck -S warning` over all tracked `*.sh`. |

The CI `validate` job and the local `task gitops:validate` differ in
composition:

- CI additionally runs the rendered-manifests drift gate and the
  renderable-set fence (locally those are `task gitops:verify-rendered` and
  not mirrored, respectively).
- The SOPS negative gate (`scripts/verify_sops_files.sh`) runs ONLY in the
  local task — no CI step invokes it (consistent with the base shipping no
  `*.sops.yaml`; the consumer-side gate is where it bites).
- Ordering differs without behavioral effect: CI runs the substrate invariants,
  NetworkPolicy bite-check and Cilium reference-values check before discovery,
  then kubeconform before conftest. The local task renders first, runs conftest
  before kubeconform, and puts those three checks after both validators.

## Related concepts

- [Task runner surface](tasks.md) — the `gitops:*` task definitions.
- [Namespace ownership + rendered manifests](../decisions/0002-namespace-ownership-rendered-manifests.md)
  — why one Application owns each namespace in the rendered model.
- [Shared render artifact](../decisions/0005-shared-render-artifact.md) —
  the decision record behind the shared render pipeline.
- [cluster.yaml reference](cluster-yaml.md) — the schema the CI
  schema-lint steps enforce.
