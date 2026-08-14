## Why

`data.helm_template.argocd_crds` renders the argo-cd chart with **no values
block**, and `null_resource.argocd_crds` applied that entire render with
`kubectl apply --server-side --force-conflicts` after the health gate. Measured
against the pinned chart, the render carries twelve kinds — `ServiceAccount`,
`ConfigMap`, `ClusterRole`, `ClusterRoleBinding`, `Role`, `RoleBinding`,
`Service`, `Deployment`, `StatefulSet`, `Job`, `Secret` alongside the CRDs. So
the apply:

- delivered a bundled `argocd-dex-server` and `server.dex.server*` cmd-params on
  every provisioned cluster, making substrate invariants I1 and I2 false at
  runtime while `scripts/check-argocd-substrate-invariants.sh` stayed green (it
  reads the two values files, which this path does not use);
- overwrote the seed's own `server.insecure` and `kustomize.buildOptions` with
  chart defaults;
- reset `argocd-rbac-cm` to chart defaults, and `--force-conflicts` meant it took
  field-manager ownership rather than erroring.

Its trigger set includes `kubernetes_version`, so this is not a one-time Day-0
event — a routine Kubernetes upgrade re-fires it. The last consequence is the
load-bearing one: `argocd-rbac-cm` is where a consumer's access policy lives once
the base stops shipping an RBAC binding, so leaving a scheduled `tofu apply` able
to reset it would convert a cosmetic defect into an outage primitive.

Separately, the shipped seed values set neither `configs.cm.url` nor
`global.domain`, so the seed's `argocd-cm` carried the chart's placeholder
hostname. Argo CD documents `url` as required for SSO and derives the OIDC
redirect URI from it, so a placeholder fails at the identity provider rather than
in the cluster.

## What Changes

- `main.tf` projects the render down to `CustomResourceDefinition` documents
  **before** the freeze, so the frozen bytes, the trigger hash and the applied
  file are the same thing and the property stays visible at plan time. A
  precondition on the freeze rejects a projection yielding fewer than three
  documents.
- The apply drops `--force-conflicts`. Nothing else co-owns the three CRDs, so a
  conflict there is a real signal.
- `helm/argocd-values.yaml` sets `configs.cm.url: ""`, which wins the chart's
  merge and drops the key from `argocd-cm` entirely.
- New output `argocd_day0_apply_kinds` exposes the surviving kinds as the binding
  point for the new `tests/argocd-crd-scope.tftest.hcl` — the frozen render's
  output is unknown until apply and cannot be asserted in a plan-only test.
- `scripts/check-argocd-substrate-invariants.sh` gains **I3**: the seed render's
  `argocd-cm` carries no `url` key. Scoped to the seed path; it extends to the
  steady-state render when the operator identity is removed there.
- `scripts/check-render-determinism.sh` gains a second accepted capture shape —
  the live render may be referenced once inside a `locals` block whose value the
  freeze captures. The #123 property is unchanged: one live read, every
  apply-path consumer through the freeze. Both directions are bite-checked.
- Comment and doc corrections where the module claimed SSO/RBAC arrive "in the
  steady state via ArgoCD self-management": they are a consumer-overlay contract,
  and `argocd_values_override` is seed-only.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `argocd-module-seed` — the post-health apply becomes CRD-only, and the seed
  gains the no-placeholder-url requirement.
- `module-interface-contract` — the audit-output set gains
  `argocd_day0_apply_kinds`.

`cluster-bootstrap-lifecycle` owns `main.tf` as a primary source and is touched,
but none of its requirements change: it describes the machine-secrets →
config-apply → bootstrap → credentials → health-gate flow, and the ArgoCD apply
is owned descriptively by `argocd-module-seed`. Only its Purpose pointer is
corrected, so it carries no delta.

## Impact

- **Specs:** `argocd-module-seed` (modified), `module-interface-contract`
  (modified), `cluster-bootstrap-lifecycle` (Purpose pointer only).
- **Code:** `tofu/modules/talos-cluster/main.tf`, `helm/argocd-values.yaml`,
  `variables.tf`, `outputs.tf`, `README.md`, new
  `tests/argocd-crd-scope.tftest.hcl`;
  `scripts/check-argocd-substrate-invariants.sh`,
  `scripts/check-render-determinism.sh`.
- **Gates:** `tofu-validate` runs `task tofu:ci`, which carries
  `check-render-determinism` (extended here) and `check:readme-parity` (the new
  output needs its README row). `tofu-test` runs the new projection test.
  `validate` runs `check-argocd-substrate-invariants.sh` with I3. `docs-lint`
  (required) runs `spec:check-staleness`, which fires on `main.tf`,
  `helm/argocd-values.yaml`, `variables.tf` and `outputs.tf`.
- **Docs:** `knowledge/decisions/0025-argocd-crd-apply-scope.md` (new), a dated
  correction on `0024-argocd-substrate-relocation.md`'s sole-field-manager-owner
  driver, `knowledge/architecture/day-zero-bootstrap.md` and
  `knowledge/reference/manifest-pipeline.md` (both re-verified and timestamped),
  `knowledge/log.md`, `CHANGELOG.md`.
- **Consumers:** existing clusters are **not** repaired retroactively — `kubectl`
  stays a recorded field manager on the ConfigMaps it already touched. This stops
  future applies from re-taking them.
