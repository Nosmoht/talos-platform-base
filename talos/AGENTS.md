# Talos Scope — Codex CLI Context

> Root scope: `@../AGENTS.md` (inherits §Hard Constraints, §Session Ritual, §MCP servers).

This file is loaded by Codex CLI when editing files under `talos/`. It provides
path-scoped context approximating Claude Code's `paths:` auto-loading. Read the
linked rule files before editing in the listed contexts.

> **Scope note.** This file documents the Talos workflow as it is consumed
> *end-to-end* — i.e. when this base is vendored into a consumer cluster repo.
> Some referenced directories (`talos/nodes/`, `talos/generated/`) and rule
> files (`.claude/rules/talos-*.md`) live in the **consumer repo** or the
> **`kube-agent-harness` plugin**, not in this base. See top-level
> [`CLAUDE.md`](../CLAUDE.md) §"Context Architecture" for the split.

## Directory Map

| Path | Purpose | Lives in |
|------|---------|----------|
| `talos/patches/` | Talos machine config patches (common, controlplane, worker, per-node) | base (this repo) |
| `talos/versions.mk` | Pinned versions (Talos, Kubernetes, Cilium, extensions) | base (this repo) |
| `talos/*.schematic-ids.mk` | Image Factory schematic IDs per node class | base (this repo) |
| `talos/Makefile` | Lifecycle targets: gen-configs, apply-*, dry-run-*, upgrade-k8s, schematics | base (this repo) |
| `talos/nodes/` | Node-specific config inputs | **consumer repo** |
| `talos/generated/` | **Generated output** — never hand-edit; regenerate with `make -C talos gen-configs` | **consumer repo** |

## Domain Rules by Edit Context

Before editing, read the applicable rule file. These rule files are shipped by
the `kube-agent-harness` Claude Code plugin (or vendored into a consumer repo's
`.claude/rules/`); they are **not** present in this base.

| Context | Rule file (plugin-shipped) |
|---------|----------------------------|
| Machine config patches, `talconfig.yaml` | `.claude/rules/talos-config.md` |
| Image Factory schematics, system extensions | `.claude/rules/talos-image-factory.md` |
| `talosctl` operations, lifecycle, gotchas (MCP-first) | `.claude/rules/talos-mcp-first.md` |
| Node IPs, endpoint flags, inventory | `.claude/rules/talos-nodes.md` |

## Patch Ordering

Patches apply in this order: `common` → `controlplane|worker` → `<node-name>`. More-specific patches override less-specific. Never edit files in `talos/generated/` — regenerate them.

## Role-spec patches field

The canonical field name for the per-role patch list at
`roles[<role>].patches` in `cluster.yaml`. This field is read at runtime
by `talos/scripts/argv-print.sh:110` and emitted by the legacy
translator `talos/scripts/translate-legacy-cluster-yaml.sh:170-196`.

The schema (`talos/schemas/cluster.schema.json`) declares
`patches` (array of strings) on `$defs.role-spec` and enforces
`additionalProperties: false`. Field-name drift across this surface is
a CI gate (`talos/scripts/check-role-patches-field.sh`).

History: v0.5.1 and v0.5.2 schemas declared the field as `default_patches`
while every other artifact in this surface used `patches`. v0.5.3
reconciles to `patches` as canonical and drops `default_patches`. See
`talos/RELEASE-NOTES-v0.5.3.md` for migration.

## Pre-Drain Safety Checklist (inline — full gate in the plugin's `.claude/hooks/pre-drain-check.sh`)

Before `talosctl` drain or `kubectl drain` on any node:

1. Confirm DRBD primary for all volumes is NOT on the node being drained
2. `kubectl get pdb -A` — verify no PodDisruptionBudget blocks eviction
3. `kubectl get pods -A --field-selector=status.phase!=Running` — no stuck pods
4. Check cluster health: `talosctl -n <cp-ip> -e <cp-ip> health`
5. For GPU node: confirm no active GPU workloads (check `nvidia.com/gpu` resource allocations)

## Hard Constraints (inline summary — canonical in `../AGENTS.md §Hard Constraints`)

