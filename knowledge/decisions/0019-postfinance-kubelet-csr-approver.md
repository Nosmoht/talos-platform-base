---
type: decision
title: "ADR: Replace cert-approver (alex1989hu) with postfinance/kubelet-csr-approver + a per-cluster config surface"
description: "Swaps the seeded kubelet-serving approver to postfinance/kubelet-csr-approver, delivered as a chart-rendered templatefile() seed with a three-knob per-cluster config surface, superseding ADR-0013 §D2 while D1 stands."
status: accepted
id: base:postfinance-kubelet-csr-approver
decided: "2026-07-17T00:00:00Z"
deciders:
  - platform-maintainer
supersedes:
  - "/decisions/0013-kubelet-serving-cert-rotation.md §D2 (approver identity + seed mechanism)"
related:
  - base:kubelet-serving-cert-rotation
  - base:substrate-only-base
  - base:namespace-ownership-rendered-manifests
  - base:cluster-yaml-sot
  - base:opentofu-cluster-lifecycle
tags: [adr, talos]
---

# ADR: Replace cert-approver (alex1989hu) with postfinance/kubelet-csr-approver + a per-cluster config surface

## Context and Problem Statement

[ADR-0013](./0013-kubelet-serving-cert-rotation.md) turns kubelet serving-cert
rotation on for every cluster (D1) and seeds a `kubernetes.io/kubelet-serving`
CSR approver as a controlplane `inlineManifest` (D2). It chose
**alex1989hu/kubelet-serving-cert-approver** precisely because it needs **zero
per-cluster config** and ships as one static vendored manifest — and it
explicitly **rejected postfinance/kubelet-csr-approver** for needing
per-cluster `providerRegex` / `providerIpPrefixes`, which "would break this
base's cluster-agnostic, fixed-seed model." ADR-0013 §Security records the
resulting residual as accepted: alex1989hu does **not** bind the requested
DNS/IP SANs to the requesting node, so a compromised node authenticated as
`system:node:worker-1` can mint a serving cert naming another node — and the
SAN-to-node binding was delegated to a **consumer-cluster Kyverno** obligation
([ADR-0004](./0004-substrate-only-base.md) places the `kubelet-serving` policy
surface in consumer clusters; the base ships none).

That residual is live on every fresh cluster until a consumer writes the
Kyverno policy. The **owner decision (this ADR)** reverses the ADR-0013
cost/benefit: accept a small per-cluster config surface at the base layer in
exchange for a substrate approver that carries a per-node SAN binding
**by default**. The cluster-agnostic objection is answered structurally — the
base ships only the **schema + generic defaults**; the real node-naming /
subnet values live in consumer repos, exactly the category as `pod_cidr` or the
cluster endpoint (schema-in-base, values-in-consumer, PUBLIC-repo hygiene
intact). This is a MAJOR-versioned breaking change (approver identity, RBAC/pod
identity, metrics port, namespace rename, new config surface) superseding
**ADR-0013 §D2 only**; ADR-0013 §D1 (rotation default-on) stands unchanged.

Load-bearing runtime facts below were verified against postfinance source at
the pinned tree (`internal/controller/csr_controller.go`,
`internal/controller/regex_ip_checks.go`).

## Decision

### D1 — Approver identity: postfinance/kubelet-csr-approver v1.2.14, digest-pinned

The seeded approver becomes **postfinance/kubelet-csr-approver v1.2.14**, image
`ghcr.io/postfinance/kubelet-csr-approver:v1.2.14@sha256:c0f6aa1abdc225a32f9a29992fd97f711e78e2df21434f9ce7bc60981f96a5f8`
(multi-arch, `IfNotPresent`). The namespace and all object names / labels /
selectors rename `kubelet-serving-cert-approver` → **`kubelet-csr-approver`**.
It remains the **same controlplane `inlineManifest` seed** delivering all
nodes' approvals with zero consumer wiring, and it preserves every still-holding
ADR-0013 invariant: unconditional seed (no disable toggle), restricted-PSA
namespace, the six recommended labels on every object, controlplane tolerations,
namespace sole-ownership ([ADR-0002](./0002-namespace-ownership-rendered-manifests.md)),
and the `approve` verb signer-scoped to `kubernetes.io/kubelet-serving` only.

