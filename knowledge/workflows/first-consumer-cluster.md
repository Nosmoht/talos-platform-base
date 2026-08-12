---
type: workflow
title: First Consumer Cluster
description: End-to-end walk-through from verifying a published base release to a reconciling App-of-Apps root on a freshly provisioned Talos cluster.
tags: [bootstrap, consumer, day-zero]
timestamp: 2026-08-12
sources:
  - README.md
  - Taskfile.yml
  - cluster.yaml.example
  - tofu/modules/talos-cluster/examples/complete/main.tf
  - tofu/modules/talos-cluster/examples/complete/variables.tf
  - tofu/modules/talos-cluster/examples/complete/cluster.yaml
  - tofu/modules/talos-cluster/outputs.tf
  - .github/workflows/oci-publish.yml
  - kubernetes/bootstrap/argocd/root-application.yaml.tmpl
  - kubernetes/bootstrap/argocd/root-project.yaml.tmpl
---

# First Consumer Cluster

This walk-through stands up a first consumer cluster from the base: verify a
published release, vendor it, declare the cluster in `cluster.yaml`, provision
Talos + Cilium + ArgoCD through the `tofu/modules/talos-cluster` module, and
seed the App-of-Apps root that hands the cluster over to GitOps. The base is
not a runnable cluster — everything cluster-specific (identity, node IPs,
secrets, overlays) lives in your consumer repo.

Sequence:

1. Verify the release (fail-closed) — [verify-release](./verify-release.md).
2. Vendor the artifact via `oras pull` into `vendor/base/`.
3. Seed and fill `cluster.yaml` (`task cluster:init-yaml`).
4. Write a thin OpenTofu root over `cluster.yaml` and `tofu apply`.
5. Seed the App-of-Apps root (`task bootstrap:argocd`).
6. Let ArgoCD reconcile your overlay; run sanity checks.

## Prerequisites

- `cosign`, `oras`, and `jq` for release verification and vendoring.
- `tofu` (OpenTofu) for cluster provisioning.
- `task` (go-task) — the repo's single runner; `yq`, `envsubst`, and `kubectl`
  are invoked by the `bootstrap:*` tasks.
- A consumer cluster repo (git) that ArgoCD will reconcile, and a checkout of
  this base at the pinned tag for the `task` targets and bootstrap templates.

## Step 1 — Verify the release

Every tagged artifact is cosign-signed (keyless OIDC), carries SLSA build
provenance, and a CycloneDX SBOM attestation. Run the full fail-closed recipe
in [verify-release](./verify-release.md) before pulling anything. Minimum
signature gate:

```bash
TAG=v1.0.0
cosign verify \
  --certificate-identity-regexp \
    "^https://github.com/Nosmoht/talos-platform-base/\\.github/workflows/oci-publish\\.yml@refs/tags/v[0-9]+\\.[0-9]+\\.[0-9]+$" \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  "ghcr.io/nosmoht/talos-platform-base:${TAG}"
```

If any verification step fails: do not vendor.

## Step 2 — Vendor the base

The publish workflow pushes two OCI layers per tag: the release tarball
`talos-platform-base-<tag>.tar.gz` and `checksums.txt`. Pull them into the
consumer repo's gitignored `vendor/base/` tree, check the checksum, extract:

```bash
oras pull "ghcr.io/nosmoht/talos-platform-base:${TAG}" --output vendor/base/
(cd vendor/base && sha256sum -c checksums.txt)
tar -xzf "vendor/base/talos-platform-base-${TAG}.tar.gz" -C vendor/base/
```

Record the pinned tag in the consumer repo (the `.base-version` convention) so
every re-vendor and CI verification runs against the same immutable release.

Tarball membership is allowlist-driven (fail-closed) by
`.ci-oci-tarball-include.txt`: the `tofu/modules/talos-cluster` module tree
(with its `helm/` values floor and the `manifests/kubelet-csr-approver.yaml` seed),
the reference Cilium values under `kubernetes/bootstrap/cilium/`, and the
Layer-C hardware-features vocabulary (`platform-hardware-features.yaml` +
`schemas/hardware-features.schema.json`). The task runner (`Taskfile.yml`),
`cluster.yaml.example`, and the ArgoCD bootstrap templates are repo files —
run steps 3 and 5 from the base checkout at the same pinned tag.

## Step 3 — Seed the cluster Source-of-Truth

```bash
task cluster:init-yaml   # copies cluster.yaml.example -> cluster.yaml if absent
"$EDITOR" cluster.yaml
```

`cluster.yaml` is the declarative cluster definition — OpenTofu is the
executor, not the SoT (see [cluster-yaml reference](../reference/cluster-yaml.md)
for the full schema and [decision 0007](../decisions/0007-cluster-yaml-sot.md)).
Two consumers read it:

- `task bootstrap:argocd` reads only the bootstrap identity:
  `.cluster.name`, `.cluster.overlay`, `.cluster.target_revision`, `.repo.url`.
- The OpenTofu root reads the full definition: endpoint, pod/service CIDR,
  dual-stack, Talos/Kubernetes versions, `images` (per-image architecture,
  CPU vendor, baseline extensions, optional boot `extra_kernel_args`, optional
  SBC overlay), `hardware-capabilities`, `nodes`, machine-config patch tiers,
  and the `substrate` block (Cilium + ArgoCD knobs).

