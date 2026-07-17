## Why

The base seeds a kubelet-serving CSR approver as a controlplane Talos
`inlineManifest` so the default-on kubelet serving-cert rotation produces
`kubernetes.io/kubelet-serving` CSRs that get approved out-of-the-box (needed
for metrics-server and `kubectl logs|exec|top`). ADR-0013 chose
`alex1989hu/kubelet-serving-cert-approver` because it needs zero per-cluster
config, but it performs no SAN-to-node binding and leaves non-conforming CSRs
Pending. The owner decision (ADR-0019, partial-supersession of ADR-0013 §D2)
switches to `postfinance/kubelet-csr-approver`: it binds each DNS SAN to the
requesting node by construction and denies terminally, at the cost of a small
per-cluster config surface.

The switch is a breaking change (approver identity, RBAC/pod identity, metrics
port, namespace rename `kubelet-serving-cert-approver` → `kubelet-csr-approver`,
new defaulted config surface, denied-vs-Pending self-healing shift) → MAJOR
OCI bump.

Full rationale, the source-verified postfinance-vs-alex1989hu security check,
rejected alternatives, and the migration sequence:
`knowledge/decisions/0019-postfinance-kubelet-csr-approver.md`.

## What Changes

- `cert-approver-seed` is rewritten for the postfinance identity: the
  unconditional-seed and namespace-floor requirements are re-worded for the
  `kubelet-csr-approver` namespace and entry names; the vendored-manifest
  requirement changes from a static `file()` read to a chart-rendered
  `templatefile()` render (digest pin `v1.2.14@sha256:c0f6…a5f8`); the
  signer-restricted RBAC requirement gains a rule-set-closure clause; and
  three requirements are added — the three-knob config surface with permissive
  defaults (all-IPs floor, non-empty `provider_ip_prefixes`), the always-on
  per-node DNS-SAN binding as an observable contract, and the
  replicas→leader-election/leases-RBAC conditional.
- `module-interface-contract` gains the three cert-approver knobs in its
  grouped typed input surface and five new cert-approver audit outputs
  (`cert_approver_rbac_rules`, `cert_approver_pod_security_context`,
  `cert_approver_container_args`, `cert_approver_env`,
  `cert_approver_replicas`).
- `cluster-yaml-sot` widens the closed `substrate` section to admit a closed
  `cert_approver` object (`provider_regex`, `provider_ip_prefixes` with
  `minItems: 1`, `replicas` with `minimum: 1`).
- `cluster-bootstrap-lifecycle` updates its §Purpose prose naming the
  cert-approver render/seed region (postfinance identity + templated render
  mechanism); its lifecycle requirements do not change.
- `bypass_dns_resolution` stays a module-local constant `true`, not a knob.
  No requirement is removed.

## Capabilities

### New Capabilities

None. The behavior modifies four existing capabilities.

### Modified Capabilities

- `cert-approver-seed`: four MODIFIED requirements (unconditional seed and
  namespace floor re-worded for the new namespace, RBAC gains rule-set
  closure, vendored-manifest becomes chart-rendered templated) plus three
  ADDED requirements (config surface, DNS-SAN binding, replicas→LE/RBAC).
- `module-interface-contract`: two MODIFIED requirements (grouped typed input
  surface, seed and wiring audit outputs).
- `cluster-yaml-sot`: one MODIFIED requirement (untyped escape hatches and
  structural secret exclusion — the substrate closure widens to
  `cert_approver`).
- `cluster-bootstrap-lifecycle`: §Purpose prose only; no requirement change.

## Impact

- Specs: `openspec/specs/cert-approver-seed/spec.md`,
  `openspec/specs/module-interface-contract/spec.md`,
  `openspec/specs/cluster-yaml-sot/spec.md`,
  `openspec/specs/cluster-bootstrap-lifecycle/spec.md` — merged in on archive
  (this change is archived in the same PR that ships the code, per
  `scripts/check-spec-staleness.py` globbing `openspec/specs/*/spec.md` only).
- Code: `tofu/modules/talos-cluster/manifests/kubelet-csr-approver.yaml` (new,
  replaces `manifests/cert-approver.yaml`),
  `tofu/modules/talos-cluster/{variables.tf,main.tf,outputs.tf}` (the three
  knobs, the `templatefile()` render, the five audit outputs),
  `schemas/cluster.schema.json` (the `substrate.cert_approver` object),
  `tofu/modules/talos-cluster/examples/complete/{main.tf,cluster.yaml}`,
  `cluster.yaml.example`.
- Gates: `tofu/modules/talos-cluster/tests/composition.tftest.hcl` (RBAC
  rule-set closure, restricted-PSA, config-injection + defaults, HA
  conditional), `.ci-oci-tarball-include.txt` + `.ci-oci-tarball-expected.txt`
  (manifest path rename).
- Docs: `knowledge/decisions/0019-postfinance-kubelet-csr-approver.md` (new
  ADR, partial-supersession of ADR-0013 §D2), `knowledge/decisions/0013-…`
  (partial-super banner), `CHANGELOG.md` (`### Changed — BREAKING`),
  `UPGRADING.md` (migration: old-approver teardown, config-inertness on
  running clusters, rollback, observability migration).
