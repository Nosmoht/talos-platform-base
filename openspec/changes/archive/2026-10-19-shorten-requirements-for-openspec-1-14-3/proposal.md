# Shorten requirements for openspec 1.14.3

## Why

openspec 1.14.1 and later reject, under `validate --strict`, a requirement
whose text before its first scenario exceeds 500 characters. 45 requirements
in 13 specs exceed it, which held the openspec pin at 1.14.0.

## What Changes

Each over-long requirement keeps its header and states its core behavior in
at most 480 characters. Facts that did not fit move into scenarios of the
same requirement or into new requirements placed after it. Sentences that
only explained why or recorded history are dropped. No specified behavior
changes.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `argocd-day-zero-bootstrap`
- `argocd-module-seed`
- `argocd-substrate`
- `cert-approver-seed`
- `cilium-cni-delivery`
- `cluster-bootstrap-lifecycle`
- `cluster-yaml-sot`
- `hardware-capability-composition`
- `hardware-features-vocabulary`
- `machine-config-generation`
- `module-interface-contract`
- `oci-supply-chain`
- `platform-invariants`

## Impact

- Specs only; no code, schema or release-artifact change.
- The openspec pin moves to 1.14.3.
