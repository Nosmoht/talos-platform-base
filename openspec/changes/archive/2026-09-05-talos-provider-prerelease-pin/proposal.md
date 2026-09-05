## Why

The module's `>= 0.7.0, < 1.0.0` provider range resolved to `siderolabs/talos`
`0.11.0`, whose bundled Talos machinery predates 1.14. Because the provider
decodes every `config_patches` entry against that machinery, none of the Talos
1.14 document kinds was reachable through the module's four opaque patch lists,
and a cluster bootstrapped at a 1.14 pin ran without the `SecurityProfileConfig`
and `FilesystemTrimConfig` documents Talos 1.14 generates for every new cluster
— with no way to opt in. Only the 0.12 line bundles the 1.14 machinery, it has
no final release, and OpenTofu never selects a prerelease from a range.

## What Changes

- Pin `siderolabs/talos` exactly to `0.12.0-beta.0` in the module, the probe
  fixture and the example root, replacing the range.
- Restate the apply-mode value-set requirement on the reason that survives an
  exact pin: the pinned provider offers `staged_if_needing_reboot` but degrades
  it to `auto` on Talos 1.14+.
- Rewrite `scripts/check-provider-document-kinds.sh` for the moved boundary:
  acceptance asserted by rendered value, one invented kind that must still be
  refused, and two expiry alarms.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `module-interface-contract`: the provider constraint is an exact prerelease
  pin that wins the intersection with a consumer root's own constraint, and the
  apply-mode value set is justified by the pinned provider's behaviour rather
  than by a range's floor.

## Impact

- Consumer roots keep resolving: measured, a root declaring a range, no
  `version` key, or no talos entry all resolve to the pin. Only a constraint that
  EXCLUDES the prerelease fails (a different exact pin, or a lower bound above
  it), as does a plain `tofu init` against a lock still recording `0.11.0`.
- BREAKING nonetheless: every consumer inherits a prerelease provider, and the
  provider's default `machine.install.image` changes, which updates
  `machine_configuration_input` on every node.
- The base's production provider pin is a prerelease bundling Talos
  `v1.14.0-rc.2`.
- The example and fixture Talos pins stay on 1.13.9; moving them is the
  remaining acceptance criterion of issue #252.
