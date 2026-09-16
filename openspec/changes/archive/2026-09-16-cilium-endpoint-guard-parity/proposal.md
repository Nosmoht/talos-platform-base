## Why

The `cilium_k8s_service_host` guard shipped as a character class: hex digits and
colons with at least two colons. That admits `1:2:3`, `fffff:1:2` and a
nine-group string — none of them an address — and the value is frozen into a
create-only machine configuration on the seed path, where a malformed
API-server endpoint is a bootstrap deadlock no later apply repairs. It also
diverged from the JSON Schema mirror in the harmful direction: the schema bounds
group length and count, so the declarative lint layer rejected values the module
accepted.

Deciding the IPv6 half by PARSE closes both. `var.nodes` already does exactly
this, so the module gains no new idiom, and the normalization the parse performs
is what makes the accepted set unambiguous.

The parse cannot be mirrored by a JSON Schema pattern, so the mirror requirement
has to say what the schema actually is: a conservative pre-filter that never
rejects a plannable value, with the module as the authoritative gate.

## What Changes

- `cilium_k8s_service_host` accepts an IPv6 literal only in the form the parser
  prints back. A non-canonical spelling (`2001:0db8::1`) or an IPv4-embedded one
  (`::ffff:192.0.2.1`) is rejected and must be written normalized.
- `schemas/cluster.schema.json` keeps its host pattern as a pre-filter; the
  requirement no longer claims it is a complete mirror.
- No change to the accepted set for DNS names or IPv4 literals, and none to the
  port guard.

## Impact

- Affected specs: `cluster-yaml-sot`, `module-interface-contract`
- Affected code: `tofu/modules/talos-cluster/variables.tf`
- A consumer who wrote a non-canonical IPv6 endpoint gets a plan-time rejection
  naming the normalized form to use. The default path (`localhost`) is
  unaffected.
