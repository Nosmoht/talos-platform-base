# Component Dependencies

Human-maintained dependency map for the components in
`kubernetes/base/infrastructure/`. **No render script enforces this
file** — see the maintenance note at the bottom.

Since the v2.0.0 substrate-only ablation
([`adr-0004-substrate-only-base.md`](adr-0004-substrate-only-base.md)) this directory
ships exactly two components — `argocd` + `cert-approver` — so the base-internal
dependency graph is now trivial. The dependency map for the 20 non-substrate
components (vault, cert-manager, monitoring, storage, GPU, virt, …) moved with
those components to the [`talos-platform-apps`](https://github.com/devobagmbh/talos-platform-apps)
catalog; consult the catalog repo for their inter-component edges.

## Scope

Hard edges (solid, labeled) are sourced from one of:

- A service-DNS reference in a `values.yaml`.
- A `ClusterIssuer`/`Issuer` name in a `values.yaml`.
- A CRD producer ↔ CR consumer relationship inside the base.

Soft edges (dotted) are sourced from one of:

- ADR-documented namespace co-tenancy
  ([`adr-0002-namespace-ownership-rendered-manifests.md`](adr-0002-namespace-ownership-rendered-manifests.md)).
- App-of-Apps deploy provenance (ArgoCD → everything).
- Hard-constraint or substrate prerequisites (Talos → Cilium → ArgoCD).

Network-policy `provide.<cap>` / `consume.<cap>` labels (the dissolved
capability-network contract, now an apps-CI Conftest + consumer-Kyverno
concern, not base-resident) are **not** a source for this graph — they are
an admission-time policy contract, not a component-dependency declaration.

## The graph

```mermaid
graph LR
  classDef boot fill:#fff3e0,stroke:#e65100,color:#000,stroke-width:2px

  %% Substrate boot/prereq chain --------------------------------------
  talos["Talos OS<br/>tofu/modules/talos-cluster"]:::boot
  cilium["Cilium CNI<br/>controlplane inlineManifest seed"]:::boot
  argocd["argocd<br/>GitOps engine"]:::boot
  cert-approver["cert-approver<br/>kubelet-serving CSR auto-approve<br/>controlplane inlineManifest seed"]:::boot

  talos --> cilium --> argocd
  talos --> cert-approver

  %% Opt-in dependency (disabled by default, out-of-base, dotted) -----
  issuer(["ClusterIssuer 'vault-internal'<br/>consumer-provided cert-manager"]):::boot
  argocd -. "server cert (opt-in;<br/>disabled by default)" .-> issuer
```

## Edge sources

| Edge | Source | File / line |
|---|---|---|
| `talos → cilium → argocd` | substrate boot order | `kubernetes/bootstrap/` README + tutorial step sequence; Cilium is a controlplane `inlineManifest` seed (`tofu/modules/talos-cluster`) |
| `talos → cert-approver` | substrate (serving-cert rotation) | controlplane `inlineManifest` seed (`tofu/modules/talos-cluster`, adr-0013). Client-kubelet CSRs auto-approve so nodes join without it; the approver approves the `kubernetes.io/kubelet-serving` CSRs default-on `serverTLSBootstrap` triggers, so metrics-server / `kubectl logs\|exec\|top` work |
| `argocd ⇢ ClusterIssuer 'vault-internal'` (opt-in, off by default) | `server.certificate` block, disabled | `kubernetes/base/infrastructure/argocd/values.yaml` sets `server.certificate.enabled: false`, so the default render emits no `Certificate`. A consumer overlay that re-enables it references a `cert-manager.io` `ClusterIssuer` named `vault-internal` — cert-manager + Vault are sourced from the apps catalog, not base-resident |

The `argocd ⇢ vault-internal` edge is **opt-in and disabled by default**.
`argocd/values.yaml` sets `server.certificate.enabled: false`, so the substrate
render emits no `cert-manager.io/v1 Certificate` and the substrate floor is
self-contained. The substrate argocd-server runs with `server.insecure=true` —
it serves plaintext at the pod, and a consumer terminates TLS at their gateway /
ingress in front of it (the substrate ships no gateway).

> **Re-enabling cert-manager TLS.** A consumer fronting ArgoCD with
> cert-manager-issued TLS re-enables `server.certificate` in a values overlay and
> provides the `vault-internal` `ClusterIssuer` (cert-manager + Vault live in the
> apps catalog); to make the pod itself serve TLS they also set
> `server.insecure=false`. Only then does this edge exist; until then there is no
> base→cert-manager coupling and no missing-CRD / missing-issuer sync hazard.

## What this graph does NOT show

- **Non-substrate component dependencies.** The 20 components removed at
  v2.0.0 — and their inter-component service-DNS / CRD edges — live in the
  [`talos-platform-apps`](https://github.com/devobagmbh/talos-platform-apps)
  catalog. This file maps only the substrate.
- **Consumer-overlay dependencies.** When a consumer cluster repo vendors the
  base and adds its own manifests (e.g. a Vault `VaultServer` CR, a CNPG
  `Cluster`), those CRs use CRDs shipped by the apps catalog. The base ships
  the **substrate**; the consumer composes the rest. Consumer-side edges are
  out of scope.
- **Runtime/operational dependencies.** Pod-to-pod L4 reachability is
  enforced by network policy; deploy order is governed by ArgoCD sync waves.
  This graph is a build-time / design-time map, not a runtime topology.
- **`platform.io/provide.<cap>` / `consume.<cap>` labels.** The
  capability-network contract dissolved out of the base (now apps-CI
  Conftest + consumer-side Kyverno). These labels describe an
  admission-policy contract for tenant traffic, not a
  component-dependency tree, and are deliberately not the source for
  this graph.

## Maintenance

This file is hand-maintained. When you submit a PR that:

- adds a new component under `kubernetes/base/infrastructure/`, OR
- removes a component, OR
- renames a component directory, OR
- changes a service-DNS cross-reference in a `values.yaml`, OR
- changes a `ClusterIssuer` / cross-component CR reference,

…edit this file in the same PR. PR reviewers flag stale graphs.

A future render-script-based approach was considered and rejected: at
the current (substrate-only) component count with a single documented
cross-reference, CNCF Platforms White Paper TVP guidance — "thinnest
viable platform layer, validate user demand before tooling investment" —
argues for the manual approach until the cross-reference count or the
consultation frequency grows materially. Re-evaluate when either crosses ~50.
