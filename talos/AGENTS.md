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

## Makefile Targets

```text
make -C talos gen-configs       # Regenerate all node configs
make -C talos apply-<node>      # Apply config to a single node
make -C talos dry-run-all       # Validate config without applying
make -C talos upgrade-k8s       # Upgrade Kubernetes (reconciles extraManifests)
make -C talos schematics        # Create/update Image Factory schematic IDs
```
