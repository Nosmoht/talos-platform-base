# Issue: ingress-front pod traffic denied by Cilium Gateway API L7 policy

## Summary

The ingress-front macvlan architecture (introduced in commit `7d5edbf`, 2026-03-28) is fundamentally incompatible with Cilium's Gateway API L7 proxy enforcement. All external traffic forwarded through the ingress-front pod to the Gateway ClusterIP returns **403 "Access denied"**.

## Architecture

```
Internet
  -> FritzBox (port forward 443 -> MAC 02:42:c0:a8:02:46 / IP 192.168.2.70)
    -> macvlan net1 on ingress-front pod (stable MAC + IP)
      -> nginx L4 stream proxy (pod eth0, Cilium CNI)
        -> cilium-gateway-homelab-gateway ClusterIP (10.109.250.84)
          -> eBPF TPROXY redirect -> cilium-envoy (shared DaemonSet)
            -> cilium.l7policy filter -> DENIED (403)
```

## Root Cause

### Identity transformation in Cilium's L7 LB proxy

Cilium's Gateway API implementation uses an L7 Load Balancer proxy for all traffic destined to a Gateway Service ClusterIP. The eBPF datapath marks the service entry with `l7-load-balancer` flag and redirects traffic via TPROXY to the local cilium-envoy DaemonSet (port 14947).

