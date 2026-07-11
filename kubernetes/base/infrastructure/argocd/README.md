# `argocd`

**Purpose:** ArgoCD GitOps engine — reconciles every other component in this base from git source via Multi-Source Applications.

## Upstream chart source

- **Chart:** [`argo-cd`](https://argoproj.github.io/argo-helm)
- **Pinned version:** `9.4.5`
- **Lock file:** [`chart.lock.yaml`](./chart.lock.yaml) — includes `tgz_sha256` for reproducible renders.

## Namespace

Deploys into namespace `argocd`. See [`namespace.yaml`](./namespace.yaml) for the full PSA label set.

## Repo-specific Helm-value overrides

Top-level keys in [`values.yaml`](./values.yaml) — anything not listed below uses the upstream chart's default:

- `crds`
- `dex` — `enabled: false` (bundled Dex off; see §Substrate invariants)
- `server`
- `repoServer`
- `configs`

## Known upgrade gotchas

- A bare `AppProject` (sync-wave -1) must reconcile before any Application (sync-wave 0) that references it.
- The base ships the ArgoCD chart and CRDs but not the root `Application` — consumer repos own that bootstrap.

## Substrate invariants

ArgoCD ships through **two render paths** serving different lifecycle phases:

- **Day-0 bootstrap seed** — [`tofu/modules/talos-cluster/helm/argocd-values.yaml`](../../../../tofu/modules/talos-cluster/helm/argocd-values.yaml), rendered by `data.helm_template.argocd` into a Talos `cluster.inlineManifest` (deliberately slim; no kustomize overlay; `include_crds = false`).
- **Steady-state self-management** — [`values.yaml`](./values.yaml), rendered (helm → kustomize) into [`_rendered/manifests.yaml`](./_rendered/manifests.yaml).

Both files are valid and necessary (the slim seed cannot depend on steady-state services). The risk is that values which must stay aligned drift silently because each path independently inherits upstream chart defaults. These **shared invariants** must hold in **both** paths and are gated in CI by [`scripts/check-argocd-substrate-invariants.sh`](../../../../scripts/check-argocd-substrate-invariants.sh) (the executable source of truth; run on every PR and locally via `task gitops:validate`):

| # | Invariant | Why |
|---|---|---|
| **I1** | Neither render produces a bundled-Dex resource — no document carrying the label `app.kubernetes.io/component: dex-server` (nor `metadata.name: argocd-dex-server`). | Consumers wire ArgoCD SSO via an **external** OIDC provider (`configs.cm` `oidc.config`), so the chart-default bundled Dex (`dex.enabled: true`) is an idle, connector-less workload in every cluster — and bloats the Talos inlineManifest in the seed. |
| **I2** | Neither render has **any** ConfigMap with a `.data` key prefixed `server.dex.server`. | These params only exist to point argocd-server at the bundled Dex; with Dex off they are moot and their presence signals drift. The chart emits them in `argocd-cmd-params-cm`, but the gate scans **all** ConfigMaps so a rename cannot evade it. |

**Reading note (I2):** argocd-server legitimately retains `configMapKeyRef` *consumer* env entries naming `server.dex.server*` with `optional: true`. Those are env references, **not** ConfigMap `.data` keys, and are **not** a violation — a naïve `grep server.dex.server` over the render will match them; the gate's structured check does not. Do not "fix" them.

**Scope.** The gate asserts a property of the **base-shipped values** (structural: does the values file disable the bundled Dex), rendered with the pinned chart — not a byte-reproduction of the inlineManifest, and not consumer behaviour. A consumer `var.argocd_values_override` that re-enables Dex is **out of base scope**; consumer-side enforcement is consumer-cluster Kyverno (AGENTS.md §ADR-0009).

**Adding an invariant:** add the assertion to `scripts/check-argocd-substrate-invariants.sh` and a row to this table in the same change.

**Deferred (named, not silently dropped): chart-version parity** between the seed (`argocd_chart_version` default in `tofu/modules/talos-cluster/variables.tf`) and steady-state (`chart.lock.yaml`). Currently maintained by review, not mechanically gated: extracting the HCL default is fragile, and a same-version chart *republish* (changed `tgz_sha256`) would not be caught by a version-string compare. Revisit if a real drift occurs.

## See also

- [`knowledge/reference/manifest-pipeline.md`](../../../../knowledge/reference/manifest-pipeline.md) — how this component is rendered into `_rendered/manifests.yaml`
- [`UPGRADING.md`](../../../../UPGRADING.md) — release-to-release migration steps
