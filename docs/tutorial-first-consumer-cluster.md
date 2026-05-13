# Tutorial — Your First Consumer Cluster

**Audience:** someone new to this base who wants to learn the structure
by following along, not someone deploying a production cluster.
**Time:** ~30 minutes of reading + commands.

This is a [Diátaxis][diataxis] **tutorial**: it teaches by doing. For
reference material, jump to the [capability reference][ref]; for
recipes, the [cookbook][cookbook]; for explanation, the
[architecture doc][arch].

[diataxis]: https://diataxis.fr/
[ref]: ./capability-reference.md
[cookbook]: ./pni-cookbook.md
[arch]: ./capability-architecture.md

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
ls vendor/base/kubernetes/base/infrastructure/ | head
```

You should see the 22 component directories. The vendored tree is
read-only by convention — do not edit it.

## Step 4 — Render a single component

```bash
kubectl kustomize --enable-helm \
  vendor/base/kubernetes/base/infrastructure/cert-manager/ | head -40
```

Note the namespace declares
`platform.io/provide.tls-issuance: "true"` and
`platform.io/provide.monitoring-scrape: "true"` — the
namespace-anchored trust anchors from the [architecture
doc][arch].

## Step 5 — Write a tiny consumer manifest

A consumer namespace that wants Prometheus scraping:

```yaml
# kubernetes/cluster/my-app-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: my-app
  labels:
    app.kubernetes.io/name: my-app
    app.kubernetes.io/managed-by: argocd
    platform.io/network-interface-version: v1
    platform.io/network-profile: managed
    platform.io/consume.monitoring-scrape: "true"
```

No tool names. The consumer never mentions Prometheus by name; the
CCNP shipped by the base selects on
`capability-consumer.monitoring-scrape`.

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

## Step 7 — Check for deprecated capabilities

If your manifests use the registry vocabulary, scan them before each
base-version bump:

```bash
vendor/base/scripts/capability-deprecation-scan.sh kubernetes/
```

Empty output = no consume-labels reference deprecated registry entries.

## What just happened

You have walked through the four operational moments a consumer-cluster
author repeats every time the base bumps a tag:

1. Pin the tag (`.base-version`).
2. Verify cryptographically.
3. Vendor (`oras pull` to `vendor/base/`).
4. Re-render and scan for deprecation.

The consumer never named a tool. That is the entire point of the
capability-first contract.

## Where to go next

| You want to | Read |
|---|---|
| The full label vocabulary | [`pni-cookbook.md`](./pni-cookbook.md) |
| What each capability is for | [`capability-reference.md`](./capability-reference.md) |
| Why the architecture looks this way | [`capability-architecture.md`](./capability-architecture.md) |
| How the registry, policies, and CCNPs interact | [`adr-capability-producer-consumer-symmetry.md`](./adr-capability-producer-consumer-symmetry.md) |
| Issue lifecycle when you find a bug | [`issue-workflow.md`](./issue-workflow.md) |
| Verify the supply chain in depth | [`oci-artifact-verification.md`](./oci-artifact-verification.md) |
