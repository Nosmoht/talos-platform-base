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

## `v0.5.0` — 2026-05-18 — PNI policy rename + cluster-agnostic refactor + Layer-A validation + per-component READMEs

**Type:** MINOR (consumer-visible breaking name change in a Kubernetes
resource name; spec semantics unchanged)
**Breaking?** yes, for any artifact that references the renamed
`pni-contract-audit` ClusterPolicy by its `metadata.name`. No other
consumer-side action is required for the rest of the v0.5.0 surface
(documentation, validation scripts, READMEs — all internal to the
base; the OCI artifact remains the same shape).

### Note on prior git tags

Git tags `v0.2.0`, `v0.3.0`, `v0.4.0` exist in the repository and
have corresponding OCI artifacts on `ghcr.io`, but were not published
as GitHub Releases. They are usable as pinning targets but are
considered pre-release internal markers; v0.5.0 is the first GitHub
Release after v0.1.0.

### Breaking changes (consumer action required)

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

### Migration on a live cluster

PolicyReports keyed on the old `policy="pni-contract-audit"` will be
GC'd by Kyverno when the renamed policy is applied (Kyverno emits a
new PolicyReport for the new resource UID). Brief gap in
PolicyReport continuity during the cutover — expected.

```bash
# Before merging the v0.5.0 bump:
kubectl get clusterpolicy pni-contract-audit -o yaml > /tmp/pre-rename.yaml

# After merging + ArgoCD reconcile:
kubectl get clusterpolicy pni-contract-enforce -o yaml | diff /tmp/pre-rename.yaml -
# Expected diff: metadata.name only, plus new UID / resourceVersion
```

### Why the rename

The policy was authored as fail-closed enforcement
(`validationFailureAction: Enforce`) but its `metadata.name` carried
an `-audit` suffix from a prior refactor. The mismatch caused two
class-of-error incidents during consumer onboarding (operators
assuming "audit" meant non-blocking, then surprised when admission
denied namespace creation). The rename aligns name, filename, and
behaviour. No spec change.

### New non-breaking surface

- **Layer-A capability-index validation in CI.** The base now ships
  three scripts (`scripts/lint-capability-index.sh`,
  `check-capability-index-refs.sh`, `render-capability-index.sh`) and
  a `capability-index-check` CI job that enforce the Two-Layer
  Capability Architecture invariant. Consumer repos that re-render
  the base inside their own CI will see the new job; no consumer
  manifests are affected.
- **Per-component READMEs.** Each `kubernetes/base/infrastructure/<comp>/`
  directory now ships a README with Purpose / Chart / PNI capabilities /
  Helm-value overrides / Upgrade gotchas. Recommended reading before
  deciding which base components to deploy and which Helm-value
  defaults to override in your consumer overlay.

### Validation steps after upgrade

1. `make validate-gitops` in consumer repo passes.
2. `kubectl get clusterpolicy pni-contract-enforce` returns one
   resource with `ADMISSION=true BACKGROUND=true READY=True`.
3. `kubectl get clusterpolicy pni-contract-audit` returns NotFound.
4. `kubectl get policyreport -A -l policy.kyverno.io/policy-name=pni-contract-enforce`
   returns reports keyed on the new name.

---

## `v0.6.0` (forthcoming) — PNI policy name/behaviour mismatch cleanup

**Type:** MINOR (consumer-visible breaking name change in two Kubernetes
resource names; spec semantics unchanged)
**Breaking?** yes, for any artifact that references the renamed
`pni-capability-validation-audit` or `pni-reserved-labels-audit`
ClusterPolicies by their `metadata.name`. No other consumer-side action
is required — rule names, validation messages, and behaviour are
unchanged.

### Why the rename

`v0.5.0` (#40) fixed the name/behaviour mismatch on
`ClusterPolicy/pni-contract-audit` (named `-audit`, actually
`validationFailureAction: Enforce`) but left two further policies with
the same defect:

| Old `metadata.name` | `spec.validationFailureAction` | New `metadata.name` |
|---|---|---|
| `pni-capability-validation-audit` | `Enforce` | `pni-capability-validation-enforce` |
| `pni-reserved-labels-audit` | `Enforce` | `pni-reserved-labels-enforce` |

The file names (`kyverno-clusterpolicy-pni-*-enforce.yaml`) already
matched the behaviour; only the `metadata.name` field was renamed. Rule
names (`validate-consume-capability-labels`,
`block-reserved-labels-on-tenant-namespaces`, …), validation messages,
and `validationFailureAction: Enforce` semantics are unchanged.

### Breaking changes (consumer action required)

Consumers must update any of the following that reference the old
names:

- PolicyReport queries / alerts (Grafana dashboards filtering on
  `policy="pni-capability-validation-audit"` or
  `policy="pni-reserved-labels-audit"`)
- `metadata.labels` or `metadata.annotations` that name either policy
- `argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource` or
  similar resource selectors keyed by the old names
- Documentation links / cookbook snippets

### Migration on a live cluster

Identical mechanism to the v0.5.0 `pni-contract` rename: Kyverno GCs
the old PolicyReports keyed on the renamed resource UID and emits
fresh ones for the new name. Brief gap in PolicyReport continuity
during cutover — expected.

```bash
# Before merging the v0.6.0 bump:
kubectl get clusterpolicy pni-capability-validation-audit -o yaml > /tmp/pre-cap-rename.yaml
kubectl get clusterpolicy pni-reserved-labels-audit -o yaml > /tmp/pre-rlbl-rename.yaml

# After merging + ArgoCD reconcile:
kubectl get clusterpolicy pni-capability-validation-enforce -o yaml \
  | diff /tmp/pre-cap-rename.yaml -
kubectl get clusterpolicy pni-reserved-labels-enforce -o yaml \
  | diff /tmp/pre-rlbl-rename.yaml -
# Expected diff: metadata.name only, plus new UID / resourceVersion
```

### Validation steps after upgrade

1. `make validate-gitops` in consumer repo passes.
2. `kubectl get clusterpolicy pni-capability-validation-enforce` and
   `kubectl get clusterpolicy pni-reserved-labels-enforce` each return
   one resource with `ADMISSION=true BACKGROUND=true READY=True`.
3. `kubectl get clusterpolicy pni-capability-validation-audit`
   and `kubectl get clusterpolicy pni-reserved-labels-audit` both
   return NotFound.
4. `kubectl get policyreport -A -l policy.kyverno.io/policy-name=pni-capability-validation-enforce`
   and the equivalent for `pni-reserved-labels-enforce` return reports
   keyed on the new names.

### Why this was not folded into v0.5.0

The two policies were missed during the v0.5.0 PR (#40) review.
Discovered during the consumer-side audit of the v0.5.0 rename
(`talos-homelab-cluster#48`). Tracked as #48; this section corresponds
to that issue's resolution.

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
