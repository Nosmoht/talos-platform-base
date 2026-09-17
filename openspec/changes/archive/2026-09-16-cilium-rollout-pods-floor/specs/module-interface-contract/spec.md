## MODIFIED Requirements

### Requirement: Opt-in Cilium self-management output

The module SHALL expose `cilium_self_management_app` — a YAML-encoded
`argoproj.io/v1alpha1` `Application` manifest string — as `""` when
`cilium_self_management = false` (the default), and as the rendered
Application when `true`, with `precondition`s rejecting both an unexpectedly
empty render while the toggle is on and a multi-source render whose first
`valueFiles` entry is not a non-empty `$values/<path>` reference — the
addressing predicate, not a list-length one, since the first entry is appended
unconditionally on that arm and a length check could therefore never fail. The
module SHALL NOT apply this
manifest itself — it is an output only, for the consumer's own GitOps to
commit and reconcile.

With `cilium_self_management_values_source` set, the manifest is no longer the
sole deliverable: the module SHALL additionally expose
`cilium_self_management_values`, the module-set values layer as a YAML
document for the consumer to commit at that source's `values_path`, non-empty
exactly when self-management and a values source are both configured. Neither
output SHALL be marked `sensitive`, and both SHALL be secret-free by
construction — the module SHALL NOT place `cilium_values_override` (which IS
sensitive) into either, referencing it only as a `$values/<path>` string
pointing at a file the consumer authors and commits themselves. Keeping the
override out of the emitted manifest is an integrity property, NOT a
confidentiality one: Argo CD reads that file as a plain Helm values document and
decrypts nothing, so the module SHALL document key material at `override_path`
as plaintext in git rather than as protected by the consumer's secret tooling.

The module SHALL additionally expose `cilium_values_override_digest` — the
SHA-256 of `cilium_values_override`, `""` when empty, and NOT `sensitive` — as
the plan-time change detector the input's `sensitive` marking removes.

Configuring or not configuring `cilium_self_management_values_source` SHALL NOT
move the single-source document at one base revision, and that promise SHALL be
bound by a whole-document comparison against a committed golden, since presence
and absence assertions cannot observe a field added, renamed or reordered
elsewhere in the manifest. The golden detects MOVEMENT and certifies no key's
correctness — it reports only that a byte moved, and a deliberate refresh
silences it — so the facts a reader depends on SHALL additionally carry named
per-key assertions that a refresh cannot silence. The promise does not extend across revisions: a
floor or computed-layer change moves this document for every consumer on this
arm, and SHALL be released as a MAJOR with the golden refreshed deliberately.

#### Scenario: Output is empty by default

- **WHEN** `cilium_self_management` is left at its default (`false`)
- **THEN** `cilium_self_management_app` is the empty string

#### Scenario: Output never renders empty while the toggle is on

- **WHEN** `cilium_self_management = true`
- **THEN** `cilium_self_management_app` is non-empty, or the plan fails on
  the output's precondition rather than emitting a hollow Application

#### Scenario: The values-source input moves nothing for a consumer who does not opt in

- **WHEN** `cilium_self_management_values_source` is left unset
- **THEN** the emitted Application is byte-for-byte the golden committed for this
  input set at this revision, so introducing the values-source input moved
  nothing for a consumer who does not configure one

#### Scenario: The override digest tracks a sensitive input

- **WHEN** `cilium_values_override` is non-empty
- **THEN** `cilium_values_override_digest` is its SHA-256, and `""` when the
  input is empty — never the hash of the empty string, so an unset override
  reads as unset

#### Scenario: The values output tracks the emitted shape in both directions

- **WHEN** `cilium_self_management` and `cilium_self_management_values_source`
  are both set
- **THEN** `cilium_self_management_values` is non-empty and carries both the
  floor and the computed layer; and with either unset it is the empty string,
  so a stray file can no more ship than a missing one
