<!--
GENERATED FILE — DO NOT EDIT BY HAND.
Source of truth: kubernetes/base/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml
Regenerate: scripts/render-capability-reference.sh
-->

# PNI Capability Reference

**Interface version:** `v2`

This document is generated from the PNI capability registry ConfigMap.
Each entry below corresponds to one capability identifier usable as the
suffix of `platform.io/consume.<id>` and
`platform.io/capability-consumer.<id>` labels in consumer manifests.

For the contract semantics (producer/consumer symmetry, per-instance
scoping, alias mechanism, denial messages), see
[ADR: Capability Producer/Consumer Symmetry](./adr-capability-producer-consumer-symmetry.md).

---

## Summary table

| ID | Stability | Instanced | Status |
|---|---|---|---|
| `monitoring-scrape` | ga | no | active |
| `hpa-metrics` | ga | no | active |
| `tls-issuance` | ga | no | active |
| `gateway-backend` | ga | no | active |
| `external-gateway-routes` | ga | no | active |
| `gpu-runtime` | beta | no | active |
| `internet-egress` | ga | no | active |
| `controlplane-egress` | ga | no | active |
| `storage-csi` | — | no | deprecated → sunset 2026-11-13 |
| `block-storage-replicated` | beta | no | active |
| `block-storage-local` | ga | no | active |
| `vault-secrets` | ga | yes | active |
| `cnpg-postgres` | ga | yes | active |
| `redis-managed` | beta | yes | active |
| `rabbitmq-managed` | beta | yes | active |
| `kafka-managed` | preview | yes | active |
| `s3-object` | ga | yes | active |
| `admission-webhook-provider` | ga | no | internal |
| `monitoring-scrape-provider` | — | no | deprecated → sunset 2026-08-13 |
| `logging-ship` | ga | no | active |

---

## Capabilities

### `monitoring-scrape`

- **Stability:** ga
- **Implementations:**
  - `kube-prometheus-stack` (port `http-metrics`, protocol `prometheus-scrape-v1`)


Prometheus-format /metrics scrape endpoint. The consumer here is
the Prometheus scraper; the producer is the workload exposing
/metrics. Direction is intentional: Prometheus consumes the
endpoint surface.

**Consumer labels:**

```yaml
# Namespace
metadata:
  labels:
    platform.io/consume.monitoring-scrape: "true"
# Pod template
metadata:
  labels:
    platform.io/capability-consumer.monitoring-scrape: "true"
```

### `hpa-metrics`

- **Stability:** ga
- **Implementations:**
  - `metrics-server` (port `https`, protocol `k8s-metrics-api-v1beta1`)


Resource Metrics API (`metrics.k8s.io`) for HorizontalPodAutoscaler
and `kubectl top`. Distinct from monitoring-scrape: aggregated
short-window CPU/memory, not arbitrary Prometheus metrics.

**Consumer labels:**

```yaml
# Namespace
metadata:
  labels:
    platform.io/consume.hpa-metrics: "true"
# Pod template
metadata:
  labels:
    platform.io/capability-consumer.hpa-metrics: "true"
```

### `tls-issuance`

- **Stability:** ga
- **Implementations:**
  - `cert-manager` (port `https`, protocol `cert-manager-webhook-v1`)


X.509 certificate issuance via cert-manager Issuer/ClusterIssuer.
Consumed by any workload that owns a Certificate resource.

**Consumer labels:**

```yaml
# Namespace
metadata:
  labels:
    platform.io/consume.tls-issuance: "true"
# Pod template
metadata:
  labels:
    platform.io/capability-consumer.tls-issuance: "true"
```

### `gateway-backend`

- **Stability:** ga
- **Implementations:**
  - `cilium-gateway-api` (port `http`, protocol `http-1.1`)


Backend of an HTTPRoute attached to a platform Gateway. Consumer
is the workload serving Gateway traffic; producer is the
envoy/cilium ingress dataplane.

**Consumer labels:**

```yaml
# Namespace
metadata:
  labels:
    platform.io/consume.gateway-backend: "true"
# Pod template
metadata:
  labels:
    platform.io/capability-consumer.gateway-backend: "true"
```

### `external-gateway-routes`

- **Stability:** ga
- **Implementations:**
  - `gateway-api` (port `https`, protocol `tls-passthrough`)


Permission to attach HTTPRoutes to the cluster's external-https
Gateway listener. Network policy unchanged (uses gateway-backend
for Envoy→consumer traffic); this label controls Gateway-API
`allowedRoutes` selection only.

