# Rendered Manifests Pipeline

This base produces fully-rendered Kubernetes YAML for every Helm-based
infrastructure component. The rendered output is committed to git and
shipped via the OCI artifact (`ghcr.io/nosmoht/talos-platform-base:<tag>`).
Consumer cluster repos use the rendered output as the basis for ArgoCD
`directory`-source applications — ArgoCD does not run helm or kustomize
at sync time.

This is the [Rendered Manifests Pattern][akuity-rmp] (Akuity, KubeCon EU
2024). It eliminates render-time drift between developer machines and
ArgoCD, surfaces all changes as readable git diffs, and removes the need
for ArgoCD repo-server plugins.

[akuity-rmp]: https://akuity.io/blog/the-rendered-manifests-pattern

## Three stages

```
Stage 1 — helm template          → .render-stage1/<comp>.yaml   (gitignored)
Stage 2 — kustomize build        → _rendered/{manifests,crds}.yaml  (committed)
Stage 3 — consumer render        → consumer repo, with cluster-locals (separate)
```

**Stage 1** runs `helm template` against a chart pinned by `chart.lock.yaml`,
parameterised by the component's `values.yaml`. The values file holds
**only repo-wide defaults** — security context, resource requests/limits,
RBAC, capability labels. It does not hold cluster-specific values
(those live in consumer overlays).

**Stage 2** runs `kustomize build` against `_rendered-overlay/`, which
references the Stage-1 output and applies platform-base standard patches
(common labels, Kyverno-relevant annotations, PNI capability metadata).
The Stage-2 output is split into `_rendered/manifests.yaml` (everything
except CRDs) and `_rendered/crds.yaml` (CRDs only) so consumer-side
ArgoCD can deploy them as separate Applications with `sync-wave -5` for
CRDs and wave 0 for the controller.

**Stage 3** lives in the consumer cluster repo. The consumer pulls the
OCI artifact, applies its own thin Kustomize layer for cluster-locals
(pod CIDR, k8sServiceHost, external DNS domain, storage pool names),
and commits the final rendered output. ArgoCD targets the consumer
repo's rendered tree only.

## chart.lock.yaml schema

Every Helm-based component under `kubernetes/base/infrastructure/<comp>/`
has a `chart.lock.yaml`:

```yaml
chart:
  repo: https://charts.jetstack.io   # HTTP repo or oci://... URL
  name: cert-manager
  version: v1.19.2
  tgz_sha256: <hex>                  # required after first render; verified on every render
release:
  name: cert-manager
  namespace: cert-manager
  includeCRDs: true                  # default true; pass --include-crds to helm
values: values.yaml                  # default; relative path to component dir
```

The `tgz_sha256` field is the integrity pin: every render verifies the
pulled chart tarball against this digest. A mismatch means either the
upstream chart was republished under the same version (a security event
worth investigating) or the pin needs updating.

## Workflows

### Add a new component to the pipeline

```bash
# 1. Discover the chart digest:
make chart-pull REPO=https://charts.jetstack.io NAME=cert-manager VERSION=v1.19.2

# 2. Create chart.lock.yaml using the printed values.

# 3. Create _rendered-overlay/kustomization.yaml referencing
#    ../.render-stage1/<comp>.yaml plus any platform-base patches.

# 4. Render:
make render-component COMPONENT=cert-manager

# 5. Commit _rendered/manifests.yaml + _rendered/crds.yaml + chart.lock.yaml.
```

### Bump a chart version

```bash
# 1. Re-pull and update the digest:
make chart-pull REPO=<repo> NAME=<name> VERSION=<new-version>
# Update chart.lock.yaml: version + tgz_sha256.

# 2. Re-render:
make render-component COMPONENT=<name>

# 3. Review the manifest diff carefully. Helm chart bumps can change
#    field names, default values, or add/remove resources.

# 4. Commit. The PR diff is the truth.
```

### Verify the committed render is reproducible

```bash
make verify-rendered
```

This re-renders every component into a tmpdir and diffs against the
committed `_rendered/` tree. Any drift fails the build. CI runs this
on every PR.

## Determinism

`helm template` is not deterministic across helm versions (output
ordering, `tpl` parsing edge cases, `randAlphaNum` without seed). The
pipeline mitigates this with:

- **Pinned helm version** in `.tool-versions`, enforced by
  `make verify-tools` and the CI drift-check.
- **Pinned chart digest** in `chart.lock.yaml.tgz_sha256`.
- **Pinned kustomize version** likewise.
- **`make verify-rendered` gate** in CI catches any remaining drift.

## Layout per component

```
kubernetes/base/infrastructure/<comp>/
├── chart.lock.yaml             # pin spec
├── values.yaml                 # repo-wide defaults (Stage-1 input)
├── kustomization.yaml          # consumed by validate-gitops; references _rendered/
├── namespace.yaml              # PNI labels, PSA labels
├── _rendered-overlay/          # Stage-2 input
│   ├── kustomization.yaml      # references ../.render-stage1/<comp>.yaml + patches
│   └── patches/*.yaml          # platform-base standard patches
├── .render-stage1/             # gitignored — Stage-1 output (intermediate)
│   └── <comp>.yaml
└── _rendered/                  # committed — Stage-2 output (OCI payload)
    ├── manifests.yaml          # everything except CRDs
    └── crds.yaml               # CRDs only (consumed by *-crds ArgoCD App)
```

## Why CRDs are split out

Consumer-side ArgoCD deploys each component as **two Applications**:
`<comp>-crds` at sync-wave -5 with `Prune=false` and `Replace=false`,
and `<comp>` at wave 0. This avoids the same-wave race between CRD
apply and CR apply, and lets large CRDs (Cilium, Prometheus-operator)
be deployed with `ServerSideApply=true` to bypass the 256 KiB
`last-applied-configuration` annotation limit.

## Tooling versions

All rendering tools are pinned in `.tool-versions`:

- `helm` — Stage-1 templater
- `kustomize` — Stage-2 builder
- `oras` — OCI artifact push (`oci-publish.yml`)
- `cosign` — signature verification

`make verify-tools` confirms the local installation matches; CI fails
on drift between `.tool-versions` and workflow env vars.

## See also

- `.work/rendered-manifests-migration/plan-v2.md` — full migration plan
- `docs/oci-artifact-verification.md` — consumer-side trust chain
  (cosign keyless OIDC + SLSA provenance)
