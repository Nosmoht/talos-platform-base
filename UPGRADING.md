# Upgrade Guide

For consumer-cluster repos vendoring `talos-platform-base` via OCI.

## How to use this file

- Per-release notes live in [`CHANGELOG.md`](CHANGELOG.md).
- This file documents **cumulative migration steps** for each MAJOR
  bump and any MINOR that requires a manual action.
- Read every section between the version you currently pin and the
  version you want to adopt. Apply in order.
- Always verify the new artifact (cosign + provenance) before vendoring
  — see [`docs/oci-artifact-verification.md`](docs/oci-artifact-verification.md).

## Upgrade workflow (every version)

```bash
# 1. Verify
TAG=v0.2.0; OWNER=nosmoht
cosign verify \
  --certificate-identity-regexp \
    "^https://github.com/${OWNER}/talos-platform-base/\.github/workflows/oci-publish\.yml@refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$" \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  ghcr.io/${OWNER}/talos-platform-base:${TAG}

# 2. Scan your manifests against the NEW registry for deprecated caps
oras pull "ghcr.io/${OWNER}/talos-platform-base:${TAG}" --output /tmp/base-${TAG}
/tmp/base-${TAG}/scripts/capability-deprecation-scan.sh kubernetes/

# 3. Render diff between current and target
kubectl kustomize --enable-helm vendor/base/kubernetes/base/infrastructure/ \
  > /tmp/before.yaml
echo "${TAG}" > .base-version
rm -rf vendor/base && oras pull "ghcr.io/${OWNER}/talos-platform-base:${TAG}" --output vendor/base
kubectl kustomize --enable-helm vendor/base/kubernetes/base/infrastructure/ \
  > /tmp/after.yaml
diff -u /tmp/before.yaml /tmp/after.yaml | less

# 4. Apply consumer-overlay patches for any MAJOR-listed breaking change below.
# 5. Commit, open PR, let ArgoCD reconcile after merge.
```

---

## Pre-`v0.2.0` MINOR releases

### `v0.1.0` (2026-03-XX) — initial public release

Baseline. No upgrade path; cleanroom install.

Capabilities present:

- `monitoring-scrape`, `hpa-metrics`, `tls-issuance`, `gateway-backend`,
  `external-gateway-routes`, `gpu-runtime`, `internet-egress`,
  `controlplane-egress`, `storage-csi`,
  `vault-secrets`, `cnpg-postgres`, `redis-managed`, `rabbitmq-managed`,
  `kafka-managed`, `s3-object`, `admission-webhook-provider`,
  `monitoring-scrape-provider`, `logging-ship`.

`storage-csi` and `monitoring-scrape-provider` are deprecated from day
one in v0.1.0 (see below).

---

## Pending sunsets

These deprecations are scheduled to remove via PR F (alias removal),
which auto-fires when the sunset date passes. PR F bumps the next OCI
tag's **MAJOR** version.

| Capability | Status | Sunset | Replacement |
|---|---|---|---|
| `storage-csi` | deprecated | 2026-11-13 | `block-storage-replicated`, `block-storage-local` |
| `monitoring-scrape-provider` | deprecated | 2026-08-13 | `monitoring-scrape` (folded) |

### Action for consumers

Before the sunset date:

1. Run `scripts/capability-deprecation-scan.sh kubernetes/` in your
   consumer repo CI. Failing the scan means you reference a
   deprecated capability.
2. Migrate `consume.storage-csi` to one of the split capabilities.
   Read [`docs/capability-reference.md`](docs/capability-reference.md)
   §`storage-csi` for the `disambiguation` guide on which split to
   choose.
3. Migrate `consume.monitoring-scrape-provider` to plain
   `consume.monitoring-scrape`.
4. Commit and merge in your consumer repo *before* you adopt the
   PR-F-bearing MAJOR tag.

---

## Template for future MAJOR/MINOR sections

When a new release ships, add a section in the format below:

```markdown
### `vX.Y.Z` (YYYY-MM-DD) — <one-line summary>

**Type:** MAJOR | MINOR | PATCH
**Breaking?** yes | no

#### Breaking changes (consumer action required)

- <bullet> — e.g. "Helm value `loki.write.s3.endpoint` renamed to
  `loki.write.objectStorage.endpoint`. Patch your consumer overlay."

#### New capabilities

- `<cap-id>` — see capability reference

#### Removed capabilities / sunsets fired

- `<cap-id>` — sunset reached, alias removed

#### Validation steps after upgrade

1. `make validate-gitops` in consumer repo
2. `kubectl get policyreport -A` in live cluster — expect no new
   PNI advisories
```

---

## See also

- [`CHANGELOG.md`](CHANGELOG.md) — per-release notes
- [`SECURITY.md`](SECURITY.md) — supported versions
- [`docs/oci-artifact-verification.md`](docs/oci-artifact-verification.md) — verify before vendoring
- [`docs/capability-architecture.md`](docs/capability-architecture.md) §"Backwards compatibility"
