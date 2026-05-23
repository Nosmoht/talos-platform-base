# Talos Makefile.lib v0.5.1 Release Notes

## Overview

v0.5.1 ships the 5-axis cluster.yaml schema, schematic cache builder, and
argv-print validation tool alongside the existing legacy gen-configs path. This
is a **non-breaking, dual-path release**: the legacy pattern rules remain
unchanged. Consumers can pull in v0.5.1 to gain schema validation and
argv-print inspection without switching the production gen-configs path.

## What is Shipped

- `talos/schemas/cluster.schema.json` — 5-axis cluster.yaml JSON Schema
- `talos/Makefile.lib` — `validate-schematics`, `schematics`, `argv-print` targets
- `talos/scripts/argv-print.sh` — emit talosctl gen-config argv for one node
- `talos/scripts/build-schematic-cache.sh` — hash-dedup schematic cache builder
- `talos/scripts/validate-schematics.sh` — cross-reference + binding diagnostics
- `talos/scripts/test-bit-identity.sh` — argv comparison against legacy dump files
- `.github/workflows/oci-publish.yml` — OCI artifact publish on tag push

## Scope-Out: v0.5.1 is argv-print + validation ONLY

The following capabilities are **explicitly deferred to Phase 3**:

### CRIT-1 (deferred): Placeholder resolution not implemented

`argv-print.sh` emits `@nodes/<name>.yaml` verbatim. Placeholders such as
`${NIC_NAME}` in KubeVirt patch files are NOT substituted in the argv output.
Using `make gen-configs` on the new path with placeholder-bearing capabilities
(e.g. `kubevirt-networking`) produces unsubstituted values in the generated
machine config.

**Mitigation**: The validation script (`validate-schematics`) correctly detects
missing `placeholder_bindings` and errors out. The argv output should not be
passed to `talosctl gen config` until Phase 3 implements the substitution
tmpdir mechanism.

**Phase 3 prerequisite**: implement per-invocation tmpdir + envsubst render step
in a new `gen-configs-new` target before cutting over production.

### CRIT-4 (deferred): NTP not configured on new path

`patches/common.yaml` has no `machine.time.servers` block. The legacy gen-configs
path injects NTP via a rendered `_out/<overlay>/cluster.yaml` patch (which reads
`cluster.ntp_server` from the consumer cluster's `cluster.yaml` via envsubst).

On the new 5-axis path this rendered intermediate is eliminated. If a consumer
runs `make gen-configs` via Makefile.lib before Phase 3, nodes get no NTP
source → clock drift → etcd peer cert renewal fails → cluster outage class.

**Mitigation**: the `talos/AGENTS.md` §v0.5.1 Dual-Path Scope section marks
new-path gen-configs as NOT safe for production use, with both blockers listed.

**Phase 3 prerequisite**: update `patches/common.yaml` to include a
`machine.time.servers` block reading `cluster.ntp_server` from the 5-axis
cluster.yaml (via Make variable interpolation or a dedicated render step).

## Safe Operations at v0.5.1

| Operation | Safe? | Notes |
|---|---|---|
| `make argv-print` | YES | Inspection / bit-identity diff only |
| `make validate-schematics` | YES | Schema + Layer-C cross-reference validation |
| `make schematics` | YES | Schematic cache refresh (POSTs to factory.talos.dev) |
| `make gen-configs` (new path) | **NO** | Phase 3 blockers above |
| Legacy `make -C talos gen-configs` (consumer Makefile) | YES | Production path unchanged |

## Breaking Changes

None. Legacy pattern rules in `AGENTS.md §Pattern Rules` are unchanged.

## Known Limitations

- `installer-profile` enum in cluster.schema.json is a snapshot; new profiles
  (GCP, Azure, Equinix) require a schema bump. Workaround: extend the enum in
  a consumer-side schema overlay until the base is updated.
- `additionalProperties: true` on node-spec and hardware-platform-spec items;
  typos in optional fields are not caught by schema validation alone.

## Upgrade Path to v0.6.0 (breaking)

v0.6.0 will remove legacy pattern rules and make the 5-axis path the only
supported gen-configs path. Migration requires Phase 3 cut-over in all consumer
cluster repos first. No v0.6.0 tag will be created until Phase 3 is complete
and a 2-week production soak window confirms stability.
