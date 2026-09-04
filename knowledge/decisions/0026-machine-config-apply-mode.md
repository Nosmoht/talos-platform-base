---
type: decision
title: "ADR: The machine-config apply mode is a per-role input defaulting to auto"
description: "Two role-scoped inputs expose the talos provider's apply_mode so an operator can stage a reboot-needing machine-config change instead of rebooting a whole role in parallel; the default stays auto because the module's only apply resource also carries the Day-0 install."
status: stable
id: base:machine-config-apply-mode
decided: "2026-08-28T00:00:00Z"
deciders:
  - maintainer
consulted: []
informed: []
supersedes: []
superseded_by: []
related:
  - /decisions/0006-opentofu-cluster-lifecycle.md
  - /decisions/0013-kubelet-serving-cert-rotation.md
tags: [adr, talos-cluster, machine-config, day-two, reboot]
---

# ADR: The machine-config apply mode is a per-role input defaulting to auto

## Context and Problem Statement

`talos_machine_configuration_apply.this` is the module's only apply resource and
carries both lifecycle phases: the Day-0 apply to maintenance-mode nodes and
every later configuration change. It is `for_each`'d over the node set with no
ordering dependency, so a change the node cannot adopt immediately — a kernel
module parameter, a sysctl, anything under `machine.files` — reboots every node
of that role concurrently.

A concurrent reboot of a whole role is not a rolling restart. Talos gives the
kubelet a graceful shutdown window (`KubeletShutdownGracePeriod = 30 * time.Second`
and a shorter critical-pods period in `pkg/machinery/constants/constants.go`,
injected into the KubeletConfiguration by
`internal/app/machined/pkg/controllers/k8s/kubelet_spec.go` unless the operator
overrides `shutdownGracePeriod` — both read on the `siderolabs/talos` default
branch on 2026-08-28; this module overrides nothing), so pods are
signalled — but kubelet's graceful node shutdown kills pods directly rather than
through the API server's eviction subresource (`killPodFunc`, typed
`eviction.KillPodFunc`, called with `isEvicted = false` in
`pkg/kubelet/nodeshutdown/nodeshutdown_manager.go`, ref `release-1.36`), so
PodDisruptionBudgets are never consulted. What is missing is therefore not the
signal but cross-node sequencing: every replica of a quorum-based store on that
role stops inside one window, and a node whose shutdown sequence stalls is
recovered with `talosctl reboot --mode force`, which skips the graceful phase
entirely and has no window at all.

A declarative parallel apply has no "apply to one node, wait for health, gate,
next" primitive, so the sequencing has to live outside the apply. Until this
decision the module offered no way to keep the apply from rebooting.

## Decision Drivers

- The module must keep standing up clusters: its documented entry state is
  PXE-booted maintenance-mode nodes, and the first apply to such a node **is**
  the install.
- Single-node and multi-node clusters, Day-0 and Day-2, are all in scope.
- Controlplanes and workers roll under different gates — etcd quorum on one
  side, whatever the workload requires on the other — so one cluster-wide knob
  would force a manual roll on nodes that do not need one.
- Reboot sequencing for stateful nodes is an operator procedure, not something
  this module can express.

## Considered Options

1. Two role-scoped `apply_mode` inputs, both defaulting to `auto`.
2. The same inputs defaulting to `staged_if_needing_reboot`, so a reboot-needing
   apply stages itself without the operator asking.
3. Health-gated rolling inside the module, via the provider's `talos_machine`
   resource.

## Decision Outcome

Chosen option: **two role-scoped inputs, `controlplane_apply_mode` and
`worker_apply_mode`, defaulting to `auto`** — the provider's own default, and the
only value that leaves Day-0 intact. An operator opens a window by setting the
affected role to `staged`, applies, and then reboots the nodes out of band, one at
a time, under whatever health gate the workload needs.