### D2 — Seed mechanism: chart-rendered, then `templatefile()`-parameterized

The seed is no longer a static vendored raw manifest read via `file()`. At pin
time the postfinance **Helm chart** (chart 1.2.14, SHA256
`4bd637228cd354c1fd8b8e44a0a1c9d7bc9074c01d3eb43c82d39ef11430a090`) is rendered
with our fixed values and committed as
`tofu/modules/talos-cluster/manifests/kubelet-csr-approver.yaml`, with **only**
the per-cluster values replaced by `${provider_regex}` / `${provider_ip_prefixes}`
/ `${replicas}` / `${leader_election}` placeholders. `main.tf` renders it once
into `local.cert_approver_manifest` via `templatefile()`, injecting the two
security values as `jsonencode()` scalars (safe single-line YAML). This gets the
container args / env / ports / probes / RBAC / securityContext correct **by
construction** from the chart (the upstream SoT) while keeping the vendored-seed
properties: provenance header, digest pin, offline determinism, readable diff.
`templatefile()` is pure, so it stays outside the `check-render-determinism.sh`
fence (which governs only `data.helm_template`). The file keeps a `.yaml`
extension (not `.yaml.tmpl`) so it stays inside the `check-spec-partition.py`
`manifests/*.yaml` governance universe.

### D3 — Three-knob per-cluster config surface, corrected defaults

`substrate.cert_approver` gains three keys (schema `additionalProperties: false`),
mapped through the consumer shim to module variables:

| Knob | Default | Semantics |
|---|---|---|
| `provider_regex` | `".*"` | `PROVIDER_REGEX` — cluster-wide DNS-SAN regex allowlist. |
| `provider_ip_prefixes` | `["0.0.0.0/0", "::/0"]` | `PROVIDER_IP_PREFIXES` — the CIDR set IP SANs must fall inside. **Never `[]`.** |
| `replicas` | `1` | Deployment replica count; `> 1` derives HA (see D4). |

The IP-prefix default is the **source-verified safe floor, never empty**:
`WhitelistedIPCheck` runs unconditionally and **denies** any SAN IP not in the
provider set, and kubelet serving CSRs carry node IPs as IP SANs — so an empty
`provider_ip_prefixes` denies **every** kubelet-serving CSR (the opposite of
"allow all"). `provider_regex` is validated to compile as an RE2 regex AND to
contain no `---` and no newline (a `---` would mis-split the audit outputs that
`split("---", …)` the rendered manifest). With the defaults, postfinance
approves conforming CSRs out-of-the-box **and** enforces the always-on per-node
DNS binding (D-Security); a consumer tightens `provider_ip_prefixes` to its node
subnets (and optionally `provider_regex`) for the additional IP-SAN-to-subnet
binding.

### D4 — `replicas` is a consumer knob (default 1); leader-election is derived

The base-wide default stays `replicas: 1` (single-node / edge clusters must not
be forced to 2), but a consumer can raise it for HA. **Leader-election + the
`coordination.k8s.io/leases` Role/RoleBinding are DERIVED** — rendered only when
`replicas > 1` (`local.cert_approver_leader_election = var.cert_approver_replicas > 1`).
The common `replicas: 1` case keeps least privilege (no leases rule, LE off); an
HA consumer gets a coherent config (the `-leader-election` arg + namespaced
leases RBAC) from the single knob. The consumer-settable HA option matters more
here than under ADR-0013's fixed single replica because postfinance **denies
terminally** (see §Consequences), so a stalled sole approver has sharper edges.

### D5 — `bypass_dns_resolution`: module-local constant `true`, not a schema knob

`BYPASS_DNS_RESOLUTION` is fixed `true` in the vendored manifest — the base
cannot assume node hostnames resolve in DNS. The per-node binding still comes
from the always-on hostname-prefix check + the IP-prefix check, so bypass-on
does not weaken it. Keeping the flag out of `cluster.yaml` avoids coupling the
MAJOR-versioned SoT to a tool flag; it is promoted to a knob only if a consumer
ever needs DNS-strict mode. `BypassHostnameCheck` stays `false` (never exposed)
— it is the per-node binding itself.

