# Upgrade Guide

For consumer-cluster repos vendoring `talos-platform-base` via OCI.

## How to use this file

- Per-release notes live in [`CHANGELOG.md`](CHANGELOG.md).
- This file documents **cumulative migration steps** for each MAJOR
  bump and any MINOR that requires a manual action.
- Read every section between the version you currently pin and the
  version you want to adopt. Apply in order.
- Always verify the new artifact (cosign + provenance) before vendoring
  — see [`knowledge/workflows/verify-release.md`](knowledge/workflows/verify-release.md).

## Upgrade workflow (every version)

```bash
# 1. Verify
TAG=v2.0.0; OWNER=Nosmoht   # TAG = your target tag; OWNER is case-sensitive in the identity regexp below (must match the owner's exact GitHub casing)
cosign verify \
  --certificate-identity-regexp \
    "^https://github.com/${OWNER}/talos-platform-base/\.github/workflows/oci-publish\.yml@refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$" \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  ghcr.io/${OWNER}/talos-platform-base:${TAG}

# 2. (capability / PNI deprecation scanning moved to the talos-platform-apps
#     catalog as of v2.0.0 — run its scan against your manifests there, not
#     against the substrate base.)

# 3. Render diff between current and target (steady-state argocd is the only
#    rendered component the artifact ships; compare its published render).
#    NOTE: `oras pull` deposits the tarball layer — it does NOT extract it;
#    the tar -xzf step is mandatory (consumer repos typically wrap this as
#    `task supply-chain:pull-base-oci` — prefer that where it exists).
cp vendor/base/kubernetes/substrate/argocd/_rendered/manifests.yaml /tmp/before.yaml
echo "${TAG}" > .base-version
rm -rf /tmp/base-pull && oras pull "ghcr.io/${OWNER}/talos-platform-base:${TAG}" --output /tmp/base-pull
rm -rf vendor/base && mkdir -p vendor/base
tar -xzf /tmp/base-pull/talos-platform-base-${TAG}.tar.gz -C vendor/base
diff -u /tmp/before.yaml vendor/base/kubernetes/substrate/argocd/_rendered/manifests.yaml | less

# 4. Apply consumer-overlay patches for any MAJOR-listed breaking change below.
# 5. Commit, open PR, let ArgoCD reconcile after merge.
```

---

## Unreleased (next MINOR) — steady-state ArgoCD relocated to `kubernetes/substrate/` and published in the OCI artifact (MINOR — manual action for argocd-overlay consumers)

**Type:** MINOR (additive for consumers). Decision: ADR-0024
(`knowledge/decisions/0024-argocd-substrate-relocation.md`, issue #156,
Option 3). Two changes land together:

1. The steady-state ArgoCD component moved from
   `kubernetes/base/infrastructure/argocd/` to `kubernetes/substrate/argocd/`;
   the now-empty `kubernetes/base/` tree is retired.
