## MODIFIED Requirements

### Requirement: Per-node configuration apply

The controlplane document carries every `inlineManifests` seed at once, so the
module SHALL reject an oversized controlplane payload at PLAN time rather than
letting it fail at apply against real hardware. The bound SHALL be expressed
against a ceiling traceable to a Talos source — the `ApplyConfiguration` message
limit — and SHALL be evaluated over inputs that are known on a first plan, so the
check cannot silently defer to apply. Its failure SHALL name the measured size,
the ceiling, and which substrate seeds are enabled, so the operator can act
without re-deriving the payload. No permanent test binds the ceiling: a synthetic
payload at that scale is impractical to commit, so the binding is a documented
re-runnable procedure (lower the ceiling constant, run the module's test target).

#### Scenario: An oversized controlplane payload fails the plan

- **WHEN** the summed controlplane machine-config patches exceed the module's
  payload ceiling
- **THEN** the plan fails with an error naming the measured byte count, the
  ceiling, and the enabled seeds — the apply is never attempted