## Security model (verified at source)

The two approvers split the conformance surface differently — the switch is a
**trade, not a strict upgrade**:

- **postfinance** denies terminally (a `Denied` condition) any CSR that fails a
  check its controller **itself** performs, but that set is **narrower** than
  alex1989hu's: it does **not** inspect Subject `Organization`, email/URI SANs,
  or requested key usages. Those are enforced downstream by the built-in
  `kubernetes.io/kubelet-serving` signer, which marks an already-Approved but
  non-compliant CSR `Failed` (`SignerValidationFailure`), **not** `Denied`
  (source-verified against `pkg/controller/certificates/signer` +
  `pkg/apis/certificates/helpers.go`).
- **alex1989hu v0.11.0** validated `Organization`, email/URI SANs and key usages
  in its own `isRequestConform` (source-verified; see ADR-0013 §Security model)
  and left a non-conforming CSR `Pending` — but performed **no** SAN-to-node
  binding (its recorded "Known limitation").

The source-verified check split:

| Check | alex1989hu v0.11.0 | postfinance v1.2.14 | Delta |
|---|---|---|---|
| `username` prefix `system:node:` | yes (approver) | yes (approver) | = |
| `x509 CN == username` (identity bind) | yes (approver) | yes (approver) | = |
| ≥1 SAN present | yes (approver) | yes (approver) | = |
| `Organization == [system:nodes]` | approver (`Pending` if not) | signer only (`Failed` if not) | approval-time → signer-time |
| No email/URI SANs | approver (`Pending`) | signer only (`Failed`) | approval-time → signer-time |
| Key usages ⊆ serving set | approver (`Pending`) | signer only (`Failed`) | approval-time → signer-time |
| Expiration ≤ max bound | no (approver) | `expirationSeconds ≤ max` | new |
| `approve` RBAC scoped to `kubernetes.io/kubelet-serving` only | yes | yes | = |
| **DNS-SAN → node bind** | **none** (delegated to consumer Kyverno) | `HasPrefix(sanDNSName, node-hostname)`, always-on, regardless of `provider_regex` / `bypass_dns` | **new gain** |
| DNS-SAN regex allowlist | none | `PROVIDER_REGEX` (default `.*`) | new (opt-in tighten) |
| IP-SAN → subnet bind | none | `PROVIDER_IP_PREFIXES`, unconditional deny outside set | new (bounded by config) |

On the three `Organization` / email-URI / key-usage rows, postfinance moves
enforcement from **approval-time** (alex1989hu leaves it `Pending`) to
**issuance-time** (signer `Failed`) — a malformed CSR is refused a certificate
either way, but the condition type and alerting signal differ (alert on signer
`Failed`, not only `Denied` — see the observability migration in the upgrade
guide). In exchange postfinance adds the always-on DNS-SAN-to-node binding
alex1989hu lacked, closing on every fresh cluster the exact SAN-spoofing gap
ADR-0013 recorded as alex1989hu's "Known limitation". No field alex1989hu
enforced goes entirely unenforced — the three moved rows are still caught by the
signer; the binding gain is the more security-relevant side of the trade.

The always-on `HasPrefix(sanDNSName, hostname)` binding — `hostname` derived
from the CSR's `system:node:<hostname>` username — is a real gain over
alex1989hu, which did **no** SAN-to-node binding. It is default-on with the
generic defaults, closing on every fresh cluster the DNS-SAN half of the gap
ADR-0013 delegated to consumer Kyverno.

**Two honest residuals (source-verified — this is not a complete per-node bind):**

- **`HasPrefix`, not exact.** `node-1` matches `node-10` — numeric-suffix
  cross-node impersonation for hostnames that are prefixes of one another.
- **IP-only CSR short-circuit.** A CSR carrying **only IP SANs and no DNS name**
  short-circuits `DNSCheck` to valid (`if len(DNSNames)==0 { valid=true }`), so
  it is bounded **only** by `provider_ip_prefixes`. With the `0.0.0.0/0` default
  that bound is open; full IP-SAN-to-node binding requires the consumer to set
  `provider_ip_prefixes` to node subnets (still subnet-level, not per-node).

