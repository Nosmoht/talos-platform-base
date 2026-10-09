# Let ADR-0029 classify a Cilium self-management floor change

## Why

Two requirements fix the release class of one change in advance: a floor or
computed-layer change that moves the single-source Cilium self-management
document ships "as a MAJOR release". ADR-0029
(`knowledge/decisions/0029-public-api-and-major-rule.md`, issue #292) now owns
the release classification. It classifies a default change behind an existing
input as MINOR with an `UPGRADING.md` note (row 12), names the single-source
self-management arm as covered by that row although it has no opt-out, and
makes such a change MAJOR only when it breaks a documented supported setup
(row 9). A spec that fixes the class independently would contradict the record
that owns it.

## What Changes

- `cilium-cni-delivery`: in "Opt-in emitted self-management Application for
  Day-2 delivery", the single-source clause states that a floor or
  computed-layer change is consumer-visible on that arm, carries an
  `UPGRADING.md` note and a deliberate golden refresh, and takes its release
  class from ADR-0029.
- `module-interface-contract`: the same correction to the closing clause of
  "Opt-in Cilium self-management output".

Every other sentence and every scenario of both requirements is unchanged. The
"Version constraints and backend agnosticism" requirement is out of scope.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `cilium-cni-delivery`
- `module-interface-contract`

## Impact

- Specs: the two above.
- Code: none. The module's behavior and its golden are unchanged, so there is
  no code to implement.
