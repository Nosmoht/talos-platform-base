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
`values_override`) plus six observability + self-management keys:
`agent_metrics` and `operator_metrics` (booleans, default `false`),
`hubble_enabled` (boolean, default `false`), `hubble_metrics` (a string
array, default `[]`), `self_management` (boolean, default `false`), and
`self_management_project` (string, default `"default"`) — a typo'd key in
any of these three closed substrate objects fails lint rather than being
silently dropped.

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

#### Scenario: Empty cert-approver IP-prefix list is rejected

- **WHEN** a `cluster.yaml` sets `substrate.cert_approver.provider_ip_prefixes`
  to an empty array
- **THEN** schema validation fails on the `minItems: 1` constraint — an empty
  set would deny every kubelet-serving CSR carrying an IP SAN

#### Scenario: Free-form patch content passes the schema

- **WHEN** a `config_patches` entry carries an arbitrary YAML map
- **THEN** schema validation accepts it without inspecting the patch content
