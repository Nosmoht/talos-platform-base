# The machine-config apply mode as a per-role input

## Why

`talos_machine_configuration_apply.this` is the module's only apply resource and
is `for_each`'d over the node set with no ordering dependency, so a configuration
change the node cannot adopt immediately reboots every node of that role at once.
That is a whole-role outage primitive on a stateful role, and the sequencing it
needs — apply, reboot one node, wait for health, next — is not expressible in a
declarative parallel apply. The module previously offered no way to keep the apply
from rebooting.

Two contracts widen: the module's typed input surface
(`module-interface-contract`, primary owner of `variables.tf`) and the runtime
apply behaviour (`cluster-bootstrap-lifecycle`, primary owner of `main.tf`).

The behaviour worth recording beyond "an input exists" is the default. The same
resource carries the Day-0 apply to maintenance-mode nodes, where the apply IS
the install, and the provider passes the configured mode straight to
`ApplyConfiguration` in Create as well as Update — so a staging default would
write the Day-0 configuration without installing and the bootstrap would run
against a node that never left maintenance mode. The default is therefore `auto`
by construction, not by preference, and the staging mode is an operator-selected
window.

## What Changes

- `cluster-bootstrap-lifecycle`: a new requirement fixing the two role-scoped
  apply-mode inputs, the `auto` default and its Day-0 rationale, and the
  obligation that a staging mode leaves the reboot to the operator as an
  out-of-band, health-gated per-node step.
- `module-interface-contract`: the two inputs join the typed input surface,
  their closed-set validation becomes its own requirement so an unsupported
  spelling fails in the module at plan time rather than at apply time, and
  `node_apply_mode` joins the audit outputs as the only in-module signal that a
  window is open.
- `cluster-yaml-sot`: the closed `cluster` object gains both keys, so the window
  lives in the committed SoT rather than in a transient apply-time override.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `cluster-bootstrap-lifecycle`
- `module-interface-contract`
- `cluster-yaml-sot`

## Impact

- Specs: `cluster-bootstrap-lifecycle`, `module-interface-contract`, `cluster-yaml-sot`.
- Code: `variables.tf` (two inputs), `nodes.tf` (role routing local), `main.tf`
  (one attribute on the apply resource), `tests/apply-mode.tftest.hcl` (the
  oracle), `Taskfile.yml` (offline test registration), module README.
- Consumers: additive. A consumer that sets neither input keeps the previous
  behaviour exactly.
- Decision record: `knowledge/decisions/0026-machine-config-apply-mode.md`.
