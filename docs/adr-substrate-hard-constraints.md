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
code and/or the `hard-constraints-check.yml` CI gate, and documented in
`AGENTS.md` §Hard Constraints as non-negotiable. They had no decision record, so
an agent (or a future maintainer) reading the agent file saw the *rule* but not
the *decision* — why it exists, what enforces it, and what the rejected
alternative actually fails at. This ADR records the three constraints
retroactively so the decision and its enforcement have an ADR home. It
introduces **no new constraint and changes no cluster-runtime behavior**; it
does add a decision back-link to the canonical `AGENTS.md §Hard Constraints`
bullets (an agent-instruction surface change only).

**Scope — why these three.** §Hard Constraints lists eleven bullets; this ADR
records the three that had **no** backing decision record. The others already
have ADR homes — e.g. "Gateway API only" is covered by the policy-stack decision
(`talos-platform-docs` ADR-0018), "never `kubectl apply` ArgoCD-managed" by the
multi-repo split. The three recorded here are grouped because they share a
property: violating each is a **known, reproducible failure** (a boot loop) or a
**deprecated Kubernetes API**, not a contested design trade-off.

## Decision

### D1 — No SecureBoot

The Talos node installer MUST be the non-SecureBoot variant. The
`metal-installer-secureboot` image, the bare `metal-secureboot`, and the
Image-Factory `installer-secureboot` URL form all cause boot loops on this
platform's hardware.

- **Enforcement (code, two mechanisms):** the `tofu/modules/talos-cluster`
  module (a) selects `urls.installer`, never `urls.installer_secureboot`; and
  (b) carries a plan-time `precondition` that fails the apply when any
  caller-supplied `config_patch` string matches `regex("-secureboot")`
  (`main.tf` `secureboot_patches`). The precondition catches the common
  copy-paste of a `*-secureboot` installer URL into a patch; it is not a
  complete SecureBoot detector (a schematic-level toggle or a by-digest image is
  out of its reach — see the `main.tf` comment).
- **Enforcement (CI):** `hard-constraints-check.yml` greps
  `(metal-secureboot|installer-secureboot)` over `tofu/**` and fails on a match.

### D2 — No `debugfs=off`

The `debugfs=off` kernel argument MUST NOT be set. It causes a "failed to create
root filesystem" boot loop **with Cilium** (the wording the CI gate uses).

### D3 — EndpointSlices only

`kind: Endpoints` MUST NOT be authored; use `EndpointSlice`, the supported
replacement (GA since Kubernetes v1.21). (`AGENTS.md §Hard Constraints` pins the
deprecation at v1.33.0; this ADR does not re-assert a specific deprecation
release.)

## Consequences

**Positive:**

- The agent file's three hard-constraint bullets now carry a decision back-link,
  closing a Phase-2 ADR-coverage gap (an agent reading the constraint can reach
  its rationale + enforcement point).
- The decision rationale (concrete failure mode per constraint) is recorded
  where a future maintainer evaluating "can we relax this?" will look.

**Neutral:**

- **No new control — all three are already enforced; this ADR is a record.** D1
  is enforced in module code (installer-URL selection + the `secureboot_patches`
  precondition) AND CI. D2 and D3 are enforced by `hard-constraints-check.yml`:
  the `debugfs=off` step (over `kubernetes/**`+`tofu/**`) and the forbidden-kinds
  step (`^kind:\s*(Ingress|Endpoints)\b` over `kubernetes/**`). There is no
  CI-gating follow-up to do.

## Validation

How will we know this decision is wrong, and what mechanical check confirms it
stays correct?

- **Mechanical check (stays correct):** `hard-constraints-check.yml` keeps all
  three gate steps red-on-violation — (D1) SecureBoot step greps
  `(metal-secureboot|installer-secureboot)` over `tofu/**`; (D2) kernel-parameter
  step greps `debugfs=off` over `kubernetes/**`+`tofu/**`; (D3) forbidden-kinds
  step greps `^kind:\s*(Ingress|Endpoints)\b` over `kubernetes/**`. The module
  `secureboot_patches` precondition rejects a `-secureboot` `config_patch` at
  plan time. The three `AGENTS.md §Hard Constraints` back-links resolve to this
  file.
- **Wrong-if (falsification):** a future Talos release that boots the SecureBoot
  installer on this hardware without a loop falsifies D1 (revisit); a
  Talos/Cilium release that no longer loops on `debugfs=off` falsifies D2;
  Kubernetes restoring `Endpoints` as non-deprecated falsifies D3.

## Alternatives considered

- **Enable SecureBoot** (D1) — rejected: empirical boot loop on this hardware,
  not a trade-off.
- **Allow `debugfs=off`** (D2) — rejected: reproducible boot loop with Cilium.
- **Use `kind: Endpoints`** (D3) — rejected: deprecated in favor of
  `EndpointSlice`.
- **Leave the constraints ADR-less** (status quo) — rejected: a constraint
  enforced in code + CI with no decision record is exactly the "constraint in
  force with no backing ADR" gap this record closes.

## References

- `AGENTS.md` §Hard Constraints — the three constraints as stated to agents (SOT for the rule text).
- `.github/workflows/hard-constraints-check.yml` — the CI gate for **all three** (SecureBoot / `debugfs=off` / forbidden-kinds steps).
- `tofu/modules/talos-cluster/main.tf` — D1 code enforcement (installer-URL selection + `secureboot_patches` precondition).
- `docs/adr-opentofu-cluster-lifecycle.md` — the ADR for that module.
