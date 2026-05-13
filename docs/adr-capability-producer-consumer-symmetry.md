# ADR: Capability Producer/Consumer Symmetry

**Status**: Accepted
**Date**: 2026-05-13
**Supersedes**: implicit consumer-only PNI contract as shipped through v0.1.0

## Context

The Platform Network Interface (PNI), as introduced through `talos-platform-base`
v0.1.0, encodes a **one-sided** capability contract:

- Consumer namespaces self-declare opt-in via `platform.io/consume.<cap>: "true"`.
- Consumer pods carry `platform.io/capability-consumer.<cap>: "true"`.
- Provider side is enforced by per-capability CiliumClusterwideNetworkPolicies
  (CCNPs) that match the implementing tool by `app.kubernetes.io/name` or by
  operator-specific selectors (`redis_setup_type`, `app.kubernetes.io/component`
  in the RabbitMQ case).

This works, but couples every consumer to the provider's *tool identity*. A
swap (Loki → Victoria-Logs, Piraeus → Rook, Vault → OpenBao, CNPG → StackGres)
silently breaks every CCNP whose `endpointSelector` mentioned the old tool by
name. Today only 5 of 18 effective capabilities carry a producer-side label
(`monitoring-scrape`, `admission-webhook`, `cnpg-postgres`, `redis-managed`,
`rabbitmq-managed`); the rest fall back to tool-name selectors.

A second gap: PNI currently grants L4 reachability at the **capability
granularity**, not the **instance granularity**. A namespace labelled
`consume.cnpg-postgres: "true"` is reachable to every CNPG cluster in the
fleet at L4. Data isolation between tenants collapses to whatever the
application-layer authentication (DB credentials, Vault policies) catches.
For a single-tenant homelab this is acceptable; for the multi-cluster
multi-tenant model the base is being built for, it is not.

## Decision

Adopt a **symmetric, instance-aware, capability-first** PNI contract. Tool
identity becomes an implementation detail; capability identity is the only
stable interface for consumer manifests, CCNP selectors, and discovery
tooling.

### Invariants — five label/annotation sites per Capability

For every Capability `<cap>` (and, where applicable, per Instance `<inst>`):

| Site                              | Key                                                              | Reserved? | Notes |
|-----------------------------------|------------------------------------------------------------------|-----------|-------|
| Producer namespace                | `platform.io/provide.<cap>[.<inst>]: "true"`                     | yes       | Kyverno-enforced; provider-side gate |
| Producer Pod (template)           | `platform.io/capability-provider.<cap>[.<inst>]: "true"`         | yes       | the selector load-bearing for CCNPs |
| Producer Service                  | annotations `platform.io/capability-endpoint.<cap>[.<inst>]: <port-name>` and `platform.io/capability-protocol.<cap>[.<inst>]: <wire-format>` | yes | discovery only — CCNPs do not match Service labels |
| Consumer namespace                | `platform.io/consume.<cap>[.<inst>]: "true"`                     | no        | consumer-set, free-form opt-in |
| Consumer Pod (template)           | `platform.io/capability-consumer.<cap>[.<inst>]: "true"`         | no        | mirrors namespace, scoped per workload |

The Service annotations are *not* used for enforcement (Cilium CCNP
`endpointSelector` matches Pod labels only). They exist for discovery
tooling, dashboards, and downstream tools that need to map a capability
to a concrete `service:port`.

### Granularity rule

A new Capability is warranted iff at least one of {port, wire protocol,
auth model, SLO class, consumer group} differs from an existing one.
Otherwise it is the same contract under a different name.

For HTTP-path-level distinctions (`gitops-api` vs `gitops-webhook`,
`secrets-kv` vs `secrets-pki-sign`), CCNPs cannot enforce the split at L4.
Such splits are **decorative** at the network layer and must be enforced at
the application layer (auth policy, RBAC, OIDC scopes). They are valid in
the registry only when (a) at least one consumer benefits from the
documentation/discovery distinction, and (b) the application layer carries
the actual enforcement.

### Per-instance scoping

Capabilities with multi-tenant data carry an instance suffix. Schema:

```
platform.io/consume.<cap>.<instance>:  "true"
platform.io/capability-consumer.<cap>.<instance>:  "true"
platform.io/provide.<cap>.<instance>:  "true"
platform.io/capability-provider.<cap>.<instance>:  "true"
```

Registry entry declares the instance source:

```yaml
- id: cnpg-postgres
  instanced: true
  instance_source: { apiVersion: postgresql.cnpg.io/v1, kind: Cluster }
```

For each `instanced: true` capability, Kyverno emits one `generate` policy
that watches `instance_source` and produces a CCNP per instance, and one
`mutate` policy that adds the per-instance label to producer pods owned by
the instance CR. Both ship in the per-instance refactor PR (PR D in
`.work/capability-refactor/plan.md`), not in this ADR's enabling PR (PR A).

