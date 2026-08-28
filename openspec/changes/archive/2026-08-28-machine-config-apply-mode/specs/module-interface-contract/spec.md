## ADDED Requirements

### Requirement: Apply-mode input validation

Each apply-mode input SHALL be constrained to the value set supported across the
whole provider range the module declares — not the set the newest provider
accepts — so that neither an unsupported spelling nor a mode newer than a
consumer's in-range provider reaches an apply against a node.

#### Scenario: An out-of-set apply mode is rejected

- **WHEN** either apply-mode input carries a value outside that set — including
  a mode the newest provider accepts but the declared floor does not
- **THEN** the plan fails on that variable's validation, naming the accepted
  values

## MODIFIED Requirements

### Requirement: Grouped typed input surface

The grouped typed input surface gains the machine-config apply mode:
`controlplane_apply_mode` and `worker_apply_mode`, both defaulting to `auto`. The
behaviour they select is specified by the `cluster-bootstrap-lifecycle` spec; this
spec owns only their presence in the typed surface and their validation.

### Requirement: Seed and wiring audit outputs

The audit-output set gains `node_apply_mode`: a per-node map of the apply mode
the last apply was written with. It is the only in-module signal that a role
sits in a staged window — the cluster stays healthy on its previous
configuration and the next plan is clean while it does.

#### Scenario: An open window is attributable per node

- **WHEN** a role's apply mode is set to a staging value and applied
- **THEN** the output reports that mode for every node of that role, and `auto`
  for the nodes of the other role
