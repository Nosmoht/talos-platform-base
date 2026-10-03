# Native Talos 1.14 support

## Why

The current beta provider and legacy module patches generate invalid native
1.14 configurations. Talos 1.14.2 validation reproduces install, kubelet,
network, proxy and scheduling conflicts. The shared base must support new
1.14 clusters while preserving existing consumers' bootstrap schema pins.

## What Changes

- Pin signed stable provider 0.12.0 and refresh its platform checksums.
- Select native documents by schema version while preserving patch precedence.
- Update examples, validation gates and consumer migration guidance.

## Capabilities

### Modified Capabilities

- `module-interface-contract`: stable provider constraint.
- `cluster-bootstrap-lifecycle`: version-compatible bootstrap configuration.
- `machine-config-generation`: native patch formats and caller responsibilities.
- `hardware-capability-composition`: native hardware patch sinks.
- `cluster-yaml-sot`: native-version example.

## Non-goals

Automatic consumer rollouts, resource migration to talos_machine, live-cluster
verification, or changing an existing cluster's schema pin.

## Impact

MAJOR base release; existing 1.14-schema consumers must migrate caller patches.
1.13-schema consumers keep their existing patch format.
