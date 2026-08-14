## MODIFIED Requirements

### Requirement: Untyped escape hatches and structural secret exclusion

The schema SHALL admit `config_patches`, `controlplane_config_patches`,
`worker_config_patches`, and per-node `config_patches` as arrays of
free-form YAML maps without content validation, SHALL close the `substrate`
section to exactly the `cilium`, `argocd`, and `cert_approver` keys, and
SHALL provide no field for secret material — neither `sops_age_key` nor
`cilium_ipsec_key` has a schema slot (normative:
knowledge/decisions/0007-cluster-yaml-sot.md). `substrate.argocd` stays a
loosely typed object. `substrate.cert_approver` is closed
(`additionalProperties: false`) and admits only `provider_regex` (string),
`provider_ip_prefixes` (a string array with `minItems: 1`), and `replicas`
(integer, `minimum: 1`) — it tunes the always-on cert-approver seed's
SAN-to-node binding and replica count but cannot disable the seed.
`substrate.cilium` is likewise closed (`additionalProperties: false`) and
admits the pre-existing seed-configuration keys (`enabled`, `chart_version`,
`chart_repository`, `routing_mode`, `kube_proxy_replacement`, `gateway_api`,
`gateway_api_crds_url`, `mtu`, `native_routing_cidr`, `encryption`,
`values_override`) plus eight observability + self-management keys:
`agent_metrics` and `operator_metrics` (booleans, default `false`),
`hubble_enabled` (boolean, default `false`), `hubble_metrics` (a string
array, default `[]`, whose entries carry the same raw-render exclusion rule
as `agent_metric_overrides` in a form that admits Hubble's context syntax),
`agent_metric_overrides` (a string array, default `[]`, whose entries the
module additionally format-validates because the chart renders them raw into
the machine configuration),
`hubble_open_metrics` (boolean, default `false`), `self_management`
(boolean, default `false`), and `self_management_project` (string, default
`"default"`) — a typo'd key in any of these three closed substrate objects
fails lint rather than being silently dropped.

`native_routing_cidr` is in the same raw-render class as the two metric lists
and SHALL carry a shape mirror of the module's guard: the CIDR form or the
empty string, with the newline and document-separator exclusion the engine
divergence between the two validators requires.

Adding a key to a closed object is additive for consumers, but reaching the
module still requires the consumer-owned shim to map it: the schema widening
and the shipped example shim SHALL land together, or a consumer writing the
new key passes lint and plan while the value silently never arrives. Because
the shim reads `cluster.yaml` through `try()` — a total function that answers a
mistyped key with the default rather than an error — this obligation SHALL be
mechanically gated rather than left to review: a repository check SHALL assert
that every key of every CLOSED substrate object is read by the shipped shim,
and it SHALL run on a diff that touches the schema alone.

#### Scenario: Mistyped substrate key is rejected

- **WHEN** a `cluster.yaml` declares a `substrate` child key other than
  `cilium`, `argocd`, or `cert_approver`
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
