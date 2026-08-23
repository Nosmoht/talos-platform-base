---
type: decision
title: "ADR: Where the per-node capability-composition logic should live (HCL vs a portable pre-processing layer)"
description: "Defers extracting the per-node capability-composition logic from HCL into a portable pre-processing layer, recording a hybrid recommendation and concrete triggers for revisiting."
status: proposed
id: base:composition-logic-placement
decided: "2026-06-20T00:00:00Z"
deciders:
  - platform-maintainer
related:
  - base:node-capability-composition
  - base:opentofu-cluster-lifecycle
tags: [adr, tooling]
---

# ADR: Where the per-node capability-composition logic should live (HCL vs a portable pre-processing layer)

> **An open question, not a settled decision** (frontmatter `status: proposed`).
> This ADR records a tension surfaced
> reviewing [base:node-capability-composition](./0009-node-capability-composition.md)
> (PR #135). It does **not** reverse that decision — the composition *model* (M1
> composite-capability) stands. It scopes a separate question the prior ADRs never
> weighed: in which *layer* the resolution logic executes. Decision deferred with a
> recommendation + a concrete trigger; tracked as a follow-up issue.

## Context and Problem Statement

`tofu/modules/talos-cluster/composition.tf` is ~266 lines of **bespoke
data-transformation authored in HCL**: set-union across a node's capabilities,
vendor-variant resolution, content-hash schematic dedup (`substr(sha256(…))`),
and a battery of plan-time `precondition` guards (symmetry both ways,
module/sysctl/kernel-arg conflicts, undefined image/capability/profile). The
`siderolabs/talos` provider supplies **none** of this — it resolves schematics,
installers, machine config, and apply. The composition layer is base-local logic.

This is in direct tension with the decision that motivated the current executor.
[base:opentofu-cluster-lifecycle](./0006-opentofu-cluster-lifecycle.md) replaced the
`make`/5-axis path precisely because it had grown "a large, base-specific
imperative surface" (a schematic-hash cache, a placeholder-substitution engine, a
feature registry) — and its generalised lesson (#99) is *"prefer maintained
declarative tooling over bespoke imperative reinvention."* PR #135 re-introduces
that surface — a schematic-hash cache + resolution engine — only now expressed in
HCL `locals` rather than shell.

**tofu is an exchangeable executor.** What it does, a Makefile did before it;
a future swap (back to scripts, to Crossplane, to another tool) is plausible. The
more resolution logic accretes in HCL, the larger the reimplementation cost of
that swap. And HCL is a *poor host* for this work:

- **Set-algebra is awkward and bug-prone in HCL.** Two MEDIUM/LOW review findings
  trace directly to HCL `for`/`merge`/`distinct` semantics: the symmetry guard
  checked the per-node *union* instead of per-capability (a malformed capability
  could be masked by a sibling — fixed in PR #135 by adding more HCL), and the
  kernel-arg conflict guard false-positived on legitimate multi-value args.
- **Not offline unit-testable.** The guard-regression suite
  (`tests/composition.tftest.hcl`) needs a live Talos Image Factory to `plan`, so
  it cannot run in the offline `task tofu:ci` — its CI enforcement requires a dedicated
  networked job (added in PR #135). Pulling the pure resolution logic into a
  general-purpose language would make it testable with ordinary offline unit tests.

## Considered Options

1. **Status quo — keep resolution in HCL** (the shape PR #135 ships).
2. **Extract resolution to a portable pre-processing step.** A script (Python/Go)
   transforms `cluster.yaml` → fully-resolved module inputs (per-node schematic
   descriptors, installer keys, generated machine-config patches). tofu becomes a
   thin executor over resolved inputs with no composition logic.
3. **Hybrid.** Resolution (union/dedup/hash) moves to the portable layer; thin
   plan-time `precondition` guards stay in HCL as a last-line defence that fires at
   the actual apply boundary against the real values.

## Decision Outcome

**Deferred (proposed).** No extraction in PR #135 — the findings there are fixed
in place to keep that PR mergeable and reversible. This ADR makes the lock-in a
*deliberate, recorded* choice rather than silent accretion.

**Recommendation:** prefer **Option 3 (hybrid)** if/when the composition logic
grows past the current footprint. The portable layer earns its keep when the
set-algebra gets richer; the thin HCL guards keep validation bound to the apply
boundary (the property that makes the current guards trustworthy).

**Trigger to revisit (any one):** a third provisioning sink is added beyond the
current schematic + machine-config split; a second vendor/arch resolution
dimension is added beyond `cpu_vendor`; the composition `locals` grow materially
past their current size; or a third HCL-semantics bug (like the union-scope or
multi-value-karg classes) is found. Until a trigger fires, status quo holds and
the cost is *recorded, not paid*.

### Consequences

- **Status quo (today):** lowest immediate change; guards fire at the apply
  boundary with clear messages; but HCL lock-in grows, set-algebra stays bug-prone,
  and the regression suite stays network-coupled.
- **Extract / hybrid (if triggered):** offline-unit-testable resolution, lower
  executor lock-in, alignment with #99; at the cost of a new consumer-side
  pre-processing step and (for pure extraction) validation decoupled from `apply`
  — the hybrid keeps the apply-bound guards to avoid that.

## Validation

This ADR is wrong if the composition logic stays small and stable (no trigger ever
fires) — in which case the status quo was correctly cheap and the extraction cost
was rightly not paid. It is also wrong if a trigger fires and extraction proves
*more* lock-in than HCL (e.g. the pre-processing step itself becomes a bespoke
engine #99 warns against) — the hybrid recommendation hedges against that by
keeping the thin guards declarative.

## Links

- [base:node-capability-composition](./0009-node-capability-composition.md) — the composition model this ADR scopes the *placement* of.
- [base:opentofu-cluster-lifecycle](./0006-opentofu-cluster-lifecycle.md) — the executor decision + the #99 anti-pattern this ADR re-applies to the HCL layer.
- PR #135 — introduces `composition.tf`; the review that surfaced this tension.
