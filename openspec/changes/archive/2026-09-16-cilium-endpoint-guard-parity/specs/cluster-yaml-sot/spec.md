## MODIFIED Requirements

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
