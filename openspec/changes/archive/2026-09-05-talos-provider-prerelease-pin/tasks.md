## 1. Provider Pin

- [x] 1.1 Replace the range with `0.12.0-beta.0` in `versions.tf`, the probe
  fixture, and `examples/complete/`; verify `tofu init` installs it signed.
- [x] 1.2 Spell the pin out in the README's example consumer root, and state what
  a consumer root's own constraint actually resolves to — measured per spelling,
  not inferred.

## 2. Boundary Gate

- [x] 2.1 Rewrite `scripts/check-provider-document-kinds.sh` for the new
  boundary; assert the 1.14 kinds by rendered VALUE, since they are generated
  by default and presence would pass on the default alone.
- [x] 2.2 Keep one rejection case on an invented kind, so the gate still
  distinguishes an accepting registry from a decode path that stopped
  validating.
- [x] 2.3 Measure every case red on a mutated expectation and green on the real
  provider.

## 3. Record

- [x] 3.1 ADR-0027 for the pin; addendum on ADR-0026 for the two statements the
  exact pin supersedes.
- [x] 3.2 Rewrite the module README's Talos 1.14 section, including the
  conflicting `UnattendedInstallConfig` a 1.14 pin generates.
- [x] 3.3 CHANGELOG entry stating the bump is MAJOR.
