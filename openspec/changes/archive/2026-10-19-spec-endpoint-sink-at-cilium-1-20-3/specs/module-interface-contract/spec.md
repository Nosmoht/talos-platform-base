## MODIFIED Requirements

### Requirement: API-server endpoint guards are well-formedness guards

The `cilium_k8s_service_host` and `cilium_k8s_service_port` guards SHALL be
treated as well-formedness rather than injection closure: the measured sink is
not the one the raw-render class rule below covers — chart 1.20.3 renders both
into the containers' `KUBERNETES_SERVICE_HOST` / `_PORT` env vars, QUOTED, so
neither can inject a sibling key.

#### Scenario: A malformed endpoint would deadlock bootstrap

- **WHEN** a malformed endpoint reaches the seed path
- **THEN** the render is frozen into a create-only machine configuration, so
  it is a bootstrap deadlock no later apply repairs — which is why the plan
  rejects it
