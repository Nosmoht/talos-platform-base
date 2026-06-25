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
- `server`
- `repoServer`
- `configs`

## Known upgrade gotchas

- A bare `AppProject` (sync-wave -1) must reconcile before any Application (sync-wave 0) that references it.
- The base ships the ArgoCD chart and CRDs but not the root `Application` — consumer repos own that bootstrap.

## See also

- [`docs/rendered-manifests.md`](../../../../docs/rendered-manifests.md) — how this component is rendered into `_rendered/manifests.yaml`
- [`UPGRADING.md`](../../../../UPGRADING.md) — release-to-release migration steps
