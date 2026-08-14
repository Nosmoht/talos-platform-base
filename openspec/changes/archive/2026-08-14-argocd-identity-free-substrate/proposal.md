## Why

Bundled Dex was removed from both ArgoCD render paths on the stated grounds that
"consumers wire ArgoCD SSO via an external OIDC provider". Nothing in the base
made that true. Three gaps remained:

- `kubernetes/substrate/argocd/values.yaml` shipped
  `configs.rbac.policy.csv: g, <a single named principal>, role:admin` together
  with `scopes: '[preferred_username]'`. An access policy names principals of a
  specific organisation, which a cluster-agnostic floor cannot know — so the base
  was shipping one organisation's identity into every consuming cluster.
- The steady-state render carried the chart's placeholder `url`
  (`https://argocd.example.com`, derived from `global.domain`). ArgoCD derives
  the OIDC redirect URI from `url`, so a placeholder does not fail in the
  cluster — it fails at the identity provider, at a human's first login.
- No published contract described what a consumer must supply instead, or by
  which mechanism. The mechanism assumed in earlier drafts does not exist:
  ArgoCD resolves the `$ref` source reference only inside `helm.valueFiles` /
  `helm.fileParameters`, so a Multi-Source Application cannot hand a base source
  to a consumer kustomization. The documented cross-repo mechanism is a Kustomize
  **remote base**.

Removing the identity is only safe once the Day-0 apply stops resetting
`argocd-rbac-cm` — that is the companion change
`2026-08-14-argocd-crd-apply-scope`, which ships in the same release. Without
it this change would convert a cosmetic defect into an outage primitive: the
consumer's whole access policy would live in a ConfigMap that a routine
Kubernetes upgrade wipes.

A fourth, adjacent gap surfaced while writing the contract. The component's spec
claims it is "consumable as a single kustomization", but
`.ci-oci-tarball-include.txt` shipped only the rendered artifacts and the
namespace — not `kustomization.yaml`. The claim held in-repo only; a consumer
vendoring a published tag received loose manifests.

## What Changes

- `kubernetes/substrate/argocd/values.yaml` drops `configs.rbac.policy.csv` and
  `configs.rbac.scopes`, and adds `configs.cm.url: ""`. `policy.default: ''`
  stays, with its comment stating honestly that it pins a value identical to the
  chart default and that no gate asserts the pin.
- `scripts/check-argocd-substrate-invariants.sh`:
  - **I3** widens from the bootstrap seed to both render paths;
  - **I4** is added, steady-state only: `argocd-rbac-cm` carries no non-empty
    `policy.csv`. Asserted on emptiness rather than absence, because the chart
    emits the key unconditionally;
  - both name-scoped invariants run behind a presence anchor, so a chart that
    renamed or dropped the ConfigMap fails loudly instead of passing vacuously;
  - **E1–E5** build the worked consumer overlay against an unpatched **control**
    build and assert the documented wiring still applies.
- `kubernetes/examples/argocd-consumer-sso/` is a worked, buildable overlay. It
  sits outside the component because kustomize refuses a root containing its own
  overlay ("cycle detected"), and it uses a local `resources:` path so the gate
  runs offline — the remote-base form lives in the contract.
- `kubernetes/substrate/argocd/kustomization.yaml` joins the OCI payload, and
  `scripts/check-substrate-consumability.sh` requires it for every renderable
  component.
- `knowledge/reference/argocd-sso-contract.md` publishes the consumer contract.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `argocd-substrate` — the component ships no identity and no base URL, and its
  consumption surface is a published payload rather than an in-repo-only
  property.
- `oci-supply-chain` — the payload's ArgoCD entry set gains `kustomization.yaml`,
  which the previous requirement explicitly excluded.

## Impact

- **Specs:** `argocd-substrate` (modified), `oci-supply-chain` (modified).
- **Code:** `kubernetes/substrate/argocd/values.yaml` and its re-rendered
  `_rendered/manifests.yaml`; `.ci-oci-tarball-include.txt`,
  `.ci-oci-tarball-expected.txt`;
  `scripts/check-argocd-substrate-invariants.sh`,
  `scripts/check-substrate-consumability.sh`; new
  `kubernetes/examples/argocd-consumer-sso/`.
- **Gates:** `validate` runs the extended invariants gate (I3 widened, I4, E1–E5)
  — its tool set grows by `kustomize` and `kubeconform`, both already present in
  that job. `oci-allowlist-check` runs the extended consumability check.
  `docs-lint` (required) runs `spec:check-staleness`, which fires on
  `values.yaml` and the two allowlist fixtures.
- **Docs:** `knowledge/reference/argocd-sso-contract.md` (new),
  `knowledge/index.md`, `knowledge/architecture/substrate.md` (its OCI entry list
  had drifted and is corrected), `knowledge/reference/manifest-pipeline.md`,
  `knowledge/workflows/first-consumer-cluster.md`, the component README, the root
  `README.md`, `CHANGELOG.md`, `UPGRADING.md`, `knowledge/log.md`.
- **Consumers: BREAKING.** A consumer relying on the shipped RBAC binding loses
  access at the next sync unless their overlay carries **both** `policy.csv` and
  the `scopes` value their subjects are written against, in the same commit as
  the pin bump. Carrying only `policy.csv` is the documented lockout path,
  because the claim silently reverts to the chart default `groups`. Ships as a
  MAJOR with a migration and a recovery path in `UPGRADING.md`.
