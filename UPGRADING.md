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

## `v0.4.0` (forthcoming) — PNI policy rename

**Type:** MINOR (consumer-visible breaking name change in a Kubernetes
resource name; spec semantics unchanged)
**Breaking?** yes, for any artifact that references the policy by its
`metadata.name`

#### Breaking changes (consumer action required)

- `ClusterPolicy/pni-contract-audit` is renamed to
  `ClusterPolicy/pni-contract-enforce`. The new name matches both the
  filename (`kyverno-clusterpolicy-pni-contract-enforce.yaml`) and the
  policy's behaviour (`spec.validationFailureAction: Enforce`). Rule
  names (`require-interface-version`, `require-network-profile`) and
  validation messages are unchanged.
- Consumers must update any of the following that reference the old
  name:
  - PolicyReport queries / alerts (e.g. Grafana dashboards filtering
    on `policy="pni-contract-audit"`)
  - `metadata.labels` or `metadata.annotations` that name the policy
  - `argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource` or
    similar resource selectors keyed by the old name
  - Documentation links / cookbook snippets

#### Migration on a live cluster

PolicyReports keyed on the old `policy="pni-contract-audit"` will be
GC'd by Kyverno when the renamed policy is applied (Kyverno emits a
new PolicyReport for the new resource UID). Brief gap in
PolicyReport continuity during the cutover — expected.

```bash
# Before merging the v0.4.0 bump:
kubectl get clusterpolicy pni-contract-audit -o yaml > /tmp/pre-rename.yaml

# After merging + ArgoCD reconcile:
kubectl get clusterpolicy pni-contract-enforce -o yaml | diff /tmp/pre-rename.yaml -
# Expected diff: metadata.name only, plus new UID / resourceVersion
```

#### Why the rename

The policy was authored as fail-closed enforcement
(`validationFailureAction: Enforce`) but its `metadata.name` carried
an `-audit` suffix from a prior refactor. The mismatch caused two
class-of-error incidents during consumer onboarding (operators
assuming "audit" meant non-blocking, then surprised when admission
denied namespace creation). The rename aligns name, filename, and
behaviour. No spec change.

#### Validation steps after upgrade

1. `make validate-gitops` in consumer repo passes.
2. `kubectl get clusterpolicy pni-contract-enforce` returns one
   resource with `ADMISSION=true BACKGROUND=true READY=True`.
3. `kubectl get clusterpolicy pni-contract-audit` returns NotFound.
4. `kubectl get policyreport -A -l policy.kyverno.io/policy-name=pni-contract-enforce`
   returns reports keyed on the new name.

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