2. The component's consumable files are now **in the OCI artifact** —
   `kubernetes/substrate/argocd/{namespace.yaml,_rendered/manifests.yaml,_rendered/crds.yaml}`
   were added to `.ci-oci-tarball-include.txt`. Before this release the
   steady-state tree existed only in git and was unconsumable at every
   published tag (the gap #156 documents; tracked downstream as the
   consumer's render-reproducibility issue).

This is NOT a breaking change for OCI consumers: the old path was never
present in any published artifact, so no consumer overlay that rendered
successfully from a published tag can break. Consumers whose argocd overlay
referenced the old path (and therefore only rendered against a stale
hand-pulled `vendor/base/`) update their `resources:` entries:

```yaml
# BEFORE (never satisfiable from a published artifact)
resources:
  - ../../../../../../vendor/base/kubernetes/base/infrastructure/argocd/namespace.yaml
  - ../../../../../../vendor/base/kubernetes/base/infrastructure/argocd/_rendered/manifests.yaml
  - ../../../../../../vendor/base/kubernetes/base/infrastructure/argocd/_rendered/crds.yaml

# AFTER
resources:
  - ../../../../../../vendor/base/kubernetes/substrate/argocd/namespace.yaml
  - ../../../../../../vendor/base/kubernetes/substrate/argocd/_rendered/manifests.yaml
  - ../../../../../../vendor/base/kubernetes/substrate/argocd/_rendered/crds.yaml
```

The `resources:` edit is the load-bearing change but NOT the whole
migration: grep your consumer tree for
`vendor/base/kubernetes/base/infrastructure/argocd` and update **every**
hit — incident runbooks (for example a self-cutover recovery step that
`kubectl apply`s the vendored render) and render scripts carry the same
path, and because the puller wipes `vendor/base/` on every pull, a stale
runbook path is discovered mid-incident, not at migration time. Then
re-pull the artifact and verify render-equivalence against your
previously committed consumer render (kustomize-patched values like
`argocd-cm.url` ride on top unchanged).

**Back-out:** the revert is paired, never partial. Rolling the base pin
back to a pre-relocation tag restores a tarball WITHOUT
`kubernetes/substrate/argocd/**`, so the pin revert and the consumer-side
path revert (the `resources:` lines and every grep hit above) must land
together — reverting only one half leaves kustomize pointing at paths no
artifact satisfies. `vendor/base/` does not preserve old files across
pulls.

Adjacency note: #105 (deliver ArgoCD CRDs without imperative `kubectl
apply`) governs the same `crds.yaml` payload the artifact now ships; its
outcome may reshape how the *bootstrap seed* delivers CRDs but does not
change this steady-state publication path.

---

## Unreleased (next MINOR) — Cilium chart `1.19.4` → `1.20.0` (MINOR — action required for EVERY consumer)

**Type:** MINOR by interface (no input renamed, no input removed, no schema
change) — but **not** low-effort to adopt, and the SemVer label is the wrong
signal to plan from. Read §1–§5 before adopting: §4 requires a NetworkPolicy
audit from every consumer on default settings, §3 requires policy edits before
upgrading, §2 requires a Gateway API CRD move first, and §1 changes how you
treat controlplane add/replace.
Cilium 1.20.0 was released 2026-07-29 and becomes the base's substrate CNI seed
version. Re-verification at the new pin is recorded as a dated addendum in
[`knowledge/decisions/0022-cilium-observability-and-argocd-self-management.md`](knowledge/decisions/0022-cilium-observability-and-argocd-self-management.md).

**Before anything else: nothing below reaches you until you move your own pin.**
The module default (`cilium_chart_version`, now `1.20.0`) is consulted only when
the caller passes nothing, and both shipped consumer paths pass it explicitly:
`cluster.yaml` carries `substrate.cilium.chart_version`, and the example shim
reads that as `try(local.cilium.chart_version, "<literal>")` — where the literal
is whatever the base shipped when you copied the shim. A consumer created from an
earlier tag therefore keeps rendering 1.19.4 after vendoring this one: no 1.20
render, no self-management move, and §2–§5 not yet in effect. Two edits, both in
files you own:

1. Set `substrate.cilium.chart_version: "1.20.0"` in your `cluster.yaml`.
2. Update the fallback literal in your copied shim if it still reads `1.19.4`.

A fresh bootstrap from the current `cluster.yaml.example` already carries 1.20.0
and needs neither edit.

### 1. Running clusters are NOT upgraded by this bump — but the frozen seed goes stale (affects anyone who adds or replaces a controlplane)

`cilium_chart_version` is a **seed knob**. `terraform_data.cilium_render` carries
`ignore_changes = [input]` and Talos `inlineManifests` are create-only, so
adopting a base tag that pins Cilium 1.20.0 does **not** upgrade Cilium on an
already-bootstrapped cluster. The new pin applies to fresh bootstraps, and to a
deliberate `tofu apply -replace=terraform_data.cilium_render[0]`.

What the bump *does* do on an existing consumer who moved the pin:
`data.helm_template.cilium` is re-read on every `tofu plan`, so your next plan
pulls chart 1.20.0 and re-renders in memory. **Your plan should still show no
machine-config change.**
`ignore_changes = [input]` means the re-render never reaches the frozen output,
so the controlplane patch — and therefore the machine configuration — is
unchanged; that is the contract in
`openspec/specs/cilium-cni-delivery/spec.md` ("Render drift does not churn
machine config"). If your plan *does* want to change machine config here, treat
it as this repo treats any unexpected plan: **stop and investigate**, do not
apply.

What the re-read *can* do is fail: the data source carries a postcondition
rejecting an empty render, and `helm template` errors on a malformed or
type-invalid value. A key that 1.20 merely **removed** does not error — Helm
runs without `--strict`, so it is dropped silently (that is the whole point of
§3). So a clean plan is **not** evidence that your `cilium_values_override`
survived; audit it against §3 by hand.

**Check your Kubernetes version first — the base does not pin it.**
`kubernetes_version` is a required module input with no default (its only
constraint is a v-prefixed-semver validation), so the version in play is whatever
your `cluster.yaml` sets. The `v1.35.0` in `cluster.yaml.example` is an example
value, not a pin. Cilium 1.20 lists Kubernetes **1.33–1.36** as e2e-tested
(`Documentation/network/kubernetes/requirements.rst` at tag `v1.20.0`), against
1.31–1.34 for Cilium 1.19 — the overlap is 1.33 and 1.34. Below 1.33 the
combination is outside the tested set: the agent still starts, since Cilium's
coded floor is 1.21 (`pkg/k8s/version/version.go`, `MinimalVersionConstraint`,
unchanged between the two versions), but upstream does not test it. If your
cluster runs 1.32 or earlier, raise Kubernetes to at least 1.33 before moving the
pin, or stay on Cilium 1.19 for now. No Talos bump is required either way.

**The flip side — a stale seed outlives the pin, and this bump is the first time
the gap is a whole minor.** `ignore_changes = [input]` freezes the render in
state *for the life of that state*, and `local.cilium_controlplane_patch` feeds
that one frozen value into **every** controlplane machine config — including the
config generated for a controlplane you add or replace later. So on a cluster
that was bootstrapped at the old pin and has since been moved to 1.20.0 through
the emitted self-management Application, a controlplane join re-seeds *1.19.4*
Cilium objects into a cluster running 1.20.0. ADR-0022 already recognizes this
class of stale-seed skew for the `cilium_values_override` dimension
(§k and the bootstrap-window datapath gap section, whose advice is to hold node
reboots/replacements until ArgoCD's adoption sync is confirmed); the chart
version is a second dimension of the same gap.

The conservative response, and the only one this base can recommend without
qualification: **treat controlplane add/replace on such a cluster as a planned
operation** — know that the joining node is seeded at the old chart version, and
verify the running Cilium version on it after ArgoCD reconciles, rather than
assuming the join produced a 1.20.0 node.

`tofu apply -replace=terraform_data.cilium_render[0]` is the only mechanism that
re-captures the render, but it is **not** a drop-in "make them agree" step and
this base does not recommend it blind. At minimum it rewrites the controlplane
patch, so machine config re-pushes to **every** controlplane — the churn and
single-node-controlplane self-eviction hazard the seed floor's own header
documents. Beyond that, two things are unverified here and you must establish
them for your own cluster before running it: whether Talos' manifest reconcile
*updates* Cilium objects it already created or only creates missing ones (a
create-only reconcile yields a mixed-version install, not agreement), and
whether the objects it would create are already owned by your self-management
`Application` (two writers on the same cluster-scoped resources — the ownership
problem v3.0.0 §3 and v7.0.0 §6 both treat as needing deliberate orphaning).
Dry-run it with `tofu plan` and inspect the `talos_machine_configuration_apply`
diff before deciding.

### 2. Gateway API must reach v1.6.1 BEFORE Cilium 1.20 (affects every Gateway-API consumer)

Cilium 1.20 requires **Gateway API v1.6.1 at a minimum**, because `TLSRoute`
graduated from `v1alpha2` to `v1`. The base previously documented v1.4.1.

- **Fresh clusters, or clusters with no `TLSRoute` objects:** seed or apply the
  **standard** channel bundle. `TLSRoute` is in the standard channel as of
  v1.6.1 (served at `v1`), so standard alone satisfies the Gateway-API-only Hard
  Constraint. The previous "use the experimental bundle for TLSRoute" guidance is
  retired.

  ```text
  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml
  ```

- **Clusters carrying pre-existing `v1alpha2` TLSRoute objects:** use the
  **experimental** bundle instead. The served flags were verified: in standard
  v1.6.1 `TLSRoute` serves only `v1` (`v1alpha2` and `v1alpha3` are declared with
  `served: false`), while experimental v1.6.1 serves all three. Upstream's own
  warning is that with the standard bundle existing `TLSRoute` objects "will not
  be able to be read by the apiserver from etcd, and will effectively disappear
  from your cluster" — that consequence is upstream's claim, not something this
  base has reproduced, but the served flags are consistent with it and the
  downside of being wrong is losing route objects. Back up your `TLSRoute`
  resources first regardless, upgrade Gateway API to v1.6.1, then move Cilium.

- **Clusters that followed the base's PREVIOUS guidance** ("use the experimental
  bundle for TLSRoute") already have the **experimental** bundle installed. Do
  not read bullet one as "switch to standard": applying `standard-install.yaml`
  over an experimental installation replaces the shared CRDs, drops served
  `v1alpha2` from `TLSRoute`, and leaves the experimental-only CRDs
  (`TCPRoute`, `UDPRoute`, …) orphaned at stale versions rather than removing
  them. Stay on experimental v1.6.1 unless you deliberately plan that migration.

**Which knob:** if you opted into bootstrap seeding, the CRD bundle URL lives in
`cluster.yaml` at `substrate.cilium.gateway_api_crds_url` (module input
`cilium_gateway_api_crds_url`). Editing it changes what Talos fetches via
`cluster.extraManifests` — but Talos' manifest handling is create-oriented, so
do **not** assume editing the URL upgrades CRDs Talos already created. Verify the
CRDs' actual `bundle-version` annotation in-cluster after applying (command in
§Validation), and if they did not move, apply the new bundle through your normal
Day-1 GitOps path instead. Consumers who left the input empty (the default) apply
CRDs via GitOps already and simply point that at v1.6.1.

Order matters: Gateway API first, Cilium second.

**Also newly tunable, but NOT a behavior change: `gatewayAPI.useRemoteAddress`.**
This Helm value does not exist in chart 1.19.4 and defaults to **`true`** in
1.20.0, rendering `gateway-api-use-remote-address: "true"` in `cilium-config`.
The default **preserves** 1.19 behavior instead of changing it: Cilium 1.19
already hardcoded the same Envoy setting in its Gateway listener translation
(`operator/pkg/model/translation/envoy_http_connection_manager.go` at tag
`v1.19.4` sets `UseRemoteAddress: true` alongside `SkipXffAppend: false`), and
1.20 keeps that same literal while adding a mutator that lets the config override
it (`envoy_listener.go`, `withUseRemoteAddress`). What 1.20 adds is the knob, not
a new posture — so no action is required unless you deliberately want the
non-default value.

Get the direction right before touching it. Per the chart's own description of
the value, enabling it means the source IP is determined from the client's remote
address instead of the proxy-protocol header. So `true` trusts the connection
peer, and a client-supplied `X-Forwarded-For` is not what the Gateway treats as
the client address; `false` is the setting that makes a forwarded address
authoritative, which is safe only where a trusted proxy is the sole path to the
Gateway. Setting `false` does not return you to 1.19 — it departs from 1.19.
Change it, or `xffNumTrustedHops` (present in both versions), only for a
deliberate trusted-proxy topology, and check the combination against Envoy's
`use_remote_address` and X-Forwarded-For documentation for that topology.

**Enabling Gateway API in 1.20 also forces two datapath keys on.** The base sets
`cilium_gateway_api = true` by default, so this applies unless you turned it off.
Rendering the base's own default value set (floor ⊕ computed) against both charts
produces exactly one changed `cilium-config` value, plus one newly emitted key:

| `cilium-config` key | 1.19.4 | 1.20.0 | Why |
|---|---|---|---|
| `bpf-lb-algorithm-annotation` | `"false"` | `"true"` | 1.20's ConfigMap template forces it `"true"` whenever `gatewayAPI.enabled`, so per-backend weights on TCPRoute/UDPRoute take effect. |
| `bpf-lb-sock-hostns-only` | not emitted | `"true"` | Same forcing branch. 1.19.4 emits this key only when `socketLB.hostNamespaceOnly` is set, and neither the chart nor the base sets it. |

The first one needs an audit. `bpf-lb-algorithm-annotation` gates whether the
`service.cilium.io/lb-algorithm` annotation is honored per Service. While it was
`"false"`, any such annotation already on your Services was **inert**; once it is
`"true"` those annotations start selecting the load-balancing algorithm for real.
Before a fresh 1.20 bootstrap or a self-management sync, find them and confirm
each value is one you want in effect — your GitOps repo is the authoritative
place to look:

```shell
git grep -n "service.cilium.io/lb-algorithm"
```

For anything applied outside GitOps, the same grep over
`kubectl get svc -A -o yaml` gives a coarse cluster-side listing.

### 3. Removed Helm values — audit your `cilium_values_override` (affects consumers who set encryption strict mode, or any removed key)

Cilium 1.20 **removed** the flat `encryption.strictMode.{enabled,cidr,
allowRemoteNodeIdentities}` values (deprecated in 1.19). Helm does not run
`--strict`, so a removed key is **silently dropped** — strict-mode encryption
would simply not be configured, with no error at plan, render, or apply time.

The base's reference file `kubernetes/bootstrap/cilium/values.yaml` is migrated
for you. If your own `cilium_values_override` sets the flat form, migrate it:

```yaml
# BEFORE (silently ignored on Cilium 1.20)
encryption:
  strictMode:
    enabled: true
    cidr: "10.244.0.0/16"
    allowRemoteNodeIdentities: true

# AFTER (also renders correctly on 1.19.x)
encryption:
  strictMode:
    egress:
      enabled: true
      cidr: "10.244.0.0/16"
      allowRemoteNodeIdentities: true
```

Other **Helm values** removed in 1.20 that an override might carry:
`clustermesh.enableMCSAPISupport` (use `clustermesh.mcsapi.enabled`),
`encryption.ipsec.interface`, `encryption.ipsec.encryptedOverlay`,
`encryption.strictMode.{enabled,cidr,allowRemoteNodeIdentities}` (above),
`hubble.redact.kafka.apiKey`, and `preflight.tofqdnsPreCache`.
`hubble.preferIpv6` is deprecated in favor of the top-level `preferIpv6`.

Upstream also removes the `--node-port-algorithm` and `--node-port-mode` **agent
flags** in favor of `--bpf-lb-algorithm` / `--bpf-lb-mode`. Those are flag
spellings, not Helm keys, so grepping your override for them finds nothing even
when you are affected: the Helm surface is `loadBalancer.algorithm` and
`loadBalancer.mode`. Audit the Helm keys, not the flags.

`CiliumNodeConfig` resources must be `cilium.io/v2` (`v2alpha1` is removed).

Kafka-aware network policies and Envoy Go extensions (proxylib) are removed
outright. Upstream's instruction is to remove the `rules` section from any
`CiliumNetworkPolicy` / `CiliumClusterwideNetworkPolicy` carrying `kafka`, `l7`
or `l7proto` **before** upgrading — but do not apply it mechanically:

> ⚠️ Those rules live under `.spec.{ingress,egress}[].toPorts[].rules`. Deleting
> the `rules` block while leaving its `toPorts` entry in place converts "allow
> only these L7 requests on this port" into **"allow all traffic on this
> port"** — a silent policy widening, done as an upgrade prerequisite. If the L7
> restriction was load-bearing, remove or tighten the whole `toPorts` entry
> instead, or replace the L7 constraint with an equivalent the 1.20 proxy still
> supports. Diff your effective policy set before and after.

### 4. NodePort traffic is now load-balanced at the CLIENT pod — audit NetworkPolicy (affects EVERY consumer on default settings)

This is a **datapath behavior change**, not a config change, and the base's
defaults put every consumer in its scope: `cilium_kube_proxy_replacement`
defaults to `true`, and the base does not set `socketLB`, so the chart default
`socketLB.enabled: false` applies.

Upstream's 1.20 release notes state it directly: with `KubeProxyReplacement` for
Service load-balancing and SocketLB either **disabled** or configured with
`socketLB.hostNamespaceOnly=true`, in-cluster connections to NodePort Services by
regular pods are now immediately load-balanced when network traffic leaves the
client pod, and not at the targeted node — matching the behavior when SocketLB
is enabled. The base meets the first trigger condition on its defaults, and — via
`cilium_gateway_api = true` — the second as well, since the chart forces
`bpf-lb-sock-hostns-only: "true"` whenever Gateway API is enabled. Note that key
is forced for Maglev per-backend-weight reasons, so treat it as a config
observation, **not** as proof of this behavior change; the release notes are the
basis for the claim.

Consequence: the client pod's NetworkPolicy must allow **egress to the
Service's backend pods**, and each backend's NetworkPolicy must allow **ingress
from the client pod**. A policy that previously only allowed egress to the node
IP / NodePort will now drop the connection. Audit any `CiliumNetworkPolicy`,
`CiliumClusterwideNetworkPolicy` or Kubernetes `NetworkPolicy` governing
in-cluster NodePort access before a fresh 1.20 bootstrap or a self-management
sync.

### 5. Self-management consumers get Cilium 1.20 on next sync (affects `cilium_self_management = true`)

The emitted Application's `spec.source.targetRevision` tracks
`cilium_chart_version`, so once you move the pin (see the note above §1) your
self-managed Cilium goes to 1.20.0 the next time ArgoCD syncs that Application.
Vendoring this base tag alone does not do it — the pin your shim passes is the
one that lands in `targetRevision`. The module emits no
`syncPolicy` — sync timing is yours. Read the upstream 1.20 upgrade notes and
§2/§3 above before syncing, and note that traffic through user-space proxies
(L7 policy, Gateway API) is disrupted during the agent roll.

One new failure mode if you copied this base's reference values
(`kubernetes/bootstrap/cilium/values.yaml`) with Hubble Relay/UI enabled: that
file sets `hubble.tls.auto.method: cronJob`, and Cilium 1.20 makes certgen
**hard-fail** when the CA chain is not valid for the entire leaf-certificate
duration (new `certgen.enforceCAValidityThroughoutLeavesDuration`, default
enabled).

State the trigger as a relation, not a date: the rotation CronJob now errors
whenever the CA's **remaining** validity is shorter than the leaf validity it
is being asked to issue. Leaf validity is
`hubble.tls.auto.certValidityDuration`, which defaults to **365** days in both
1.19.4 and 1.20.0; the reference file does not pin it, and the chart exposes no
CA-duration knob (`certgen.generateCA: true` uses certgen's own default), so the
margin is whatever your CA was created with. Consequence: this can fire on a
routine rotation well before the CA itself expires, not only when the CA is
nearly dead — and regenerating the CA buys only (CA duration − leaf duration)
before it recurs. Either set `certgen.enforceCAValidityThroughoutLeavesDuration=false`
to keep the old silently-over-long-leaf behavior, or pin
`hubble.tls.auto.certValidityDuration` short enough to stay inside your CA's
remaining life. The failure is quiet: a failing CronJob emits no readiness
signal and Relay/UI keep serving the existing leaf, so without alerting on
CronJob failures you learn about it at leaf expiry.

This does not affect the bootstrap seed (Hubble is off in the floor) or the
module's `cilium_hubble_enabled` observability path, which forces
`hubble.tls.enabled=false` — metrics-only, no certgen.

**Back-out:** the two delivery paths roll back differently and must not be
confused. For the **seed**, `ignore_changes = [input]` blocks re-capture in
**both** directions, so which action reverts it depends on how you adopted it:

- If you never re-froze, re-pinning an earlier base tag is enough and touches
  nothing running — the frozen render is still the old one, so no machine config
  changes and no node is disturbed.
- If you adopted the new pin via `tofu apply -replace=terraform_data.cilium_render[0]`
  (the path §1 recommends), re-pinning the tag alone does **not** revert the
  seed — the 1.20.0 render stays frozen in state and the next controlplane join
  would seed it into a cluster you believe is rolled back. Run a second
  `-replace` at the earlier pin and confirm the plan's machine-config diff shows
  the 1.19.4 render. Land that paired revert **before** any controlplane
  add/replace, not after.

For **self-management**, a rollback is a real running downgrade of the CNI: pin
the previous
`cilium_chart_version` and re-sync. Cilium supports rollback only between
consecutive minors, and only before new-minor features have been consumed — so
roll back promptly if at all, and consult the upstream version notes first if
any 1.20-only feature (for example `encryption.strictMode.ingress`,
`bpf.datapathMode=auto`) was enabled in the interim.

Reverting §2 needs care — leaving the CRDs untouched is **not** safe. Cilium
1.19 documents support for Gateway API v1.4.1 and expects `TLSRoute` at
`v1alpha2`, which the v1.6.1 **standard** bundle declares but does not serve —
so a Cilium downgrade to 1.19 while standard v1.6.1 is installed leaves 1.19
unable to read `TLSRoute`. If you use `TLSRoute` and must roll Cilium back,
install the v1.6.1 **experimental** bundle (it serves `v1alpha2`) before
downgrading, or plan a coordinated CRD downgrade. Consumers with no `TLSRoute`
objects are unaffected: HTTPRoute/Gateway/GatewayClass are `v1` in both
bundles.

### Validation steps after upgrade

1. `task tofu:ci` in the base (or your vendored copy) — offline gates.
2. `task tofu:test` — **networked**; the only gate that actually pulls chart
   1.20.0 and re-binds the seed-render assertions. Not run by `tofu:ci`.
3. `tofu plan` in your consumer root — the Cilium re-render must produce **no**
   machine-config change and no chart error (§1). A machine-config diff here is a
   signal to stop and investigate, not something to apply.
4. `task gitops:validate` in your consumer repo.
5. Confirm Gateway API actually reached v1.6.1 **before** syncing Cilium — this
   is also the check for whether editing `gateway_api_crds_url` updated
   already-created CRDs (§2):

   ```shell
   kubectl get crd tlsroutes.gateway.networking.k8s.io \
     -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}{"\n"}'
   kubectl get crd tlsroutes.gateway.networking.k8s.io \
     -o jsonpath='{range .spec.versions[*]}{.name}{" served="}{.served}{"\n"}{end}'
   ```

   The second command tells you which `TLSRoute` versions are actually served —
   the standard-vs-experimental distinction §2 turns on.
6. If you have `TLSRoute` objects, confirm they still list after the CRD move:
   `kubectl get tlsroutes.gateway.networking.k8s.io -A`.

---

## `v8.0.0` — `nodes` is keyed by node name (MAJOR — consumer-facing)

**Type:** MAJOR (input-shape breaking, runtime-neutral). `var.nodes` /
`cluster.yaml` `nodes:` change from a LIST of node objects to a MAP keyed by the
node's name. The per-node `hostname` field is removed — the key *is* the
hostname. See [ADR-0023](knowledge/decisions/0023-node-identity-map-key.md).

Nothing about a running cluster changes: the per-node apply resource is still
`for_each`-keyed by the same hostname strings, so state addresses are stable and
an unchanged node set must produce a **zero-diff plan**. If your plan is not
empty after the conversion, stop and investigate — do not apply.

### 1. Convert `cluster.yaml` `nodes:` to a mapping (required)

```yaml
# BEFORE (v7)
nodes:
  - hostname: node-01
    ip: 192.0.2.11
    role: controlplane
    image: intel

