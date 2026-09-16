---
sources:
  primary:
    - schemas/cluster.schema.json
    - scripts/lint-cluster-yaml.sh
    - scripts/check-shim-key-parity.sh
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

### Requirement: Apply mode in the closed cluster object

The closed `cluster` object SHALL carry `controlplane_apply_mode` and
`worker_apply_mode`, each constrained to the same enum the module's inputs
accept, so the Day-2 window a consumer opens lives in the committed
Source-of-Truth rather than in a transient apply-time override. A window held
only in an override is discharged by the next apply that omits it — which
re-applies still-staged configurations in `auto` mode and reboots exactly the
nodes not yet gated.

#### Scenario: A mode outside the enum is rejected at lint time

- **WHEN** `cluster.worker_apply_mode` carries a value the module does not
  accept — including a mode a newer provider supports but the module's declared
  provider floor does not
- **THEN** the schema lint fails, naming the accepted values

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

`nodes` SHALL be a MAPPING keyed by node name, not a sequence — a node is
declared exactly once, at exactly one place, and the key is the node's name
rather than a field of the entry. The schema SHALL require at least one entry
and SHALL require each node to declare `ip`, `role` (one of `controlplane`,
`worker`) and `image` (documented as a key of the `images` catalog), with
optional `hardware_capabilities` (a string array of capability ids) and
per-node `config_patches`.

The schema SHALL constrain node keys to canonical Kubernetes node names —
lowercase `[a-z0-9-.]`, starting and ending alphanumeric, at most 253
characters. The per-label 63-character bound is not expressible in JSON Schema
without a lookahead and is enforced by the module instead.

#### Scenario: Node with undeclared role is rejected

- **WHEN** a node declares a `role` outside `controlplane` and `worker`, or
  omits any of the three required fields
- **THEN** schema validation fails on that node entry

#### Scenario: Non-canonical node key is rejected

- **WHEN** a node key carries uppercase or an underscore (values Talos itself
  would accept and silently rewrite)
- **THEN** schema validation fails on `nodes`, naming the offending key

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

### Requirement: Operator replica count in the closed Cilium object

The closed `substrate.cilium` object SHALL additionally admit
`operator_replicas` (integer, `minimum: 1`). Omitting it derives the count
from the node set; setting it pins the count on both delivery paths.

The `minimum` mirrors the module's own validation so the declarative path
rejects a zero at lint time rather than only at plan time, following the
convention `substrate.cert_approver.replicas` established. The schema does not
mirror the module's node-count bound: the schema validates one document in
isolation and the bound is relational, so that conjunct stays a plan-time
rejection.

The object SHALL further admit `k8s_service_host` and `k8s_service_port`
(strings, defaulting in the module to Talos KubePrism) — the API-server
endpoint Cilium reaches before the CNI is up. The port pattern SHALL be a
COMPLETE mirror of the module's guard, digit shape and the 1-65535 range both,
since a port range is non-relational and therefore expressible in a
single-document schema. The host pattern SHALL be a CONSERVATIVE PRE-FILTER
instead: it rejects a scheme, a `:port`, whitespace and brackets — brackets
because client-go joins this value with the port through `net.JoinHostPort`,
which brackets a colon-bearing host itself — but it SHALL NOT reject a value the
module accepts. A complete mirror is unavailable here by construction: the
module decides an IPv6 value by PARSING it (the `cidrhost` round trip
`var.nodes` uses), which admits only the canonical spelling and which no JSON
Schema pattern expresses. The module therefore stays the authoritative gate for
that shape, and the schema catches the classes a reader gets wrong at authoring
time. On the seed path the resulting render
is frozen into a create-only machine configuration, so a malformed endpoint is
a bootstrap deadlock rather than a repairable misconfiguration.

The object SHALL further admit `self_management_values_source`, a closed object
whose `values_path` is REQUIRED and whose `repo_url`, `revision` and
`override_path` are optional. It names the git source the emitted Day-2
`Application` reads its two ordered Helm values layers from. `repo_url` and
`revision` are optional in the SCHEMA because the consumer shim defaults them
to this document's own `repo.url` and `cluster.target_revision`: declaring the
consumer's repository twice in one Source-of-Truth would let the two spellings
diverge silently. `values_path` and `override_path` SHALL be constrained to
NORMALIZED repo-root-relative paths — a character allowlist
admitting neither a leading `/` nor whitespace, and no `..`, `.` or empty
segment — mirroring the module's guard. A malformed path stops all Cilium
reconciliation with no plan-time signal, and a non-normalized one ("./x" beside
"x") would additionally let two spellings of ONE file pass the module's
distinctness guard.

Every lint-time rule this requirement adds SHALL be bound red-green by an
offending entry in the negative schema fixture, with its own CI needle — the
convention the kernel-arg and `operator_replicas` rules established — because
`cluster.yaml.example` deliberately leaves these keys commented out and a schema
pattern nothing exercises can be relaxed unnoticed.

Two of the module's guards on this object SHALL remain plan-time-only, and the
reason is structural rather than an omission: `repo_url`'s git-remote-form
allowlist encodes a value space the schema's consumers would have to re-encode,
and the requirement that `values_path` and `override_path` differ is a relation
between fields. The lint-time claim above therefore covers the path and endpoint
patterns only.

#### Scenario: A zero or fractional replica count fails lint

- **WHEN** `substrate.cilium.operator_replicas` is below 1, or not an integer
- **THEN** schema validation reports the violation for that path, with each
  of the two constraints separately observable so neither can be relaxed
  unnoticed

#### Scenario: A malformed values-source path fails lint

- **WHEN** `substrate.cilium.self_management_values_source.values_path` is
  absolute, carries whitespace or a `..` segment, or the object omits
  `values_path` entirely
- **THEN** schema validation reports the violation for that path, so the
  declarative path rejects it at lint time and not only at plan time

#### Scenario: An out-of-range API-server port fails lint

- **WHEN** `substrate.cilium.k8s_service_port` is `"0"`, above 65535, or
  carries a non-digit character
- **THEN** schema validation reports the violation, so a port the module
  rejects at plan time cannot pass the declarative gate

#### Scenario: The shim maps every closed Cilium key

- **WHEN** a key is added to the closed `substrate.cilium` object
- **THEN** the shipped consumer shim reads it, including each nested key of
  `self_management_values_source`, so a consumer writing it cannot pass lint
  and plan while the value silently never reaches the module