Secrets are never in this file — it has no slot for them. `sops_age_key` and
`cilium_ipsec_key` are supplied via `TF_VAR_*` / a gitignored tfvars / SOPS.
The file is gitignored in the base; consumer repos commit it per their own
convention.

## Step 4 — The consumer OpenTofu root

Your tofu root is out-of-repo by design. Its canonical shape is
`tofu/modules/talos-cluster/examples/complete/`: a thin `yamldecode` shim that
maps `cluster.yaml` onto the module's typed interface, roughly:

```hcl
locals {
  cfg = yamldecode(file("${path.module}/cluster.yaml"))
}

module "cluster" {
  source           = "./vendor/base/tofu/modules/talos-cluster"
  cluster_name     = local.cfg.cluster.name
  cluster_endpoint = local.cfg.cluster.endpoint
  # ... full mapping per examples/complete/main.tf ...
  sops_age_key     = var.sops_age_key     # secret — tfvar/env, never cluster.yaml
  cilium_ipsec_key = var.cilium_ipsec_key # secret — tfvar/env, never cluster.yaml
}
```

Contract points (from `examples/complete` and the module interface):

- Structured YAML `config_patches` from `cluster.yaml` are re-encoded to YAML
  strings via `yamlencode` — the module takes patch strings.
- `sops_age_key` is required when `deploy_argocd = true` (the default); the
  module's precondition rejects anything not starting with
  `AGE-SECRET-KEY-1`. Supply it via `TF_VAR_sops_age_key`.
- `cilium_ipsec_key` is needed only for `substrate.cilium.encryption.type:
  ipsec`.
- The example is a `tofu validate`/`plan` fixture with RFC5737 documentation
  IPs and no backend; a real root additionally configures an encrypted state
  backend and real cluster identity.

Then provision:

```bash
tofu init
tofu plan
tofu apply
```

`tofu apply` generates machine secrets, composes one Image-Factory installer
per node (content-hash-deduped across identical nodes), applies per-node
machine config with `cni: none` forced (Flannel cannot come back via a caller
patch), bootstraps the cluster, seeds Cilium and ArgoCD as create-only
controlplane `inlineManifest`s, applies the ArgoCD CRDs server-side via
`kubectl`, and blocks until the cluster health gate passes. The sensitive
outputs `kubeconfig` and `talosconfig` are only released once healthy. See
`tofu/modules/talos-cluster/README.md` for the interface tables and
[day-zero-bootstrap](../architecture/day-zero-bootstrap.md) for the layered
bring-up model.

## Step 5 — Seed the App-of-Apps root

The module deliberately does not deliver the consumer-identity root. Seed it
after `tofu apply` completes:

```bash
task bootstrap:argocd            # or: task bootstrap:argocd ENV=other.yaml
```

What the task does (all in `Taskfile.yml`):

- Renders `kubernetes/bootstrap/argocd/root-project.yaml.tmpl` and
  `root-application.yaml.tmpl` via `envsubst` into
  `kubernetes/bootstrap/argocd/_out/`, substituting `CLUSTER_NAME`,
  `REPO_URL`, `OVERLAY`, `TARGET_REVISION` from `cluster.yaml` (values
  containing `$` are rejected as envsubst-unsafe).
- Waits for both ArgoCD root CRDs (`applications.argoproj.io`,
  `appprojects.argoproj.io`) to exist and become `Established`, then for
  `deployment/argocd-server` in `argocd` to be available.
- `kubectl apply`s the rendered root AppProject and root Application — the
  documented direct-apply exception for `kubernetes/bootstrap/` content.

A persistent CRD `NotFound` means the module's CRD step did not finish;
recover with `tofu apply -replace=null_resource.argocd_crds[0]`.

## Step 6 — The root App-of-Apps takes over

The seeded pair is intentionally minimal:

- AppProject `root-bootstrap`: source restricted to your `repo.url`,
  destination restricted to the `argocd` namespace, cluster-scope whitelist of
  `Namespace` only, namespaced whitelist of `AppProject` + `Application`.
- Application `root`: reconciles `kubernetes/overlays/<overlay>` of your
  consumer repo at `<target_revision>` with automated sync
  (`prune: true`, `selfHeal: true`, `ServerSideApply=true`).

Your overlay directory is where all further Applications live. Day-2
consumption of the base by those Applications uses ArgoCD Multi-Source
Applications — `spec.sources[base, cluster]` pinning a base tag as a
`ref: base` values source alongside your cluster repo.

## Step 7 — Sanity checks

```bash
tofu output cluster_health              # "healthy (...)" once the module gate passed
task bootstrap:argocd-password          # initial admin password — rotate after first login
kubectl -n argocd get applications.argoproj.io root
```

The `root` Application should report `Synced`/`Healthy` once your overlay
renders cleanly. From here on, never `kubectl apply` ArgoCD-managed resources
— commit to git and let ArgoCD reconcile.

## Related

- [verify-release](./verify-release.md) — the full fail-closed verification recipe.
- [cluster-yaml](../reference/cluster-yaml.md) — the SoT schema.
- `tofu/modules/talos-cluster/README.md` — module interface and outputs;
  `openspec/specs/module-interface-contract/` for the normative requirements.
- [day-zero-bootstrap](../architecture/day-zero-bootstrap.md) — the layered bring-up model.
- [substrate](../architecture/substrate.md) — what is (and is not) in the base.
