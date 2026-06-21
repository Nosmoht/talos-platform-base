---
status: proposed
id: base:substrate-hard-constraints
date: 2026-06-21
deciders:
  - Thomas Krahn
consulted: []
informed: []
supersedes: []
related:
  - base:opentofu-cluster-lifecycle
  - base:substrate-only-base
---

# ADR: Substrate Hard Constraints — boot-loop guards and deprecated-API bans

## Context and Problem Statement

Three substrate-level invariants are already **in force**: enforced in module
code and/or a CI gate, and documented in `AGENTS.md` §Hard Constraints as
non-negotiable. They had no decision record, so an agent (or a future
maintainer) reading the agent file saw the *rule* but not the *decision* — why
it exists, what enforces it, and what the rejected alternative actually fails
at. This ADR records the three constraints retroactively so the decision and
its enforcement have an ADR home. It introduces no new constraint and changes
no behavior.

The three are heterogeneous in nature but share one property: violating them is
a **known, reproducible failure** (a Talos boot loop) or a **deprecated
Kubernetes API**, not a contested design trade-off. They are recorded together
because the agent file groups them together as "hard constraints".

## Decision

### D1 — No SecureBoot

The Talos node installer MUST be the non-SecureBoot variant. The
`metal-installer-secureboot` image, the bare `metal-secureboot`, and the
Image-Factory `installer-secureboot` URL form all cause boot loops on this
platform's hardware.

- **Enforcement (code):** `tofu/modules/talos-cluster` selects `urls.installer`,
  never `urls.installer_secureboot`.
- **Enforcement (CI):** `hard-constraints-check.yml` greps
  `(metal-secureboot|installer-secureboot)` over `tofu/**` and fails on a match.

### D2 — No `debugfs=off`

The `debugfs=off` kernel argument MUST NOT be set. It causes a "failed to create
root filesystem" boot loop in Talos.

### D3 — EndpointSlices only

`kind: Endpoints` MUST NOT be authored; use `EndpointSlice`. The `Endpoints` API
is deprecated as of Kubernetes v1.33.0.

## Consequences

**Positive:**

- The agent file's three hard-constraint bullets now carry a decision back-link,
  closing a Phase-2 ADR-coverage gap (an agent reading the constraint can reach
  its rationale + enforcement point).
- The decision rationale (concrete failure mode per constraint) is recorded
  where a future maintainer evaluating "can we relax this?" will look.

**Neutral:**

- No behavior change. D1 is already enforced in module code + CI; D2/D3 are
  authoring rules already stated in `AGENTS.md`. This ADR is a record, not a
  new control.
- D2 and D3 are not independently CI-gated today (only D1 is). Adding a CI grep
  for `debugfs=off` and `kind: Endpoints` is a possible follow-up but is out of
  scope for this record-only ADR.

## Alternatives considered

- **Enable SecureBoot** (D1) — rejected: the SecureBoot installer variants boot-
  loop on this platform's hardware. Not a trade-off; an empirical failure.
- **Allow `debugfs=off`** (D2) — rejected: reproducible "failed to create root
  filesystem" boot loop.
- **Use `kind: Endpoints`** (D3) — rejected: deprecated Kubernetes API
  (since v1.33.0); `EndpointSlice` is the supported replacement.
- **Leave the constraints ADR-less** (status quo) — rejected: a hard constraint
  enforced in code + CI with no decision record is exactly the "constraint in
  force with no backing ADR" gap this record closes.

## References

- `AGENTS.md` §Hard Constraints — the three constraints as stated to agents (SOT for the rule text).
- `.github/workflows/hard-constraints-check.yml` — the D1 CI gate.
- `docs/adr-opentofu-cluster-lifecycle.md` — the module that enforces D1 in code.
