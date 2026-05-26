# Talos library v0.5.4 — schema hygiene release

Two schema-hygiene fixes discovered during the homelab consumer's 5-axis
migration audit (2026-05-23). Both are narrow, reversible, and
**require NO consumer cluster.yaml change at the v0.5.4 bump**.

## F2-B — Consumer-local metadata convention (documentation only)

`cluster.yaml` is the 5-axis Talos cluster contract. Consumer-local
metadata (`repo:`, `kubeconfig:`, etc.) does NOT belong in `cluster.yaml`
and should live in a separate consumer-local file. The top-level
`additionalProperties: true` is preserved for backward compatibility
(tightening is a separate concern), but the convention is now documented
in `talos/AGENTS.md` so new consumers don't follow the audit-flagged
homelab pattern.

**Consumer impact**: zero. Existing consumer cluster.yamls continue to
validate; the convention is documentation-only.

## F21-A — Per-node hardware-capabilities canonical kebab-case (schema-side only in v0.5.4)

The schema previously declared the per-node capability list as
`hardware_capabilities` (snake_case) while the top-level map used
`hardware-capabilities` (kebab-case). v0.5.4 reconciles **at the schema
layer only** by adding kebab-case as the canonical name and marking
snake_case as a deprecated alias. **The Makefile.lib runtime scripts
still read only snake_case during v0.5.4.**

**Schema change** (`$defs.node-spec`):
- `hardware-capabilities` added as canonical property (kebab-case).
- `hardware_capabilities` retained as `deprecated: true` alias.
- `required` array updated: hard `hardware_capabilities` entry replaced
  with an `anyOf` accepting either casing.

**Consumer impact at v0.5.4 bump**: zero. Existing snake_case
cluster.yamls continue to validate AND continue to be read correctly
by all scripts (`argv-print.sh`, `validate-schematics.sh`,
`build-schematic-cache.sh`, `translate-legacy-cluster-yaml.sh`).

### IMPORTANT — Do NOT manually migrate cluster.yamls during v0.5.4

The schema accepts kebab-case in v0.5.4, but the runtime scripts read
only snake_case. Renaming a consumer cluster.yaml to kebab-case while
still on v0.5.4 produces silent zero-capability nodes in `make
argv-print` / `make gen-configs` (the schema validates, but every node
reads as empty).

Consumer migration is gated on v0.6.0, which lands the coordinated
package: script renames (`hardware_capabilities` → kebab-case
canonical with snake fallback) + fixture renames + example file
rename + alias removal. The migration command, pre-bump survey, and
verification commands will ship in `RELEASE-NOTES-v0.6.0.md`.

This v0.5.4 release is intentionally schema-only so that:
- the schema declares the canonical form for new consumers reading
  the schema as authoring documentation,
- existing consumers see no breaking change,
- the v0.6.0 coordinated migration has a single bright line.

## Known limitations (carried)

Same as v0.5.3:
- Capability `patches:` declared on a capability spec are still
  declarative-only (auto-composition post-v0.6.0; see #75).
- `additionalProperties: true` on top-level `cluster.yaml`, `node-spec`,
  and `hardware-platform-spec` items; tightening these is a separate
  concern.

## Upgrade Path

`oras pull ghcr.io/nosmoht/talos-platform-base:v0.5.4` into `vendor/base/`.
**No consumer cluster.yaml change required.** Do NOT run a kebab-case
rename until v0.6.0.