**Consumer labels:**

```yaml
# Namespace
metadata:
  labels:
    platform.io/consume.external-gateway-routes: "true"
# Pod template
metadata:
  labels:
    platform.io/capability-consumer.external-gateway-routes: "true"
```

### `gpu-runtime`

- **Stability:** beta
- **Implementations:**
  - `nvidia-device-plugin`
  - `nvidia-dcgm-exporter`
  - `node-feature-discovery`


NVIDIA GPU scheduling and telemetry. Node-local device plugin;
no Service endpoint, opt-in is namespace-level only.

**Consumer labels:**

```yaml
# Namespace
metadata:
  labels:
    platform.io/consume.gpu-runtime: "true"
# Pod template
metadata:
  labels:
    platform.io/capability-consumer.gpu-runtime: "true"
```

### `internet-egress`

- **Stability:** ga
- **Implementations:**
  - `cilium`


Egress to public internet IP ranges. Excludes RFC1918, link-local,
loopback, multicast. Enforced as a CIDR-based egress CCNP.

**Consumer labels:**

```yaml
# Namespace
metadata:
  labels:
    platform.io/consume.internet-egress: "true"
# Pod template
metadata:
  labels:
    platform.io/capability-consumer.internet-egress: "true"
```

### `controlplane-egress`

- **Stability:** ga
- **Implementations:**
  - `kube-apiserver` (port `https`, protocol `kubernetes-api-v1`)


Egress to the in-cluster kube-apiserver. Required for any
workload using a ServiceAccount token, watching CRs, etc.

**Consumer labels:**

```yaml
# Namespace
metadata:
  labels:
    platform.io/consume.controlplane-egress: "true"
# Pod template
metadata:
  labels:
    platform.io/capability-consumer.controlplane-egress: "true"
```

### `storage-csi`

- **Stability:** —
- **Deprecated** — sunset: `2026-11-13`
- **Split into:** `block-storage-replicated, block-storage-local`

**Disambiguation:** Use block-storage-replicated for stateful workloads needing
cross-node DRBD replication (databases, message brokers,
object stores). Use block-storage-local for ephemeral or
single-node workloads (build caches, scratch space). Setting
both is rarely correct.

**Consumer labels:**


_Deprecated — do not introduce in new manifests._

### `block-storage-replicated`

- **Stability:** beta
- **Implementations:**
  - `piraeus-operator`


Cross-node replicated block storage via LINSTOR/DRBD. Higher
latency, survives node loss.

**Consumer labels:**

```yaml
# Namespace
metadata:
  labels:
    platform.io/consume.block-storage-replicated: "true"
# Pod template
metadata:
  labels:
    platform.io/capability-consumer.block-storage-replicated: "true"
```

### `block-storage-local`

- **Stability:** ga
- **Implementations:**
  - `local-path-provisioner`


Node-local block storage. Lowest latency, lost on node failure.
PVs are not portable across nodes.

**Consumer labels:**

```yaml
# Namespace
metadata:
  labels:
    platform.io/consume.block-storage-local: "true"
# Pod template
metadata:
  labels:
    platform.io/capability-consumer.block-storage-local: "true"
```

### `vault-secrets`

- **Stability:** ga
- **Instanced:** yes — instance source: `kv-mount`
- **Implementations:**
  - `vault-operator` (port `https`, protocol `vault-kv-v2`)


HashiCorp Vault secrets access. Instance unit is a KV mount path
(e.g. `team-foo`). Each mount maps to a Vault policy with a
single tenant's secret scope. Instance enumeration is static —
maintained in vault-operator Helm values, not CRD-watched.

**Consumer labels:**

```yaml
# Namespace
metadata:
  labels:
    platform.io/consume.vault-secrets.<instance>: "true"
# Pod template
metadata:
  labels:
    platform.io/capability-consumer.vault-secrets.<instance>: "true"
```

### `cnpg-postgres`

- **Stability:** ga
- **Instanced:** yes — instance source: `postgresql.cnpg.io/v1/Cluster`
- **Implementations:**
  - `cloudnative-pg` (port `postgres`, protocol `pgwire-v3`)


PostgreSQL via CloudNative-PG. Instance unit is one CNPG
`Cluster` CR. Consumers scope per cluster; cross-instance L4
access is denied.

**Consumer labels:**