# AFTER (v8) — the key is the hostname; the field is gone
nodes:
  node-01:
    ip: 192.0.2.11
    role: controlplane
    image: intel
```

Mechanically, with `yq` (mikefarah, v4). **Run the duplicate check first** — the
conversion cannot detect a hostname declared twice, and a collapsed node silently
leaves `for_each`, which drops it from state and from every future config
rollout while the machine keeps running:

```bash
cp cluster.yaml cluster.yaml.orig                 # the verification below needs it

# Refuse to convert a file that already carries the defect this change removes.
test "$(yq '[.nodes[].hostname] | length' cluster.yaml.orig)" \
   = "$(yq '[.nodes[].hostname] | unique | length' cluster.yaml.orig)" \
  || { echo "duplicate hostname in cluster.yaml — resolve it before converting"; exit 1; }

yq -i '.nodes |= ([.[] | {"key": .hostname, "value": (del(.hostname))}] | from_entries)' cluster.yaml
```

Then verify nothing was lost. Both sides re-attach the hostname and normalise
key order, so a correct conversion prints nothing and any real loss shows up:

```bash
diff <(yq -o=json '[.nodes[]]                                    | sort_by(.hostname) | sort_keys(..)' cluster.yaml.orig) \
     <(yq -o=json '[.nodes | to_entries[] | .value * {"hostname": .key}] | sort_by(.hostname) | sort_keys(..)' cluster.yaml) \
  && echo "conversion lost nothing"
```

> `yq -i` re-serialises the WHOLE document, not just `.nodes`. If your
> `config_patches` use literal block scalars (`|`), check `git diff cluster.yaml`
> for restyling outside `.nodes` before committing: a re-styled patch string is a
> changed value in `talos_machine_configuration_apply`, which would re-push
> machine config to those nodes and break the zero-diff expectation below.

### 2. Update your consumer shim (required)

```hcl
# BEFORE
nodes = [for n in local.cfg.nodes : {
  hostname              = n.hostname
  ip                    = n.ip
  role                  = n.role
  image                 = n.image
  hardware_capabilities = try(n.hardware_capabilities, [])
  config_patches        = [for p in try(n.config_patches, []) : yamlencode(p)]
}]

# AFTER — every field except hostname carries over unchanged
nodes = { for name, n in local.cfg.nodes : name => {
  ip                    = n.ip
  role                  = n.role
  image                 = n.image
  hardware_capabilities = try(n.hardware_capabilities, [])
  config_patches        = [for p in try(n.config_patches, []) : yamlencode(p)]
} }
```

Do not shorten the field list while converting: `hardware_capabilities` and
`config_patches` are `optional(..., [])`, so dropping them is **silent** — the
node loses its capability composition and its per-node patches, and the plan
that rewrites its machine config looks entirely valid.

Any `for n in local.cfg.nodes : n.hostname => …` comprehension elsewhere in your
root becomes `for name, n in local.cfg.nodes : name => …`.

### 3. Update tooling that looked a node up by field (required if you have any)

`yq` selectors keyed on the hostname field must become key lookups:

```bash
# BEFORE
yq -r '.nodes[] | select(.hostname == "node-01") | .ip' cluster.yaml
# AFTER
yq -r '.nodes["node-01"].ip' cluster.yaml
```

Role filters (`.nodes[] | select(.role == "controlplane") | .ip`) keep working
unchanged — `yq`'s `.nodes[]` iterates a mapping's values.

### 4. New rejections — these may fail your first plan

Six rules the list model could not express are now enforced at plan time. Each
one names a real, previously silent failure mode:

- **The controlplane count must be ODD.** An even etcd membership tolerates no
  more failures than the odd count below it. Two consequences to plan around:
  growing 3 → 5 must be declared in one step, and a dead control-plane node
  cannot be *removed* to leave 2 — **replace its entry** (same key, new IP /
  hardware) instead of deleting it. The rule lives on `var.nodes`, so while it
  fails, nothing else in your root plans either.
- **Node keys must already be canonical Kubernetes node names** — lowercase
  `[a-z0-9-.]`, no leading/trailing `-` or `.`, ≤63 per label, ≤253 total.
  Talos validates hostname LENGTH only and then silently rewrites the rest
  (`nodename.FromHostname`: lowercase, `_` → `-`, other characters dropped), so
  a key like `NODE_01` would have arrived in Kubernetes as `node-01` — a
  different name than the one you declared, and one that two different keys can
  collide onto.
- **First labels must be unique while `register_with_fqdn` is false.** Talos
  splits the hostname at the first dot and registers the SHORT hostname, so
  `node-a.site1.example.org` and `node-a.site2.example.org` would put two
  kubelets on one Node object. With `register_with_fqdn = true` the full name is
  the Kubernetes identity and the pair is allowed — the two machines then share
  an OS hostname, which is yours to live with.
- **A dotted node key requires `register_with_fqdn = true`** (new input, default
  `false` → `machine.kubelet.registerWithFQDN`, settable as
  `cluster.register_with_fqdn` in `cluster.yaml`). Without it Kubernetes only
  ever sees the first label and the domain part silently disappears. It is
  **all-or-nothing**: one dotted key flips FQDN registration for every node,
  including short-named ones, which changes their Kubernetes node name.
- **`node.ip` must be a canonical single address.** `192.0.2.011` and
  `::ffff:192.0.2.11` are distinct strings naming one host, so they used to slip
  past the ip-uniqueness check and point two apply resources at one machine.
- **Node roles must be `controlplane` or `worker`** and at least one controlplane
  must exist (both pre-existing, now covered by tests).

If your existing node names trip the canonicality rule, renaming a node is a
genuine identity change: new state address, new Kubernetes node. Plan it as a
node replacement, not as an edit.

### 5. Two plan diffs that are EXPECTED (not conversion errors)

The zero-diff expectation covers the machine config. Two things can legitimately
show up anyway:

- **Reordered outputs / talosconfig, if your old `nodes:` list was not already in
  node-name order.** The derived lists are now name-ordered; previously they
  followed declaration order. You will see `Changes to Outputs` for
  `controlplane_ips` and a changed talosconfig. Nothing about the cluster
  changes — only the order of an emitted list. Confirm the SET is identical and
  proceed.
- **Growing a control plane can move the bootstrap target.** The bootstrap node
  is the lowest-named controlplane. Adding a controlplane whose name sorts BELOW
  the incumbent repoints `talos_machine_bootstrap`. On an already-bootstrapped
  cluster that resource must not be re-created — if your plan shows
  `talos_machine_bootstrap` being replaced, stop: name the new nodes so they sort
  above the incumbent, or `tofu state mv` deliberately. This hazard predates v8;
  the odd-count rule makes multi-node additions more common, so it is worth
  stating.

### Validation steps after upgrade

```bash
scripts/lint-cluster-yaml.sh cluster.yaml   # or your repo's equivalent
tofu validate
tofu plan                                   # empty for an unchanged node set,
                                            # except for the two cases in §5
