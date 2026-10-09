# Constrain the talos provider to a range

## Why

The requirement "Version constraints and backend agnosticism" mandates an exact
stable `siderolabs/talos` pin, `0.12.0`. ADR-0029
(`knowledge/decisions/0029-public-api-and-major-rule.md`, §Provider
constraints) allows an exact pin only when the machinery the module needs
exists only in a prerelease. No prerelease-only machinery requires `0.12.0`,
so the pin does not conform. Its effect is that every later provider release
needs a moved pin, and a moved pin excludes a version the previous release
admitted, which ADR-0029 classifies as MAJOR.

## What Changes

- `module-interface-contract`: "Version constraints and backend agnosticism"
  constrains `siderolabs/talos` to `>= 0.12.0, < 0.13.0-0`. The floor is the
  oldest version the module's code needs; the `-0` upper bound excludes the
  0.13 line, its prereleases included. The exact-pin sentence goes. The
  committed module lock selects the floor, and the base's gates run against it;
  later admitted 0.12.x releases are not exercised by base CI. The scenarios
  follow: a root range admitting a version in the range resolves; a root
  constraint excluding every admitted version fails; a root exact-pinning a
  0.13.0 prerelease fails; a lock below the floor needs a refresh; a lock at
  0.12.0 initializes without one.

The admitted set today is `{0.12.0}`, the same as before, so no consumer root
that initialized before fails now.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `module-interface-contract`

## Impact

- Code: `tofu/modules/talos-cluster/versions.tf`, its lock, the example root,
  the provider probe fixture and gate, the PKI microtest, the module README.
