# `cert-manager`

**Purpose:** cert-manager — issues, renews, and revokes X.509 certificates from ClusterIssuers (Vault, ACME, self-signed) for all in-cluster TLS.

## Upstream chart source

- **Chart:** [`cert-manager`](https://charts.jetstack.io)
- **Pinned version:** `v1.19.2`
- **Lock file:** [`chart.lock.yaml`](./chart.lock.yaml) — includes `tgz_sha256` for reproducible renders.

## Namespace

Deploys into namespace `cert-manager`. See [`namespace.yaml`](./namespace.yaml) for the full PSA + PNI label set.

## Declared PNI capabilities

**Provider labels** (on the namespace; see [ADR — Capability Producer/Consumer Symmetry](../../../../docs/adr-capability-producer-consumer-symmetry.md)):

- `platform.io/provide.tls-issuance`
- `platform.io/provide.monitoring-scrape`

**Consumer labels:**

- `platform.io/consume.vault-secrets`
- `platform.io/consume.controlplane-egress`

For the full label vocabulary see [`docs/capability-reference.md`](../../../../docs/capability-reference.md).

## Repo-specific Helm-value overrides

Top-level keys in [`values.yaml`](./values.yaml) — anything not listed below uses the upstream chart's default:

- `crds`
- `podLabels`
- `resources`
- `securityContext`
- `containerSecurityContext`
- `webhook`
- `cainjector`

## Known upgrade gotchas

- The `vault-ca` Secret is owned by cert-manager; the namespace carries `platform.io/vault-ca-distribution: skip` so the distribution policy does not clone it.
- Webhook port `10260` must be reachable from kube-apiserver — see Cilium's CCNP `ccnp-cert-manager-webhook`.

## See also

- [`docs/rendered-manifests.md`](../../../../docs/rendered-manifests.md) — how this component is rendered into `_rendered/manifests.yaml`
- [`docs/capability-architecture.md`](../../../../docs/capability-architecture.md) — capability-first contract overview
- [`UPGRADING.md`](../../../../UPGRADING.md) — release-to-release migration steps