```

---

## `v6.0.0` — kubelet-serving CSR approver replaced with `postfinance/kubelet-csr-approver` (MAJOR — consumer-facing)

**Type:** MAJOR (consumer-runtime breaking). The seeded kubelet-serving CSR
approver changes from `alex1989hu/kubelet-serving-cert-approver` to
`postfinance/kubelet-csr-approver` (digest-pinned `v1.2.14`), delivered as the
same controlplane `inlineManifest` seed but now chart-rendered and templated with
a per-cluster config surface. Decision:
[`knowledge/decisions/0019-postfinance-kubelet-csr-approver.md`](knowledge/decisions/0019-postfinance-kubelet-csr-approver.md)
(supersedes ADR-0013 §D2; ADR-0013 §D1 — rotation default-on — is unchanged).

New `cluster.yaml` surface under `substrate.cert_approver` (all defaulted — every
cluster still boots and approves out-of-the-box):

| Key | Default | Meaning |
|---|---|---|
| `provider_regex` | `".*"` | node-name regex the approver accepts |
| `provider_ip_prefixes` | `["0.0.0.0/0", "::/0"]` | CIDRs a CSR's IP SANs must fall within — the **safe floor**; **never `[]`** (an empty list denies every serving CSR) |
| `replicas` | `1` | `> 1` opts into HA — auto leader-election + a namespaced leases RBAC |

postfinance adds an **always-on per-node DNS-SAN binding** the old approver
lacked (a CSR's DNS SANs must be prefixed by the requesting node's hostname).
Tightening `provider_ip_prefixes` to your node subnets adds an IP-SAN-to-subnet
binding on top. Two honest limits (source-verified): the DNS binding is a
hostname *prefix* match, not exact (`node-1` also matches `node-10`), and an
IP-only CSR (no DNS SAN) is bounded only by `provider_ip_prefixes`.

### 1. Tear down the OLD approver (required — it does not self-remove)

The prior tag seeded alex1989hu as a **create-only** `inlineManifest`; Talos
never deletes a resource it created, and the namespace rename means the new seed
lands in a **different** namespace. So after adopting this tag **two
cluster-scoped approvers coexist** — the old permissive one keeps approving what a
tightened new one would Deny.

Sequence (do NOT reverse):

1. Confirm the new approver is up: the `kubelet-csr-approver` Deployment is
   Running and `kubectl get csr` shows `kubernetes.io/kubelet-serving` CSRs
   `Approved,Issued` on controlplane AND worker nodes.
2. THEN delete the old objects in full:

   ```bash
   kubectl delete namespace kubelet-serving-cert-approver
   kubectl delete clusterrole certificates:kubelet-serving-cert-approver \
                              events:kubelet-serving-cert-approver
   # the ClusterRoleBinding(s) that referenced those roles — discover the exact
   # name(s) rather than assuming, then delete:
   kubectl get clusterrolebinding -o json \
     | jq -r '.items[]
              | select(.roleRef.name | test("kubelet-serving-cert-approver"))
              | .metadata.name'
   # upstream also plants an events: RoleBinding in the `default` namespace —
   # neither the namespace delete nor the cluster-scoped deletes reap it:
   kubectl -n default delete rolebinding events:kubelet-serving-cert-approver
   ```

   Confirm the exact old binding names against your cluster before deleting.

If you are **also tightening `provider_ip_prefixes`** in the same bump, sequence
it AFTER the old approver is gone — during the coexistence window the old
permissive approver races and can approve a CSR the new one would Deny (terminal,
one-way).

### 2. Config changes do NOT propagate on a running cluster

The seed is **create-only**: `tofu apply` re-renders the machine config, but Talos
does not update a Deployment it already created. Editing
`substrate.cert_approver.*` in `cluster.yaml` and re-applying therefore hardens
**new** clusters only. To change `provider_*` on a live cluster, patch the running
Deployment directly (`kubectl set env`) or re-seed. Do not assume a `cluster.yaml`
edit tightened a running cluster — it did not.

### 3. Rollback / bad-config recovery

postfinance **denies terminally**. A `provider_ip_prefixes` / `provider_regex`
that excludes your real nodes → **every** kubelet-serving CSR is Denied (a terminal
`Denied` condition, not `Pending`) → serving certs stop issuing → metrics-server,
`kubectl logs|exec|top` break cluster-wide. Immediate rollback on the live
Deployment (namespace `kubelet-csr-approver`):

```bash
kubectl -n kubelet-csr-approver set env deployment/kubelet-csr-approver \
  PROVIDER_IP_PREFIXES=0.0.0.0/0,::/0 PROVIDER_REGEX='.*'
```

`.*` + all-IPs is the safe floor — restore it first, then re-tighten
deliberately. A Denied CSR is terminal, so affected nodes recover once the kubelet
issues a fresh CSR (its next rotation attempt) and the restored approver accepts
it.

### 4. Observability migration

- **Metrics port `9090` → `8080`.** Repoint any ServiceMonitor / scrape config
  (health probe is on `8081`).
- **Namespace selector** → `kubelet-csr-approver` (was
  `kubelet-serving-cert-approver`).
- **Metric names differ.** postfinance does not expose the same series as
  alex1989hu — rebuild dashboards/alerts against postfinance's metric set.
- **Add a denied-CSR alert.** Because denies are now terminal, a rising count of
  `Denied` `kubernetes.io/kubelet-serving` CSRs is the signal that a `provider_*`
  value is excluding real nodes (see step 3) — alert on it.
- **Also alert on signer failures.** The approver only checks what its controller
  inspects (username, CN, SAN presence, IP-prefix, DNS-prefix, expiration).
  Constraints it does **not** check — Subject `Organization`, email/URI SANs, key
  usages — are enforced by the built-in `kubernetes.io/kubelet-serving` signer,
  which marks such a CSR `Failed` (`SignerValidationFailure`): Approved by the
  approver, then never Issued — **not** `Denied`. A `Denied`-only alert misses
  this; alert on `Failed` kubelet-serving CSRs too.
- **Single-replica availability (unchanged default).** The approver still runs
  `replicas: 1` and (absent worker scheduling) on a control-plane node; a rolling
  OS upgrade / CP-node reboot (`talosctl upgrade`) evicts it, and any kubelet
  serving-cert rotation during that window stalls until it reschedules and is
  Ready. Set `substrate.cert_approver.replicas: 2` for HA on new clusters, or
  `kubectl scale` an existing one (2 replicas approve idempotently even without
  leader-election). Time mass-rotation-affecting upgrades accordingly.

---

## `v7.0.0` — Cilium observability inputs + opt-in ArgoCD self-management (MAJOR — consumer-facing)

**Type:** MAJOR (bundles two independent compatibility breaks). Adds
first-class default-off Cilium observability inputs and an opt-in
emitted-Application ArgoCD self-management delivery mode for Cilium. Decision:
[`knowledge/decisions/0022-cilium-observability-and-argocd-self-management.md`](knowledge/decisions/0022-cilium-observability-and-argocd-self-management.md).

### 1. OpenTofu floor raised to `>= 1.9` (affects EVERY consumer)

The new cross-variable `validation` guards on `cilium_self_management`
require OpenTofu >= 1.9. This is not opt-in: **every** consumer of
`tofu/modules/talos-cluster`, whether or not they use the new Cilium
features, must run OpenTofu >= 1.9 to `plan`/`apply` this module version.
Upgrade your OpenTofu binary before adopting this tag.

### 2. `substrate.cilium` schema is now CLOSED (affects consumers with extra/typo'd keys)

`schemas/cluster.schema.json`'s `substrate.cilium` object now sets
`additionalProperties: false` with the full enumerated key set. Audit your
`cluster.yaml`'s `substrate.cilium` block: any key that isn't one of the
documented `cilium_*` names (see the module README Inputs table) now fails
`check-jsonschema` at lint time instead of being silently dropped by the
`try()`-based shim in `examples/complete/main.tf`. Fix by removing or
correcting the offending key before adopting this tag.

### 3. New opt-in surface (default off — no action if you set nothing)

- `substrate.cilium.agent_metrics` / `operator_metrics` — Cilium
  agent/operator Prometheus metrics. Wire your own `ServiceMonitor` /
  `PodMonitor` to scrape them; none is shipped by the base.
- `substrate.cilium.hubble_enabled` + `hubble_metrics` — Hubble
  flow/metrics observability, metrics-only scope (`hubble.tls.enabled` is
  forced `false`; this does not disable the metrics endpoint, only the
  unused observer-API TLS — see the ADR). **Enabling Hubble triggers a
  graceful-restart-gated Cilium agent DaemonSet roll** — expect a rolling
  agent restart across your nodes when you first turn this on (or change
  the metrics set thereafter).
- `substrate.cilium.self_management` + `self_management_project` — opt-in:
  the module emits a new `cilium_self_management_app` output (a rendered
  ArgoCD `Application` manifest). The module never applies it. Consumer
  action to adopt: write a one-line `local_file` resource in your own root
  against the output, commit it to your GitOps repo, let your existing
  ArgoCD sync it. You must own **exactly one** Cilium `Application` —
  ensure you are not already running a separate hand-authored one.

### 4. Override-drop hazard — REQUIRED reading before enabling self-management

If you set `substrate.cilium.values_override` (BGP control-plane, L2
announcements, bpf tuning, or any other datapath-critical Helm value), the
module **hard-rejects** `cilium_self_management=true` at plan time while
that override is non-empty. This is intentional: the emitted
`Application`'s values do **not** inherit `cilium_values_override`, so
enabling self-management with it still set would have your datapath config
silently **DROPPED** the moment ArgoCD adopts Cilium. To migrate safely:

1. Re-add the equivalent Helm values in your own Cilium `Application`
   (the one the emitted manifest becomes, once you adopt it).
2. Only THEN empty `substrate.cilium.values_override` in `cluster.yaml`.
3. Only THEN set `substrate.cilium.self_management = true`.

Reversing this order (emptying the override before your own `Application`
carries the equivalent values) creates a window where your datapath config
exists nowhere. Plan the migration as one atomic cutover, not two separate
commits.

### 5. Bootstrap-window datapath gap (accepted trade-off — plan around it on BGP/L2 clusters)

The seed is create-only, so the guard above and a future fresh
bootstrap/`-replace` interact in tension: (a) while `values_override` stays
set, you cannot enable self-management at all; (b) once you empty it to
enable self-management, a **future** fresh bootstrap or node replacement
brings that node up with plain-floor Cilium (no BGP/L2/bpf) until ArgoCD's
first sync re-applies your override via the self-managed `Application` — a
bootstrap-window datapath gap. If you depend on BGP/L2 for cluster
connectivity, hold new-node bootstraps/replacements until you have confirmed
ArgoCD's adoption sync completed, or accept the gap window.

### 6. ArgoCD-adoption runtime caveat

The first ArgoCD sync that adopts the seed-created Cilium resources into the
emitted `Application` may trigger managed-fields reconciliation and an agent
restart. This is expected seed-to-GitOps takeover behavior, not a failure —
do not intervene on your own before confirming the sync completed.

### 7. `spec.project` hardening (recommended, not required)

`cilium_self_management_project` defaults to `"default"` so the feature
works out of the box. For hardening, create a scoped `AppProject` granting
destination namespace `kube-system` at `https://kubernetes.default.svc`
plus Cilium's cluster-scoped resources (CRDs, ClusterRoles,
ClusterRoleBindings) in `clusterResourceWhitelist`, then point
`self_management_project` at it. Without that whitelist, a scoped project
leaves the adopted `Application` inert/degraded.

### Validation steps after upgrade

1. `tofu fmt -check` + `tofu validate` (module + your root) — confirms your
   OpenTofu binary meets the new `>= 1.9` floor.
2. `check-jsonschema --schemafile vendor/base/schemas/cluster.schema.json
   --default-filetype yaml cluster.yaml` — confirms no stray key under
   `substrate.cilium`.
3. If adopting `self_management`: confirm `tofu plan` succeeds (the guard
   would otherwise hard-reject it) and review the emitted
   `cilium_self_management_app` output before committing it to GitOps.

---

## `v5.1.0` — consumer kernel args on UKI/systemd-boot nodes (MINOR — manual action for consumers carrying boot args in machine-config)

**Applies to you** if you need to set custom kernel command-line arguments on
nodes booting via UKI/systemd-boot (the Talos v1.10+ default for fresh metal
UEFI installs) — performance/security tuning, huge pages, or (post-`v5.0.0`)
`iommu=pt`. Everyone who sets nothing: no action, no re-image.

**What changed.** `var.images[*].extra_kernel_args` (`list(string)`, default
`[]`) is a new optional per-image input. It is unioned into the node's
Image-Factory schematic `customization.extraKernelArgs` alongside the
selected provisioning profiles' kernel args — the same UKI-correct sink the
module already builds, now with a consumer-facing input reaching it.
`cluster.yaml` exposes it as `images.<id>.extra_kernel_args`.

**What it does NOT change.** `machine.install.extraKernelArgs` remains a
no-op under UKI/systemd-boot (Talos v1.10+) — this input does **not** route
through it, and never will (a base Hard Constraint). Only
`images.<id>.extra_kernel_args` reaches the boot cmdline.

**Consumer action required:**

1. **If you carry boot-kernel-arg tuning in `machine.install.extraKernelArgs`
   via `config_patches` today**, it has been silently ignored since your
   cluster adopted the Talos v1.10+ UKI default — move it to
   `images.<id>.extra_kernel_args` in `cluster.yaml` instead. This is the
   migration this input exists to unblock.
