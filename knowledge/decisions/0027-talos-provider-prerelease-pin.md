---
type: decision
title: "ADR: The talos provider is pinned exactly to the 0.12.0-beta.0 prerelease"
description: "The module drops its >= 0.7.0, < 1.0.0 provider range for an exact pin on 0.12.0-beta.0, the only release bundling the Talos 1.14 machinery, because a range never selects a prerelease — closing the 1.14 document gap at the cost of shipping a prerelease every consumer inherits."
status: stable
id: base:talos-provider-prerelease-pin
decided: "2026-09-05T00:00:00Z"
deciders:
  - maintainer
consulted: []
informed: []
supersedes: []
superseded_by: []
related:
  - /decisions/0006-opentofu-cluster-lifecycle.md
  - /decisions/0026-machine-config-apply-mode.md
tags: [adr, talos-cluster, provider, talos-1-14, version-pin]
---

# ADR: The talos provider is pinned exactly to the 0.12.0-beta.0 prerelease

## Context and Problem Statement

Talos 1.14.0 reached general availability on 2026-09-03 and moved most of the
v1alpha1 machine-config surface into dedicated document kinds, adding
`SecurityProfileConfig` and `FilesystemTrimConfig` to what it generates for
every new cluster. The `siderolabs/talos` provider decodes every
`config_patches` entry against its OWN bundled Talos machinery before
rendering, so the module's four opaque patch lists reach the provider's
document surface and not Talos'. On the previously declared range the module
resolved provider `0.11.0`, whose machinery predates 1.14: a cluster
bootstrapped through this module at a 1.14 pin ran without workload isolation
and without filesystem trim, with no patch able to add either — worse off than
one from `talosctl gen config`.

Only the 0.12 line bundles the 1.14 machinery, and that line has no final
release: the registry's newest `siderolabs/talos` version is `0.12.0-beta.0`
(read 2026-09-05). OpenTofu never selects a prerelease from a range, so the
declared `>= 0.7.0, < 1.0.0` resolved to `0.11.0` no matter how the bound was
widened. Issue #252 recorded the blocker as a signature failure
("the provider is not signed with a valid signing key"); that no longer
reproduces — `tofu init` installs `0.12.0-beta.0` signed, key ID
`3A983D7A800C63E0` (measured 2026-09-05). The remaining blocker was the range
semantics alone.

## Decision Drivers

- The escape hatch the module advertises — arbitrary machine-config patches —
  was bounded by a provider version no consumer input mentions.
- The 1.14 default gap is a security posture gap, not a feature gap. Talos'
  own reference for `SecurityProfileConfig` states that `talosctl gen config`
  emits the document with `workloadIsolation: true` for 1.14+, and that clusters
  without the document "keep the old (non-isolated) behavior unless it is added"
  — so a cluster bootstrapped here at a 1.14 pin was not isolated, and no patch
  could add the document.
- Three issues share this release as their blocker: #252 (this gap), #146 (the
  0.11.0 inconsistent-final-plan bug on migration applies) and #129 (the
  `talos_machine` resource for native in-place upgrades).

## Considered Options

1. Keep the range and wait for a final 0.12.0.
2. Pin exactly to `0.12.0-beta.0`.
3. Widen the range so it admits the prerelease.

## Decision Outcome

Chosen option: **an exact pin on `0.12.0-beta.0`**, because it is the only
constraint that resolves to machinery a 1.14 cluster's own defaults are
expressible in, and its cost is bounded: consumer roots keep resolving, and the
one spelling that does not (a different exact pin) fails at `tofu init` rather
than at runtime.

Option 3 is not expressible: an OpenTofu version constraint matches a
prerelease only through an exact `=` on that exact version, so there is no
range spelling that admits `0.12.0-beta.0` and no way to keep a range while
reaching the 1.14 machinery.

### Consequences

- Positive: the 1.14 document kinds are reachable through `config_patches`, by
  value and not merely by kind — `SecurityProfileConfig.workloadIsolation` and
  `KubeNodeConfig.labels` both reach the rendered configuration
  (`scripts/check-provider-document-kinds.sh` cases B and C).
- Positive: a 1.14 pin now generates `SecurityProfileConfig` and
  `FilesystemTrimConfig`, so the two absent defaults are present.
- Consumer impact, measured rather than inferred: a root declaring a version
  RANGE still resolves — the exact pin wins the intersection and installs
  `0.12.0-beta.0` (checked with `>= 0.7.0, < 1.0.0`, `~> 0.11.0` and even
  `< 0.12.0`, since a prerelease sorts below the release of the same number), as
  does a root with no `version` key or no talos entry. Two spellings do fail: a
  constraint that EXCLUDES the version — a different exact pin (`0.11.0`) or a
  lower bound above it (`>= 0.12.0`) — and a plain `tofu init` against a lock
  still recording `0.11.0`, which needs `tofu init -upgrade`. The release is
  still MAJOR, but for the behaviour below rather than for a broken `tofu init`.
