---
sources:
  primary:
    - schemas/cluster.schema.json
    - scripts/lint-cluster-yaml.sh
references:
  - knowledge/decisions/0007-cluster-yaml-sot.md
---

# cluster-yaml-sot

## Purpose

Define the contract a consumer's declarative `cluster.yaml` must satisfy.
`cluster.yaml` is the human-edited cluster Source-of-Truth — identity,
versions, endpoint, network, nodes, images, composite hardware capabilities,
machine-config patches, and substrate toggles — which the consumer's thin
OpenTofu root maps onto the `tofu/modules/talos-cluster` typed interface
(normative: knowledge/decisions/0007-cluster-yaml-sot.md). The shape is
enforced by `schemas/cluster.schema.json` (JSON Schema draft 2020-12) through
the `scripts/lint-cluster-yaml.sh` gate. The base ships only
`cluster.yaml.example`; a committed `cluster.yaml` exists solely in consumer
repos.

## Requirements

### Requirement: Closed top-level document shape

The schema SHALL require the top-level sections `cluster`, `repo`, `talos`,
`kubernetes`, `images`, and `nodes`, SHALL additionally admit only
`hardware-capabilities`, `config_patches`, `controlplane_config_patches`,
`worker_config_patches`, and `substrate`, and SHALL reject any other
top-level key.

#### Scenario: Unknown top-level key is rejected

- **WHEN** a `cluster.yaml` carries a top-level key outside the admitted set
- **THEN** schema validation reports the additional property as a violation
  and the lint gate exits non-zero

#### Scenario: Missing required section is rejected

- **WHEN** a `cluster.yaml` omits any of `cluster`, `repo`, `talos`,
  `kubernetes`, `images`, or `nodes`
- **THEN** schema validation reports the missing required section and the
  lint gate exits non-zero

### Requirement: Cluster identity, endpoint, and network shape

The schema SHALL require `cluster.name` (a lowercase RFC-1123 label) and
`cluster.endpoint` (an `https://` URL), and SHALL admit the optional
bootstrap-identity fields `overlay` and `target_revision`, the network
fields `pod_cidr` and `service_cidr` (non-empty string arrays) and
`dual_stack` (boolean), plus `allow_scheduling_on_controlplanes` (boolean).
The `repo` section SHALL require a non-empty `url`.