So the shipped default posture is "meaningfully stronger than alex1989hu for DNS
SANs, plus IP SANs bounded by the configured prefixes" — **not** a complete
per-node bind. Consumer Kyverno remains available for anything beyond
(exact-match hostname binding, per-node IP binding). Net of the approval-time →
signer-time trade on the three conformance rows above, the switch is a security
**gain** overall (the SAN-to-node binding closes a real spoofing gap; no field
alex1989hu enforced goes entirely unenforced), but it is **not** a strict
superset — on the three moved rows alex1989hu leaves a violating CSR `Pending`
(approver-time), while postfinance approves it and the signer marks it `Failed`
(issuance-time). (The terminal `Denied` condition is postfinance's own distinct
behavior for the checks it *does* perform — see the Consequences section — not
alex1989hu's.) The `approve` verb stays signer-restricted
(no client-signer escalation). The Deployment satisfies
restricted PSA (`runAsNonRoot`, `drop: [ALL]`, `readOnlyRootFilesystem`,
`seccompProfile: RuntimeDefault`, uid/gid 65532).

## Consequences

**Positive:** the DNS-SAN-to-node binding is default-on for every consumer with
no Kyverno prerequisite; a consumer can tighten to node subnets via one config
value; consumer-settable HA; still zero-wiring at bootstrap.

**Breaking (MAJOR OCI bump):**

- **Approver identity + pod/RBAC identity** change (new registry
  `ghcr.io/postfinance`, new ServiceAccount / ClusterRole / bindings, new pod
  labels/selectors).
- **Namespace rename** `kubelet-serving-cert-approver` → `kubelet-csr-approver`
  — anything a consumer scoped to the old namespace (ServiceMonitor selectors,
  NetworkPolicy, RBAC) breaks.
- **Metrics port 9090 → 8080** — ServiceMonitor / scrape config and alert
  expressions must move; postfinance metric names differ (a Pending/Denied-CSR
  alert must be re-expressed).
- **Denied-vs-Pending self-healing shift.** alex1989hu left non-conforming CSRs
  Pending (self-heal once a valid approver runs); postfinance writes a terminal
  `Denied`. A bad `provider_*` value → cluster-wide **Denied** serving CSRs
  (not Pending) → metrics-server / `logs|exec|top` break; recovery is a live
  `kubectl set env` to the safe floor, not a wait. A denied-CSR alert becomes
  valuable.
- **Create-only seed → config changes do NOT propagate on running clusters.**
  The per-cluster config takes effect **only at initial bootstrap**. On an
  already-bootstrapped cluster a `cluster.yaml` change re-renders the machine
  config but Talos does not update the running Deployment — tightening
  `provider_ip_prefixes` on a live cluster is a manual `kubectl set env` / patch
  or a deliberate re-seed. A consumer must not believe a `cluster.yaml` edit
  hardened a live cluster when it did not.
- **Migration double-approver window.** The old alex1989hu seed is create-only;
  Talos never deletes it, and the rename lands the new seed in a different
  namespace, so two cluster-scoped approvers coexist. The old permissive one can
  approve what a tightened new one would Deny (terminal, one-way) — so the old
  approver objects must be fully torn down (namespace + both ClusterRoles + the
  ClusterRoleBinding + the `events:` RoleBinding upstream plants in `default`)
  **before** tightening `provider_ip_prefixes`. Full sequence in
  `UPGRADING.md`.

## Validation

- **Mechanical (`tofu test`, `tests/composition.tftest.hcl`, red-green bound via
  module outputs):**
  - `kubelet_serving_cert_rotation_and_cert_approver_seed` (defaults) asserts:
    the seed is wired into the controlplane patch list and the base sub-list is
    a prefix of the final list; the namespace enforces PSA `restricted` + the
    six recommended labels; every seed object carries all six labels; the
    `approve` verb is resourceNames-scoped to **exactly**
    `[kubernetes.io/kubelet-serving]`; the default env decodes
    `PROVIDER_REGEX='.*'`, `PROVIDER_IP_PREFIXES='0.0.0.0/0,::/0'` (the all-IPs
    floor, not empty), `BYPASS_DNS_RESOLUTION='true'`; the container
    securityContext sets runAsNonRoot / readOnlyRootFilesystem / drop [ALL] /
    RuntimeDefault; and at `replicas: 1` there is **no** `-leader-election` arg
    and **no** `coordination.k8s.io/leases` RBAC rule (least privilege).
  - `cert_approver_ha_and_config_override` asserts: `replicas: 2` renders
    `replicas: 2` + the `-leader-election` arg + the namespaced leases RBAC rule;
    overridden `provider_regex` / `provider_ip_prefixes` flow through unchanged
    (escaping intact); and the approve scope stays signer-restricted in HA mode
    (not broadened).
- **Behavioral (homelab, out-of-band — CI has no live cluster):** under the
  generic defaults a kubelet-serving CSR reaches `Approved,Issued`; with a
  tightened `provider_ip_prefixes` a CSR whose IP SAN is **outside** the subnet
  is **Denied** (the actual new capability — automated gates prove render/wiring
  only). This deny-path is a **release gate**, not optional; the pinned version
  (D1) fixes the IP-check semantics so a later bump cannot drift them silently
  behind green render gates.
- **Wrong-if:** a postfinance bump renames an env var (`PROVIDER_*`) or changes
  the IP/DNS-check semantics (revisit the pin + the homelab predicate); Talos
  drops reconcile-on-change so the create-only seed no longer lands on running
  clusters (revisit the migration guidance).

## Alternatives considered

- **Keep alex1989hu (ADR-0013 status quo).** Rejected: the SAN-to-node residual
  stays live on every cluster until the consumer writes Kyverno, and the owner
  chose to close the DNS-SAN half at the substrate layer. This is the decision
  ADR-0013 §D2 made; this ADR reverses it on the config-surface cost/benefit.
- **Freeze the Helm render as a static `file()` manifest** (the ADR-0013
  vendored-static pattern). Rejected: the two security values must be
  per-cluster, so the manifest cannot be fully static; `templatefile()` over the
  chart-rendered output keeps chart-correct wiring AND per-cluster values, while
  a hand-edited static file would re-introduce the hand-wiring error class the
  chart render closes.
- **Permissive fixed config (no knobs, `.*` + all-IPs baked in).** Rejected: it
  would ship the default-on DNS binding but foreclose the IP-SAN-to-subnet
  tightening that is the headline reason to adopt postfinance — the knob is the
  value.
- **HA by default (`replicas: 2`).** Rejected: single-node / edge clusters must
  not be forced to two replicas; HA is a consumer opt-in (D4) with LE + leases
  derived, so the default stays least-privilege single-replica while HA is one
  knob away.

## References

- `tofu/modules/talos-cluster/manifests/kubelet-csr-approver.yaml` —
  chart-rendered, digest-pinned seed with `${…}` placeholders (provenance in the
  file header).
- `tofu/modules/talos-cluster/main.tf` — `cert_approver_manifest` (the
  `templatefile()` render), `cert_approver_leader_election`,
  `cert_approver_controlplane_patch`.
- `tofu/modules/talos-cluster/variables.tf` — `cert_approver_provider_regex`,
  `cert_approver_provider_ip_prefixes`, `cert_approver_replicas` (+ validations).
- `tofu/modules/talos-cluster/tests/composition.tftest.hcl` — the red-green AC
  gates (`kubelet_serving_cert_rotation_and_cert_approver_seed`,
  `cert_approver_ha_and_config_override`).
- [0013-kubelet-serving-cert-rotation.md](./0013-kubelet-serving-cert-rotation.md)
  — §D1 (rotation default-on) stands; §D2 (approver identity + seed mechanism)
  superseded here.
- [0004-substrate-only-base.md](./0004-substrate-only-base.md) — the consumer
  Kyverno / `kubelet-serving` policy surface this ADR partially relieves.
- postfinance/kubelet-csr-approver `internal/controller/csr_controller.go`,
  `internal/controller/regex_ip_checks.go` @ v1.2.14 (source of the security
  model above).
