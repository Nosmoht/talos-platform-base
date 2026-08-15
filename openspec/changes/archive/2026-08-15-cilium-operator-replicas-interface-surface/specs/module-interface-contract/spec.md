## ADDED Requirements

### Requirement: Operator replica count input and provenance output

The module SHALL accept an optional Cilium operator replica count and SHALL
reject a value that is not an integer of at least 1, or that exceeds the number
of declared nodes. The over-count rejection sits on the REJECT side of the
inert-input tier rule rather than the warn side, on three grounds: the declared
node set is not an estimate of the environment but the cluster the module
builds, so the predicate is decidable from the module's own state; the operator's
`podAntiAffinity` is `requiredDuringScheduling` on `kubernetes.io/hostname`, so
the surplus can never place; and the value is baked into a create-only
`inlineManifest`, so the bootstrap that carries it cannot be corrected by a later
apply. Each conjunct SHALL be its own validation block, per the guard-isolation
obligation the module's other cross-variable validations carry.

The module SHALL additionally expose a secret-free plan-time output reporting
the resolved count together with the mechanism that produced it — the explicit
pin, the node-count derivation, or the shipped floor — so an operator debugging
a live Deployment can attribute the number without reading module internals.
This is a different kind of audit surface from the seed markers: those report
what was baked in, this reports which rule decided it.

#### Scenario: A replica count below one or fractional is rejected

- **WHEN** the operator replica count is set to 0, or to a fractional value
- **THEN** variable validation fails, with each conjunct bound by its own
  rejected shape so neither can be relaxed while the other still fails

#### Scenario: A replica count above the declared node count is rejected

- **WHEN** the operator replica count exceeds the number of declared nodes
- **THEN** variable validation fails — rejection rather than a warning,
  because the surplus can never place and the value reaches a create-only
  seed

#### Scenario: A count that cannot reach an operator warns

- **WHEN** the operator replica count is set with Cilium delivery off
- **THEN** the plan succeeds and reports a warning: the input is inert
  rather than wrong, which is the lower tier

#### Scenario: The resolved count reports its origin

- **WHEN** the module plans with Cilium delivered
- **THEN** the audit output carries the resolved count together with one of
  the three origins — pin, node-count derivation, or floor — and its shape
  and value types do not vary with the delivery toggle