`overlay` is optional **to the document**, not to every consumer of it: a
cluster driven only through the OpenTofu root never needs one, while the
App-of-Apps bootstrap refuses to render without it
(`argocd-day-zero-bootstrap`, Requirement "Bootstrap-identity subset read from
cluster.yaml"). Schema-conformance is therefore necessary but not sufficient
for a given path — this file's shape is one contract, and what each consumer
demands of it is another.

#### Scenario: Invalid cluster name is rejected

- **WHEN** `cluster.name` contains characters outside the lowercase
  RFC-1123 label alphabet
- **THEN** schema validation fails on the `cluster.name` pattern

#### Scenario: Non-HTTPS endpoint is rejected

- **WHEN** `cluster.endpoint` does not begin with `https://`
- **THEN** schema validation fails on the `cluster.endpoint` pattern

### Requirement: Version pinning

The schema SHALL require `talos.version` and `kubernetes.version` to be
v-prefixed MAJOR.MINOR.PATCH versions with at most a hyphen- or
plus-introduced pre-release/build suffix, and SHALL admit an optional
`talos.install_version` that is either empty (matching `talos.version`)
or the same version form. Unpinned or malformed forms (`latest`, a
missing v-prefix, arbitrary trailing text after the PATCH segment) are
rejected by the fully anchored pattern.

#### Scenario: Unpinned or malformed version string is rejected

- **WHEN** `talos.version` or `kubernetes.version` is not a v-prefixed
  MAJOR.MINOR.PATCH version (for example `latest`, a version missing the
  v-prefix, or a version with trailing text outside a `-`/`+` suffix)
- **THEN** schema validation fails on the version pattern

#### Scenario: Pre-release suffix is accepted

- **WHEN** `talos.version` or `talos.install_version` carries a
  hyphen-introduced pre-release suffix
- **THEN** schema validation accepts the value

### Requirement: Image catalog entries

The schema SHALL require at least one entry under `images`, SHALL require
each entry to declare `cpu_vendor` (one of `intel`, `amd`, `arm`), and SHALL
constrain the optional fields: `architecture` to `amd64` or `arm64`,
`extensions` to a string array, `extra_kernel_args` to a string array, and
`overlay` (the single-board-computer overlay) to an object requiring `name`
and `image` when present. The schema SHALL reject an `extra_kernel_args`
element carrying whitespace, an element whose key begins with `-`, an
element with an empty key, or any element whose key is `debugfs` —
mirroring the module's `var.images` validations for the declarative path.

#### Scenario: Image without cpu_vendor is rejected

- **WHEN** an `images` entry omits `cpu_vendor` or uses a value outside the
  enumerated vendors
- **THEN** schema validation fails on that image entry

#### Scenario: A well-formed extra_kernel_args list passes the lint gate

- **WHEN** an `images` entry's `extra_kernel_args` contains only elements
  with a non-empty key, no leading `-`, no whitespace, and no `debugfs` key
- **THEN** the lint gate accepts the cluster.yaml

#### Scenario: A debugfs-keyed element is rejected by the schema

- **WHEN** an `images` entry's `extra_kernel_args` contains an element whose
  key is `debugfs`, at any value
- **THEN** schema validation fails on that element — the reachability the
  base's `hard-constraints-check.yml` cannot cover for a repo-root or
  consumer `cluster.yaml`

#### Scenario: A whitespace-bearing, removal-spelled, or empty-key element is rejected by the schema

- **WHEN** an `images` entry's `extra_kernel_args` contains an element with
  whitespace, an element whose key begins with `-`, or an empty-key element
- **THEN** schema validation fails on that element

### Requirement: Node entries

The schema SHALL require at least one entry under `nodes` and SHALL require
each node to declare `hostname`, `ip`, `role` (one of `controlplane`,
`worker`), and `image` (documented as a key of the `images` catalog), with
optional `hardware_capabilities` (a string array of capability ids) and
per-node `config_patches`.

#### Scenario: Node with undeclared role is rejected

- **WHEN** a node declares a `role` outside `controlplane` and `worker`, or
  omits any of the four required fields
- **THEN** schema validation fails on that node entry

### Requirement: Composite capability entries

The schema SHALL require each `hardware-capabilities` entry to declare
`emits_label` matching the `platform.io/hardware-capability.` prefix, and
SHALL admit the optional `requires_features` (Layer-C atom ids) and
`provisioning_profiles` (base catalog profile ids) string arrays.

#### Scenario: Capability label outside the reserved namespace is rejected

- **WHEN** a `hardware-capabilities` entry sets `emits_label` to a key
  outside the `platform.io/hardware-capability.` namespace
- **THEN** schema validation fails on the `emits_label` pattern

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

### Requirement: Lint gate behavior

The `scripts/lint-cluster-yaml.sh` gate SHALL validate its target file
(defaulting to `cluster.yaml.example`) against
`schemas/cluster.schema.json` using `check-jsonschema` (with a `uvx`
fallback when the binary is absent), SHALL always pass
`--default-filetype yaml` so a target without a `.yaml` suffix is parsed as
YAML, and SHALL exit `0` on a passing file, `1` on at least one schema
violation, and `2` on an environment or argument error.

#### Scenario: Passing file yields exit 0 with a summary

- **WHEN** the target file satisfies the schema
- **THEN** the script exits `0` and prints an `OK` summary line

#### Scenario: Missing target or validator yields exit 2

- **WHEN** the target file or the schema file does not exist, or neither
  `check-jsonschema` nor `uvx` is on `PATH`
- **THEN** the script exits `2` with an error on stderr
