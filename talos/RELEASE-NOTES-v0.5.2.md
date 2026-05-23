# Talos Makefile.lib v0.5.2 Release Notes

## Overview

v0.5.2 closes the two **Phase 3 prerequisite blockers** documented in
[`RELEASE-NOTES-v0.5.1.md`](./RELEASE-NOTES-v0.5.1.md): placeholder
substitution (CRIT-1) and NTP injection on the new path (CRIT-4). With
v0.5.2, `make argv-print` is the source of truth for what `talosctl gen
config` would receive, ready to be piped to the production tool.

Non-breaking. Legacy pattern rules remain untouched and continue to be
the default production path until v0.6.0 (≥2-week soak after Phase 3
homelab cut-over).

## What changed since v0.5.1

- `talos/scripts/resolve-placeholders.sh` (new) — deterministic literal
  substitution of `${NAME}` tokens in patch files. POSIX `sed`-based,
  multi-line values rejected explicitly, no `envsubst` or `eval`.
- `talos/scripts/argv-print.sh` — per-node placeholder bindings are
  collected from each capability's `placeholder_bindings` map, resolved
  against `nodes/<NODE>.yaml`, and applied to patches that reference
  any token. Patches without tokens are emitted byte-identically to the
  legacy path.
- `talos/scripts/argv-print.sh` — when `cluster.ntp_server` is set in
  the consumer's cluster.yaml, a synthetic NTP patch is rendered to
  tmpdir and emitted right after the first `common.yaml` reference in
  the per-role patch list. Matches the legacy intermediate
  `_out/<overlay>/cluster.yaml` patch position semantically.
- `talos/test/cluster.yaml.example` and
  `talos/test/fixtures/{invalid-binding-missing,nodes/missing-binding}.yaml`
   — `placeholder_bindings` field paths are now absolute from the
  `nodes/<n>.yaml` root (`machine.network.bridge.nic`, not
  `network.bridge.nic`). The earlier relative-path convention was a
  v0.5.1 fixture authoring bug that masked the binding-missing
  diagnostic on the positive worker-test case.
- `.ci-oci-tarball-include.txt` and `.ci-oci-tarball-expected.txt` —
  add the new `resolve-placeholders.sh` script.

## Closed in v0.5.2

### CRIT-1 — Placeholder resolution

Resolved. `argv-print.sh` now substitutes any `${[A-Z][A-Z0-9_]*}` token
in a patch file against the per-node bindings table assembled from
capability `placeholder_bindings`. Unresolved tokens cause
`resolve-placeholders.sh` to exit non-zero with a named diagnostic
(reachable also at `validate-schematics`'s `binding-missing` check, which
fires earlier in the pipeline).

Mechanism:

1. argv-print iterates the node's `hardware_capabilities` array.
2. For each capability, reads `placeholder_bindings: { NAME: <yq-path> }`
   from `cluster.yaml`.
3. Looks up the path in `nodes/<NODE>.yaml`. Empty/null values are
   dropped (validate-schematics surfaces them as `binding-missing` FAIL).
4. Writes a flat `NAME<TAB>VALUE` bindings file per node.
5. For each patch in the role's patch list, if the patch file contains
   any `${...}` token, calls `resolve-placeholders.sh patch bindings`
   which writes the substituted patch to tmpdir; argv-print emits
   `--config-patch @<tmp-rendered>`.

Patches without tokens take the verbatim path — no regression.

Security: substitutions are literal (`sed s|...|...|g`), never
`envsubst` or shell evaluation. Multi-line values are rejected. Sed
RHS metachars are escaped.

### CRIT-4 — NTP on new path

Resolved. `argv-print.sh` reads `cluster.ntp_server` (singular,
matching the existing v0.5.1 schema and legacy Makefile convention),
renders a synthetic patch into tmpdir:

```yaml
machine:
  time:
    servers:
      - <cluster.ntp_server value>
```

and emits `--config-patch @<tmpdir>/ntp.yaml` immediately after the
first patch whose basename is `common.yaml` in the role's patch list
(or first, if no `common.yaml` is present). When `cluster.ntp_server`
is unset, no NTP patch is emitted (preserves opt-in semantics for
consumers who manage NTP externally).

The position-after-common heuristic matches the legacy injection
position (`_out/<overlay>/cluster.yaml` came right after
`patches/common.yaml` in legacy ordering).

## Safe Operations at v0.5.2

| Operation | Safe? | Notes |
|---|---|---|
| `make argv-print` | YES | Now includes substituted patches + NTP |
| `make validate-schematics` | YES | Schema + Layer-C + binding-missing |
| `make schematics` | YES | Cache refresh |
| `make gen-configs` (new path) | YES | **Production-safe when consumer cluster.yaml + nodes/<n>.yaml are complete (see Phase 3 Cut-Over Checklist below)** |
| Legacy `make -C talos gen-configs` (consumer wrapper) | YES | Production path unchanged |

## Phase 3 Cut-Over Checklist (consumer-side)

Production cut-over from legacy to new path requires:

1. Every `hardware-capabilities[<cap>]` that uses a placeholder-bearing
   patch declares a `placeholder_bindings` map with absolute field
   paths from the `nodes/<n>.yaml` root.
2. Every node with such a capability has the corresponding field set
   in its `nodes/<NODE>.yaml`.
3. `make validate-schematics` exits 0 with no `binding-missing`
   diagnostics for any node.
4. `make test-bit-identity` exits 0 with **zero** delta against the
   legacy argv-dump baseline for every node.
5. CI runs `make argv-print` for every node nightly during the soak
   window, asserting no schema drift.

Consumer-side Phase 3 work (vendor + thin wrapper + cluster.yaml
authoring) is documented in the talos-platform-base
`.work/p2-talos-oci/phase-3-brief.md`.

## Breaking Changes

None. v0.5.2 is non-breaking — same dual-path discipline as v0.5.1.

## Known Limitations (carried from v0.5.1)

- `additionalProperties: true` on node-spec and hardware-platform-spec
  items; typos in optional fields are not caught by schema alone.
- Capability `patches:` declared on a capability spec are NOT
  auto-composed into the per-node argv; consumers must include each
  capability-patch literally in the relevant `roles[].patches` list.
  Composition automation is post-v0.6.0 work.

## Upgrade Path

`oras pull ghcr.io/nosmoht/talos-platform-base:v0.5.2` into
`vendor/base/` (or wherever the consumer pins it). No consumer
cluster.yaml changes required to drop in v0.5.2; the new behaviors
activate only when `cluster.ntp_server` is set and/or capabilities
declare `placeholder_bindings`.

v0.6.0 (breaking — legacy `node-(gpu|pi)-%` / `worker-kubevirt-%`
pattern rules removed from `talos/Makefile`) remains gated on the
≥2-week soak after Phase 3 homelab cut-over.
