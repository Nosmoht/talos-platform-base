## Why

`cilium_values_override` reached exactly one place — the bootstrap seed's Helm
values list — and the seed is create-only, so the long tail the override exists
to carry (Hubble beyond the typed inputs, L2/BGP announcements, bpf tuning,
`secretsNamespaceLabels`) had no base-delivered route into an already-bootstrapped
cluster. Enabling `cilium_self_management` alongside a non-empty override was a
hard plan-time rejection, which closed the silent-drop hazard by closing the
capability. ADR-0028 §(b) supersedes both properties.

Composing the override so the consumer's layer WINS means letting Helm merge it:
the override is an opaque YAML document of arbitrary depth and HCL has no generic
recursive merge. ArgoCD orders `valueFiles` entries, but `$values/<path>` resolves
only through a sibling `spec.sources[]` entry carrying `ref` — verified against
ArgoCD v3.5.2's repo-server — so a single-source chart `Application` cannot address
a consumer-committed file at all. The emitted `Application` therefore becomes
MULTI-SOURCE when a values source is configured.

Moving the module-set values layer out of the manifest and into a
consumer-committed file re-opens ADR-0028 §(d)'s own unbootable state by omission:
`kubeProxyReplacement`, `k8sServiceHost` and `k8sServicePort` are produced by the
computed layer alone, so a missing or stale values file renders a Cilium that does
not replace kube-proxy while Talos already carries `cluster.proxy.disabled` — on a
running cluster, delivered by a sync, with a create-only seed that cannot repair
it. The three keys are re-asserted as the last values layer, which is sound
precisely because §(d) forbids the override from naming them.

§(d)'s claim that closing those keys "costs no capability" did not hold: only
`kubeProxyReplacement` had a typed input. The endpoint was hardcoded to Talos
KubePrism, while Cilium documents `k8sServiceHost`/`k8sServicePort` as
endpoint-derived in general. Typed inputs for both ship here, which is what makes
the rejection cost-free and closes #227.

## What Changes

- The emitted Day-2 `Application` inherits `cilium_values_override` as the LAST of
  two ordered `valueFiles` entries, gated on a new
  `cilium_self_management_values_source` object input. Unset keeps today's
  single-source manifest byte-identical.
- A second output, `cilium_self_management_values`, carries the module-set layer
  for the consumer to commit; a `values-digest` annotation on the `Application`
  is the only mechanical link between the two artifacts.
- The `cilium_self_management` × non-empty-override hard reject is replaced by a
  reject on the MISSING values source (the same silent drop, differently caused).
- `cilium_values_override` is rejected when it names an ADR-0028 §(d) joint key or
  is not a YAML mapping, and is marked `sensitive`.
- New typed `cilium_k8s_service_host` / `cilium_k8s_service_port` inputs, defaulting
  to Talos KubePrism.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `cilium-cni-delivery`: the emitted self-management Application's values are two
  ordered `valueFiles` plus a joint-key `valuesObject` when a values source is
  configured, and the override reaches Day-2.
- `module-interface-contract`: the self-management guard set changes shape, the
  override gains two content guards and a sensitivity classification, the
  API-server endpoint becomes two typed inputs, and a second self-management
  output appears.
- `cluster-yaml-sot`: the closed `substrate.cilium` object admits three more keys.

## Impact

- BREAKING (MAJOR). The emitted `Application`'s values shape changes on the new
  arm; an input's accepted range widens (`cilium_self_management` with an
  override) while another narrows (the override may no longer name three keys);
  `cilium_values_override` becomes `sensitive`, so `tofu plan` stops showing its
  diff.
- A consumer whose override names `kubeProxyReplacement`, `k8sServiceHost` or
  `k8sServicePort` must move it to the typed input of the same name. The frozen
  seed does not change on an already-bootstrapped cluster either way.
- A consumer adopting the multi-source arm commits TWO artifacts and must keep
  them in step, must have the values repo registered in ArgoCD, and must list both
  repos in a scoped `AppProject`'s `sourceRepos`.
- Pinning back to a pre-MAJOR base tag re-arms the old hard reject, so the
  downgrade path requires emptying the override first. `UPGRADING.md` carries both
  directions plus the break-glass path for a sync that breaks the datapath.
- The live seed ↔ `Application` re-capture behaviour stays UNVERIFIED (ADR-0028
  §(b)); this repository has no live cluster.
