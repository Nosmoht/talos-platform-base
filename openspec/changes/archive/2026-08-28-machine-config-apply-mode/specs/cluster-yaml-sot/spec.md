## ADDED Requirements

### Requirement: Apply mode in the closed cluster object

The closed `cluster` object SHALL carry `controlplane_apply_mode` and
`worker_apply_mode`, each constrained to the same enum the module's inputs
accept, so the Day-2 window a consumer opens lives in the committed
Source-of-Truth rather than in a transient apply-time override. A window held
only in an override is discharged by the next apply that omits it — which
re-applies still-staged configurations in `auto` mode and reboots exactly the
nodes not yet gated.

#### Scenario: A mode outside the enum is rejected at lint time

- **WHEN** `cluster.worker_apply_mode` carries a value the module does not
  accept — including a mode a newer provider supports but the module's declared
  provider floor does not
- **THEN** the schema lint fails, naming the accepted values