2. **Adopting the input re-images the affected nodes**: a new
   `extra_kernel_args` value changes the node's schematic content hash → new
   schematic id → new installer URL. Roll out via the usual out-of-band
   `talosctl upgrade`.
3. **A single-value kernel-arg key your image sets that collides with a
   selected profile's kernel arg for that key fails the plan** (for example,
   setting `intel_iommu=on,sm_on` on a node that also selects the `iommu` capability,
   whose profile sets `intel_iommu=on`) — this is a guard, not a defect;
   restate the profile's value verbatim if you want both applied (it collapses
   to one). A key no selected profile contributes (most tuning args, including
   `hugepagesz=`/`hugepages=` pairs and `iommu=pt`) is never guarded.
4. **A consumer setting nothing is unaffected**: the default `[]` composes
   byte-identically to the pre-`v5.1.0` schematic — no re-image.

---

## `v5.0.0` — the `iommu` profile stops baking `iommu=pt` (MAJOR — bare-metal-consumer-facing)

Applies to you **only** if a node selects a capability resolving to the
`iommu` provisioning profile. Everyone else: no action, no re-image.

**What changed.** The profile's `intel`/`amd` variants now carry only
`intel_iommu=on` / `amd_iommu=on` — the args the `iommu-enabled` Layer-C
atom's `presence_predicate` names. `iommu=pt` was host-DMA tuning that
entered the catalog from a README example and was never decided
([`knowledge/decisions/0016-capability-profiles-predicate-only.md`](knowledge/decisions/0016-capability-profiles-predicate-only.md)).

**What it does NOT change.** PCI passthrough itself. A device bound to
`vfio-pci` is isolated by its own VFIO domain regardless of `iommu=pt`, so
the `iommu-enabled` atom still delivers what it promises. What changes is
DMA translation for the devices the **host** keeps: they move from
bypass-by-default to **lazy DMA translation**. Talos builds
`CONFIG_IOMMU_DEFAULT_DMA_LAZY=y` with `CONFIG_IOMMU_DEFAULT_PASSTHROUGH`
unset (verified across the v1.10 — v1.12 kernel configs, amd64 and arm64),
so `iommu=pt` was doing real work — expect a possible host-datapath
throughput cost (SR-IOV PFs, NVMe, onboard NICs) in exchange for the DMA
protection the bypass removed.

**Consumer action required:**

1. **Expect a one-time re-image** on every node holding the `iommu`
   capability: the composed schematic content changes → new schematic id →
   new installer URL. To see exactly which nodes, diff
   `tofu output node_schematic_hashes` before and after the tag adoption;
   every changed hash is a re-imaging node. The re-image rolls out via the
   usual out-of-band `talosctl upgrade`.
