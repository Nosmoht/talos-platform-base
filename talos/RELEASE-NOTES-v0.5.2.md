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

**Additional hardening in v0.5.2 (R1 team-red findings):**

- The `field_path` value (RHS of `placeholder_bindings`) is
  charset-validated against `^[A-Za-z_][A-Za-z0-9_.-]*$` before yq
  interpolation. This prevents an attacker-controlled cluster.yaml
  from authoring a binding RHS like
  `nic // .cluster.secrets.kubernetes_ca` that would exfiltrate
  sibling fields from `nodes/<n>.yaml` into the substituted patch
  (and into the talosctl argv visible in CI logs / argv-dump).
- Duplicate placeholder names across capabilities on the same node
  are now detected and fail closed with a `binding-conflict`
  diagnostic; the prior silent-first-wins ordering was non-deterministic.
- Schema declares `placeholder_bindings` on the
  `hardware-capability-spec` (matches runtime); the prior dual
  declaration on the patch-item file-form has been removed to
  eliminate the silent-skip footgun.

### Cap-patches composition (scope clarification)

A capability spec can declare its own `patches:` array. v0.5.2 does
**not** auto-compose capability patches into the per-node argv —
`argv-print.sh` emits only the patches listed in
`roles[<role>].patches`. Consumers who want a capability's patch to
apply on a node must include the patch file in the role's patch
list manually. Auto-composition is post-v0.6.0 work.

The positive test fixture
`talos/test/fixtures/valid-substitution.yaml` demonstrates the
manual-inclusion pattern: `roles.kubevirt-worker.patches` carries
`worker-kubevirt.yaml` explicitly even though the
`kubevirt-networking` capability also lists it.

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

and emits `--config-patch @<tmpdir>/ntp.yaml` as the **first**
`--config-patch` in the per-node argv (before any role-patch and
before `nodes/<n>.yaml`). Every subsequent patch can therefore
override `machine.time.servers` if a consumer needs different NTP
configuration at the role or per-node layer. When `cluster.ntp_server`
is unset, no NTP patch is emitted (opt-in for consumers managing NTP
externally).

Position note: legacy gen-configs emitted the NTP-bearing
`_out/<overlay>/cluster.yaml` patch *after* `patches/common.yaml`.
v0.5.2 changes this to position-1 universally (drops the legacy
"after first common.yaml" heuristic + its fallback path, which
produced different precedences for roles with vs without a
`common.yaml` patch — see R1 review of commit 37dd69a). Bit-identity
diff against the legacy argv-dump will show a 1-position shift of
the NTP entry; the semantic effect is identical when consumer
patches do not contain `machine.time.servers`.

Install-image JSON patch retains its prior position (final, after
`nodes/<n>.yaml`); NTP slots before everything.

**Security hardening (R2 closures of R1 team-red findings):**

- `cluster.ntp_server` value is charset-validated against
  `^[A-Za-z0-9.:_-]{1,253}$` before substitution into the heredoc.
  Refusal at gen-configs time prevents YAML-injection via a
  newline-bearing value (e.g., an attacker landing
  `machine.install.extraKernelArgs` through the NTP slot to bypass
  the AGENTS.md Hard Constraints check on SecureBoot / debugfs=off).

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

### Schema: `placeholder_bindings` removed from patch-item file-form

The v0.5.1 JSON Schema declared `placeholder_bindings` on **two** sites
simultaneously: the `$defs/patch-item` file-form (where it was inert at
runtime — neither `argv-print.sh` nor `validate-schematics.sh` ever read
it from there) and implicitly on the `hardware-capability-spec` (via
`additionalProperties: true`). v0.5.2 makes the schema match runtime:
`placeholder_bindings` lives **only** on the capability spec, with
`additionalProperties: false` on the patch-item file-form.

**Breaking impact:** any consumer cluster.yaml that placed
`placeholder_bindings` directly on a patch-item file-form (matching the
v0.5.1 schema-documented but runtime-ignored location) now fails schema
validation. The binding was silently no-op under v0.5.1; v0.5.2 surfaces
that as a hard fail.

**Detect:**

```bash
grep -rA3 'file: ' "$(yq -r '.cluster.name' cluster.yaml)/patches/" \
    | grep -B1 placeholder_bindings && \
    echo "MIGRATE: move placeholder_bindings to hardware-capabilities.<cap>.placeholder_bindings"
```

**Migrate:** move the `placeholder_bindings` block from the patch-item
to the capability spec that includes that patch:

```yaml
# v0.5.1 (schema-documented but runtime-ignored — REMOVE):
hardware-capabilities:
  kubevirt-networking:
    patches:
      - file: patches/worker-kubevirt.yaml
        placeholder_bindings:       # <-- delete this
          NIC_NAME: machine.network.bridge.nic

# v0.5.2 (runtime-honored — ADD):
hardware-capabilities:
  kubevirt-networking:
    placeholder_bindings:           # <-- move here
      NIC_NAME: machine.network.bridge.nic
    patches:
      - file: patches/worker-kubevirt.yaml
```

### Behavior: NTP patch precedence inverts on consumers that set `machine.time.servers` in a role-patch

The legacy `gen-configs` path emitted the NTP-bearing
`_out/<overlay>/cluster.yaml` patch **after** `patches/common.yaml`, so
`cluster.ntp_server` overrode any `machine.time.servers` declared in
`common.yaml`. v0.5.2 emits the NTP patch at **position 1** (before all
role-patches and the per-node patch), so any role-patch or per-node
patch that declares `machine.time.servers` now **overrides**
`cluster.ntp_server`.

For most consumers this is a no-op (NTP is typically declared only via
`cluster.ntp_server`). The behavior diverges only for consumers whose
role-patches or per-node yaml explicitly carry `machine.time.servers`.

**Detect:**

```bash
grep -rEn 'machine\.time\.servers|^[[:space:]]*time:[[:space:]]*$' \
    patches/ nodes/ | grep -v RELEASE-NOTES
# Non-empty output => audit precedence intent before v0.5.2 cut-over.
```

**Decision tree:**

- No match — no behavior change; ship.
- Match in a role-patch with intent that `cluster.ntp_server` should
  win — move the `machine.time.servers` declaration out of the role-patch
  (rely on `cluster.ntp_server` alone) OR keep it and rely on the new
  v0.5.2 ordering (role-patch wins).
- Match in a per-node yaml — same options; per-node now wins
  unconditionally.

Documented at length in §CRIT-4 above.

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
