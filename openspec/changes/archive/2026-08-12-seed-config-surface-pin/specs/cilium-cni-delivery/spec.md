## ADDED Requirements

### Requirement: Seed configuration surface is pinned

The seed bypasses the kustomize/conftest render gate, so a chart bump can move a
datapath- or security-relevant default into the create-only controlplane machine
configuration with nothing failing. The repo SHALL therefore pin the seed's
rendered `cilium-config` surface at two levels: its full KEY SET against a
committed fixture, so a bump that adds or removes any key fails until the fixture
is refreshed deliberately; and the VALUES of a curated set of datapath- and
security-relevant keys, because a key set alone cannot catch a default that
changed under an unchanged key. A refresh SHALL be a deliberate act that answers
the consumer-facing question in `UPGRADING.md`, never a silent regeneration.

The curated value set is intentionally open: it starts from the keys whose flip
would break the cluster silently or widen its exposure, and grows as bumps reveal
more. Its purpose is not exhaustive coverage but to make the class of regression
visible — the Cilium 1.20 bump moved `bpf-lb-algorithm-annotation` from `"false"`
to `"true"`, turning a previously inert `service.cilium.io/lb-algorithm` Service
annotation live, and nothing in the suite noticed.

#### Scenario: A chart bump that changes the seed's config surface fails the suite

- **WHEN** the pinned chart renders a `cilium-config` whose key set differs from
  the committed fixture, or whose value for a curated key differs from its pin
- **THEN** the module's test target fails, naming the divergence, rather than
  freezing the new default into the machine configuration unnoticed
