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

## v0.5.1 Dual-Path Scope (IMPORTANT — read before using Makefile.lib)

At v0.5.1, the 5-axis Makefile.lib ships **argv-print + validation ONLY**. The
legacy `gen-configs` path (consumer-side `talos/Makefile`) remains the only
production-blessed path for generating talosctl machine config.

**DO NOT use `make gen-configs` via Makefile.lib (the new path) in production
until Phase 3 cut-over is complete.** Two blockers:

1. **Placeholder resolution not implemented** (CRIT-1): `argv-print.sh` emits
   `@nodes/<name>.yaml` verbatim; `${NIC_NAME}` and similar placeholders in
   KubeVirt patch files are NOT substituted. Phase 3 adds the substitution
   mechanism.

2. **NTP not configured on new path** (CRIT-4): `patches/common.yaml` does not
   include a `machine.time.servers` block. The legacy path injected NTP via a
   rendered `_out/<overlay>/cluster.yaml` patch. On the new path, clock drift
   accumulates until Phase 3 updates `common.yaml` to read `cluster.ntp_server`
   from the 5-axis cluster.yaml.

**Phase 3 is a HARD prerequisite for new-path gen-configs.** Until then:

- `make argv-print` — safe for inspection / bit-identity diff
- `make validate-schematics` — safe for cluster.yaml validation
- `make schematics` — safe for schematic cache refresh
- `make gen-configs` (new path) — **NOT safe for production use**