```yaml
# Namespace
metadata:
  labels:
    platform.io/consume.cnpg-postgres.<instance>: "true"
# Pod template
metadata:
  labels:
    platform.io/capability-consumer.cnpg-postgres.<instance>: "true"
```

### `redis-managed`

- **Stability:** beta
- **Instanced:** yes — instance source: `redis.redis.opstreelabs.in/v1beta2/RedisReplication`
- **Implementations:**
  - `redis-operator` (port `redis`, protocol `resp3`)


Redis via OT-Container-Kit redis-operator. Instance unit is a
RedisReplication / RedisCluster / RedisStandalone / RedisSentinel
CR. Consumers scope per CR.

**Consumer labels:**

```yaml
# Namespace
metadata:
  labels:
    platform.io/consume.redis-managed.<instance>: "true"
# Pod template
metadata:
  labels:
    platform.io/capability-consumer.redis-managed.<instance>: "true"
```

### `rabbitmq-managed`

- **Stability:** beta
- **Instanced:** yes — instance source: `rabbitmq.com/v1beta1/RabbitmqCluster`
- **Implementations:**
  - `rabbitmq-cluster-operator` (port `amqp`, protocol `amqp-0-9-1`)


RabbitMQ via the official cluster-operator. Instance unit is a
RabbitmqCluster CR. messaging-topology-operator reconciles
topology via the management API (operator-dataplane path,
internal to PNI).

**Consumer labels:**

```yaml
# Namespace
metadata:
  labels:
    platform.io/consume.rabbitmq-managed.<instance>: "true"
# Pod template
metadata:
  labels:
    platform.io/capability-consumer.rabbitmq-managed.<instance>: "true"
```

### `kafka-managed`

- **Stability:** preview
- **Instanced:** yes — instance source: `kafka.strimzi.io/v1beta2/Kafka`
- **Implementations:**
  - `strimzi-kafka-operator` (port `tcp-clients`, protocol `kafka-wire`)


Apache Kafka via Strimzi. Instance unit is a Kafka CR.

**Consumer labels:**

```yaml
# Namespace
metadata:
  labels:
    platform.io/consume.kafka-managed.<instance>: "true"
# Pod template
metadata:
  labels:
    platform.io/capability-consumer.kafka-managed.<instance>: "true"
```

### `s3-object`

- **Stability:** ga
- **Instanced:** yes — instance source: `bucket`
- **Implementations:**
  - `minio-operator` (port `https`, protocol `s3-api`)
  - `external`


S3-API object storage. Instance unit is a bucket name. May
resolve to in-cluster MinIO or external S3; for external,
CCNP is FQDN/CIDR-based and no producer pod exists.

**Consumer labels:**

```yaml
# Namespace
metadata:
  labels:
    platform.io/consume.s3-object.<instance>: "true"
# Pod template
metadata:
  labels:
    platform.io/capability-consumer.s3-object.<instance>: "true"
```

### `admission-webhook-provider`

- **Stability:** ga

Reserved. Internal capability allowing kube-apiserver →
ValidatingAdmissionWebhook traffic to land at operator pods
carrying capability-provider.admission-webhook. Not part of
the tenant PNI vocabulary.

**Consumer labels:**

```yaml
# Namespace
metadata:
  labels:
    platform.io/consume.admission-webhook-provider: "true"
# Pod template
metadata:
  labels:
    platform.io/capability-consumer.admission-webhook-provider: "true"
```

### `monitoring-scrape-provider`

- **Stability:** —
- **Deprecated** — sunset: `2026-08-13`
- **Replaced by:** `monitoring-scrape`

Legacy alias from v0.1.0. The provider side of monitoring-scrape
is now represented by `capability-provider.monitoring-scrape` on
pods directly; this consume-side surrogate is redundant.

**Consumer labels:**


_Deprecated — do not introduce in new manifests._

### `logging-ship`

- **Stability:** ga
- **Implementations:**
  - `alloy`
  - `loki` (port `http`, protocol `loki-push-v1`)


Egress from a workload to the log aggregation pipeline (alloy
and/or loki). Kept as a single capability in v2; a future split
into logs-ingest / logs-query will land when a second log
backend or a downstream log-query consumer appears.

**Consumer labels:**

```yaml
# Namespace
metadata:
  labels:
    platform.io/consume.logging-ship: "true"
# Pod template
metadata:
  labels:
    platform.io/capability-consumer.logging-ship: "true"
```