- **No `metal-installer-secureboot`** — use `metal-installer` (SecureBoot causes boot loops)
- **No `debugfs=off`** kernel boot param — causes "failed to create root filesystem"
- **Talos MCP-first**: use MCP tools (`talos_health`, `talos_get`, etc.) over raw `talosctl` for supported operations. CLI-only exceptions: `upgrade-k8s`, `config backup to file`, `client version`.
- **Always use explicit endpoint flags**: `talosctl -n <node-ip> -e <node-ip>` (never implicit)
- **Apply configs BEFORE `upgrade-k8s`**: `upgrade-k8s` reads extraManifests URLs from the LIVE node config

## Schematic IDs are per-cluster state

The Image Factory schematic IDs (`SCHEMATIC_ID`, `GPU_SCHEMATIC_ID`,
`PI_SCHEMATIC_ID`) are content-hashes of a cluster-specific extension set.
They depend on which extensions a given cluster pins in `versions.mk` plus
local schematic patches and therefore differ between consumer clusters —
they MUST NOT be committed in this cluster-agnostic base.

Both the generated `talos/.schematic-ids.mk` (the IDs themselves) and the
`talos/.schematics.stamp` (a Make stamp tracking last regeneration) are
`.gitignore`d. Each consumer cluster regenerates them locally by running
`make schematics` inside `talos/` (or `make -C talos schematics` from the
repo root):

```text
make schematics                 # POSTs to factory.talos.dev/schematics
                                # writes IDs into .schematic-ids.mk
                                # touches .schematics.stamp
```

The generation rule itself (`talos/Makefile` ~line 291) remains intact and
unchanged; only the cached output is no longer tracked.

## Makefile Targets

```text
make -C talos gen-configs       # Regenerate all node configs
make -C talos apply-<node>      # Apply config to a single node
make -C talos dry-run-all       # Validate config without applying
make -C talos upgrade-k8s       # Upgrade Kubernetes (reconciles extraManifests)
make -C talos schematics        # Create/update Image Factory schematic IDs
```

## v0.5.x Dual-Path Status

Legacy `gen-configs` (consumer-side `talos/Makefile` pattern rules) remains
the default production path until v0.6.0. The 5-axis Makefile.lib path is
additive and now production-eligible per v0.5.2 when the Phase 3 cut-over
checklist is satisfied (see `talos/RELEASE-NOTES-v0.5.2.md`).

History:

- **v0.5.1** — argv-print + validation only. Two blockers: CRIT-1 (placeholder
  resolution not implemented) and CRIT-4 (NTP not injected on new path).
  `talos/RELEASE-NOTES-v0.5.1.md` documents both.
- **v0.5.2** — both CRIT-1 and CRIT-4 closed. `argv-print.sh` substitutes
  `${PLACEHOLDER}` tokens via `resolve-placeholders.sh` (capability-level
  `placeholder_bindings` resolved against `nodes/<NODE>.yaml`) and renders a
  synthetic NTP patch from `cluster.ntp_server` immediately after the first
  `common.yaml` reference. Both behaviours are opt-in (no NTP patch when
  `cluster.ntp_server` unset; no substitution when patch contains no token).

### Placeholder convention

Capability spec carries a `placeholder_bindings` map:

```yaml
hardware-capabilities:
  <cap-id>:
    placeholder_bindings:
      NIC_NAME: machine.network.bridge.nic   # ABSOLUTE path from nodes/<n>.yaml root
    patches:
      - file: patches/<cap-patch>.yaml
```

The value is a yq path **absolute from the `nodes/<n>.yaml` root** — include
the `machine.` prefix where appropriate. `argv-print` does not add any
implicit prefix; the same path is read at validate-schematics' `binding-missing`
diagnostic time.

Placeholder names in patch files: `${[A-Z][A-Z0-9_]*}` (shouty-snake). Both
`resolve-placeholders.sh` and `validate-schematics.sh` enforce the
charset constraint.

### Safe operations matrix

| Operation | v0.5.1 | v0.5.2 |
|---|---|---|
| `make argv-print` | YES (inspection) | YES (production-eligible, includes substitution + NTP) |
| `make validate-schematics` | YES | YES |
| `make schematics` | YES | YES |
| `make gen-configs` (new path) | **NO** | YES — when Phase 3 cut-over checklist satisfied |
| Legacy `make -C talos gen-configs` (consumer wrapper) | YES | YES (default until v0.6.0) |