Vault has no native cluster-CRD. Instance unit for `vault-secrets` is the
**KV mount path** (e.g. `team-foo`). Mutation is static (Helm values list),
not CRD-watched.

For capabilities without instances (cluster-singletons —
`monitoring-scrape`, `tls-issuance`, `gateway-backend`, `gpu-runtime`,
`internet-egress`, `controlplane-egress`, `hpa-metrics`,
`block-storage-{replicated,local}`), the bare suffix-less form is used.
The validate policy in PR D rejects the suffix-less form for `instanced:
true` capabilities, eliminating the multi-tenant collapse.

### Backwards compatibility — alias mechanism

Each renamed or split Capability keeps its legacy ID in the registry with:

```yaml
- id: storage-csi
  deprecated: true
  sunset: "2026-11-13"
  split_into: [block-storage-replicated, block-storage-local]
  disambiguation: |
    Use block-storage-replicated for stateful workloads needing cross-node
    DRBD replication; block-storage-local for ephemeral or single-node.
```

CCNPs match both old and new selectors in parallel during the grace window.
A conftest rule (`policies/conftest/capability_sunset.rego`) fails the
build on `now > sunset`. PR F (alias removal) ships automatically once a
sunset date passes — there is no "user go-ahead" gate; consumers receive
the deprecation signal mechanically.

### Namespace-anchored producer trust

The `capability-provider.<cap>[.<inst>]` label on a workload is **valid
iff** the workload's namespace carries the matching
`platform.io/provide.<cap>[.<inst>]: "true"` label. Trust derives from
the namespace, which is platform-controlled, not from tool-identifying
signatures on the pod.

This invariant rules out two anti-patterns that were considered and
explicitly rejected:

1. **Hardcoded tool-signature whitelists.** A central Kyverno policy
   that whitelists `app.kubernetes.io/component: rabbitmq`,
   `redis_setup_type: <X>`, `app.kubernetes.io/managed-by: <tool>`
   grows linearly with every producer integration, contradicts the
   "tools are swappable" core invariant of the capability-first
   architecture, and creates a central coupling point that every new
   capability or tool swap must edit. PR B explicitly deletes such
   signatures from `kyverno-clusterpolicy-pni-reserved-labels-enforce.yaml`
   and replaces them with the namespace-anchored rule.

2. **Kube-system exemptions.** A producer component that lives in
   `kube-system` (or any other shared system namespace) cannot
   self-attach the `provide.<cap>` trust anchor because the platform
   base does not control system namespaces. The architectural fix is
   **relocation to a dedicated, base-controlled namespace**, not a
   policy exemption. Symptom-fixing exemptions accumulate; relocation
   reverses the root cause. PR B relocates `metrics-server` from
   `kube-system` to a dedicated `metrics-server` namespace for this
   reason. `local-path-provisioner` (a consumer-overlay-deployed
   component) is documented in its `values.yaml` as requiring a
   dedicated `local-path-storage` namespace from the consumer side.

Every capability-provider component MUST therefore:

- ship its own `namespace.yaml` in this base (one per provider, even if
  it duplicates a shared namespace declaration like `monitoring`);
- declare in that `namespace.yaml` every `provide.<cap>` it provides;
- carry the matching `capability-provider.<cap>` on its pod template
  via Helm values (`podLabels`) or operator CRD wiring;
- expose endpoint discovery via Service annotations
  (`capability-endpoint.<cap>`, `capability-protocol.<cap>`).

The trust assertion (`provide.<cap>` on namespace) is itself a reserved
label — its setter is gated by RBAC (only platform-base manifests
applied via ArgoCD set it); a future Kyverno rule may add defence-in-
depth admission validation, but RBAC is the load-bearing control.

### Reserved-annotation enforcement

`platform.io/capability-endpoint.*` and `platform.io/capability-protocol.*`
on a Service from any tenant namespace are rejected by a new Kyverno policy
(`kyverno-clusterpolicy-pni-reserved-annotations-enforce.yaml`). Without
this, a malicious or buggy consumer manifest could forge endpoint
discovery and shadow the real provider in downstream tooling.

### Denial-message contract

Every PNI Kyverno policy MUST set `validate.message` (or
`foreach[].deny.message`) to a template of the form:

```
PNI violation: <resource kind> '<name>' in namespace '<ns>' <what is wrong>.
Add '<label key>: "<value>"' to <correct subject>.
See docs/capability-reference.md#<cap>
```

This is enforced by an extension to `make validate-kyverno-policies` —
policies without a parametrised message string fail the lint.

### Network-layer isolation scope

