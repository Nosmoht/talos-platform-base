## MODIFIED Requirements

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

Three inputs are in the class, all reaching the `cilium-config` ConfigMap that
the module bakes into a create-only `inlineManifest`. The Cilium agent
metric-delta list and the Hubble metric list are rendered raw and unquoted as
list entries: an entry containing a newline with matching indentation escapes
the surrounding scalar and injects arbitrary ConfigMap keys; an entry
containing a document separator splits the rendered manifest and blanks the
seed-marker output that parses it. The native-routing CIDR is rendered raw as a
scalar value and carries the same newline vector.

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
