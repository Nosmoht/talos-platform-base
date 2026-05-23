<!--
GENERATED FILE — DO NOT EDIT BY HAND.
Source of truth: docs/platform-capability-index.yaml
Regenerate: scripts/render-capability-index.sh
-->

# Platform Capability Index (Layer A)

**Schema version:** `1` · **Base version stamp:** `0.X` · **Default owner:** `platform-maintainers`

This document is generated from `docs/platform-capability-index.yaml`.
It is the **Layer A** catalogue defined in
[ADR — Two-Layer Capability Architecture](./adr-two-layer-capability-architecture.md):
the tool-capability-index that names every functional capability this
base provides, its current implementations, and what swap classes
exist between alternatives. For the network-trust subset (Layer B,
Kyverno-consumed), see
[capability-reference.md](./capability-reference.md).

---

## Summary

| ID | Stability | Domain | Topology | Layer B id |
|---|---|---|---|---|
| [`metrics-scrape`](#metrics-scrape) | ga | observability / Metrics | host-and-tenant | monitoring-scrape |
| [`metrics-storage`](#metrics-storage) | beta | observability / Metrics | host-and-tenant | — |
| [`metrics-query`](#metrics-query) | beta | observability / Metrics | host-singleton | — |
| [`hpa-metrics`](#hpa-metrics) | ga | observability / Metrics | tenant-instance | hpa-metrics |
| [`logs-collect`](#logs-collect) | beta | observability / Logs | tenant-instance | logging-ship |
| [`logs-storage`](#logs-storage) | beta | observability / Logs | host-singleton | logging-ship |
| [`logs-query`](#logs-query) | beta | observability / Logs | host-singleton | — |
| [`traces-collect`](#traces-collect) | alpha | observability / Tracing | tenant-instance | — |
| [`traces-storage`](#traces-storage) | alpha | observability / Tracing | host-singleton | — |
| [`traces-query`](#traces-query) | alpha | observability / Tracing | host-singleton | — |
| [`alert-routing`](#alert-routing) | beta | observability / Alerts | host-singleton | — |
| [`dashboards`](#dashboards) | beta | observability / Visualization | host-singleton | — |
| [`tls-issuance`](#tls-issuance) | ga | provisioning / Security & Compliance | tenant-instance | tls-issuance |
| [`vault-secrets`](#vault-secrets) | ga | provisioning / Key Management | host-singleton | vault-secrets |
| [`identity-oidc`](#identity-oidc) | beta | provisioning / Key Management | host-singleton | — |
| [`block-storage-replicated`](#block-storage-replicated) | beta | runtime / Cloud Native Storage | tenant-instance | block-storage-replicated |
| [`block-storage-local`](#block-storage-local) | ga | runtime / Cloud Native Storage | tenant-instance | block-storage-local |
| [`s3-object`](#s3-object) | ga | runtime / Cloud Native Storage | host-singleton | s3-object |
| [`internet-egress`](#internet-egress) | ga | runtime / Cloud Native Network | tenant-instance | internet-egress |
| [`controlplane-egress`](#controlplane-egress) | ga | runtime / Cloud Native Network | tenant-instance | controlplane-egress |
| [`gateway-backend`](#gateway-backend) | ga | orchestration / API Gateway | tenant-instance | gateway-backend |
| [`external-gateway-routes`](#external-gateway-routes) | ga | orchestration / API Gateway | tenant-instance | external-gateway-routes |
| [`secondary-network-attachment`](#secondary-network-attachment) | alpha | runtime / Cloud Native Network | tenant-instance | — |
| [`cnpg-postgres`](#cnpg-postgres) | ga | app-def / Database | host-singleton | cnpg-postgres |
| [`redis-managed`](#redis-managed) | beta | app-def / Database | host-singleton | redis-managed |
| [`rabbitmq-managed`](#rabbitmq-managed) | beta | app-def / Streaming & Messaging | host-singleton | rabbitmq-managed |
| [`kafka-managed`](#kafka-managed) | alpha | app-def / Streaming & Messaging | host-singleton | kafka-managed |
| [`gpu-runtime`](#gpu-runtime) | beta | runtime / Container Runtime | tenant-instance | gpu-runtime |
| [`vm-runtime`](#vm-runtime) | beta | app-def / Application Definition & Image Build | host-only | — |
| [`gitops-engine`](#gitops-engine) | ga | app-def / Continuous Integration & Delivery | host-only | — |
| [`admission-policy`](#admission-policy) | ga | provisioning / Security & Compliance | tenant-instance | — |
| [`runtime-security`](#runtime-security) | ga | provisioning / Security & Compliance | tenant-instance | — |
| [`secret-sync`](#secret-sync) | ga | provisioning / Key Management | tenant-instance | — |
| [`csr-approval`](#csr-approval) | ga | provisioning / Security & Compliance | tenant-instance | — |
| [`secret-config-declarative`](#secret-config-declarative) | ga | provisioning / Key Management | host-only | — |
| [`cluster-provisioning`](#cluster-provisioning) | alpha | orchestration / Scheduling & Orchestration | host-only | — |

---

## Capabilities

### `metrics-scrape`

**Prometheus-format metrics scrape** · stability `ga` · domain observability / Metrics · topology `host-and-tenant`

Producer pod exposes a /metrics endpoint speaking Prometheus
scrape protocol v1. A scraper pulls that endpoint over HTTP.

**Contract:**

```text
HTTP GET on a named port (typical: http-metrics).
Response is Prometheus text-format exposition. No protocol-level auth.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `kube-prometheus-stack` — status `active`, swap-class `drop-in` — composition: kube-prometheus-stack
- `victoria-metrics-agent` — status `considered`, swap-class `drop-in` · _external_
- `grafana-alloy` — status `considered`, swap-class `drop-in` · _external_

**Layer B (PNI) counterpart:** `monitoring-scrape`

### `metrics-storage`

**Time-series storage for metrics** · stability `beta` · domain observability / Metrics · topology `host-and-tenant`

Long-term retention store for Prometheus-format metrics,
ingested via remote_write or OTLP-metrics.

**Contract:**

```text
HTTP POST /api/v1/write (Prometheus remote_write v1) OR
gRPC OTLP-metrics. Ingestion authenticates via mTLS in mesh.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `kube-prometheus-stack` — status `active`, swap-class `data-migration` — composition: kube-prometheus-stack
- `victoria-metrics` — status `considered`, swap-class `data-migration` · _external_
- `thanos` — status `considered`, swap-class `data-migration` · _external_
- `mimir` — status `considered`, swap-class `data-migration` · _external_

### `metrics-query`

**PromQL/MetricsQL query endpoint** · stability `beta` · domain observability / Metrics · topology `host-singleton`

HTTP endpoint speaking PromQL or MetricsQL, consumed by
dashboards, recording rules, and alert-rule-evaluators.

**Contract:**

```text
HTTP GET /api/v1/query and /api/v1/query_range (PromQL).
MetricsQL is a superset; same wire shape.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `kube-prometheus-stack` — status `active`, swap-class `drop-in` — composition: kube-prometheus-stack
- `thanos-query` — status `considered`, swap-class `drop-in` · _external_
- `victoria-metrics-select` — status `considered`, swap-class `drop-in` · _external_

### `hpa-metrics`

**Resource metrics API (HPA + kubectl top)** · stability `ga` · domain observability / Metrics · topology `tenant-instance`

Aggregated short-window CPU/memory metrics via metrics.k8s.io,
consumed by HorizontalPodAutoscaler and kubectl top.

**Contract:**

```text
Kubernetes Resource Metrics API (metrics.k8s.io/v1beta1).
Stable, K8s-native, served by an APIService.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `metrics-server` — status `active`, swap-class `drop-in` — composition: metrics-server
- `keda-metrics-adapter` — status `considered`, swap-class `drop-in` · _external_

**Layer B (PNI) counterpart:** `hpa-metrics`

### `logs-collect`

**Log collection agent (push side)** · stability `beta` · domain observability / Logs · topology `tenant-instance`

Per-node or per-pod agent that reads stdout/stderr and ships
logs to a downstream store via Loki-push or OTLP-logs.

**Contract:**

```text
No inbound surface; outbound HTTP/gRPC to logs-storage.
Per-tenant deployment, configured at tenant boot.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `alloy` — status `active`, swap-class `label-move` — composition: alloy
- `fluent-bit` — status `considered`, swap-class `label-move` · _external_
- `vector` — status `considered`, swap-class `label-move` · _external_
- `otelcol` — status `considered`, swap-class `label-move` · _external_

**Layer B (PNI) counterpart:** `logging-ship`

### `logs-storage`

**Log storage (ingest side)** · stability `beta` · domain observability / Logs · topology `host-singleton`

Backend that accepts Loki-push or OTLP-logs and stores them
for retention + querying.

**Contract:**

```text
HTTP POST /loki/api/v1/push (Loki push v1).
OTLP-logs also accepted by recent versions.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `loki` — status `active`, swap-class `data-migration` — composition: loki
- `victoria-logs` — status `considered`, swap-class `data-migration` · _external_
- `opensearch` — status `considered`, swap-class `rewrite-required` · _external_

**Layer B (PNI) counterpart:** `logging-ship`

### `logs-query`

**LogQL query endpoint** · stability `beta` · domain observability / Logs · topology `host-singleton`

Read-side HTTP endpoint for log queries (LogQL or equivalent).

**Contract:**

```text
HTTP GET /loki/api/v1/query and /query_range (LogQL).
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `loki` — status `active`, swap-class `drop-in` — composition: loki
- `victoria-logs` — status `considered`, swap-class `drop-in` · _external_

### `traces-collect`

**Distributed trace collection agent** · stability `alpha` · domain observability / Tracing · topology `tenant-instance`

Agent that receives spans from instrumented apps via OTLP
and forwards to a traces-storage backend.

**Contract:**

```text
OTLP-traces over gRPC (port 4317) or HTTP (port 4318).
Standard OpenTelemetry protocol.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `alloy` — status `candidate`, swap-class `label-move` — composition: alloy
- `otelcol` — status `considered`, swap-class `label-move` · _external_

### `traces-storage`

**Distributed trace storage** · stability `alpha` · domain observability / Tracing · topology `host-singleton`

Backend that ingests OTLP-traces and retains them for query.

**Contract:**

```text
OTLP-traces ingest (gRPC) or Jaeger-proto.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `tempo` — status `considered`, swap-class `data-migration` · _external_
- `jaeger` — status `considered`, swap-class `data-migration` · _external_

### `traces-query`

**Trace query endpoint** · stability `alpha` · domain observability / Tracing · topology `host-singleton`

Read-side HTTP API for trace search and trace-by-id lookups.

**Contract:**

```text
Tempo HTTP API or Jaeger HTTP API.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `tempo` — status `considered`, swap-class `drop-in` · _external_
- `jaeger` — status `considered`, swap-class `drop-in` · _external_

### `alert-routing`

**Alert routing and delivery** · stability `beta` · domain observability / Alerts · topology `host-singleton`

Receives Prometheus-format alerts and dispatches via email,
webhooks, paging integrations.

**Contract:**

```text
HTTP POST /api/v2/alerts (Alertmanager v2 API).
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `alertmanager-via-kps` — status `active`, swap-class `drop-in` — composition: kube-prometheus-stack
- `grafana-oncall` — status `considered`, swap-class `drop-in` · _external_
- `ntfy-webhook` — status `considered`, swap-class `drop-in` · _external_

### `dashboards`

**Dashboard / visualization UI** · stability `beta` · domain observability / Visualization · topology `host-singleton`

Human-facing UI that queries metrics-query, logs-query,
traces-query via HTTP datasource plugins.

**Contract:**

```text
HTTP UI; datasource plugins speak Prom API, Loki API,
Tempo API. Consumer is humans via browser, not pods.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `grafana-via-kps` — status `active`, swap-class `label-move` — composition: kube-prometheus-stack
- `perses` — status `considered`, swap-class `label-move` · _external_

### `tls-issuance`

**X.509 certificate issuance** · stability `ga` · domain provisioning / Security & Compliance · topology `tenant-instance`

Tenant emits a Certificate CR; controller issues a cert
from a configured CA (ACME, Vault-PKI, internal CA).

**Contract:**

```text
Tenant interaction via cert-manager Issuer/ClusterIssuer/
Certificate CRDs. Egress to ACME providers if used.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `cert-manager` — status `active`, swap-class `label-move` — composition: cert-manager, cert-approver
- `vault-pki` — status `considered`, swap-class `rewrite-required` · _external_

**Layer B (PNI) counterpart:** `tls-issuance`

### `vault-secrets`

**KV-style secret access** · stability `ga` · domain provisioning / Key Management · topology `host-singleton`

Tenant authenticates and reads/writes secrets in a per-tenant
KV mount path.

**Contract:**

```text
HTTPS REST API (Vault KV v2). Authentication via Kubernetes
auth method (K8s SA token validated against tenant cluster's
JWKS endpoint).
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `vault-operator` — status `active`, swap-class `data-migration` — composition: vault-operator, vault-config-operator
- `openbao` — status `considered`, swap-class `drop-in` · _external_
- `infisical` — status `considered`, swap-class `rewrite-required` · _external_

**Layer B (PNI) counterpart:** `vault-secrets`

### `identity-oidc`

**OIDC identity provider** · stability `beta` · domain provisioning / Key Management · topology `host-singleton`

OIDC provider issuing ID tokens for workloads and humans.
Tenants federate against it.

**Contract:**

```text
OIDC v1 over HTTPS (.well-known/openid-configuration,
/auth, /token endpoints).
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `dex` — status `active`, swap-class `label-move` — composition: dex
- `keycloak` — status `considered`, swap-class `label-move` · _external_
- `authelia` — status `considered`, swap-class `label-move` · _external_

### `block-storage-replicated`

**Cross-node replicated block storage** · stability `beta` · domain runtime / Cloud Native Storage · topology `tenant-instance`

Block storage replicated across nodes via DRBD; PV survives
node loss. Higher latency than local.

**Contract:**

```text
CSI gRPC interface (standard K8s CSI v1).
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `piraeus-operator` — status `active`, swap-class `data-migration` — composition: piraeus-operator
- `rook-ceph` — status `considered`, swap-class `rewrite-required` · _external_
- `longhorn` — status `considered`, swap-class `rewrite-required` · _external_
- `openebs-mayastor` — status `considered`, swap-class `rewrite-required` · _external_

**Layer B (PNI) counterpart:** `block-storage-replicated`

### `block-storage-local`

**Node-local block storage** · stability `ga` · domain runtime / Cloud Native Storage · topology `tenant-instance`

Block storage bound to a single node; lowest latency, lost
on node failure. PVs not portable.

**Contract:**

```text
CSI gRPC interface; topology-aware scheduling required.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `local-path-provisioner` — status `active`, swap-class `data-migration` — composition: local-path-provisioner
- `openebs-localpv` — status `considered`, swap-class `drop-in` · _external_
- `topolvm` — status `considered`, swap-class `rewrite-required` · _external_

**Layer B (PNI) counterpart:** `block-storage-local`

### `s3-object`

**S3-API object storage** · stability `ga` · domain runtime / Cloud Native Storage · topology `host-singleton`

S3-compatible object storage; bucket-scoped per tenant.

**Contract:**

```text
S3 REST API over HTTPS, signature v4. Bucket per tenant.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `minio-operator` — status `candidate`, swap-class `drop-in` · _external_
- `external-s3` — status `candidate`, swap-class `drop-in` · _external_

**Layer B (PNI) counterpart:** `s3-object`

### `internet-egress`

**Public-internet egress** · stability `ga` · domain runtime / Cloud Native Network · topology `tenant-instance`

Network policy permitting egress to public IP ranges
(excluding RFC1918, link-local, loopback).

**Contract:**

```text
Implemented as CIDR-based CCNP; namespace opts in.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `cilium` — status `active`, swap-class `label-move` · _external_

**Layer B (PNI) counterpart:** `internet-egress`

### `controlplane-egress`

**kube-apiserver egress** · stability `ga` · domain runtime / Cloud Native Network · topology `tenant-instance`

Egress to in-cluster kube-apiserver; required for any
workload using a ServiceAccount token.

**Contract:**

```text
L4 egress to apiserver service port.
```

**Independence test:** alt-impls=— · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `kube-apiserver` — status `active`, swap-class `drop-in` · _external_

**Layer B (PNI) counterpart:** `controlplane-egress`

### `gateway-backend`

**Gateway-API HTTPRoute backend** · stability `ga` · domain orchestration / API Gateway · topology `tenant-instance`

Workload exposed as HTTPRoute backend behind a platform Gateway.

**Contract:**

```text
Gateway-API v1 HTTPRoute; consumer is the in-cluster Gateway
controller (Envoy/Cilium).
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `cilium-gateway-api` — status `active`, swap-class `label-move` · _external_
- `envoy-gateway` — status `considered`, swap-class `label-move` · _external_
- `contour` — status `considered`, swap-class `label-move` · _external_

**Layer B (PNI) counterpart:** `gateway-backend`

### `external-gateway-routes`

**External-HTTPS Gateway-route attachment** · stability `ga` · domain orchestration / API Gateway · topology `tenant-instance`

Permission to attach HTTPRoutes to the cluster's external-https
Gateway listener. Selection only, no separate dataplane.

**Contract:**

```text
Gateway-API allowedRoutes selector.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `gateway-api` — status `active`, swap-class `drop-in` · _external_

**Layer B (PNI) counterpart:** `external-gateway-routes`

### `secondary-network-attachment`

**Pod secondary network interfaces** · stability `alpha` · domain runtime / Cloud Native Network · topology `tenant-instance`

Pod opts into one or more additional network interfaces
beyond the default pod network.

**Contract:**

```text
Pod annotation k8s.v1.cni.cncf.io/networks plus a
NetworkAttachmentDefinition CRD.
```

**Independence test:** alt-impls=— · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `multus-cni` — status `active`, swap-class `rewrite-required` — composition: multus-cni

### `cnpg-postgres`

**PostgreSQL (managed)** · stability `ga` · domain app-def / Database · topology `host-singleton`

PostgreSQL via the CloudNative-PG operator; one instance
per CNPG Cluster CR.

**Contract:**

```text
pgwire v3 (Postgres native protocol) over TCP 5432.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `cloudnative-pg` — status `candidate`, swap-class `data-migration` · _external_
- `stackgres` — status `considered`, swap-class `data-migration` · _external_
- `zalando-pg` — status `considered`, swap-class `data-migration` · _external_

**Layer B (PNI) counterpart:** `cnpg-postgres`

### `redis-managed`

**Redis (managed)** · stability `beta` · domain app-def / Database · topology `host-singleton`

Redis via OT-Container-Kit operator; one instance per
RedisReplication/Cluster/Standalone CR.

**Contract:**

```text
RESP3 protocol over TCP 6379.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `redis-operator` — status `candidate`, swap-class `data-migration` · _external_

**Layer B (PNI) counterpart:** `redis-managed`

### `rabbitmq-managed`

**RabbitMQ (managed)** · stability `beta` · domain app-def / Streaming & Messaging · topology `host-singleton`

RabbitMQ via the official cluster-operator; one instance
per RabbitmqCluster CR.

**Contract:**

```text
AMQP 0-9-1 over TCP 5672.
```

**Independence test:** alt-impls=— · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `rabbitmq-cluster-operator` — status `candidate`, swap-class `data-migration` · _external_

**Layer B (PNI) counterpart:** `rabbitmq-managed`

### `kafka-managed`

**Apache Kafka (managed)** · stability `alpha` · domain app-def / Streaming & Messaging · topology `host-singleton`

Kafka via the Strimzi operator; one instance per Kafka CR.

**Contract:**

```text
Kafka wire protocol over TCP.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `strimzi` — status `considered`, swap-class `data-migration` · _external_
- `redpanda-operator` — status `considered`, swap-class `data-migration` · _external_

**Layer B (PNI) counterpart:** `kafka-managed`

### `gpu-runtime`

**NVIDIA GPU scheduling and telemetry** · stability `beta` · domain runtime / Container Runtime · topology `tenant-instance`

GPU device-plugin + DCGM telemetry. Schedules GPU resources via
the NVIDIA device plugin and surfaces per-GPU utilization metrics
via DCGM exporter. Node-feature discovery (NFD) is Layer-C
producer-tooling (see adr-three-layer-capability-architecture.md);
it discovers the hardware predicate but is not part of this
capability's composition.

**Contract:**

```text
Node-local device-plugin socket + DCGM metrics exporter
on host-network.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `nvidia-stack` — status `active`, swap-class `rewrite-required` — composition: nvidia-device-plugin, nvidia-dcgm-exporter

**Layer B (PNI) counterpart:** `gpu-runtime`

### `vm-runtime`

**VM workload runtime** · stability `beta` · domain app-def / Application Definition & Image Build · topology `host-only`

Run VMs as first-class Kubernetes workloads via KubeVirt
CRDs (VirtualMachine, VirtualMachineInstance).

**Contract:**

```text
KubeVirt CRDs + Containerized Data Importer for image
ingestion. Tenant-cluster VMs run on host's KubeVirt.
```

**Independence test:** alt-impls=— · contract-stable=true · independent-lifecycle=—

**Implementations:**

- `kubevirt` — status `active`, swap-class `rewrite-required` — composition: kubevirt, kubevirt-cdi

### `gitops-engine`

**GitOps reconciliation engine** · stability `ga` · domain app-def / Continuous Integration & Delivery · topology `host-only`

Watches Git, reconciles desired state into the cluster.
Tenant interaction is via Git pushes, not pod-to-pod traffic.

**Contract:**

```text
Pull-based reconciliation from Git refs; sync wave + health
assessment per resource.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `argocd` — status `active`, swap-class `rewrite-required` — composition: argocd
- `fluxcd` — status `considered`, swap-class `rewrite-required` · _external_

### `admission-policy`

**Admission policy engine** · stability `ga` · domain provisioning / Security & Compliance · topology `tenant-instance`

Validating/mutating admission control; policies authored
per-engine.

**Contract:**

```text
K8s admission-webhook protocol. Policy authoring is
tool-specific (Kyverno CEL/DSL; Gatekeeper Rego;
native VAP CEL).
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `kyverno` — status `active`, swap-class `rewrite-required` — composition: kyverno
- `opa-gatekeeper` — status `considered`, swap-class `rewrite-required` · _external_
- `native-vap` — status `considered`, swap-class `consumer-change` · _external_

### `runtime-security`

**Runtime security observability** · stability `ga` · domain provisioning / Security & Compliance · topology `tenant-instance`

eBPF-based observation of kernel events for security
monitoring; emits to log/SIEM.

**Contract:**

```text
DaemonSet per node; output is event log (security-events
go to logs-collect pipeline).
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `tetragon` — status `active`, swap-class `rewrite-required` — composition: tetragon
- `falco` — status `considered`, swap-class `rewrite-required` · _external_

### `secret-sync`

**External secret synchronization** · stability `ga` · domain provisioning / Key Management · topology `tenant-instance`

Reconciles ExternalSecret CRD into native K8s Secret by
pulling from upstream secret-storage (vault-secrets etc.).

**Contract:**

```text
ExternalSecret CRD; controller polls upstream and emits
Secret objects.
```

**Independence test:** alt-impls=true · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `external-secrets` — status `active`, swap-class `rewrite-required` — composition: external-secrets
- `sealed-secrets` — status `considered`, swap-class `rewrite-required` · _external_
- `reloader` — status `considered`, swap-class `rewrite-required` · _external_

### `csr-approval`

**CertificateSigningRequest approval automation** · stability `ga` · domain provisioning / Security & Compliance · topology `tenant-instance`

Auto-approves K8s CSRs matching policy (typical: node
kubelet-serving certs).

**Contract:**

```text
Watches CSR API resource; applies approval decision.
```

**Independence test:** alt-impls=— · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `cert-approver` — status `active`, swap-class `rewrite-required` — composition: cert-approver

### `secret-config-declarative`

**Vault declarative configuration** · stability `ga` · domain provisioning / Key Management · topology `host-only`

Reconciles Vault-config CRDs into Vault state (policies,
auth-backends, secrets).

**Contract:**

```text
Vault-config-operator CRDs; reconciles via Vault REST API.
```

**Independence test:** alt-impls=— · contract-stable=true · independent-lifecycle=true

**Implementations:**

- `vault-config-operator` — status `active`, swap-class `rewrite-required` — composition: vault-config-operator

### `cluster-provisioning`

**Self-service tenant Kubernetes cluster provisioning** · stability `alpha` · domain orchestration / Scheduling & Orchestration · topology `host-only`

Customer requests a fully-isolated K8s cluster via portal.
Orchestrator materializes a Cluster-API workload cluster
whose nodes are KubeVirt VMs on the host. Customer has root
inside the resulting cluster.

**Contract:**

```text
Customer submits XKubernetesCluster XR (or Backstage
scaffolder request that produces one). Crossplane Composition
materializes CAPI Cluster + KubeadmControlPlane +
KubevirtMachineTemplate. Output: kubeconfig Secret.
```

**Independence test:** alt-impls=true · contract-stable=— · independent-lifecycle=true

**Implementations:**

- `capi-kubevirt-via-crossplane` — status `candidate`, swap-class `rewrite-required` · _external_ — composition: kubevirt, kubevirt-cdi
- `capi-kubevirt-via-red-hat-mce` — status `considered`, swap-class `rewrite-required` · _external_
- `kamaji` — status `considered`, swap-class `rewrite-required` · _external_
