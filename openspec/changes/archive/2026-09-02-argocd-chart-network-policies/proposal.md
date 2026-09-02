# Component NetworkPolicies enter both ArgoCD render paths

## Why

The `argo-cd` chart's 10.0.0 major flipped `global.networkPolicy.create` from
`false` to `true`, aligning the chart with the upstream Argo CD manifests. The
base carries no override for that key on either render path, so bumping the pin
from 9.4.5 to 10.6.0 makes five `networking.k8s.io/v1` NetworkPolicy documents
appear in the committed steady-state render AND in the Day-0 inlineManifest
seed.

That is a substrate behaviour change a consumer observes in their cluster, not a
version literal: after the bump, ingress to `argocd-redis` and to the
`argocd-repo-server` service port is restricted to the Argo CD components that
legitimately call them, and Cilium — the substrate CNI — enforces it. It is kept
rather than overridden because it is upstream's security posture for the chart
and the substrate's job is to ship the floor, not to weaken it.

The two render paths are owned by two specs, so both widen.

## What Changes

- `argocd-substrate`: a new requirement fixing the NetworkPolicy set in the
  committed render, and the two properties that make the set safe to ship on a
  cluster-agnostic floor — `argocd-server` stays open to all ingress so a
  consumer's gateway is never cut off, and the policies are per-component
  allow-rules rather than a namespace default-deny.
- `argocd-module-seed`: the same set ships in the slim Day-0 seed, so a cluster
  is policed from bootstrap rather than from the first ArgoCD self-management
  sync.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `argocd-substrate`
- `argocd-module-seed`

## Impact

- Specs: `argocd-substrate`, `argocd-module-seed`.
- Code: `kubernetes/substrate/argocd/chart.lock.yaml` (pin + `tgz_sha256`),
  `kubernetes/substrate/argocd/_rendered/{manifests,crds}.yaml` (re-render),
  `kubernetes/substrate/argocd/README.md` (pin), and
  `tofu/modules/talos-cluster/variables.tf` (the `argocd_chart_version` default
  the chart-pin-parity gate binds to the lock file).
- Consumers: a consumer that fronts Argo CD through a gateway is unaffected —
  `argocd-server` allows all ingress. A consumer reaching `argocd-repo-server`
  or `argocd-redis` from a workload outside the Argo CD component set must add
  their own allow-rule, or set `global.networkPolicy.create: false` in their
  values overlay.
- No decision record: this adopts an upstream chart default, it does not decide
  between options the base owns.
