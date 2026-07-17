## MODIFIED Requirements

### Requirement: Untyped escape hatches and structural secret exclusion

The schema SHALL admit `config_patches`, `controlplane_config_patches`,
`worker_config_patches`, and per-node `config_patches` as arrays of
free-form YAML maps without content validation, SHALL close the `substrate`
section to exactly the `cilium`, `argocd`, and `cert_approver` keys (each a
loosely typed object; `substrate.cert_approver` is itself closed with
`additionalProperties: false` and admits only `provider_regex` (string),
`provider_ip_prefixes` (a string array with `minItems: 1`), and `replicas`
(integer, `minimum: 1`) — a typo'd security-control key fails lint rather
than being silently dropped), and SHALL provide no field for secret material
— neither `sops_age_key` nor `cilium_ipsec_key` has a schema slot (normative:
knowledge/decisions/0007-cluster-yaml-sot.md). `substrate.cert_approver`
tunes the always-on cert-approver seed's SAN-to-node binding and replica
count but cannot disable the seed.

#### Scenario: Mistyped substrate key is rejected

- **WHEN** a `cluster.yaml` declares a `substrate` child key other than
  `cilium`, `argocd`, or `cert_approver`
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