PNI provides **L4 reachability** between consumer and provider pods.
**L7 authorisation** (Vault tokens, Postgres roles, OIDC scopes,
Argo RBAC, Kafka ACLs) remains the responsibility of the application
layer. PNI does not, and will not, enforce identity-based or
attribute-based access at the network layer; that decision is deferred
to a future ADR if/when Cilium's identity-aware L7 features (or SPIFFE
integration) cross the cost/benefit threshold.

Per-instance scoping closes the *cross-instance* L4 collapse: a
compromised tenant pod with `consume.cnpg-postgres.team-foo` cannot
reach `team-bar`'s database at L4. It does not close the *intra-instance*
authorisation question — that remains app-layer.

## Consequences

### Positive

- Tool swaps become a producer-side label/annotation change; consumer
  manifests stay untouched. Loki → Victoria-Logs is a base-version bump
  for a consumer, not a manifest sweep.
- Per-instance L4 isolation eliminates the largest documented multi-tenant
  gap.
- Reserved annotations close the discovery-forgery vector.
- Mechanical sunset removes the debt-accumulator failure mode of
  open-ended deprecation windows.
- Capability reference doc auto-generated from registry — single source of
  truth, no docs drift.

### Negative

- Five Kyverno generate-policies + five mutate-policies + one validate
  policy add ~700 LoC of policy surface (PR D). All run in `Audit` mode
  during bootstrap to avoid sync-wave deadlock; flipped to `Enforce` once
  the registry ConfigMap is reconciled.
- StatefulSets carrying new labels (Vault, Piraeus) trigger rolling restart
  on first deployment of the new producer-label set. Accepted in PR C with
  no maintenance window (Vault HA standby→leader path; Piraeus DRBD in
  kernel).
- Cilium policy evaluation is OR-of-rules. During the alias grace window,
  pods double-labeled with legacy + new IDs match both old and new CCNPs;
  the union is permissive, which means narrowed-in-rewrite rules are
  silently widened during the window. Per-CCNP rewrite must be diff-direction
  audited before merge (see PR E acceptance criteria).
- Consumers vendoring an older OCI tag that skips the grace window
  experience hard breakage on the alias-removal release. Mitigated by:
  (a) `scripts/capability-deprecation-scan.sh` consumers run in their own
  CI, (b) `kubectl get policyreport -A` surfacing audit-mode warnings in
  live clusters, (c) MAJOR OCI tag bump on alias removal.

### Neutral

- Service-level annotations duplicate information that could be derived
  from the registry ConfigMap. The duplication is intentional — annotations
  travel with the live object and survive registry desync; the registry is
  the design-time source of truth, annotations are the runtime echo.

## Alternatives considered

### A1. Service-label-based CCNP selectors

Cilium `endpointSelector` matches Pod labels, not Service labels. A
Service-based selector would require a controller that mirrors Service
labels onto backing Pods. Adds machinery for no enforcement gain. Rejected.

### A2. CRD-based registry

A `CapabilityDefinition` CRD instead of a ConfigMap. Adds API versioning,
conversion webhooks, and an admission controller surface. The registry is
read by Kyverno (`context.configMap`) and by yq in shell scripts;
ConfigMap covers both with no machinery. Rejected.

### A3. SPIFFE / Cilium L7 identity

Per-instance authorisation at L7 with SPIFFE SVIDs. Overkill for L4
isolation; deferred to a future ADR.

### A4. Generate one CCNP per (capability × instance) at template time

Instead of Kyverno generate-policies watching CRDs, render CCNPs from the
registry + a list of instance names at kustomize time. Loses dynamic
instance creation — a new Postgres cluster would require a manifest
change in the base or in the consumer. Rejected because operator-managed
instance creation is the common case.

### A5. Keep registry IDs tool-named permanently

Drop the alias mechanism entirely; `cnpg-postgres` stays as-is forever.
Loses tool-swap resilience, which is the whole motivation. Rejected.

## Migration

Six PRs, sequenced in `.work/capability-refactor/plan.md`. PR A (this
ADR's enabling PR) is foundation-only and has no runtime effect. PR B and
C add producer labels. PR D introduces per-instance machinery. PR E
rewrites static CCNPs. PR F auto-fires on sunset.

## Validation

- `make validate-gitops` includes:
  - kustomize render of the rewritten registry ConfigMap
  - conftest rule `capability_sunset.rego` checking sunset dates
  - kubeconform schema check
- `make validate-kyverno-policies` includes the denial-message-contract lint
- `scripts/render-capability-reference.sh` is idempotent; CI fails on
  regen diff ≠ 0
- `scripts/lint-consume-labels.sh` is callable by consumer cluster repos
  via the vendored base

## References

- `.work/capability-refactor/plan.md` — full execution plan
- `kubernetes/base/infrastructure/platform-network-interface/resources/capability-registry-configmap.yaml` — registry v2 source
- `docs/capability-reference.md` — generated reference (do not hand-edit)
- `AGENTS.md` §Platform Network Interface (PNI) Rules — consumer contract surface
