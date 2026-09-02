# `argocd`

**Purpose:** ArgoCD GitOps engine — reconciles every other component in this base from git source via Multi-Source Applications.

## Upstream chart source

- **Chart:** [`argo-cd`](https://argoproj.github.io/argo-helm)
- **Pinned version:** `10.6.0`
- **Lock file:** [`chart.lock.yaml`](./chart.lock.yaml) — includes `tgz_sha256` for reproducible renders.

## Namespace

Deploys into namespace `argocd`. See [`namespace.yaml`](./namespace.yaml) for the full PSA label set.

## Repo-specific Helm-value overrides

Top-level keys in [`values.yaml`](./values.yaml) — anything not listed below uses the upstream chart's default:

- `crds`
- `dex` — `enabled: false` (bundled Dex off; see §Substrate invariants)
- `server`
- `repoServer`
- `configs`

## Known upgrade gotchas

- A bare `AppProject` (sync-wave -1) must reconcile before any Application (sync-wave 0) that references it.
- The base ships the ArgoCD chart and CRDs but not the root `Application` — consumer repos own that bootstrap.

## Substrate invariants

ArgoCD ships through **two render paths** serving different lifecycle phases:

- **Day-0 bootstrap seed** — [`tofu/modules/talos-cluster/helm/argocd-values.yaml`](../../../tofu/modules/talos-cluster/helm/argocd-values.yaml), rendered by `data.helm_template.argocd` into a Talos `cluster.inlineManifest` (deliberately slim; no kustomize overlay; `include_crds = false`).
- **Steady-state self-management** — [`values.yaml`](./values.yaml), rendered (helm → kustomize) into [`_rendered/manifests.yaml`](./_rendered/manifests.yaml).

Both files are valid and necessary (the slim seed cannot depend on steady-state services). The risk is that values which must stay aligned drift silently because each path independently inherits upstream chart defaults. These invariants are gated in CI by [`scripts/check-argocd-substrate-invariants.sh`](../../../scripts/check-argocd-substrate-invariants.sh) (the executable source of truth; run on every PR and locally via `task gitops:validate`). I1-I3 and I6 are **shared** — they must hold in both paths; I4 and I5 are **steady-state-only**; P is a parity assertion across the two pins. The table says which and why:

| # | Invariant | Why |
|---|---|---|
| **I1** | Neither render produces a bundled-Dex resource — no document carrying the label `app.kubernetes.io/component: dex-server` (nor `metadata.name: argocd-dex-server`). | Consumers wire ArgoCD SSO against an **external** OIDC provider by patching the `oidc.config` key of the `argocd-cm` ConfigMap in their own kustomize overlay — not through these Helm values, which a consumer of the published component never has. So the chart-default bundled Dex (`dex.enabled: true`) is an idle, connector-less workload in every cluster — and bloats the Talos inlineManifest in the seed. |
| **I2** | Neither render has **any** ConfigMap with a `.data` key prefixed `server.dex.server`. | These params only exist to point argocd-server at the bundled Dex; with Dex off they are moot and their presence signals drift. The chart emits them in `argocd-cmd-params-cm`, but the gate scans **all** ConfigMaps so a rename cannot evade it. |
| **I3** | Neither render's `argocd-cm` carries a `url` key. | The chart derives `configs.cm.url` from `global.domain`, whose default is a placeholder hostname. ArgoCD documents `url` as **required when configuring SSO** and derives the OIDC redirect URI from it, so a placeholder does not fail loudly — it fails at the IdP with a redirect-URI mismatch, at a human's first login. `configs.cm.url: ""` drops the key entirely, so an unconfigured cluster is visibly unconfigured and the consumer supplies the real value in their overlay. Scoped by ConfigMap **name**, unlike I2's blanket key sweep: `url` is a generic key other ConfigMaps legitimately carry. |
| **I4** *(steady-state only)* | The steady-state `argocd-rbac-cm` carries no **non-empty** `policy.csv`. | The substrate ships no identity: an access policy names principals of a specific organisation, which a cluster-agnostic floor cannot know. Steady-state-only by construction, not by omission — the published component is what a consumer's overlay merges onto, so a principal shipped here becomes a standing grant in **every** consuming cluster; the seed values have never carried a policy. Asserted on **emptiness**, not absence: the chart emits `policy.csv` unconditionally, so `""` is the shipped state and a presence check would false-positive forever. |
| **I5** *(steady-state only)* | The steady-state `argocd-rbac-cm` carries no **non-empty** `policy.default`. | Strictly wider blast radius than I4, which is why it is a separate assertion rather than folded in: a policy binds the subjects it names, while `policy.default` grants its role to **every authenticated principal** with no subject at all. Before I5 the key with the smaller radius was gated and the larger one was not. |
| **I6** | Both renders carry the chart's five per-component NetworkPolicies (application-controller, notifications-controller, redis, repo-server, server), no policy has an empty `podSelector`, and the `argocd-server` policy admits ingress from every source. | `argo-cd` 10.0.0 flipped `global.networkPolicy.create` to `true` and the base carries no override, so the policies are the substrate's shipped network posture — Cilium enforces them in every consuming cluster. Three assertions because they fail differently: **presence** is an anchor (a negative check on a resource class the chart could stop emitting passes vacuously — same idiom as `require_cm`, and it exits 2, not 3, because a vanished set is a render-shape problem); an **empty `podSelector`** with `policyTypes: Ingress` is a namespace default-deny, which a floor must not ship blind onto a consumer's own workloads in `argocd`; and the **open `argocd-server` rule** is what keeps a consumer's gateway — whose pod labels and namespace the base cannot know — from being cut off, since the substrate runs argocd-server with `server.insecure` and expects TLS termination in front of it. |
| **P** *(cross-path)* | The module's `argocd_chart_version` default equals `chart.lock.yaml`'s `.chart.version`. | Formerly a named deferral (see below), promoted to a gate because the Day-0 apply no longer forces conflicts: the module renders the seed CRDs at one pin and ArgoCD owns the steady-state CRDs rendered at the other, so a divergence now fails **every** consumer's next `tofu apply`, not just the bumping one. Version-string parity only — a same-version upstream republish still slips through on the module side. |

**Reading note (I2):** argocd-server legitimately retains `configMapKeyRef` *consumer* env entries naming `server.dex.server*` with `optional: true`. Those are env references, **not** ConfigMap `.data` keys, and are **not** a violation — a naïve `grep server.dex.server` over the render will match them; the gate's structured check does not. Do not "fix" them.

**Reading note (I3):** `argocd-notifications-cm` keeps `context.argocdUrl` at the chart's placeholder, and that is an **accepted, structurally forced residual** — the chart renders it as `{{ .Values.notifications.argocdUrl | default (printf "https://%s" .Values.global.domain) }}`, and Helm's `default` treats `""` as unset, so the key cannot be cleared without disabling the whole notifications workload. It feeds notification links, never the SSO redirect. `global.domain: ""` is not the lever either: it yields a broken literal `https://` in *both* ConfigMaps.

**Scope.** The gate asserts a property of the **base-shipped values** (structural: does the values file disable the bundled Dex), rendered with the pinned chart — not a byte-reproduction of the inlineManifest, and not consumer behaviour. A consumer `var.argocd_values_override` that re-enables Dex is **out of base scope**; consumer-side enforcement is consumer-cluster Kyverno (AGENTS.md §ADR-0009).

**Reading note (I4):** `scopes` is **not** covered by I4 and deliberately so. The chart default `'[groups]'` is a claim selector, not a principal, so shipping it grants nothing. It is still half of a pair, and a consumer who carries `policy.csv` into their overlay without the matching `scopes` matches their policy against a claim it was never written for. That fails in **two** directions: usually lockout, but — because Casbin subjects share one flat, unprefixed namespace — a username subject can also silently match an IdP *group* of the same value, granting the whole group. See [`knowledge/reference/argocd-sso-contract.md`](../../../knowledge/reference/argocd-sso-contract.md).

**Consumer side (E-checks).** The same gate builds the worked overlay in [`kubernetes/examples/argocd-consumer-sso/`](../../examples/argocd-consumer-sso/) against an unpatched **control** build, and asserts the documented wiring still applies: a merged `url`, a parseable `oidc.config`, a non-empty `policy.csv`, no base-shipped `.data` key dropped by the patch, and `kubeconform -strict` on the result. I1–I5 assert what the base does *not* ship; without the E-checks nothing would assert that the missing half can still be supplied. The overlay is a **required input**, not an optional one — a missing example exits 1 rather than skipping the block, because a check that disappears with its own input reports green while proving nothing.

**Adding an invariant:** add the assertion to `scripts/check-argocd-substrate-invariants.sh` and a row to this table in the same change.

**Formerly deferred, now gated: chart-version parity** between the seed (`argocd_chart_version` default in `tofu/modules/talos-cluster/variables.tf`) and steady-state (`chart.lock.yaml`) — invariant P above. It was maintained by review while the Day-0 apply forced conflicts and a divergence was silently steamrolled; removing the force made it load-bearing, so it is asserted. The residual is unchanged and still real: a same-version chart *republish* (changed `tgz_sha256`) is not caught by a version-string compare, and the module side carries no digest pin at all.

## See also

- [`knowledge/reference/argocd-sso-contract.md`](../../../knowledge/reference/argocd-sso-contract.md) — **what a consumer must supply** to attach an identity provider to this identity-free component, and the cut-over that retires the local `admin` account
- [`knowledge/reference/manifest-pipeline.md`](../../../knowledge/reference/manifest-pipeline.md) — how this component is rendered into `_rendered/manifests.yaml`
- [`UPGRADING.md`](../../../UPGRADING.md) — release-to-release migration steps
