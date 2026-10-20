## MODIFIED Requirements

### Requirement: Untyped escape hatches and structural secret exclusion

The schema SHALL admit `config_patches`, `controlplane_config_patches`,
`worker_config_patches`, and per-node `config_patches` as arrays of
free-form YAML maps without content validation, SHALL close the `substrate`
section to exactly the `cilium`, `argocd`, `cert_approver` and `coredns` keys, and
SHALL provide no field for secret material — neither `sops_age_key` nor
`cilium_ipsec_key` has a schema slot (normative:
knowledge/decisions/0007-cluster-yaml-sot.md).

#### Scenario: Mistyped substrate key is rejected

- **WHEN** a `cluster.yaml` declares a `substrate` child key other than
  `cilium`, `argocd`, `cert_approver` or `coredns`
- **THEN** schema validation reports the additional property instead of the
  key being silently dropped downstream

#### Scenario: Mistyped cilium key is rejected

- **WHEN** a `cluster.yaml` declares a `substrate.cilium` child key outside
  the enumerated seed-configuration and observability/self-management keys
- **THEN** schema validation reports the additional property instead of the
  key being silently dropped downstream

#### Scenario: A closed substrate key the shim never reads fails the gate

- **WHEN** a closed substrate object declares a key that the shipped example
  shim does not read, whether because the schema widened without the shim or
  because the shim's read is misspelled
- **THEN** the repository check fails and names the unmapped key, rather than
  the consumer's declared value silently resolving to the module default

#### Scenario: Empty cert-approver IP-prefix list is rejected

- **WHEN** a `cluster.yaml` sets `substrate.cert_approver.provider_ip_prefixes`
  to an empty array
- **THEN** schema validation fails on the `minItems: 1` constraint — an empty
  set would deny every kubelet-serving CSR carrying an IP SAN

#### Scenario: Free-form patch content passes the schema

- **WHEN** a `config_patches` entry carries an arbitrary YAML map
- **THEN** schema validation accepts it without inspecting the patch content

## ADDED Requirements

### Requirement: Closed CoreDNS substrate object

`substrate.coredns` SHALL be closed (`additionalProperties: false`) and admit
only `node_separation` (boolean), `replicas` (integer, `minimum: 2`) and
`image` (a string without whitespace), mirroring the module's three CoreDNS
seed inputs; the shipped shim SHALL read each key.

#### Scenario: A single CoreDNS replica fails at lint time

- **WHEN** `substrate.coredns.replicas` is `1`
- **THEN** schema validation fails on the `minimum: 2` constraint

#### Scenario: The node-count bound stays a plan-time rejection

- **WHEN** `substrate.coredns.replicas` is not lower than the number of
  declared nodes
- **THEN** the schema does not reject it, because the bound is relational, and
  the module rejects it at plan time