All traffic passing through this proxy gets **identity-transformed** to `reserved:ingress` (identity 8). This is by design (CFP cilium/cilium#24536, implemented in PR #24826): Gateway/Ingress listeners should see a unified ingress identity regardless of the traffic source.

The `cilium.l7policy` Envoy filter then evaluates policy based on this identity. The filter denies the request because `reserved:ingress` (identity 8) attempting to reach `reserved:world` (identity 16777220, the Gateway Service CIDR identity) has no explicit allow policy — and the filter applies **implicit default-deny**.

### Verified evidence

`cilium-dbg monitor -t l7` output:
```
-> Request http from 3237 ([reserved:ingress]) to 0 ([cidr:10.0.0.0/8 reserved:world]),
   identity 8->16777220, verdict Denied
   GET https://kb.homelab.local/healthz => 0
```

### Why internal test pods work but ingress-front doesn't

Test pods (without any CiliumNetworkPolicy) also have their traffic redirected through the L7 LB proxy when targeting the Gateway ClusterIP. However, test pods consistently received 200 OK. The exact mechanism difference remains unclear — it may relate to how the eBPF metadata is propagated differently for pods with vs. without CNP egress rules, or to timing/caching of the policy filter state.

## Approaches Tested (all failed)

| Approach | Result | Why |
|----------|--------|-----|
| Remove `toPorts` from `toServices` in cnp-ingress-front | 403 | L7 LB proxy is set by Gateway Service itself (BPF flag), not by CNP |
| Remove ALL CNPs and CCNPs | 403 | `cilium.l7policy` filter has its own implicit deny, independent of endpoint policies |
| Add CCNP for `reserved:ingress` endpoint (egress to cluster+world) | 403 | The L7 filter's policy evaluation is separate from endpoint BPF policy maps |
| Restart Cilium agent + Envoy DaemonSet | 403 | Not stale state — the behavior is architectural |
| `gateway-api-hostnetwork-enabled: true` | Gateway Programmed:False | **Incompatible with `external-envoy-proxy: true`** (shared DaemonSet mode). The hostNetwork option only works with per-Gateway Envoy Deployments. With shared DaemonSet, the Gateway listener disappears entirely. |

## Relevant Cilium Issues

| Issue | Title | Status | Relevance |
|-------|-------|--------|-----------|
| [#28254](https://github.com/cilium/cilium/issues/28254) | Service hairpinning does not work with cilium envoy | Closed (partial fix) | **Direct match.** Hairpinning through Gateway returns 403 with "Policy NOT FOUND". Fix assumed all traffic through Gateway gets ingress identity — but L7 filter still denies. |
| [#43964](https://github.com/cilium/cilium/issues/43964) | CiliumEnvoyConfig: missing implicit L7 policy state | Open | Missing L7 policy state for certain traffic paths causes 403s and TCP resets. Likely contributing factor. |
| [#24536](https://github.com/cilium/cilium/issues/24536) | CFP: Fix Ingress traffic interactions with Policy enforcement | Closed (implemented) | Architecture CFP defining that all Gateway/Ingress traffic assumes `reserved:ingress` identity. |
| [#30073](https://github.com/cilium/cilium/issues/30073) | Ingress Controller 403 Access denied in policyAuditMode | Closed | `reserved:ingress` endpoint flips to default-deny after Cilium restart. |
| [#36509](https://github.com/cilium/cilium/issues/36509) | NetworkPolicy not work as expected with Gateway API | Closed | Maintainer-confirmed workaround: `fromEntities: [ingress]` in CNP. Works for backend pods but does not fix the Gateway listener's own L7 filter denial. |
| [#44113](https://github.com/cilium/cilium/issues/44113) | CFP: Gateway API support for internal gateways | Open | Proposes ClusterIP-type Gateway for internal traffic. Would be the clean solution but not yet implemented. |
| [#43952](https://github.com/cilium/cilium/issues/43952) | CFP: CiliumNetworkPolicy entity alias for Gateway API | Open | Cosmetic — proposes `gateway-api` alias for `reserved:ingress`. |
| [#35525](https://github.com/cilium/cilium/issues/35525) | cilium.l7policy: No policy found | Closed | Stale ipcache entries cause L7 policy lookup failures. Related symptom. |
| [#43556](https://github.com/cilium/cilium/issues/43556) | Per-application IP allowlisting impossible with Gateway API | Open | Confirms architectural limitation: single ingress identity for all gateways. |

## Key Technical Details

### Cilium cluster configuration

- Cilium version: **1.19.2**
- `external-envoy-proxy: "true"` — shared cilium-envoy DaemonSet (hostNetwork), not per-Gateway Deployments
- `enable-l7-proxy: "true"`
- `enable-gateway-api: "true"`
- `gateway-api-hostnetwork-enabled: "false"` — incompatible with external-envoy-proxy
- `enable-policy: "default"` — endpoints without policy allow all; endpoints with policy enforce
- Gateway uses `CiliumLoadBalancerIPPool` (192.168.2.70/32) for address assignment

### The `cilium.l7policy` Envoy filter

- Injected at runtime by Cilium into all Gateway Envoy listeners (not in CiliumEnvoyConfig spec)
- Communicates with Cilium agent via Unix socket for policy decisions
- Returns HTTP 403 with body `"Access denied\r\n"` when policy check fails
- The filter config only has `access_log_path` — no user-configurable policy overrides
- Cannot be disabled or bypassed via configuration

### `gateway-api-hostnetwork-enabled` incompatibility

With `external-envoy-proxy: true`, the cilium-envoy DaemonSet already runs on hostNetwork. The `gateway-api-hostnetwork-enabled` option controls per-Gateway **Deployments** (the non-shared mode). When enabled with shared DaemonSet mode:
- Cilium does not create per-Gateway Deployments (because external-envoy-proxy is enabled)
- Cilium does not bind Gateway listener ports on node interfaces (because it expects per-Gateway pods to do that)
- Result: Gateway listener disappears, Gateway becomes `Programmed: False`

## Additional Issues Found During Investigation

### Missing CiliumLoadBalancerIPPool (fixed)

Commit `7d5edbf` deleted the `CiliumLoadBalancerIPPool` along with the L2 Announcement Policies. This caused `Gateway Programmed: False` because no IP pool existed to assign the LoadBalancer address. Fixed in commit `1a1f791` by restoring the IP pool. API version bumped from `cilium.io/v2alpha1` to `cilium.io/v2` (deprecation).

### Port 8001 missing in PNI CCNP (fixed)

The `pni-gateway-backend-consumer-ingress` CCNP did not include port 8001 (kb-mcp MCP server) in the `fromEntities: ["ingress"]` port list. Fixed in commit `448494e`.

### Deployment strategy (fixed)

The ingress-front Deployment used the default `RollingUpdate` strategy. Since the macvlan IP (192.168.2.70) is exclusive, a new pod cannot bind it while the old pod holds it. Changed to `strategy.type: Recreate` in commit `448494e`.

## Remaining Options

### Option 1: Restore L2 Announcements (revert to pre-ingress-front architecture)

Remove ingress-front entirely and restore `CiliumL2AnnouncementPolicy` + `CiliumLoadBalancerIPPool`. External traffic arrives directly at the Gateway LoadBalancer IP — no hairpin, no identity mismatch.

**Trade-off**: MAC flapping on node failover breaks FritzBox port forwarding (the original reason ingress-front was built). Mitigatable by constraining `nodeSelector` to a single node.

### Option 2: Wait for Cilium internal gateway support (cilium/cilium#44113)

The CFP proposes ClusterIP-type Gateway services for internal traffic. This would cleanly support the ingress-front architecture. Status: Open, no implementation timeline.

### Option 3: Switch from `external-envoy-proxy` to per-Gateway Deployments

Disable `external-envoy-proxy` so Cilium creates per-Gateway Envoy Deployments instead of using the shared DaemonSet. Then `gateway-api-hostnetwork-enabled: true` would work, binding the Gateway listener directly on node interfaces.

**Risk**: Significant architecture change. Per-Gateway Deployments have different resource and scheduling characteristics than the shared DaemonSet. Requires thorough testing.

## Files Modified During Investigation

| Commit | Change | Status |
|--------|--------|--------|
| `1a1f791` | Restore CiliumLoadBalancerIPPool | **Committed, pushed** |
| `448494e` | Fix CNP toPorts, add port 8001 to CCNP, Recreate strategy | **Committed, pushed** |
| `3d96905` | Add CCNP for reserved:ingress identity | **Committed, pushed** (ineffective, should be removed) |
| `1a8d876` | Enable hostNetwork mode | **Reverted** in `cb758d1` |

### Live cluster state divergence

The following resources were applied live during debugging and may differ from git:
- `cnp-ingress-front` (default namespace) — was deleted/recreated multiple times
- `kb-mcp-gateway` (knowledge-base namespace) — was modified with extra `fromEndpoints` rule
- `pni-gateway-backend-consumer-ingress` (CCNP) — was deleted and re-applied
- `pni-gateway-ingress-identity` (CCNP) — exists in cluster from commit `3d96905`, should be removed

ArgoCD auto-sync should reconcile these to git state, but verify after cleanup.
