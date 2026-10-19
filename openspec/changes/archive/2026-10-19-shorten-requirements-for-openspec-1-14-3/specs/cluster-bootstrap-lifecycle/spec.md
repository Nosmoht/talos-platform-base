## MODIFIED Requirements

### Requirement: Apply mode per role

The module SHALL expose the apply mode of the machine-configuration apply as two
separate inputs, one per role, so an operator can keep an apply from rebooting the
nodes of one role without affecting the other. The default SHALL be the
provider's own `auto`.

#### Scenario: The default keeps the Day-0 install path intact

- **WHEN** neither apply-mode input is set, on a single-node or a multi-node
  cluster
- **THEN** every node's apply resolves to `auto`, and the Day-0 apply installs and
  reboots as before

#### Scenario: One role is staged for a window

- **WHEN** the worker apply mode is set to a staging mode and the controlplane
  input is left at its default
- **THEN** the worker applies carry the staging mode and the controlplane applies
  carry `auto`, so no controlplane reboot follows from the change

#### Scenario: A staging default would break the Day-0 install

- **WHEN** the apply resource carries the Day-0 apply to maintenance-mode
  nodes, where the apply IS the install
- **THEN** the default stays `auto`, because a staging default would write the
  configuration without installing
- **AND** the bootstrap would then run against a node that never left
  maintenance mode

#### Scenario: A staging mode leaves the reboot to the operator

- **WHEN** a staging mode is set for a role
- **THEN** the module SHALL write the configuration and leave the reboot to
  the operator
- **AND** that reboot is an out-of-band, health-gated step performed one node
  at a time, outside this module
