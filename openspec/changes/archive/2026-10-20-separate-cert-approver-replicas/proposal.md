# Separate and budget the kubelet-csr-approver replicas

## Why

`cert_approver_replicas > 1` renders leader election, but the seeded
Deployment carries no pod anti-affinity and the seed ships no
PodDisruptionBudget. Both replicas can land on one node, and a drain can evict
both at once, so raising the count does not keep an approver running through
the node failure or drain it is meant to survive (#326).

## What Changes

- `cert-approver-seed`: a new requirement — at `cert_approver_replicas > 1`
  the Deployment carries a required `kubernetes.io/hostname` pod
  anti-affinity on its own `name` + `instance` labels with
  `matchLabelKeys: [pod-template-hash]`, and the seed adds a `policy/v1`
  PodDisruptionBudget with `maxUnavailable: 1` and
  `unhealthyPodEvictionPolicy: AlwaysAllow`. At the default `1` neither
  renders and the seed is byte-identical.
- `cert-approver-seed`: "Vendored, chart-rendered, digest-pinned templated
  manifest" names the replica-separation blocks among the templated parts and
  records where a modification that renders only at `replicas > 1` is
  described.

- `module-interface-contract`: a new requirement "Cert-approver
  replica-separation audit outputs" adds `cert_approver_affinity` and
  `cert_approver_pod_disruption_budgets`.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `cert-approver-seed`
- `module-interface-contract`

## Impact

- Code: the vendored approver manifest, two new module outputs
  (`cert_approver_affinity`, `cert_approver_pod_disruption_budgets`), the
  `cert_approver_replicas` description (also in `schemas/cluster.schema.json`
  and `cluster.yaml.example`), and the composition test suite.
- Consumers: none at the default. At `cert_approver_replicas > 1` every
  controlplane gets a machine-configuration apply; Talos creates the
  PodDisruptionBudget, and `talosctl upgrade-k8s` brings the anti-affinity to
  the existing Deployment. The replica count must stay below the number of
  nodes the approver can schedule on.
- Verification: `tofu test -filter=tests/composition.tftest.hcl` — the two
  `replicas = 2` assertions fail against the unmodified manifest and pass after
  the change; the default-run assertion fails when the gate is widened to
  `replicas >= 1`.