`auto` is not a compromise between safety and compatibility; it is what the
resource's Create path requires. The provider hands the configured mode straight
to `ApplyConfiguration` in Create as well as Update (`getEffectiveMode` feeding
the `ApplyConfigurationRequest` in
`pkg/talos/talos_machine_configuration_apply_resource.go`, ref
`v0.12.0-beta.0`), so a staging default would write the Day-0 configuration
without installing, and
`talos_machine_bootstrap` would then run against a node that never left
maintenance mode.

### Consequences

- Positive: a reboot-bound change to a stateful role is a deliberate, sequenced
  operator action rather than a side effect of `tofu apply`.
- Positive: purely additive, and not merely by intent — the provider declares
  `apply_mode` as `Optional + Computed` with `Default: stringdefault.StaticString("auto")`
  (`pkg/talos/talos_machine_configuration_apply_resource.go`, ref `v0.11.0`), so a
  resource created before this change already holds `"auto"` in state and writing
  it explicitly produces no plan diff on adoption.
- Negative: between the staged apply and the operator's reboot, the state file
  and the node's effective configuration disagree, and a subsequent plan is
  clean. Closing that window is the operator's obligation; nothing in the module
  detects it.
- Negative: no protection by default. A consumer with a stateful role has to know
  to set the input.
- Negative: the window has an ordering obligation the module cannot enforce.
  An apply-mode change alone reaches the provider's `Update` path, so reverting a
  role to `auto` while its configs are still staged re-applies them in `auto` mode
  and reboots exactly the nodes not yet gated. Revert last, after every node of
  the role has been rebooted.
- Negative: the mode is role-scoped, not lifecycle-scoped. A node added while a
  window is open is staged rather than installed, stays in maintenance mode, and
  the apply blocks on the health gate until it times out.
- Negative: a staged config is adopted at the NEXT boot, whoever causes it. An
  out-of-band `talosctl upgrade` run during an open window adopts the staged
  machine-config change alongside the OS upgrade, with no signal that two
  changes landed together.
- Follow-up: health-gated rolling stays out of reach — see option 3 below.

## Pros and Cons of the Options

### Option 1 — role-scoped inputs, default `auto`

- Pro: Day-0 unaffected; single-node and multi-node behave identically.
- Pro: the two roles are independently gateable, which is what their different
  quorum models require.
- Con: the safe behaviour is opt-in.

### Option 2 — default `staged_if_needing_reboot`

- Pro: would protect a stateful role without the operator knowing to ask.
- Con: the mode is not dependable. It resolves by dry-running the apply, and its
  `handleRebootPrevention` path falls back to `auto` when the node address is
  unknown, when the client configuration is unknown, and when that configuration
  cannot be read — three returns that emit no diagnostic at all at ref `v0.11.0`.
  The module's `client_configuration` comes from `talos_machine_secrets`, so on a
  first apply it is unknown and the fallback is silent.
- Con: it has a scheduled expiry. Talos 1.14 removed reboot detection from
  apply-config, and from ref `v0.12.0-beta.0` the provider gates the mode on its
  own bundled Talos SDK version and warns that it "will always resolve to 'auto'
  on Talos 1.14+", recommending explicit `staged` instead.
- Con: it is not available across the provider range this module declares. The
  mode arrived in provider 0.11.0, while `versions.tf` declares
  `>= 0.7.0, < 1.0.0`; `apply_mode` itself and its other four values exist at
  ref `v0.7.0`. Admitting the fifth value would let a consumer inside the
  declared range pass the module's validation and be rejected by their own
  provider, so the module's accepted set is the four-value 0.7.0 set.
- Con: does not fix Day-0 either — it only happens to fall back to `auto` there,
  by way of the unknown-client-configuration path.

### Option 3 — health-gated rolling via `talos_machine`

- Con: `talos_machine` has no `apply_mode` and hardcodes
  `ApplyConfigurationRequest_AUTO` in its apply path, and its `reboot_mode` covers
  only `DEFAULT` and `POWERCYCLE`. Adopting it would remove the capability this
  decision adds.
- Con: it sequences only via `depends_on`, which the module's `for_each` over the
  node set cannot express.
