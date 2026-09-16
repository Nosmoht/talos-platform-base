## MODIFIED Requirements

### Requirement: Cilium self-management guard validations

The module SHALL reject at plan time, via separate cross-variable
`validation` blocks on `cilium_self_management`: (1) enabling it while
`deploy_argocd` is false or `deploy_cilium` is false — self-management
hands the Day-2 config off from the module-delivered Cilium seed to the
consumer's ArgoCD, so both must be present; and (2) enabling it with a
non-empty `cilium_values_override` and no
`cilium_self_management_values_source` — without a values source the emitted
Application is single-source and its `valuesObject` carries no override term
(see `cilium-cni-delivery`), so a seed-active datapath override would be
silently dropped on ArgoCD adoption.

The module SHALL further reject, via separate `validation` blocks on
`cilium_self_management_values_source`: a values source missing any of
`repo_url`, `revision` or `values_path`; a `values_path` or `override_path`
that is absolute or contains a `..` segment, because both are interpolated
into a `$values/<path>` reference the repo-server resolves against the ref
source's checkout root and a malformed one stops all Cilium reconciliation
with no plan-time signal; and a missing `override_path` while
`cilium_values_override` is non-empty, which is the same silent drop one layer
down.

Every guard SHALL remain its own `validation` block rather than being combined
into one `condition`, so each is independently exercisable by a dedicated
`expect_failures` test leg — an `expect_failures` check proves only that SOME
validation on the named variable fired, so a merged condition would leave half
a predicate vacuously green.

#### Scenario: Self-management without ArgoCD or Cilium is rejected

- **WHEN** `cilium_self_management = true` and either `deploy_argocd` or
  `deploy_cilium` is `false`
- **THEN** variable validation fails with an error naming the missing
  prerequisite

#### Scenario: Self-management with an active override is rejected

- **WHEN** `cilium_self_management = true`, `cilium_values_override` is
  non-empty, and `cilium_self_management_values_source` is unset
- **THEN** variable validation fails with an error directing the caller to
  configure the values source the emitted Application would read the override
  from

#### Scenario: An unresolvable values path is rejected

- **WHEN** `cilium_self_management_values_source` carries an empty
  `values_path`, an absolute path, or a path containing a `..` segment
- **THEN** variable validation fails, rather than emitting an Application
  whose `$values/` reference the repo-server cannot resolve

#### Scenario: An override with nowhere to be read from is rejected

- **WHEN** `cilium_self_management_values_source` is set with an empty
  `override_path` while `cilium_values_override` is non-empty
- **THEN** variable validation fails, because the emitted Application would
  otherwise render from the module-set layer alone

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

The single-source shape SHALL be unchanged from the shape that preceded the
values-source input, and that promise SHALL be bound by a whole-document
comparison against a golden captured from the preceding revision, since presence
and absence assertions cannot observe a field added, renamed or reordered
elsewhere in the manifest.

#### Scenario: Output is empty by default

- **WHEN** `cilium_self_management` is left at its default (`false`)
- **THEN** `cilium_self_management_app` is the empty string

#### Scenario: Output never renders empty while the toggle is on

- **WHEN** `cilium_self_management = true`
- **THEN** `cilium_self_management_app` is non-empty, or the plan fails on
  the output's precondition rather than emitting a hollow Application

#### Scenario: The single-source manifest is byte-identical to the previous release

- **WHEN** `cilium_self_management_values_source` is left unset
- **THEN** the emitted Application is byte-for-byte the document the preceding
  revision emitted for the same inputs, so the values-source input moves nothing
  for a consumer who does not opt in

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
literal, or an UNBRACKETED IPv6 literal — no scheme, no `:port`, no
whitespace, no brackets —
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

### Requirement: Free-form values reaching the machine config are format-validated

A typed input whose value is rendered verbatim into a resource that becomes
part of the controlplane machine configuration SHALL constrain its accepted
character set by variable `validation`, and the module's test suite SHALL
carry a rejection leg per corruption vector plus a negative-space control
proving the documented form is still accepted. The obligation is on the input
CLASS, not on individual inputs: every sibling reaching the same rendered
document carries it, or the guard documents a boundary it does not hold.

The rule's FORM follows the value space, in three shapes. Where the documented
form is a narrow token, an allowlist is correct. Where legitimate values carry
structured punctuation — Hubble's context syntax uses colons, semicolons and
equals signs — an allowlist would encode a grammar the module does not own and
would break on the next upstream option; there the rule SHALL instead exclude
the measured corruption vectors, and the negative-space control SHALL exercise
the documented structured form so a later copy-paste of the wrong guard shape
fails loudly. Where the value space is a COMPUTABLE TYPE, the rule SHALL be a
semantic predicate over that type rather than a lexical rule: it admits exactly
the shape the input is for, so it rejects every corruption vector without
enumerating one, and the test suite SHALL carry a leg that a lexical guard
would pass so the distinction cannot silently degrade.

The schema SHALL mirror each such guard so the declarative path rejects a
corrupting entry at lint time, and the mirror SHALL account for regex-engine
divergence between the two validators rather than copying the expression
verbatim. Where the module's guard is a semantic predicate the mirror SHALL
constrain the value's SHAPE only, leaving the precise verdict to the module.

Five inputs are in the class, all reaching the `cilium-config` ConfigMap that
the module bakes into a create-only `inlineManifest`. The Cilium agent
metric-delta list and the Hubble metric list are rendered raw and unquoted as
list entries: an entry containing a newline with matching indentation escapes
the surrounding scalar and injects arbitrary ConfigMap keys; an entry
containing a document separator splits the rendered manifest and blanks the
seed-marker output that parses it. The native-routing CIDR is rendered raw as a
scalar value and carries the same newline vector, and so do
`cilium_k8s_service_host` and `cilium_k8s_service_port` — the API-server
endpoint the kube-proxy replacement needs, whose guards are stated with the
rest of the Cilium input validation above and whose form is an allowlist,
because a bare host and a decimal port are narrow tokens rather than a
structured grammar the module does not own.

#### Scenario: A corrupting entry is rejected at plan time

- **WHEN** an entry contains an embedded newline, a document separator, or
  omits the required add/remove prefix
- **THEN** the plan fails at the variable, naming the offending value

#### Scenario: The documented form is not rejected

- **WHEN** every entry is a well-formed add or remove of a metric name
- **THEN** the plan succeeds and the list reaches the computed values layer
  intact

#### Scenario: A malformed native-routing CIDR is rejected at plan time

- **WHEN** the native-routing CIDR is neither empty nor a well-formed CIDR —
  whether because it carries an embedded newline or because it is an address
  with no prefix length, which a lexical guard would accept
- **THEN** the plan fails at the variable

#### Scenario: Both documented native-routing forms are accepted

- **WHEN** the native-routing CIDR is a well-formed CIDR, or is empty
- **THEN** the plan succeeds, and the empty form keeps deriving the value from
  the first IPv4 pod CIDR entry
