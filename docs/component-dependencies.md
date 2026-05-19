# Component Dependencies

Human-maintained dependency map for the components in
`kubernetes/base/infrastructure/`. **No render script enforces this
file** — see the maintenance note at the bottom.

## Scope

Hard edges (solid, labeled) are sourced from one of:

- A service-DNS reference in a `values.yaml` (e.g.
  `vault.vault.svc.cluster.local:8200`).
- A `ClusterIssuer`/`Issuer` name in a `values.yaml`.
- A CRD producer ↔ CR consumer relationship inside the base.

Soft edges (dotted) are sourced from one of:

- ADR-documented namespace co-tenancy
  ([`adr-namespace-ownership-rendered-manifests.md`](adr-namespace-ownership-rendered-manifests.md)).
- App-of-Apps deploy provenance (ArgoCD → everything).
- Hard-constraint or substrate prerequisites (Talos → Cilium → ArgoCD).

PNI `provide.<cap>` / `consume.<cap>` labels are **not** a source for
this graph — the labels are an admission-time policy contract, not a
component-dependency declaration, and are incomplete across components
that don't ship a `namespace.yaml`.

## The graph

```mermaid
graph LR
  classDef boot fill:#fff3e0,stroke:#e65100,color:#000,stroke-width:2px
  classDef gov fill:#ede7f6,stroke:#5e35b1,color:#000
  classDef sec fill:#fde7e7,stroke:#c2185b,color:#000
  classDef obs fill:#e3f2fd,stroke:#1976d2,color:#000
  classDef stor fill:#fffde7,stroke:#f9a825,color:#000
  classDef compute fill:#fce4ec,stroke:#ad1457,color:#000
  classDef policy fill:#e8f5e9,stroke:#2e7d32,color:#000

  %% Substrate (outside base/infrastructure/) -------------------------
  talos["Talos OS<br/>talos/"]:::boot
  cilium["Cilium CNI<br/>bootstrap/cilium"]:::boot
  argocd["argocd<br/>GitOps engine"]:::boot
  cert-approver["cert-approver<br/>kubelet-serving CSR auto-approve"]:::boot

  talos --> cilium --> argocd
  talos --> cert-approver

  %% Policy + network contract ----------------------------------------
  kyverno["kyverno<br/>admission controller"]:::policy
  pni["platform-network-interface<br/>registry + ClusterPolicies + CCNPs"]:::policy

  argocd ==> kyverno
  cilium --> pni
  kyverno --> pni

  %% Identity + secret chain ------------------------------------------
  vault-op["vault-operator<br/>CRD: VaultServer"]:::sec
  vault-cfg["vault-config-operator<br/>redhatcop.redhat.io CRDs"]:::sec
  cert-mgr["cert-manager<br/>CRD: Issuer, Certificate"]:::sec
  eso["external-secrets<br/>CRD: ExternalSecret, SecretStore"]:::sec
  dex["dex<br/>OIDC; backend: cnpg-postgres (consumer-side)"]:::sec

  argocd ==> vault-op
  vault-op -- "vault.vault.svc:8200" --> vault-cfg
  vault-op -- "PKI backend" --> cert-mgr
  vault-op -- "KV backend" --> eso
  cert-mgr -- "ClusterIssuer<br/>'vault-internal'" --> argocd

  %% Observability ----------------------------------------------------
  kps["kube-prometheus-stack<br/>CRDs: ServiceMonitor, PrometheusRule, …<br/>owns ns:monitoring"]:::obs
  alloy["alloy<br/>secondary tenant of ns:monitoring"]:::obs
  loki["loki<br/>secondary tenant of ns:monitoring"]:::obs
  metrics-srv["metrics-server<br/>metrics.k8s.io APIService"]:::obs

  argocd ==> kps
  kps -. "ns:monitoring + ServiceMonitor CRD" .-> alloy
  kps -. "ns:monitoring" .-> loki
  alloy -- "loki-gateway.monitoring.svc" --> loki
  loki -- "alertmanager URL" --> kps
  argocd ==> metrics-srv

  %% Storage ----------------------------------------------------------
  piraeus["piraeus-operator<br/>LINSTOR/DRBD CRDs"]:::stor
  lpp["local-path-provisioner<br/>StorageClass"]:::stor

  argocd ==> piraeus
  argocd ==> lpp

  %% Compute / Virt / GPU --------------------------------------------
  nfd["node-feature-discovery<br/>nfd.k8s-sigs.io CRDs"]:::compute
  nvdp["nvidia-device-plugin"]:::compute
  dcgm["nvidia-dcgm-exporter"]:::compute
  multus["multus-cni<br/>NetworkAttachmentDefinition CRD"]:::compute
  kvirt["kubevirt<br/>CRD: VirtualMachine"]:::compute
  cdi["kubevirt-cdi<br/>CRD: DataVolume"]:::compute
  tetragon["tetragon<br/>eBPF security observability"]:::compute

  argocd ==> nfd
  nfd -- "node-label gating" --> nvdp
  nvdp -- "device exposure" --> dcgm
  kps -. "ServiceMonitor for DCGM" .-> dcgm

  argocd ==> multus
  multus --> kvirt
  cdi --> kvirt
  piraeus -. "PV/PVC" .-> kvirt
  lpp -. "PV/PVC fallback" .-> kvirt

  argocd ==> tetragon
  argocd ==> dex
  argocd ==> cert-mgr
  argocd ==> eso
  argocd ==> cdi
```

