## ADDED Requirements

### Requirement: Operator replica count in the closed Cilium object

The closed `substrate.cilium` object SHALL additionally admit
`operator_replicas` (integer, `minimum: 1`). Omitting it derives the count
from the node set; setting it pins the count on both delivery paths.

The `minimum` mirrors the module's own validation so the declarative path
rejects a zero at lint time rather than only at plan time, following the
convention `substrate.cert_approver.replicas` established. The schema does not
mirror the module's node-count bound: the schema validates one document in
isolation and the bound is relational, so that conjunct stays a plan-time
rejection.

#### Scenario: A zero or fractional replica count fails lint

- **WHEN** `substrate.cilium.operator_replicas` is below 1, or not an integer
- **THEN** schema validation reports the violation for that path, with each
  of the two constraints separately observable so neither can be relaxed
  unnoticed
