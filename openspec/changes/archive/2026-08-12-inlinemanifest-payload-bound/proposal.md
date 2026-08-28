## Why

The module bakes three `inlineManifests` seeds into the controlplane machine
configuration — cilium, argocd and the always-on cert-approver. Talos receives
them as ONE document, but nothing bounded that sum. An overflow surfaced as an
apply failure against real hardware, after the plan had looked clean.

`main.tf` carried a "~66 KB total" budget attached to the Cilium render, as if the
budget were per-seed. That figure had no cited Talos-side source, and the sourced
ceiling turns out to be three orders of magnitude larger, so the comment was
actively misleading in both directions: wrong scale, wrong scope.

## What Changes

- A precondition on `data.talos_machine_configuration.controlplane` rejects an
  oversized payload at plan time, naming the measured byte count, the ceiling and
  the enabled seeds.
- The ceiling is traceable: Talos' `GRPCMaxMessageSize = 32 * 1024 * 1024`
  (`pkg/machinery/constants/constants.go` at `v1.11.0`), which caps the
  `ApplyConfiguration` message, minus headroom for the generated base document and
  the pass-2 per-node overlays.
- The unsourced `~66 KB` prose is removed.

A precondition over the patch locals, deliberately, not a postcondition over the
data source's `machine_configuration`. That attribute depends on
`talos_machine_secrets`, so on a first plan it is unknown and a postcondition over
it defers to apply — the exact failure this gate exists to move earlier. This was
measured, not reasoned: the postcondition form did not fire even with the ceiling
lowered to 1000 bytes.

## Capabilities

- `cluster-bootstrap-lifecycle` — MODIFIED: the per-node apply requirement gains
  the plan-time payload bound, its traceable-ceiling and known-at-first-plan
  obligations, and a scenario for the oversized case.

## Impact

No consumer-visible change under any realistic configuration: the ceiling sits far
above the current payload, so no existing plan starts failing. What changes is the
failure MODE for a future oversized seed — plan-time error instead of an apply
failure against hardware.

Two residuals, recorded in ADR-0022 rather than implied closed: 32 MiB is the
bound that could be sourced, not proof that nothing tighter binds first (STATE
partition, etcd, maintenance mode are unverified); and no permanent test binds the
ceiling, because a synthetic payload at that scale is impractical to commit — the
binding is a documented re-runnable procedure.