## Edge sources

| Edge | Source | File / line |
|---|---|---|
| `talos → cilium → argocd` | bootstrap order | `kubernetes/bootstrap/` README + tutorial step sequence |
| `argocd → *` | App-of-Apps deploy provenance | `kubernetes/bootstrap/argocd/root-application.yaml.tmpl` |
| `argocd → cert-manager` | `ClusterIssuer` reference | `kubernetes/base/infrastructure/argocd/values.yaml:8-11` (`group: cert-manager.io`, `kind: ClusterIssuer`, `name: vault-internal`) |
| `cert-manager → argocd` | same block as above | Issuer name `vault-internal` (Vault-issued) |
| `vault-operator → vault-config-operator` | service DNS in chart values | `kubernetes/base/infrastructure/vault-config-operator/values.yaml`: `https://vault.vault.svc.cluster.local:8200` |
| `alloy → loki` | service DNS in chart values | `kubernetes/base/infrastructure/alloy/values.yaml`: `url = "http://loki-gateway.monitoring.svc/loki/api/v1/push"` |
| `loki → kube-prometheus-stack` | service DNS in chart values | `kubernetes/base/infrastructure/loki/values.yaml`: `alertmanager_url: …monitoring.svc:9093` |
| `kube-prometheus-stack → {alloy, loki}` (ns co-tenancy) | namespace-ownership ADR | [`adr-namespace-ownership-rendered-manifests.md`](adr-namespace-ownership-rendered-manifests.md) + `kubernetes/base/infrastructure/alloy/kustomization.yaml` header comment |
| `pni → {kyverno, cilium}` | Layer-B contract | `ARCHITECTURE.md §"L2 Container View"`, `docs/glossary.md` ("Kyverno + Cilium contract") |
| CRD-producer edges (NFD → nvdp → DCGM, multus → kvirt, cdi → kvirt, …) | rendered CRD manifests | each component's `_rendered/crds.yaml` or rendered manifest |

## What this graph does NOT show

- **Consumer-overlay dependencies.** When a consumer cluster repo
  vendors the base and adds its own manifests (e.g. a Vault
  `VaultServer` CR, a CNPG `Cluster`), those CRs use the CRDs shipped
  here. The base ships the **vocabulary**; the consumer ships the
  **instances**. Consumer-side edges are out of scope.
- **Runtime/operational dependencies.** Pod-to-pod L4 reachability is
  enforced by CCNPs; deploy order is governed by ArgoCD sync waves.
  This graph is a build-time / design-time map, not a runtime topology.
- **`platform.io/provide.<cap>` / `consume.<cap>` labels.** These
  exist on `namespace.yaml` of *some* components and not others. They
  describe an admission-policy contract for tenant traffic, not a
  component-dependency tree. They are deliberately not the source for
  this graph.

## Maintenance

This file is hand-maintained. When you submit a PR that:

- adds a new component under `kubernetes/base/infrastructure/`, OR
- removes a component, OR
- renames a component directory, OR
- changes a service-DNS cross-reference in a `values.yaml`, OR
- changes a `ClusterIssuer` / cross-component CR reference,

…edit this file in the same PR. PR reviewers flag stale graphs.

A future render-script-based approach was considered and rejected:
the catalog (`docs/platform-capability-index.yaml`) is the right
SOT for **capability-level** dependency, but at 22 components with
3 documented service-endpoint cross-references, CNCF Platforms
White Paper TVP guidance — "thinnest viable platform layer,
validate user demand before tooling investment" — argues for the
manual approach until the cross-reference count or the consultation
frequency grows materially. Re-evaluate when either crosses ~50.
