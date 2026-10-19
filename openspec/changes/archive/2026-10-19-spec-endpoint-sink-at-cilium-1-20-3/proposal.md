# Name Cilium 1.20.3 as the measured endpoint sink

## Why

"API-server endpoint guards are well-formedness guards" names chart 1.20.0
as the measured render of the API-server endpoint. The seeded chart is
1.20.3 since #319.

## What Changes

- `module-interface-contract`: the requirement names chart 1.20.3. A render
  of 1.20.3 still places `cilium_k8s_service_host` and
  `cilium_k8s_service_port` only into quoted `KUBERNETES_SERVICE_HOST` /
  `KUBERNETES_SERVICE_PORT` env values, so the requirement holds unchanged.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `module-interface-contract`

## Impact

- Spec only; no code change.
