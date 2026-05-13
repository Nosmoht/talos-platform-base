# PNI Cookbook — Concrete Recipes

**Audience:** authors of consumer-cluster manifests and base producers.
**Companion docs:** [Architecture][arch] · [Capability Reference][ref] · [ADR][adr]

[arch]: ./capability-architecture.md
[ref]: ./capability-reference.md
[adr]: ./adr-capability-producer-consumer-symmetry.md

These are how-to recipes. For the *why*, read the [architecture
document][arch] first; for the *what each capability does*, read the
[capability reference][ref].

## 1. Consumer recipes

### 1.1 Consume a non-instanced capability

Goal: my workload in namespace `my-app` needs to be scraped by
Prometheus.

```yaml
# my-app/namespace.yaml
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

```yaml
# my-app/deployment.yaml — pod template
spec:
  template:
    metadata:
      labels:
        platform.io/capability-consumer.monitoring-scrape: "true"
```

That is the entire wiring. The `ccnp-pni-monitoring-scrape-consumer-egress`
CCNP grants Prometheus pod → `my-app` namespace at the moment both
labels appear.

### 1.2 Consume an instanced capability

Goal: my workload needs Postgres cluster `team-foo` and Vault mount
`team-foo`.

```yaml
# my-app/namespace.yaml
metadata:
  labels:
    platform.io/network-interface-version: v1
    platform.io/network-profile: managed
    platform.io/consume.cnpg-postgres.team-foo: "true"
    platform.io/consume.vault-secrets.team-foo: "true"
```

```yaml
# my-app/deployment.yaml — pod template
spec:
  template:
    metadata:
      labels:
        platform.io/capability-consumer.cnpg-postgres.team-foo: "true"
        platform.io/capability-consumer.vault-secrets.team-foo: "true"
```

The audit-mode policy `pni-instanced-suffix-required-audit` would
emit a PolicyReport entry if you wrote `consume.cnpg-postgres` without
the `.team-foo` suffix. Per-instance L4 CCNPs are created by the
**consumer overlay** that deploys the `Cluster` CR (not by this base).

### 1.3 Look up which capabilities exist

```bash
yq '.data."capabilities.yaml" | from_yaml | .capabilities[] | .id' \
  kubernetes/base/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml
```

Or read the auto-generated [capability reference][ref].

### 1.4 Verify your usage against deprecation/sunset

Run inside your consumer cluster repo (assuming the base is vendored to
`vendor/base/`):

```bash
vendor/base/scripts/capability-deprecation-scan.sh kubernetes/
```

The script reads `vendor/base/.../capability-registry-configmap.yaml`,
greps your tree for `consume.<id>` usages, and prints any entries with
`deprecated: true`. Wire it into your PR CI to catch sunset breakage
before the OCI tag flip.

## 2. Producer recipes (base components only)

> Producers are **base-internal**. Tenant-owned namespaces cannot set
> reserved keys; Kyverno denies it. The recipes below are for
> contributors adding a new component to `kubernetes/base/infrastructure/`.

### 2.1 New component — single capability

Goal: ship a metrics-server-style component that provides one
capability (`hpa-metrics`).

**Step 1.** Component layout:

```text
kubernetes/base/infrastructure/<component>/
├── application.yaml
├── kustomization.yaml
├── namespace.yaml      # provide.<cap> trust anchor
└── values.yaml         # podLabels.capability-provider + service.annotations
```

**Step 2.** `namespace.yaml` — trust anchor:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: <component>
  labels:
    app.kubernetes.io/name: <component>
    app.kubernetes.io/managed-by: argocd
    platform.io/provide.hpa-metrics: "true"
```

**Step 3.** Helm `values.yaml`:

```yaml
podLabels:
  platform.io/capability-provider.hpa-metrics: "true"
service:
  annotations:
    platform.io/capability-endpoint.hpa-metrics: "https"
    platform.io/capability-protocol.hpa-metrics: "k8s-metrics-api-v1beta1"
```

**Step 4.** No CCNP — the consumer's egress CCNP already exists for the
capability; the producer side is selected via the
`capability-provider.<cap>` label.

### 2.2 New component — multiple capabilities (cert-manager pattern)

cert-manager provides both `tls-issuance` (webhook) and
`monitoring-scrape` (controller + webhook). Both go on the namespace,
and the per-pod labels split by subchart:

```yaml
# namespace.yaml
metadata:
  labels:
    platform.io/provide.tls-issuance: "true"
    platform.io/provide.monitoring-scrape: "true"
```

```yaml
# values.yaml
podLabels:
  platform.io/capability-provider.monitoring-scrape: "true"
webhook:
  podLabels:
    platform.io/capability-provider.tls-issuance: "true"
    platform.io/capability-provider.monitoring-scrape: "true"
  serviceAnnotations:
    platform.io/capability-endpoint.tls-issuance: "https"
    platform.io/capability-protocol.tls-issuance: "cert-manager-webhook-v1"
```