2. **You cannot keep `iommu=pt` in this tag.** The schematic kernel-arg sink
   is fed exclusively by profile `kernel_args`; the module exposes no
   consumer kernel-arg input, and `config_patches` reach
   `machine.install.extraKernelArgs`, which is a **no-op** under the Talos
   v1.10+ UKI/systemd-boot default — writing `iommu=pt` there applies cleanly
   and has no effect. If you need it, wait for the consumer kernel-arg path
   (#169) before adopting this tag.
3. **If you migrated at `v2.0.0`**, re-read the note below: it told you to
   drop your `class.config_patches` IOMMU kernel args because the `iommu`
   profile "now actually bakes" them. That remains true for
   `intel_iommu=on`/`amd_iommu=on` and is **no longer true for `iommu=pt`**.
4. **Watch the first re-imaged node's boot.** Host-owned devices moving from
   identity-mapped to translated DMA is the class that surfaces DMAR faults
   on chassis with defective reserved-region (RMRR) reporting. If a storage
   controller or NIC fails to initialise after the re-image, that is the
   signal — and per (2) there is no in-tag mitigation, so roll back the tag.

## `v4.0.0` — docs/ replaced by the knowledge/ OKF bundle; machine contracts relocated (MAJOR — path-consumer-facing)

**Type:** MAJOR. Two path surfaces changed: (1) two OCI-tarball members
moved, so a vendored tree's references to them break; (2) the `docs/` tree
no longer exists, so any deep link or hardcoded path into `docs/**` breaks.
Rendered manifests, the module interface, and all Helm values are
UNCHANGED — no cluster-runtime impact.

**Old → new path table:**

| Old | New |
|---|---|
| `docs/platform-hardware-features.yaml` (ships in tarball) | `platform-hardware-features.yaml` (repo root) |
| `docs/schemas/hardware-features.schema.json` (ships in tarball) | `schemas/hardware-features.schema.json` |
| `docs/schemas/cluster.schema.json` | `schemas/cluster.schema.json` |
| `docs/schemas/fixtures/cluster.invalid.yaml` | `schemas/fixtures/cluster.invalid.yaml` |
| `docs/primitive-contract.md` (machine-read by external harnesses) | `contracts/primitive-contract.md` |
| `docs/README.md` (doc index) | `knowledge/index.md` |
| `docs/adr-NNNN-<slug>.md` (13 ADRs) | `knowledge/decisions/NNNN-<slug>.md` |
| `docs/rendered-manifests.md` | `knowledge/reference/manifest-pipeline.md` |
| `docs/tutorial-first-consumer-cluster.md` | `knowledge/workflows/first-consumer-cluster.md` |
| `docs/oci-artifact-verification.md` | `knowledge/workflows/verify-release.md` |
| `docs/release-automation.md` | `knowledge/workflows/release-process.md` |
| `docs/issue-workflow.md` | `knowledge/workflows/issue-lifecycle.md` |
| `docs/mcp-setup.md` | `knowledge/workflows/mcp-setup.md` |
| `docs/day-zero-pattern.md` | `knowledge/architecture/day-zero-bootstrap.md` |
| `docs/component-dependencies.md` | dissolved into `knowledge/architecture/substrate.md` |
| `docs/glossary.md` | `knowledge/glossary.md` |
| `docs/{vision,openssf-best-practices,harness-plugin-integration}.md` | `knowledge/project/{vision,openssf-self-assessment,harness-plugin-contract}.md` |

**Migration:**

1. Re-vendor at `v4.0.0` (the tarball now carries
   `platform-hardware-features.yaml` and
   `schemas/hardware-features.schema.json` at their new paths); update any
   consumer script that referenced the two old tarball paths.
2. If an external harness reads the diagnostics primitive contract at a
   hardcoded path, repoint it: `docs/primitive-contract.md` →
   `contracts/primitive-contract.md` (the lookup is fail-closed — an
   unrepointed harness returns `PRECONDITION_NOT_MET` on every Phase-1a
   primitive until updated).
3. Repoint any bookmarks, runbooks, or docs deep-linking `docs/**` per the
   table above. The JSON Schema `$id` URLs changed with the paths; the
   schemas are versioned by `$id` + OCI tag, so this bump is the migration
   signal.

---

## `v3.0.0` — go-task single runner + Makefile retired; kubelet serving-cert rotation default-on + cert-approver seed (MAJOR — dev-facing + consumer-facing)

**Type:** MAJOR (dev-facing). The `Makefile` is retired and go-task is the sole
runner — every former `make <target>` is now a namespaced `task <target>`. A
`Makefile` deprecation stub remains for one release cycle: any `make <target>`
prints the migration mapping and exits non-zero. There is **no consumer-runtime
impact** — the OCI artifact ships neither the Makefile nor the Taskfile, so this
affects only workstation / runbook / CI tooling, not the vendored module or the
rendered manifests. Decision:
[`knowledge/decisions/0012-makefile-retirement.md`](knowledge/decisions/0012-makefile-retirement.md).

**Migration — replace `make` with `task` in any runbook, script, or CI you own:**

| Retired `make` target | Replacement |
|---|---|
| `make validate-gitops` | `task gitops:validate` |
| `make render-component COMPONENT=<c>` | `task gitops:render-component COMPONENT=<c>` |
| `make render-all` | `task gitops:render-all` |
| `make verify-rendered` | `task gitops:verify-rendered` |
| `make argocd-bootstrap` | `task bootstrap:argocd` |
| `make argocd-password` | `task bootstrap:argocd-password` |
| `make init-cluster-yaml` | `task cluster:init-yaml` |
| `make oci-allowlist-check` | `task supply-chain:oci-allowlist` |
| `make mcp-install` / `mcp-verify` / `mcp-uninstall` | `task mcp:install` / `mcp:verify` / `mcp:uninstall` |
| `make install-pre-commit` / `verify-tools` | `task dev:install-pre-commit` / `dev:verify-tools` |

The pre-existing tofu tasks were also namespaced: `task ci` → `task tofu:ci`,
`task test` → `task tofu:test` (and `fmt` / `validate` / `lint` → `tofu:*`).
Run `devbox shell -- task --list` for the full set.

**Dropped (no replacement):**

- `make chart-pull` — for a new `chart.lock.yaml` digest, run
  `helm pull <chart> --repo <repo> --version <v> --destination .helm-cache`
  then `shasum -a 256 .helm-cache/<chart>-*.tgz`.
- `make grafana-dashboards-check` — it scanned a consumer-overlay path
  (`kubernetes/overlays/…`) absent in the substrate base.

**devbox:** `devbox.json` gains `yq-go`, `gettext`, and `ripgrep` (no `gnumake`)
so the folded `bootstrap:*` / `cluster:*` / `gitops:*` tasks run inside
`devbox shell`.

### Kubelet serving-cert rotation default-on + cert-approver seed (consumer action required)

**Type:** consumer-runtime breaking (folded into this MAJOR). Decision:
[`knowledge/decisions/0013-kubelet-serving-cert-rotation.md`](knowledge/decisions/0013-kubelet-serving-cert-rotation.md).

The module now enables `machine.kubelet.extraConfig.serverTLSBootstrap: true` on all
nodes (default-on) and seeds cert-approver as a controlplane `inlineManifest` (it was
a namespace-only stub before). On a **fresh** cluster this is automatic.

On an **already-bootstrapped** cluster adopting this tag, the approver seed **also
lands automatically** via the config-apply reconcile. Talos reconciles the manifests in
the machine config on *every change*, not only at initial bootstrap, and *creates* any
manifest whose resources do not yet exist ([Talos docs — inlineManifests](https://docs.siderolabs.com/kubernetes-guides/advanced-guides/inlinemanifests)).
So `tofu apply` re-pushes the machine config → rotation turns on → kubelets emit
`kubernetes.io/kubelet-serving` CSRs → the newly-seeded approver (created by the same
reconcile) approves them. **Empirically confirmed** on a live single-node,
already-bootstrapped cluster (base v2.0.0 → v3.0.0 driven by a Crossplane self-heal
reconcile): the approver pod came up and the CSRs went `Approved,Issued` with **no
manual step**. Talos's "create-only" semantics mean it never *updates or deletes* a
resource it already created (see "Approver upgrades" below) — NOT that a new manifest is
skipped on a running cluster.

1. **Verify after the apply:** `kubectl get csr` shows `kubernetes.io/kubelet-serving`
   CSRs `Approved,Issued` on controlplane AND worker nodes; metrics-server works without
   `--kubelet-insecure-tls`; the `kubelet-serving-cert-approver` Deployment is Running.
2. **Fallback — only if the seed does not land** (CSRs stuck `Pending`, for example an
   older Talos without reconcile-on-change): apply the **complete upstream** manifest once
   (self-contained, namespace included):
   `kubectl apply -f https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/v0.11.0/deploy/standalone-install.yaml`.
   Do NOT `kubectl apply` the vendored seed manifest
   (`tofu/modules/talos-cluster/manifests/cert-approver.yaml`) directly — its
   `Namespace` document is stripped (the module seeds the namespace separately), so it
   would land the ServiceAccount/Deployment into a non-existent namespace.
3. **If you already wired an upstream cert-approver Application** (pre-v3.0.0), you now
   have two owners of the cluster-scoped ClusterRole/ClusterRoleBinding. The already-
   existing objects are not re-created or mutated by the seed (create-only applies to
   *existing* resources), so resolve the double-management **without pruning the running
   approver**: **orphan** your Application — remove the
   `resources-finalizer.argocd.argoproj.io` finalizer (and/or set
   `spec.syncPolicy.automated.prune: false`) *before* deleting it — so ArgoCD leaves the
   live approver in place. Server-side apply reconciles the identical objects; a
   cascading prune would instead leave `serverTLSBootstrap` on with NO approver and
   CSRs stuck `Pending`.

**Opt-out** (rare): add `- machine: { kubelet: { extraConfig: { serverTLSBootstrap: false } } }`
to `config_patches` in your `cluster.yaml` (the base patch is placed FIRST, so the
override wins; confirm on the homelab apply since the merge is server-side).

**Approver upgrades on a running cluster are manual** (create-only seed):
`kubectl -n kubelet-serving-cert-approver set image deployment/kubelet-serving-cert-approver cert-approver=<new-image@digest>`,
or re-apply the upstream manifest. A plain `tofu apply` does NOT update an
already-seeded approver.

**Availability note (single replica):** the approver runs `replicas: 1` and (absent
worker scheduling) on a control-plane node. A rolling OS upgrade / CP-node reboot
(`talosctl upgrade`) evicts it; any kubelet serving-cert rotation during that window
stalls until it reschedules and is Ready. Time mass-rotation-affecting upgrades
accordingly, and wire a consumer alert on the count of `Pending`
`kubernetes.io/kubelet-serving` CSRs (the approver exposes metrics on port 9090).

**Security — REQUIRED for multi-tenant / untrusted-node clusters (not optional
hardening):** the approver (alex1989hu) validates node identity (CN ==
`system:node:<name>`, Org `system:nodes`) but does NOT bind requested DNS/IP SANs to
the requesting node — a compromised node could mint a serving cert for another node's
SANs (MITM). Rotation is now default-on cluster-wide, so every cluster ships this
residual until you add it. **Add a consumer-cluster Kyverno policy enforcing
SAN-to-node** for `kubernetes.io/kubelet-serving` CSRs (the base ships no admission
policy — ADR-0004 puts the `kubelet-serving` policy surface in consumer clusters).
See adr-0013 §Security.

---

## `v2.0.0` — node-capability composition + substrate-only ablation (MAJOR / breaking)

**Type:** MAJOR. v2.0.0 bundles **two** breaking changes:

1. **Node-capability composition** — the `tofu/modules/talos-cluster`
   interface changes (detailed below).
2. **Substrate-only ablation** — the base is reduced to substrate
   (Talos + Cilium + ArgoCD + `cert-approver`); the entire PNI /
   capability-network contract and every non-substrate component move to
   the [`talos-platform-apps`](https://github.com/devobagmbh/talos-platform-apps)
   catalog (see [`knowledge/decisions/0004-substrate-only-base.md`](knowledge/decisions/0004-substrate-only-base.md)).
   See [§Substrate-only ablation](#substrate-only-ablation-consumer-action-required)
   below for the consumer action.

v1.0.0 shipped earlier **without** the ablation; the ablation lands in
v2.0.0.

### Node-capability composition (consumer action required)

The `tofu/modules/talos-cluster` interface changes: the monolithic per-node
`class` is replaced by a composable `image` + a SET of `hardware_capabilities`.
Boot kernel args now bake into the Image Factory schematic
(`customization.extraKernelArgs`) — the v1.10+ UKI correctness fix; the old
`machine.install.extraKernelArgs` path was a silent no-op. See
[`knowledge/decisions/0009-node-capability-composition.md`](knowledge/decisions/0009-node-capability-composition.md)
(the §Migration table is authoritative).

- **`var.classes` and `node.class` are removed.** Map your `cluster.yaml`:
  - `class.architecture` / `class.overlay` → `images.<id>.architecture` / `.overlay`
  - `class.extensions` **baseline** (microcode/firmware/tooling/runtime — for
    example `intel-ucode`/`i915`/`nvme-cli`/`gvisor`) → `images.<id>.extensions`
  - `class.extensions` **capability-specific** (drbd, nvidia) → a base
    provisioning profile selected via a `hardware_capabilities` composite
  - `class.config_patches` IOMMU/boot kernel args → the `iommu` profile (now
    actually bakes); other `class.config_patches` → role / node `config_patches`
    — **superseded at `v5.0.0`:** the profile bakes `intel_iommu=on` /
    `amd_iommu=on` but no longer `iommu=pt`. If you dropped an `iommu=pt` here
    on this instruction, see the `v5.0.0` section.
  - `node.class` → `node.image` + `node.hardware_capabilities: [...]`
- **`installer_images` output is now keyed by node hostname** (was per class).
  Update any consumer `talos:upgrade:cluster` task that reads it from tfplan JSON.
- **One-time re-image is expected** for nodes whose kernel-arg provisioning is
  corrected (for example, the kubevirt IOMMU that was a no-op now actually
  applies). A node whose *effective provisioning is unchanged* (for example, a
  plain controlplane
  whose baseline extensions are preserved in its `image`) keeps a stable
  schematic hash and does **not** re-image. Verify with `tofu plan` before the
  MAJOR-tag adoption; the re-image rolls out via the usual out-of-band
  `talosctl upgrade`. To see *exactly which* nodes re-image, diff
  `tofu output node_schematic_hashes` before and after — every changed hash is a
  re-imaging node (see the module README "Re-image blast-radius").

A worked migration is the `tofu/modules/talos-cluster/examples/complete/`
fixture (its `kubevirt` IOMMU is the live no-op this fixes) and the module README
Usage block.

### Substrate-only ablation (consumer action required)

As of v2.0.0 the base is **substrate-only**:
`kubernetes/base/infrastructure/` ships only `argocd/` and
`cert-approver/`. The PNI / capability-network contract and every
non-substrate component (observability, storage, the capability registry
and its policies, the application-supporting services) have **dissolved
out of the base** — the PNI surface is now realized by apps-CI Conftest
plus consumer-cluster Kyverno, and the components live as independently
versioned, signed OCI artifacts in the
[`talos-platform-apps`](https://github.com/devobagmbh/talos-platform-apps)
catalog. Decision + sequencing:
[`knowledge/decisions/0004-substrate-only-base.md`](knowledge/decisions/0004-substrate-only-base.md).

Consumer action:

- **Re-source non-substrate components from `talos-platform-apps`.** Any
  consumer that referenced `kubernetes/base/infrastructure/<comp>/` paths
  for a non-substrate component (anything other than `argocd/` /
  `cert-approver/`) must now pull that component from the apps catalog by
  the OCI artifact it needs.
- **Move PNI / capability-network enforcement to your cluster.** The
  reserved-label, capability-registry, and CCNP machinery the base used
  to ship is gone; adopt the corresponding Conftest + Kyverno from the
  apps catalog and run them in your own CI / cluster.
- **ArgoCD cert-manager Certificate is now opt-in (Helm-value default change).**
  `argocd` no longer renders a `cert-manager.io/v1 Certificate` by default
  (`server.certificate.enabled: false`), so the substrate floor carries no
  cert-manager dependency. The substrate argocd-server already runs with
  `server.insecure=true` — it serves plaintext at the pod; terminate TLS at your
  gateway / ingress. A consumer that relied on the base-rendered
  `argocd-server-tls` cert re-enables `server.certificate` in a values overlay and
  provides the `vault-internal` `ClusterIssuer` (cert-manager comes from the apps
  catalog); to have the pod itself serve TLS, also set `server.insecure=false`.
- **Layer-C node-capability work stays in the base.**
  `docs/platform-hardware-features.yaml`,
  `docs/adr-0009-node-capability-composition.md`,
  `docs/adr-0003-three-layer-capability-architecture.md`, and the
  `tofu/modules/talos-cluster` provisioning catalog are substrate and
  remain here — no consumer move needed for those.

---

## Pre-`v0.2.0` MINOR releases

### `v0.1.0` (2026-03-XX) — initial public release

Baseline. No upgrade path; cleanroom install.

Capabilities present:

- `monitoring-scrape`, `hpa-metrics`, `tls-issuance`, `gateway-backend`,
  `external-gateway-routes`, `gpu-runtime`, `internet-egress`,
  `controlplane-egress`, `storage-csi`,
  `vault-secrets`, `cnpg-postgres`, `redis-managed`, `rabbitmq-managed`,
  `kafka-managed`, `s3-object`, `admission-webhook-provider`,
  `monitoring-scrape-provider`, `logging-ship`.

`storage-csi` and `monitoring-scrape-provider` are deprecated from day
one in v0.1.0 (see below).

---

## `v0.5.0` — 2026-05-18 — PNI policy rename + cluster-agnostic refactor + Layer-A validation + per-component READMEs

**Type:** MINOR (consumer-visible breaking name change in a Kubernetes
resource name; spec semantics unchanged)
**Breaking?** yes, for any artifact that references the renamed
`pni-contract-audit` ClusterPolicy by its `metadata.name`. No other
consumer-side action is required for the rest of the v0.5.0 surface
(documentation, validation scripts, READMEs — all internal to the
base; the OCI artifact remains the same shape).

### Note on prior git tags

Git tags `v0.2.0`, `v0.3.0`, `v0.4.0` exist in the repository and
have corresponding OCI artifacts on `ghcr.io`, but were not published
as GitHub Releases. They are usable as pinning targets but are
considered pre-release internal markers; v0.5.0 is the first GitHub
Release after v0.1.0.

### Breaking changes (consumer action required)

- `ClusterPolicy/pni-contract-audit` is renamed to
  `ClusterPolicy/pni-contract-enforce`. The new name matches both the
  filename (`kyverno-clusterpolicy-pni-contract-enforce.yaml`) and the
  policy's behaviour (`spec.validationFailureAction: Enforce`). Rule
  names (`require-interface-version`, `require-network-profile`) and
  validation messages are unchanged.
- Consumers must update any of the following that reference the old
  name:
  - PolicyReport queries / alerts (for example Grafana dashboards filtering
    on `policy="pni-contract-audit"`)
  - `metadata.labels` or `metadata.annotations` that name the policy
  - `argocd.argoproj.io/sync-options: SkipDryRunOnMissingResource` or
    similar resource selectors keyed by the old name
  - Documentation links / cookbook snippets

### Migration on a live cluster

PolicyReports keyed on the old `policy="pni-contract-audit"` will be
GC'd by Kyverno when the renamed policy is applied (Kyverno emits a
new PolicyReport for the new resource UID). Brief gap in
PolicyReport continuity during the cutover — expected.

```bash
# Before merging the v0.5.0 bump:
kubectl get clusterpolicy pni-contract-audit -o yaml > /tmp/pre-rename.yaml

# After merging + ArgoCD reconcile:
kubectl get clusterpolicy pni-contract-enforce -o yaml | diff /tmp/pre-rename.yaml -
# Expected diff: metadata.name only, plus new UID / resourceVersion
```

### Why the rename

The policy was authored as fail-closed enforcement
(`validationFailureAction: Enforce`) but its `metadata.name` carried
an `-audit` suffix from a prior refactor. The mismatch caused two
class-of-error incidents during consumer onboarding (operators
assuming "audit" meant non-blocking, then surprised when admission
denied namespace creation). The rename aligns name, filename, and
behaviour. No spec change.

### New non-breaking surface

- **Layer-A capability-index validation in CI.** v0.5.0 added a set of
  capability-index lint/render scripts and a CI job that enforced the
  two-layer capability-architecture invariant. *Historical only:* this
  Layer-A capability surface dissolved out of the substrate in v2.0.0
  (see [§Substrate-only ablation](#substrate-only-ablation-consumer-action-required)) —
  the scripts and job no longer exist in the base, and the concern moved
  to [`talos-platform-apps`](https://github.com/devobagmbh/talos-platform-apps).
- **Per-component READMEs.** Each `kubernetes/base/infrastructure/<comp>/`
  directory shipped a README with Purpose / Chart / capabilities /
  Helm-value overrides / Upgrade gotchas. *Historical only:* with the
  v2.0.0 ablation only `argocd/` and `cert-approver/` remain in the base;
  the non-substrate component READMEs travelled to the apps catalog.

### Validation steps after upgrade

1. `task gitops:validate` in consumer repo passes.
2. `kubectl get clusterpolicy pni-contract-enforce` returns one
   resource with `ADMISSION=true BACKGROUND=true READY=True`.
3. `kubectl get clusterpolicy pni-contract-audit` returns NotFound.
4. `kubectl get policyreport -A -l policy.kyverno.io/policy-name=pni-contract-enforce`
   returns reports keyed on the new name.

---

## `v0.6.0` (forthcoming) — 5-axis cutover (MAJOR / breaking)

> **Superseded by the OpenTofu cluster-lifecycle cutover** (see the section
> below). The 5-axis `cluster.yaml` schema this checklist migrates *to* has
> itself been removed — the entire `talos/Makefile.lib` + 5-axis generator is
> gone. This section is retained for historical context only; consumers
> migrate per the OpenTofu cutover instead.

**Type:** MAJOR. Every consumer `cluster.yaml` needs migration plus,
for live clusters, two ClusterPolicy renames.
**Breaking?** yes — coordinated package of seven `cluster.yaml`-level
changes plus the v0.5.0-style PNI policy cleanup. Engineering rationale
per item lived in `talos/RELEASE-NOTES-v0.6.0.md` (removed with the
`talos/` tree; see git history); this
section is the consumer migration recipe.

### Migration checklist

Apply in this order. Steps 1–7 edit your `cluster.yaml`; step 8 is the
ClusterPolicy GitOps drift; step 9 verifies.

#### 1. Rename `cluster.api_vip` → `cluster.vip`; drop `gateway_vip`

```diff
 cluster:
   name: example-cluster
-  api_vip: <api-vip>
-  gateway_vip: <gateway-vip>
+  vip: <api-vip>
   network: <cluster-cidr>
   gateway: <default-gw>
```

A cluster has exactly one Kubernetes API VIP. Gateway / LoadBalancer
VIPs are not cluster-identity — they belong with the respective
`Gateway` / `HTTPRoute` manifests under
`kubernetes/base/infrastructure/<gateway>/values.yaml`. If you carried
`gateway_vip` as a single value, move it to the cluster's Gateway
manifest. If you have multiple Gateway VIPs, this field never matched
them anyway.

#### 2. Rename `cluster.ntp_server` (string) → `cluster.ntp_servers` (array)

```diff
 cluster:
-  ntp_server: <primary-ntp>
+  ntp_servers:
+    - <primary-ntp>
+    - <fallback-ntp>     # ≥2 servers recommended for redundancy
```

Talos `machine.time.servers` is natively an array. Single-NTP is a SPOF
that propagates to etcd cert validation failure on outage. Each element
is charset-validated against `^[A-Za-z0-9.:_-]{1,253}$` to prevent YAML
injection through the NTP slot.

#### 3. Remove `hardware-platforms.nvidia-gpu-node`; GPU nodes use `intel-generic`

```diff
 hardware-platforms:
   intel-generic:
     vendor: Intel
     model: "Generic x86-64 server / NUC"
-
-  nvidia-gpu-node:
-    vendor: NVIDIA
-    model: "x86-64 server with NVIDIA PCIe GPU"

   raspberry-pi-4:
     vendor: Raspberry Pi Foundation
     model: Raspberry Pi 4 Model B
```

And on every GPU node:

```diff
 - name: node-gpu-01
   role: worker
   arch: amd64
   infrastructure-platform: metal
-  hardware-platform: nvidia-gpu-node
+  hardware-platform: intel-generic
   hardware-capabilities: [gpu-nvidia]
```

A PCIe GPU is peripheral, not platform. GPU presence already lives on
Axis 5 as the `gpu-nvidia` capability; the Axis-4 entry was a
duplicate contract.

#### 4. Move gVisor out of `hardware-capabilities` into role-patches

```diff
 hardware-capabilities:
-  gvisor-sandbox:
-    description: "Run untrusted workloads in gVisor sandbox"
-    patches:
-      - file: patches/worker-gvisor.yaml

   drbd-storage:
     description: "DRBD-based replicated block storage (LINSTOR)"
```

Add `patches/worker-gvisor.yaml` to the relevant role's `patches[]`:

```diff
 roles:
   worker:
     description: "Kubernetes worker node"
     patches:
       - patches/common.yaml
+      - patches/worker-gvisor.yaml
```

And strip the capability from every node that listed it:

```diff
 - name: node-a
-  hardware-capabilities: [gvisor-sandbox, drbd-storage, kubevirt-networking]
+  hardware-capabilities: [drbd-storage, kubevirt-networking]
```

gVisor is a **workload-runtime-class** label
(`platform.io/gvisor: "true"`), not a hardware predicate (ADR
Three-Layer §D7). Role-uniform static labels belong on roles, not on
Axis 5. The correct slot for this concern is documented in
`talos/AGENTS.md §"Patch slots — where things go"`.

#### 5. Rename `hardware_capabilities` (underscore) → `hardware-capabilities` (kebab)

```diff
 - name: node-a
   role: worker
-  hardware_capabilities:
+  hardware-capabilities:
     - drbd-storage
```

The v0.5.4 grace-window underscore alias is removed in v0.6.0.
The schema, `argv-print.sh`, and `validate-schematics.sh` now read
only kebab-case. Underscore-only `cluster.yaml` documents fail
schema validation with:

```text
$.nodes[0]: 'hardware-capabilities' is a required property
```

#### 6. Replace legacy `talos/Makefile` with `Makefile.lib` include

The 439-LOC pattern-rule generator at `talos/Makefile` is deleted from
base. Consumer-side `talos/Makefile` MUST include `Makefile.lib` from
the vendored base:

```makefile
ENV ?= ../cluster.yaml
SCHEMATIC_CACHE ?= .schematic-cache.yaml
BASE_DIR ?= ../vendor/base/talos
ifneq ($(wildcard $(BASE_DIR)/Makefile.lib),)
include $(BASE_DIR)/Makefile.lib
else
$(error Base library not found at $(BASE_DIR)/Makefile.lib. Run 'make pull-base-oci' from repo root.)
endif
```

See a consumer cluster repo for the reference pattern.

#### 7. Audit role/cap patch duplication (cap-patches now auto-composed)

`hardware-capabilities[*].patches[].file` entries were declarative-only
in v0.5.x — listed in the schema but ignored by `argv-print.sh`. In
v0.6.0 they are auto-composed into the per-node talosctl argv as
`--config-patch` after role-patches.

This means a patch listed in both `roles.<role>.patches[]` AND a
capability's `patches[].file` is emitted **twice**. For identical
content this is harmless (talosctl merge is idempotent); for content
that diverges between the two paths, behaviour is now
last-`--config-patch`-wins (cap overrides role).

Action: grep your `cluster.yaml` for each patch file. If it appears in
both a role's `patches[]` AND a capability's `patches[].file`, pick
one source. Convention: hardware-predicate patches live on the
capability, role-uniform patches live on the role.

#### 8. PNI policy renames (live-cluster GitOps drift)

Two ClusterPolicy renames inherit the v0.5.0 `pni-contract-audit` →
`-enforce` mechanism:

| Old `metadata.name` | `spec.validationFailureAction` | New `metadata.name` |
|---|---|---|
| `pni-capability-validation-audit` | `Enforce` | `pni-capability-validation-enforce` |
| `pni-reserved-labels-audit` | `Enforce` | `pni-reserved-labels-enforce` |

File names already matched the behaviour; only `metadata.name` is
renamed. Rule names, validation messages, and
`validationFailureAction: Enforce` are unchanged.

Update any of the following that reference the old names:

- PolicyReport queries / alerts (Grafana dashboards filtering on
  `policy="pni-capability-validation-audit"` etc.)
- `metadata.labels` / `metadata.annotations` that name either policy
- ArgoCD `sync-options` resource selectors keyed by the old names
- Documentation links / cookbook snippets

On the live cluster, Kyverno GCs the old PolicyReports keyed on the
renamed resource UID and emits fresh ones for the new name. Brief gap
in PolicyReport continuity during cutover — expected.

```bash
# Before the v0.6.0 ArgoCD reconcile:
kubectl get clusterpolicy pni-capability-validation-audit -o yaml > /tmp/pre-cap-rename.yaml
kubectl get clusterpolicy pni-reserved-labels-audit -o yaml > /tmp/pre-rlbl-rename.yaml

# After reconcile:
kubectl get clusterpolicy pni-capability-validation-enforce -o yaml \
  | diff /tmp/pre-cap-rename.yaml -
# Expected diff: metadata.name only, plus new UID / resourceVersion
```

#### 9. Validate the migrated `cluster.yaml`

```bash
# Schema validation
check-jsonschema --schemafile vendor/base/talos/schemas/cluster.schema.json \
  --default-filetype yaml cluster.yaml

# Schematics + Layer-C cross-refs + capability resolution
make -C talos validate-schematics ENV=../cluster.yaml

# Per-node argv-print spot-check
make -C talos argv-print NODE=<node-name> ENV=../cluster.yaml
```

Live-cluster checks (post-reconcile):

```bash
task gitops:validate    # consumer-side
kubectl get clusterpolicy pni-capability-validation-enforce \
                         pni-reserved-labels-enforce
# Both should return one resource each with ADMISSION=true BACKGROUND=true READY=True
kubectl get clusterpolicy pni-capability-validation-audit pni-reserved-labels-audit
# Both should return NotFound
```

### Why not bundle the substrate split into v0.6.0

`docs/adr-0004-substrate-only-base.md` (accepted 2026-05-27) reclassifies
the platform-network-interface, Kyverno, observability stack, and the
further `kubernetes/base/infrastructure/` components as platform
**offerings**, not substrate. They moved to the separate
[`talos-platform-apps`](https://github.com/devobagmbh/talos-platform-apps)
catalog **as of v2.0.0** — not in v0.6.0, and not in v1.0.0 (which
shipped without the ablation).

Rationale: v0.6.0 was already in the consumer-cluster preparation
pipeline when the substrate-only ADR landed. Bundling the substrate
split into v0.6.0 would have invalidated that preparation; sequencing
it later preserved consumer planning at the cost of touching the
PNI cleanup work twice (here in v0.6.0, then again at the v2.0.0
ablation). See the ADR's §Release sequencing and §Migration plan.

Consumers who reference `platform-network-interface/**` paths from
this repo re-source from `talos-platform-apps` at the v2.0.0 cut — see
[§Substrate-only ablation](#substrate-only-ablation-consumer-action-required).

---

## `v0.7.0` (2026-06-02) — OpenTofu cluster-lifecycle cutover (MAJOR / breaking)

**Type:** MAJOR. The Talos cluster lifecycle moves from the removed
`talos/Makefile.lib` + 5-axis `cluster.yaml` generator to the OpenTofu module
`tofu/modules/talos-cluster`. Rationale + consequences:
[`knowledge/decisions/0006-opentofu-cluster-lifecycle.md`](knowledge/decisions/0006-opentofu-cluster-lifecycle.md).

**Breaking?** Yes. Consumers stop generating Talos configs with
`make -C talos gen-configs` and instead author an OpenTofu root that calls the
module.

### Migration checklist

1. **Stop vendoring the `talos/` make path.** It no longer exists in the base.
   `make -C talos gen-configs`, `argv-print.sh`, `validate-schematics.sh`,
   `Makefile.lib`, and the 5-axis `cluster.schema.json` are gone.
2. **Slim your `cluster.yaml`.** Keep only the ArgoCD-bootstrap identity:
   `cluster.{name,overlay,target_revision}` and `repo.url`. Remove the Talos
   sections (`roles`, `architectures`, `infrastructure-platforms`,
   `hardware-platforms`, `hardware-capabilities`, `nodes`, `cluster.vip`,
   `cluster.ntp_servers`, `kubeconfig`). `task bootstrap:argocd` still reads the
   slim file.
3. **Author an OpenTofu root** in your consumer repo that calls the module:

   ```hcl
   module "cluster" {
     source = "git::https://github.com/Nosmoht/talos-platform-base.git//tofu/modules/talos-cluster?ref=<tag>"
     # cluster_name / talos_version / kubernetes_version / cluster_endpoint
     # nodes = [{ hostname, ip, role, class, config_patches? }, ...]
     # classes = { standard = { architecture, extensions, overlay?, config_patches } , ... }
     # config_patches = [...]  # NTP, registry mirrors, install disk
   }
   ```

   Map your old `cluster.yaml` axes onto module inputs: per-node `role` →
   `controlplane`/`worker` only; GPU/Pi/storage specialisations → a node
   `class`; extension sets → `classes[class].extensions`; ARM/Pi → `class`
   with `architecture = "arm64"` + an `overlay`; capability/kubevirt patches →
   `classes[class].config_patches`; per-node NIC → `node.config_patches`; NTP
   (formerly `cluster.ntp_servers`) → a `config_patches` entry. The
   [`examples/complete/`](tofu/modules/talos-cluster/examples/complete) fixture is
   a full mixed amd64+arm64 worked example.
4. **Supply provider + encrypted backend** in your root (state holds
   `machine_secrets`). See the module README for an example `versions.tf`.
5. **Validate**: `task tofu:ci` (or `tofu fmt -check` + `tofu validate` + `tflint`).
6. **⚠️ Already-running cluster?** The module *generates* fresh PKI by default,
   so a naive `tofu apply` against a live cluster would regenerate PKI and
   re-bootstrap etcd — destroying it. Do **not** apply against a running cluster
   without first following the import-based adoption runbook in
   [§Adopting an already-running cluster](#adopting-an-already-running-cluster-no-re-bootstrap)
   below. Greenfield clusters need no special steps.

### Adopting an already-running cluster (no re-bootstrap)

> **Status: validated against a live, already-bootstrapped cluster** (issue #97
> AC#2). Proven on a real 9-node cluster (amd64 controlplanes + amd64 workers +
> a GPU worker + an arm64 Raspberry-Pi worker) with the **v0.7.0** module,
> provider **siderolabs/talos v0.11.0**, OpenTofu **v1.12.1**: import + `tofu
> plan` reported `0 to destroy` — neither identity resource is replaced, so no
> PKI roll and no re-bootstrap. Still **dry-run it on your own cluster** (import
> and plan only, never apply blind) before trusting it against production —
> provider defaults and your version pins shape the exact plan (see step 5).

Use this when the cluster is **already running** and its PKI lives in a
`talosctl gen secrets` bundle (for example a SOPS-encrypted `talos/secrets.yaml`
from the old Makefile path), and you want to move it onto the module **without
regenerating PKI or re-bootstrapping etcd**. The module needs no code change —
adoption is a `tofu import` of the two identity-bearing resources before the
first apply.

**Why two imports make it safe** — they neutralise the two cluster-destroying
actions a fresh apply would take:

| A fresh `tofu apply` would… | The import that prevents it |
|---|---|
| generate fresh `machine_secrets` → every node certificate invalid, cluster unreachable | import `talos_machine_secrets.this` ← your existing `secrets.yaml` |
| call `MachineBootstrap` on already-bootstrapped etcd | import `talos_machine_bootstrap.this` (marks done in state; no RPC) |

**Critical precondition — the imported bundle must be the cluster's *real,
current* PKI.** `talos_machine_configuration_apply` is **not importable** (the
provider exposes no import for it), so after the two imports the per-node apply
resources plan as *to be created* and the first apply re-pushes the
module-rendered machine config to the running nodes. That rendered config
**embeds the cluster PKI** (`data.talos_machine_configuration` injects
`machine_secrets`). So the apply does **not** reconcile "config only" — it
re-asserts the **same** PKI you imported. If the imported `secrets.yaml` is the
node's actual current bundle, that is a no-op for PKI and at most a **rolling
reboot** if non-PKI config fields differ (never a wipe). If the bundle is
**stale, partial, or from another cluster**, the apply pushes *mismatched* PKI
and can sever node↔etcd / kubelet↔apiserver trust on the live controlplane. Use
the exact, current bundle; verify the diff in step 5 before applying.

**Runbook** (adjust `module.cluster` to your module instance name):

```bash
# 0. Author your OpenTofu root (steps 1–4 above) so module + provider + an
#    ENCRYPTED state backend are wired. Init, but do NOT apply yet.
#    - `tofu import` of machine_secrets sets talos_version to the PROVIDER
#      DEFAULT (observed v1.3 with provider v0.11.0) — it is NOT read from the
#      bundle. So if your var.talos_version is pinned higher, expect an in-place
#      `update` (talos_version: v1.3 -> <your pin>) on machine_secrets. That is
#      a metadata reconcile and preserves the PKI bytes (verified, sha256
#      identical); it is NOT a replacement. See step 5 — only a destroy/create
#      (replacement) is the stop condition.
tofu init

# 0a. CONFIRM state encryption is active BEFORE importing — the import writes the
#     full PKI into Tofu state. With an unencrypted/local backend you would leak
#     plaintext PKI to disk. Verify your encryption {} block / backend is wired
#     (e.g. inspect the backend config; a freshly-written state file must not
#     contain readable cert PEM blocks).

# 1. Decrypt your existing Talos secrets bundle to a TEMP plaintext file.
#    Prefer a RAM-backed dir so no plaintext ever hits persistent storage:
#      Linux:  TMPDIR=/dev/shm
#      macOS:  create a RAM disk, or accept that secure single-file erase is
#              unreliable on APFS/SSD (see "Plaintext hygiene" below).
umask 077
SECRETS_PLAINTEXT="$(mktemp "${TMPDIR:-/tmp}/talos-secrets-XXXXXX.yaml")"
sops -d talos/secrets.yaml > "$SECRETS_PLAINTEXT"

# 2. Import the existing PKI — no fresh generation. Import ID is the file path.
tofu import 'module.cluster.talos_machine_secrets.this' "$SECRETS_PLAINTEXT"

# 3. Import bootstrap state — no re-bootstrap RPC. The id is arbitrary.
#    BOTH imports must succeed. If this one fails or is skipped while step 2
#    succeeded, the next apply will run MachineBootstrap on live etcd. Verify:
#      tofu state list | grep -E 'talos_machine_(secrets|bootstrap)\.this'
#    must list BOTH before you proceed.
tofu import 'module.cluster.talos_machine_bootstrap.this' adopted

# 4. Remove the plaintext (see "Plaintext hygiene" — on SSD/COW this is best
#    effort; rotation is the real remedy if the workstation is untrusted).
rm -f "$SECRETS_PLAINTEXT"

# 5. PROOF the adoption neither regenerated PKI nor scheduled a re-bootstrap.
#    Use -refresh=false so the plan reflects imported state, not a live re-read.
tofu plan -refresh=false
#    PRIMARY GATE — the plan summary MUST end with "0 to destroy":
#        Plan: <N> to add, <M> to change, 0 to destroy.
#      `0 to destroy` == no resource is REPLACED == no PKI roll, no re-bootstrap.
#      Any non-zero destroy count is a STOP — investigate before applying.
#    EXPECTED "to change" (in-place update, NOT replacement — both are safe):
#      * module.cluster.talos_machine_secrets.this    -> update
#        (talos_version: v1.3 import-default -> your pin; PKI bytes preserved.
#         The computed machine_secrets/client_configuration show "known after
#         apply" as a CONSEQUENCE of that metadata change — not a regen.)
#      * module.cluster.talos_machine_bootstrap.this  -> update  (no re-bootstrap)
#    EXPECTED "to add" (not importable / recomputed; none re-bootstrap or roll PKI):
#      * module.cluster.talos_image_factory_schematic.per_class[*]  (factory
#        compute, no cluster contact)
#      * module.cluster.talos_machine_configuration_apply.this["<host>"]  (on a
#        real apply, pushes config — review the rendered diff vs the running
#        nodes first; a no-op if it matches, else a rolling reboot)
#      * module.cluster.talos_cluster_kubeconfig.this  (pulls a kubeconfig from
#        the first controlplane — a read RPC, harmless on a healthy cluster)
#    Anything with a destroy, or a create/change OUTSIDE this set, is a STOP.

# 6. Apply only once the plan shows "0 to destroy" and matches the above.
tofu apply
```

**Plaintext hygiene.** The import reads a *plaintext* file (the provider has no
native SOPS support). Minimise exposure: `umask 077`, and decrypt into a
RAM-backed location (`/dev/shm` on Linux; a RAM disk on macOS) so the plaintext
never reaches persistent storage. Note that `shred`/`rm -P` do **not** reliably
erase a single file on SSD or copy-on-write filesystems (APFS, Btrfs, ZFS) and
`shred` is absent on stock macOS — do not rely on overwrite-delete for
assurance. If the workstation is untrusted or the plaintext may have been
swapped/snapshotted, the real remedy is to **rotate the Talos secrets**, not to
trust an in-place erase. Never commit or persist the plaintext.

**Prove it on your own cluster first.** This was validated against one live
cluster (status note above), but provider defaults and your version pins shape
the exact plan — dry-run it yourself before trusting it against production.
Two reproducible harness scripts live in the module's
[`test/`](tofu/modules/talos-cluster/test/README.md):

- `pki-reconcile-microtest.sh` — self-contained (no cluster); proves the
  `talos_version: v1.3 -> <pin>` reconcile preserves the `machine_secrets` bytes.
- `run-adoption-proof.sh` — drives the import + `tofu plan` against an isolated
  copy of your root (never your real backend) and asserts `0 to destroy`.

Run both, and confirm step 5 shows no `machine_secrets`/`machine_bootstrap`
replacement, before adopting any real cluster.

---

## Pending sunsets

Capability deprecations and their sunset schedule are no longer a
substrate-base concern. The capabilities and the PNI / capability-network
contract that defined them dissolved out of the base in v2.0.0 (see
[§Substrate-only ablation](#substrate-only-ablation-consumer-action-required)).

Capability deprecation scanning and the per-capability replacement guidance
(for example the former `storage-csi` → `block-storage-replicated` /
`block-storage-local` split, or `monitoring-scrape-provider` folding into
`monitoring-scrape`) now live in the
[`talos-platform-apps`](https://github.com/devobagmbh/talos-platform-apps)
catalog. Run that catalog's deprecation scan against your manifests, and
follow its replacement guidance, before adopting a catalog artifact that
fires a sunset.

---

## Template for future MAJOR/MINOR sections

Releases are now tagged automatically by semantic-release (see
[`knowledge/workflows/release-process.md`](knowledge/workflows/release-process.md)), which does **not**
write this file. Migration sections here are curated by a maintainer
retroactively — typically alongside the release for a MAJOR/MINOR with consumer
impact — using the format below:

```markdown
### `vX.Y.Z` (YYYY-MM-DD) — <one-line summary>

**Type:** MAJOR | MINOR | PATCH
**Breaking?** yes | no

#### Breaking changes (consumer action required)

- <bullet> — for example "Substrate Helm value `argocd.server.replicas`
  default changed. Patch your consumer overlay." or "`tofu/modules/talos-cluster`
  input `<var>` renamed."

#### Validation steps after upgrade

1. `task gitops:validate` in consumer repo
2. `task tofu:ci` (for `tofu/` interface changes)
3. `scripts/lint-hardware-features.sh` (for Layer-C hardware-feature changes)
```

---

## See also

- [`CHANGELOG.md`](CHANGELOG.md) — per-release notes
- [`SECURITY.md`](SECURITY.md) — supported versions
- [`knowledge/workflows/verify-release.md`](knowledge/workflows/verify-release.md) — verify before vendoring
- [`knowledge/decisions/0004-substrate-only-base.md`](knowledge/decisions/0004-substrate-only-base.md) — substrate-only scope; PNI dissolution
- [`knowledge/decisions/0009-node-capability-composition.md`](knowledge/decisions/0009-node-capability-composition.md) — node-capability composition migration