- Negative, and the reason for the MAJOR: every consumer inherits a prerelease
  provider whether or not their root names it, and one rendered value changes on
  the 1.13 line as well. The provider's DEFAULT `machine.install.image` moved
  from `ghcr.io/siderolabs/installer:v1.13.0` to a
  `factory.talos.dev/metal-installer/…:v1.14.0-rc.2` URL; a byte-diff of a
  rendered `v1.13.9` configuration across the two providers, same machine
  secrets, shows that line and nothing else. The module overrides it per node
  from the Image Factory, and those per-node installer URLs were compared across
  both providers and are identical — same schematic IDs, same tag — so no node
  re-images. What does change is `machine_configuration_input` on every
  `talos_machine_configuration_apply`, so every consumer's first plan updates
  every node, at the `auto` apply-mode default.
- Negative: an exact pin is version-deterministic, not artifact-deterministic. A
  prerelease can be withdrawn upstream, and the former range had `0.11.0` to fall
  back to while this has nothing — a fresh `tofu init` would fail for every
  consumer and for this repo's own required CI, and committing a lock does not
  change that — a lock records checksums, it does not host bytes. What the
  committed module `.terraform.lock.hcl` (un-ignored for this one path) does
  cover is the adjacent threat: bytes re-published under the same version are
  then a visible checksum diff rather than a silent substitution. It binds this
  repo's own fences; it does not reach consumers, who are told to commit their
  own, and `examples/complete/` has none.
- Negative: the pin move is now a recurring consumer-visible event. Replacing
  this beta with the final `0.12.0` is another provider change every consumer
  inherits, and the fence's expectations were calibrated against `v1.14.0-rc.2`
  machinery rather than 1.14.0 GA, so that swap is a measured change, not a
  routine bump.
- Negative: the base's production provider pin is a prerelease, and its bundled
  machinery is `v1.14.0-rc.2` rather than 1.14.0 GA — visible in the installer
  image tag of the `UnattendedInstallConfig` it generates.
- Negative: at a 1.14 pin the provider also generates an
  `UnattendedInstallConfig` from its own defaults — a `/dev/sda` disk selector
  and that rc.2 installer image — and it does NOT follow the `machine.install`
  patch the module writes. Two install descriptions that disagree is why the
  examples and fixtures stay on 1.13.9 here; moving them is #252's remaining
  acceptance criterion, not this decision.
- Negative: reachability is no longer bounded in the safe direction either. At
  a 1.13.9 pin the provider now accepts and renders a `SecurityProfileConfig`
  patch, producing a document a 1.13 node does not know.
- Follow-up: replace the pin with the final `0.12.0` when it ships, and reopen
  #146 and #129, whose blocker this release also is.

## Pros and Cons of the Options

### Option 1 — keep the range, wait for a final 0.12.0

- Pro: no prerelease in the consumer-inherited pin, and no breaking change.
- Con: the wait is unbounded and upstream-owned; the 1.14 gap stays open
  meanwhile, and it is the one gap that makes a 1.14 cluster from this module
  strictly worse than one from `talosctl gen config`.
- Con: leaves #146's known plan bug in the resolved provider.

### Option 2 — exact pin on `0.12.0-beta.0`

- Pro: the only constraint that reaches the 1.14 machinery.
- Pro: an exact pin makes the resolved VERSION deterministic without relying on
  a lock file to decide it. Artifact determinism still needs the lock, which is
  why this change commits one.
- Con: prerelease semantics — a beta is the base's production pin, inherited by
  every consumer.
- Con: every consumer inherits the prerelease, one rendered value changes on the
  1.13 line, and a withdrawn upstream artifact has no fallback — the three
  Consequences above.

### Option 3 — widen the range to admit the prerelease

- Con: not expressible. A prerelease satisfies a constraint only under an exact
  `=` match, so no widening of `>= 0.7.0, < 1.0.0` selects it.

## Validation

`scripts/check-provider-document-kinds.sh` (`task tofu:check:provider-document-kinds`,
inside `tofu:ci`) is the oracle, and it was rewritten with this decision: pin
parity across the five sites carrying the version, the patch path, the two 1.14
kinds asserted by rendered value, an invented kind that must still be refused,
the 1.14 defaults asserted by VALUE (`workloadIsolation: true`, a 168h trim
interval) and absent at the 1.13.9 pin, the install-document conflict with a
positive control that the `machine.install` patch itself still lands, and the
remedy the README prescribes for that conflict.
`scripts/check-provider-document-kinds-bites.sh`
(`task tofu:check:provider-document-kinds-bites`, run ahead of the fence in
`tofu:ci`) mutates a copy of the fence per expectation and requires that
expectation's own message. It binds every assertion it can falsify — fourteen —
and deliberately not the branches that fire only on different PROVIDER behaviour
(each case's rejection branch, the render-failure branches), which no
expectation-level mutation can reach. Two assertions are deliberate expiry alarms: the 1.14
documents must not reach the 1.13.9 pin the examples carry, and the generated
install document must keep ignoring `machine.install`.

## Links

- [issue #252](https://github.com/Nosmoht/talos-platform-base/issues/252) — the
  1.14 document surface, and the remaining pin move
- [issue #146](https://github.com/Nosmoht/talos-platform-base/issues/146) — the
  0.11.0 inconsistent-final-plan bug
- [issue #129](https://github.com/Nosmoht/talos-platform-base/issues/129) —
  native in-place upgrade via `talos_machine`
- [ADR-0026](0026-machine-config-apply-mode.md) — the apply-mode surface of the
  same provider
