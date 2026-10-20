# Separate the CoreDNS replicas onto different nodes

## Why

The Talos built-in CoreDNS Deployment runs two replicas with only a preferred
hostname anti-affinity and no PodDisruptionBudget, so both replicas may share a
node and one node failure stops cluster DNS (issue #325). The Talos machine
config offers no setting for replicas, affinity or a budget, and
`talosctl upgrade-k8s` re-applies the built-in on every run, so a consumer
cannot fix it. Decision and rejected alternatives:
`knowledge/decisions/0031-coredns-required-node-separation.md`.

## What Changes

- New capability `coredns-seed`: an opt-in input disables the Talos built-in
  CoreDNS and seeds the same objects under the same kinds, names and namespace
  as a controlplane inline manifest, with a required hostname anti-affinity, a
  PodDisruptionBudget and the recommended labels. The `kube-dns` ClusterIP and
  the Corefile equal what Talos renders, and the plan fails if a caller,
  worker or per-node patch changes or deletes the DNS domain or the service
  subnets beneath them, sets another CoreDNS image, or replaces the seed on a
  node. The budget carries a digest of the seed objects.
- `module-interface-contract`: three inputs (`coredns_node_separation`,
  default `false`; `coredns_replicas`, default `2`; `coredns_image`) and four
  audit outputs (`coredns_seeded`, `coredns_builtin_setting`,
  `coredns_seed_objects`, `coredns_seed_digest`).
- `machine-config-generation`: the controlplane list appends the CoreDNS seed
  patch after the cert-approver seed patch.
- `cluster-yaml-sot`: the closed `substrate` section gains a closed `coredns`
  object mirroring the three inputs.

## Capabilities

### New Capabilities

- `coredns-seed`

### Modified Capabilities

- `module-interface-contract`
- `machine-config-generation`
- `cluster-yaml-sot`

## Impact

- Code: `tofu/modules/talos-cluster/coredns-seed.tf` (new), `variables.tf`,
  `outputs.tf`, `machine-config.tf`, the example shim and both example
  `cluster.yaml` files, `schemas/cluster.schema.json`, the OCI allowlist.
- Tests: `tests/coredns-seed.tftest.hcl` (offline, mocked providers);
  `scripts/check-talos-config-validation.sh` renders the seed on both schema
  lines and runs `talosctl validate`; the invalid `cluster.yaml` fixture binds
  the replica floor.
- Consumers: none until they opt in — MINOR under ADR-0029. Opting in on a
  running cluster takes a controlplane apply, then a `talosctl upgrade-k8s`
  dry-run and sync (`UPGRADING.md`). With the input on, the base, not Talos,
  pins the CoreDNS image and Corefile.

## Verification

The proposal and its implementation land in one change. The red legs are
mutation runs of `tests/coredns-seed.tftest.hcl` against a copy of the module:
a preferred-only term, a missing `matchLabelKeys`, a changed budget policy, a
built-in left on (both schema lines), a renamed Service, a shifted ClusterIP,
a changed Corefile, a dropped replica bound, a dropped network guard and an
unwired seed patch each fail at least one run. Further runs bind the
disable's position after caller and per-node patches, the replica and image
inputs, the version label of a digest reference, an IPv6-first dual stack, the
legacy seed's identities, and the guard: each branch as the only finding
(native and legacy domain, subnets and image; worker and per-node paths;
JSON6902 operations on every guarded path and parent; documents the guard
cannot read), the separator and CRLF split, and reordered subnets; disabling a
branch fails its run. `scripts/check-talos-config-validation.sh` adds a
real-render leg per schema line for the exact finding of a domain and a subnet
patch, a dual-stack network and a non-default image, and
`scripts/check-coredns-builtin-parity.sh` compares the newest release of each
supported line with the recorded baseline.