- Con: the resource exists only in the 0.12.x line, whose releases are not
  installable from the OpenTofu registry at the time of this decision — an exact
  pin resolves and then fails signature verification with "the provider is not
  signed with a valid signing key". REVISIT TRIGGER: that last point is a
  registry/signing state, not a property of the design. Re-read this option when
  a signed 0.12.x lands; the first two cons are the durable ones.

## Validation

`tofu/modules/talos-cluster/tests/apply-mode.tftest.hcl`, in the offline chain
(`task tofu:test:offline`, hence `task tofu:ci`), is the oracle: seven runs over
`mock_provider` covering the single-node and multi-node Day-0 defaults, a
workers-staged/controlplanes-auto window, a staged single-node controlplane, a
positive control across the closed value set, and two rejections. The file records
its own red-green binding: removing the `apply_mode` line in `main.tf` turns five
runs red, and swapping the arms of `local.node_apply_mode` in `nodes.tf` turns
three red — the two default runs cannot see that mutant, which is why the window
runs use distinct values per role.

One coupling stays unbound: the module's accepted value set is a hand-kept mirror
of the provider's, pinned to what the declared floor (`>= 0.7.0`) supports. No
gate compares the two, and the offline tests run under `mock_provider`, so a
future provider release that renames or drops a mode would surface at apply time
against a node rather than in CI.

The decision is wrong if a staged configuration turns out not to be adopted on the
next boot. That is not observable in this repository — it needs a live cluster —
and is therefore an open predicate at the time of writing, to be answered by
reading the effective parameter back after a forced reboot rather than by reading
the machine configuration.

## Links

- Requirement text: `openspec/specs/cluster-bootstrap-lifecycle/spec.md`
  §Apply mode per role, `openspec/specs/module-interface-contract/spec.md`
  §Grouped typed input surface.

## Addendum 2026-09-04 — the unbound mirror is now half bound, and `reboot` is untested on Talos 1.14

Talos 1.14.0 reached general availability on 2026-09-03, which turns two of this
decision's forward-looking statements into observations.

**The provider coupling is now gated, one layer up.** §Validation records that
nothing compares the module's accepted `apply_mode` set against the provider's,
because the offline runs use `mock_provider`. That specific mirror is still
unbound, but the adjacent and larger one is not: `scripts/check-provider-document-kinds.sh`
(`task tofu:check:provider-document-kinds`, in `tofu:ci`) probes the pinned
provider with the real thing and asserts which Talos machine-config document
kinds it accepts. It exists because the same failure shape bites the four
`config_patches` inputs far harder than it bites `apply_mode`: the provider
decodes patches against its own bundled Talos machinery, so the module's
"arbitrary machine-config" escape hatch reaches the provider's document surface
and not Talos'. Measured on provider `0.11.0`: `UserVolumeConfig` renders,
while `SecurityProfileConfig`, `FilesystemTrimConfig`, `KubeNodeConfig`,
`UnattendedInstallConfig` and `BGPInstanceConfig` are each refused with
`"<kind>" "v1alpha1": not registered`.

**`reboot` is now a value the operating system no longer offers.** The Talos
1.14 CLI reference lists `auto`, `no-reboot`, `staged` and `try` as the
`talosctl apply-config --mode` values; `reboot` was removed. This module keeps
accepting `reboot` because its value set mirrors the provider's, and the
provider still exposes it. Whether a 1.14 node honours the provider's REBOOT
request over the machined API is UNVERIFIED — the CLI flag removal is not
evidence about the API enum, and answering it needs a 1.14 cluster. Until it is
answered, `reboot` is untested on 1.14 and `staged` plus an out-of-band reboot
is the supported way to force one. The decision's four-value set is unchanged:
narrowing it would break consumers on 1.13 and below for a value that may still
work.

**`staged_if_needing_reboot` stays rejected**, for the reason §Considered
Options already gives, now confirmed from the other side: the sole provider
release bundling the 1.14 machinery, `0.12.0-beta.0`, does not install from the
OpenTofu registry at all — `tofu init` refuses it as "not signed with a valid
signing key (authentication signature from unknown issuer)". So the provider
range this module declares still cannot reach it.