### 2.3 Chart does not expose `podLabels`

Some upstream charts (`vault-config-operator`) hardcode pod labels and
do not expose a `podLabels` value. Solve with a kustomize strategic-merge
patch:

```yaml
# kustomization.yaml
patches:
  - target:
      kind: Deployment
      name: vault-config-operator-controller-manager
    patch: |
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: vault-config-operator-controller-manager
      spec:
        template:
          metadata:
            labels:
              platform.io/capability-provider.admission-webhook: "true"
              platform.io/capability-provider.monitoring-scrape: "true"
```

### 2.4 Component must NOT live in a system namespace

If the producer chart's default namespace is `kube-system` or another
shared system namespace, **relocate** before adding capability labels.
Trust is namespace-anchored: a system namespace cannot carry
`provide.<cap>` without violating the base's "no exemptions" rule.

`metrics-server` was relocated `kube-system → metrics-server` for this
reason; the override goes in the component's `kustomization.yaml`:

```yaml
namespace: metrics-server
patches:
  - target:
      kind: Deployment
    patch: |-
      - op: replace
        path: /metadata/namespace
        value: metrics-server
```

### 2.5 Adding a new capability to the registry

Registry edits are the highest-impact change in the base. Procedure:

1. Edit `kubernetes/base/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml`.
2. Set required keys: `id`, `stability` (`preview|beta|ga`),
   `instanced` (bool), `implementations` (list — names of base-shipped
   implementing components), `description`.
3. For instanced caps: set `instance_source` (apiVersion/kind whose
   instances drive label suffixes).
4. Run `scripts/render-capability-reference.sh` → updates
   `docs/capability-reference.md` (idempotent; CI fails on diff).
5. Run `make validate-gitops` + `make validate-kyverno-policies`.

### 2.6 Deprecating or renaming a capability

```yaml
- id: old-name
  deprecated: true
  sunset: "<YYYY-MM-DD>"  # 6+ months in the future
  split_into: [new-id-a, new-id-b]   # optional, for splits
  disambiguation: |
    Free-text guide for choosing between the new IDs.
```

CCNPs during the grace window match both legacy and new selectors.
Conftest fails the build at `now > sunset` — PR F (alias removal)
ships automatically.

## 3. Selector recipes (CCNP authors)

### 3.1 Capability-only selector (preferred)

```yaml
endpointSelector:
  matchLabels:
    platform.io/capability-provider.monitoring-scrape: "true"
egress:
  - toEndpoints:
      - matchLabels:
          k8s:io.cilium.k8s.namespace.labels.platform.io/consume.monitoring-scrape: "true"
          k8s:io.cilium.k8s.namespace.labels.platform.io/network-interface-version: "v1"
```

Tool-swap-proof.

### 3.2 Plumbing selector (documented exception)

When no capability fits (`kube-dns`, etc.), keep the tool selector
**and** document why in the file header:

```yaml
# Plumbing — kube-dns is a cluster-singleton with no capability fit.
# Selector retained intentionally; see ADR §"Tool-swap mechanics".
endpointSelector:
  matchLabels:
    k8s-app: kube-dns
```

## 4. Validation recipes

| What | Command |
|---|---|
| All rendering passes | `make validate-gitops` |
| Server-side Kyverno test | `make validate-kyverno-policies` |
| Single component render | `kubectl kustomize --enable-helm kubernetes/base/infrastructure/<comp>/` |
| Regen capability reference | `scripts/render-capability-reference.sh` |
| Lint consume-label usage | `scripts/lint-consume-labels.sh <path>` |
| Scan for deprecated caps | `scripts/capability-deprecation-scan.sh <path>` |

## 5. Anti-patterns (do not do these)

| Anti-pattern | Why bad | Correct form |
|---|---|---|
| `endpointSelector: {app.kubernetes.io/name: prometheus}` | Couples CCNP to tool identity | `capability-consumer.monitoring-scrape` |
| Adding `app.kubernetes.io/component: <tool>` to a central Kyverno whitelist | Central tool registry grows linearly with integrations | Namespace-anchored rule — `provide.<cap>` on the namespace |
| Producer in `kube-system` with `provide.<cap>` exemption | Trust anchor cannot live in a namespace the base doesn't own | Relocate to a dedicated namespace |
| Consumer sets `provide.<cap>` to enable a service | Reserved key; Kyverno-denied | Set `consume.<cap>`; producer side already exists |
| Bare `consume.cnpg-postgres` on a tenant namespace | Audit-mode advisory fires; cross-tenant L4 collapse | Use `.<inst>` suffix |
| Wrap a tool selector in a CCNP for a tool the base doesn't deploy | Speculative coupling — PR D scope-cut rationale | Ship in the consumer overlay that deploys the tool |
