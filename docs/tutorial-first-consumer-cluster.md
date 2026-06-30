# Tutorial — Your First Consumer Cluster

**Audience:** someone new to this base who wants to learn the structure
by following along, not someone deploying a production cluster.
**Time:** ~30 minutes of reading + commands.

This is a [Diátaxis][diataxis] **tutorial**: it teaches by doing. For
the day-zero path from rendered manifests to a live cluster, see the
[day-zero pattern][dayzero]; for the substrate-only scope, see the
[substrate-only base ADR][substrate].

[diataxis]: https://diataxis.fr/
[dayzero]: ./day-zero-pattern.md
[substrate]: ./adr-0004-substrate-only-base.md

## Prerequisites

- `git` ≥ 2.40, `make`, `bash` ≥ 3.2
- `kubectl` ≥ 1.30 with `kubectl-kustomize`
- `kustomize` ≥ 5.x with `--enable-helm` support
- `oras` ≥ 1.2 (`brew install oras` or `go install`)
- `cosign` ≥ 2.x (`brew install cosign`)
- `yq` ≥ 4.x
- A GitHub account with `gh auth login` completed

You do **not** need a live cluster for this tutorial. We will render
manifests, verify the OCI artifact, and stop short of `kubectl apply`.

## What you will build

By the end you will have:

1. A scratch consumer cluster repo that pins this base at a specific
   version.
2. A verified, vendored copy of the base under `vendor/base/`.
3. A rendered Multi-Source view of merged base + consumer manifests.
4. An understanding of where to look next.

## Step 1 — Pin and verify the OCI artifact

Pick the most recent tag. Three lookup options, in order of preference:

```bash
# (a) Browse GHCR in the browser — no auth required for public images:
#     https://github.com/nosmoht/talos-platform-base/pkgs/container/talos-platform-base
#
# (b) Query the public GHCR registry API anonymously (works without any
#     OAuth scope):
TOKEN=$(curl -s "https://ghcr.io/token?scope=repository:nosmoht/talos-platform-base:pull" | jq -r .token)
curl -s -H "Authorization: Bearer ${TOKEN}" \
  https://ghcr.io/v2/nosmoht/talos-platform-base/tags/list \
  | jq -r '.tags[]' | grep -E '^v[0-9]' | sort -V | tail -5
#
# (c) Authenticated `gh` (requires read:packages scope, NOT in gh's
#     default scope set — refresh first):
#       gh auth refresh -h github.com -s read:packages
#       gh api /users/nosmoht/packages/container/talos-platform-base/versions \
#         --jq '.[].metadata.container.tags[]' | sort -V | tail -5

OWNER=nosmoht
TAG=$(curl -s "https://ghcr.io/v2/${OWNER}/talos-platform-base/tags/list" \
        -H "Authorization: Bearer $(curl -s "https://ghcr.io/token?scope=repository:${OWNER}/talos-platform-base:pull" | jq -r .token)" \
      | jq -r '.tags[]' | grep -E '^v[0-9]' | sort -V | tail -1)
echo "Picked TAG=${TAG}"
```

Verify cosign signature + provenance (see
[`oci-artifact-verification.md`](./oci-artifact-verification.md) for
detail):

```bash
cosign verify \
  --certificate-identity-regexp \
    "^https://github.com/${OWNER}/talos-platform-base/\.github/workflows/oci-publish\.yml@refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$" \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  ghcr.io/${OWNER}/talos-platform-base:${TAG}
```

Expected: lines starting `Verification for ghcr.io/...` ending in
`Verified OK`. If verification fails, stop and report — see
[`SECURITY.md`](../SECURITY.md).

## Step 2 — Create a scratch consumer repo

```bash
mkdir -p $HOME/scratch/my-cluster && cd $_
git init -q
echo "${TAG}" > .base-version
mkdir -p kubernetes/cluster/ vendor/
echo "vendor/" >> .gitignore
git add -A && git commit -q -m "chore: bootstrap scratch consumer repo"
```

## Step 3 — Vendor the base

```bash
oras pull "ghcr.io/${OWNER}/talos-platform-base:$(cat .base-version)" \
  --output vendor/base
ls vendor/base/kubernetes/base/infrastructure/
```

You should see the substrate component directory (`argocd/`). (`cert-approver`
ships as a Talos `inlineManifest` seed in the OpenTofu module, not a kustomize
component — adr-0013.) The vendored tree is read-only by convention — do
not edit it. Everything that is not substrate lives in the separate
[`talos-platform-apps`][substrate] catalog, which consumers self-serve
from as signed OCI artifacts.

## Step 4 — Render a single component

```bash
kubectl kustomize --enable-helm \
  vendor/base/kubernetes/base/infrastructure/argocd/ | head -40
```

## Step 5 — Write a tiny consumer manifest

A note on namespaces, before you write any: **platform namespaces are
owned by the platform**. A consumer never authors a Namespace resource
for `argocd` or any other substrate component this base ships under
`vendor/base/kubernetes/base/infrastructure/<component>/` (cert-approver's
namespace is platform-owned too, seeded by its Talos `inlineManifest`). Each
per-component Application takes the vendor `namespace.yaml` from its
`_rendered/manifests.yaml` and becomes the sole ArgoCD tracking-id
owner of that namespace. Consumer overlays that declare a duplicate
in a top-level file create a double-tracking conflict that ArgoCD
cannot resolve safely — see
[`adr-0002-namespace-ownership-rendered-manifests.md`](adr-0002-namespace-ownership-rendered-manifests.md)
for the architectural rationale.

What you DO author: namespaces for your own tenant workloads. Below,
a minimal consumer namespace:

```yaml
# kubernetes/cluster/my-app-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-app
  labels:
    app.kubernetes.io/name: my-app
    app.kubernetes.io/managed-by: argocd
```

## Step 6 — Sanity-render the merged view

In a real cluster this is what the ArgoCD Multi-Source Application
would assemble:

```bash
mkdir -p kubernetes/cluster
cat > kubernetes/cluster/kustomization.yaml <<'EOF'
resources:
  - my-app-namespace.yaml
EOF
kubectl kustomize kubernetes/cluster/
```

## What just happened

You have walked through the three operational moments a consumer-cluster
author repeats every time the base bumps a tag:

1. Pin the tag (`.base-version`).
2. Verify cryptographically.
3. Vendor (`oras pull` to `vendor/base/`) and re-render.

## Where to go next

| You want to | Read |
|---|---|
| Why the base ships substrate only | [`adr-0004-substrate-only-base.md`](./adr-0004-substrate-only-base.md) |
| Take the cluster from rendered manifests to a live ArgoCD-reconciled environment | [`day-zero-pattern.md`](./day-zero-pattern.md) |
| Issue lifecycle when you find a bug | [`issue-workflow.md`](./issue-workflow.md) |
| Verify the supply chain in depth | [`oci-artifact-verification.md`](./oci-artifact-verification.md) |
