## ADDED Requirements

### Requirement: CoreDNS seed inputs

The substrate delivery group SHALL carry `coredns_node_separation` (bool,
default `false`), `coredns_replicas` (default `2`) and `coredns_image`
(default `registry.k8s.io/coredns/coredns:v1.14.7`, which `null` also
selects). `coredns_replicas` SHALL be an integer of at least `2` and, with the seed on, lower than the
number of declared nodes; `coredns_image` SHALL carry no whitespace.

#### Scenario: Replicas that leave a drained replica nowhere to go

- **WHEN** the seed is on and `coredns_replicas` is not lower than the number
  of declared nodes
- **THEN** the plan fails at the variable

#### Scenario: A single replica is rejected

- **WHEN** `coredns_replicas` is `1`
- **THEN** the plan fails at the variable, whatever the seed toggle

### Requirement: CoreDNS seed audit outputs

The module SHALL expose four secret-free outputs: `coredns_seeded` (the
built-in disable and the seed manifest are in the controlplane patch list),
`coredns_builtin_setting` (`{document, enabled}` of the Talos CoreDNS setting
written, `null` when none), `coredns_seed_objects` (the objects decoded from
the seed manifest, `[]` with the seed off) and `coredns_seed_digest` (the
budget's digest annotation, `null` with the seed off).

#### Scenario: The outputs bind the seed tests

- **WHEN** the CoreDNS seed suite reads the four outputs
- **THEN** the identities, the anti-affinity term, the budget, the Service
  addresses, the Corefile and the recommended labels are asserted from the
  rendered manifest rather than from the module's locals
