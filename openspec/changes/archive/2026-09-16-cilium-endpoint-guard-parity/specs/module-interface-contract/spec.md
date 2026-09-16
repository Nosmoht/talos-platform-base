## MODIFIED Requirements

### Requirement: Network and Cilium input validation

The module SHALL reject an empty `pod_cidr` or `service_cidr` list, a
CIDR entry that is not a valid CIDR, a `cilium_routing_mode` outside
`tunnel`/`native`, a `cilium_encryption.type` outside
`none`/`wireguard`/`ipsec`, and a non-empty `cilium_ipsec_key` that does
not begin with a numeric key id.

`cilium_values_override` SHALL be rejected when it is non-empty and does not
decode to a YAML MAPPING — a comment-only document decodes to null and a
list-rooted one to a sequence, and either would reach a Helm values slot as a
non-object — and when its top-level key set names `kubeProxyReplacement`,
`k8sServiceHost` or `k8sServicePort`. Those three are JOINT keys: the module
writes their counterpart into the Talos machine config
(`cluster.proxy.disabled`) or depends on them to reach the API server before
the CNI is up, so setting one half alone yields a cluster with no ClusterIP
datapath and no cluster DNS. The rejection SHALL name the typed inputs that
set both halves together — `cilium_kube_proxy_replacement`,
`cilium_k8s_service_host`, `cilium_k8s_service_port` — which is what makes it
cost no capability. It is a footgun guard and SHALL NOT be documented as a
boundary: the chart's own `extraConfig` passthrough and a caller
`config_patches` entry both reach the same state around it.

`cilium_values_override` SHALL be marked `sensitive`, because Cilium values
legitimately carry key material (IPsec keys, Hubble and clustermesh TLS, BGP
peer passwords) and the string reaches the machine configuration. The
consequence SHALL be documented rather than mitigated: `tofu plan` no longer
shows the override's diff, so a datapath-relevant change to it is invisible in
plan output. Values DERIVED from it that carry no part of it — notably the
boolean "is the override empty", which decides the emitted Application's shape
and is already observable in that manifest — MAY be declassified so the
secret-free outputs stay exportable; the override's CONTENT SHALL NOT be.

`cilium_k8s_service_host` SHALL be constrained to a bare DNS name or IPv4
literal, or an UNBRACKETED IPv6 literal in CANONICAL form — no scheme, no
`:port`, no whitespace, no brackets. The IPv6 half SHALL be decided by a parse
rather than a character class, so a string that merely looks like a literal
("1:2:3", a nine-group string) is rejected; normalization is part of that
decision, so a non-canonical or IPv4-embedded spelling is rejected too, as it
already is for `var.nodes` —
and `cilium_k8s_service_port` to a decimal port in 1-65535, each conjunct in its
OWN validation block so a test binding one cannot pass on the other's rejection.
The measured sink is not the one the raw-render class rule below covers: chart
1.20.0 renders both into the containers' `KUBERNETES_SERVICE_HOST` /
`_PORT` env vars, QUOTED, so neither can inject a sibling key. These guards are
well-formedness rather than injection closure — on the seed path the render is
frozen into a create-only machine configuration, so a malformed endpoint is a
bootstrap deadlock no later apply repairs.

#### Scenario: Invalid CIDR entry is rejected

- **WHEN** a `pod_cidr` or `service_cidr` entry is not parseable as a
  CIDR
- **THEN** variable validation fails with the variable's error message

#### Scenario: An override naming a joint key is rejected

- **WHEN** `cilium_values_override` names `kubeProxyReplacement`,
  `k8sServiceHost` or `k8sServicePort` at its top level
- **THEN** variable validation fails with an error naming the typed input
  that sets both halves, and a key that merely resembles one of the three is
  NOT rejected

#### Scenario: An override that is not a mapping is rejected

- **WHEN** `cilium_values_override` is non-empty and decodes to null or to a
  sequence
- **THEN** variable validation fails on the input rather than on the emitted
  artifact

#### Scenario: A repo URL that is not a resolvable git remote is rejected

- **WHEN** `cilium_self_management_values_source.repo_url` is not one of the git
  remote forms Argo CD resolves (`https://`, `ssh://user@host[:port]/path`,
  `git@host:path`), or carries an embedded PASSWORD — an SSH username is the
  documented form and stays accepted
- **THEN** the plan is rejected — the value becomes `spec.sources[0].repoURL`
  verbatim and decides where a privileged DaemonSet's Helm values are fetched
  from, and a credential there would be committed to git

#### Scenario: One path for both values layers is rejected

- **WHEN** `values_path` and `override_path` name the same file, in the same or
  in an equivalent spelling
- **THEN** the plan is rejected: the two are ordered layers of one Helm merge,
  and the prescribed `local_file` write would overwrite the consumer's override
  with the module-set layer while every other guard — the emptied-override
  warning and the values-digest pair included — stays green

#### Scenario: A malformed API-server endpoint is rejected

- **WHEN** `cilium_k8s_service_host` carries a scheme, an embedded port or a
  newline, or `cilium_k8s_service_port` is non-numeric or out of range
- **THEN** variable validation fails, because the value is rendered raw into
  a ConfigMap baked into a create-only machine configuration
