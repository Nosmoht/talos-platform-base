---
type: decision
title: "ADR: Verify public Day-0 chart downloads before local rendering"
description: "ArgoCD and Cilium chart archives stay publicly hosted; the module downloads them into the consumer cache, verifies base-owned SHA-256 digests, and renders only the verified local files."
status: stable
id: base:verified-public-seed-charts
decided: "2026-09-02T00:00:00Z"
deciders:
  - maintainer
consulted: []
informed: []
supersedes:
  - /decisions/0007-cluster-yaml-sot.md §Deferred — chart/CRD integrity pinning
superseded_by: []
related:
  - /decisions/0024-argocd-substrate-relocation.md
tags: [adr, supply-chain, day-zero, helm, sha256]
---

# ADR: Verify public Day-0 chart downloads before local rendering

## Context and Problem Statement

The Day-0 module resolved ArgoCD and Cilium by version directly through
`data.helm_template`. A public repository could therefore return changed bytes
under the same version, and those unchecked manifests entered the controlplane
machine configuration. The Helm provider exposes no caller-supplied SHA-256
check, and Cilium publishes no provenance file for its chart.

## Decision Drivers

- Verify the exact bytes before Helm renders them.
- Keep publicly available chart archives out of this repository and its OCI
  artifact.
- Preserve the Cilium HTTP-mirror option for air-gapped consumers.
- Fail before any unchecked manifest reaches a Talos machine configuration.

## Considered Options

1. Package both chart archives in the base artifact.
2. Mirror the charts into a private OCI registry and consume by digest.
3. Download the public archives, verify base-owned SHA-256 digests, then render
   the verified local files.

## Decision Outcome

Chosen option: **verified public download before local rendering**. A small
module-shipped helper downloads each archive into the consumer root's
`.terraform` cache. It fails on a digest mismatch; only then does the existing
Helm provider render the local archive.

The base accepts only chart versions for which it declares a digest. A Cilium
repository override remains valid when the mirror serves the exact pinned
bytes. The ArgoCD seed digest must equal the steady-state chart-lock digest.

### Consequences

- Positive: the privileged Day-0 manifests are built only from attested chart
  bytes, without storing public packages in the base.
- Negative: every apply host needs `curl` and `sha256sum` or `shasum`; a first
  plan needs access to the public repository or configured mirror.
- Breaking: an unpinned consumer chart-version override now fails at plan time.
- Residual: container images and the optional Cilium self-management
  Application's repeated Day-2 fetch are not covered.

## Validation

`scripts/check-fetch-verified-chart.sh` tests matching, changed and
cache-tampered bytes offline. `scripts/check-argocd-substrate-invariants.sh`
binds the ArgoCD Day-0 digest to `chart.lock.yaml`, and the OCI checks require
the helper to ship with the module.

## Links

- GitHub issue #249
