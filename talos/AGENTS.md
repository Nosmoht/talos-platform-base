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
| `talos/Makefile.lib` | Includable library: gen-configs, schematics, validate-schematics, argv-print, test-substitution. Consumer-side: `include $(BASE_DIR)/Makefile.lib`. | base (this repo) |
| `talos/nodes/` | Node-specific config inputs | **consumer repo** |
| `talos/generated/` | **Generated output** — never hand-edit; regenerate with `make -C talos gen-configs` (consumer wrapper that includes Makefile.lib) | **consumer repo** |

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

## Patch slots — where things go

A Talos node's machine-config is composed at `gen-configs` time by feeding
patches to `talosctl gen config --config-patch @<file>` in a specific order.
Knowing which slot to write in is more useful than memorising which slot
overrides which — choosing the wrong slot still works but spreads the
intent across files that future readers won't think to look at.

### Composition order (v0.5.2 — `talos/scripts/argv-print.sh:268-279`)

Patches apply in this order; each subsequent patch may override
`machine.*` keys set by earlier ones.

1. **NTP baseline** — synthetic patch rendered from `cluster.ntp_servers[]`
   (emitted first when set; opt-in — no patch when the list is empty or
   absent).
2. **`roles.<role>.patches[]`** — role-wide patch files in declared
   order. This is the canonical place for anything every node of that
   role needs (static `machine.nodeLabels`, install-image variants,
   role-uniform sysctls).
3. **`nodes/<NODE_NAME>.yaml`** — last in composition; **highest
   override precedence**. Per-node overrides go here.
4. **`hardware-capabilities[X].patches[]`** — **DECLARATIVE-ONLY in
   v0.5.x.** Listed in the capability spec but **NOT auto-composed
   into the per-node argv** by `argv-print.sh` today. Auto-composition
   is post-v0.6.0 work (see `talos/RELEASE-NOTES-v0.5.2.md:89-100`).
   Consumers who want a capability's patch to apply on a node MUST
   include the patch file in the role's patch list manually.

### Which slot for which concern

| Concern | Slot | Example |
|---|---|---|
| Role-uniform static node-labels (every node of the role) | `roles.<role>.patches[]` with a `machine.nodeLabels` patch file | `roles.worker.patches: [patches/worker-gvisor.yaml]` writes `node.kubernetes.io/runtime=gvisor` on every worker |
| Conceptual single-purpose role for N≥1 nodes (dedicated topology cluster: pi-edge, kubevirt-host, GPU-worker) | A **dedicated role** with its own `roles.<role-name>.patches[]` | `roles.pi-worker.patches: [patches/worker-pi.yaml, patches/pi-firewall.yaml]` |
| Ad-hoc per-node override (NIC name, install-disk specifics, bridge-NIC binding) | `nodes/<NODE_NAME>.yaml` | `nodes/n1.yaml` sets `machine.install.disk` for that node only |
| hardware predicate (CPU features, GPU presence, storage class) | `hardware-capabilities` — **declarative composition only**, no runtime effect today | `hardware-capabilities.gpu-nvidia.requires_features: [pci.10de.*]` (the hardware predicate is read; the `.patches[]` field is informational until v0.6.0) |

### Post-v0.6.0 milestone

`hardware-capabilities[X].patches[]` becomes runtime-composing in
post-v0.6.0; see `talos/RELEASE-NOTES-v0.5.2.md:89-100` (cap-patches
composition scope). The slot exists in the schema today so consumer
cluster.yaml files can be authored against the eventual contract;
they have no per-node argv effect until the v0.6.0 path lands.

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

The schematics-cache build (`talos/scripts/build-schematic-cache.sh`,
invoked via `make schematics` from a consumer Makefile that
`include`s `Makefile.lib`) remains intact and unchanged; only the
cached output is no longer tracked.

## Makefile Targets

```text
make -C talos gen-configs       # Regenerate all node configs
make -C talos apply-<node>      # Apply config to a single node
make -C talos dry-run-all       # Validate config without applying
make -C talos upgrade-k8s       # Upgrade Kubernetes (reconciles extraManifests)
make -C talos schematics        # Create/update Image Factory schematic IDs
```

## v0.6.0 single-path

The legacy `talos/Makefile` (Phase-1A pattern-rule generator) was removed
in v0.6.0. `talos/Makefile.lib` is the single supported path: consumer
Makefiles `include $(BASE_DIR)/Makefile.lib`. The Phase-3 blockers from
v0.5.x (placeholder resolution, NTP patch ordering) closed in v0.5.2;
the production `gen-configs` recipe lives in `Makefile.lib` `_node-rule`.

History:

- **v0.5.1** — argv-print + validation only. Two blockers: CRIT-1 (placeholder
  resolution not implemented) and CRIT-4 (NTP not injected on new path).
  `talos/RELEASE-NOTES-v0.5.1.md` documents both.
- **v0.5.2** — both CRIT-1 and CRIT-4 closed. `argv-print.sh` substitutes
  `${PLACEHOLDER}` tokens via `resolve-placeholders.sh` (capability-level
  `placeholder_bindings` resolved against `nodes/<NODE>.yaml`) and renders a
  synthetic NTP patch from `cluster.ntp_server` as the first patch (before
  any role patch — see §"Patch slots — where things go" for full composition
  order). Both behaviours are opt-in (no NTP patch when
  `cluster.ntp_server` unset; no substitution when patch contains no token).
- **v0.6.0** — `cluster.ntp_server` (scalar) hard-renamed to `cluster.ntp_servers[]`
  (array) so consumers can declare ≥2 NTP servers for redundancy. Talos
  `machine.time.servers` is natively a list; the v0.5.x single-value field
  was a SPOF. argv-print.sh charset-validates every list element.

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

## Schema hygiene — consumer-local metadata vs cluster.yaml fields (F2-B)

`cluster.yaml` is the **5-axis Talos cluster contract** consumed by
`talos/Makefile.lib`. Its schema (`talos/schemas/cluster.schema.json`)
declares the required fields: `roles`, `architectures`,
`infrastructure-platforms`, `hardware-platforms`, `hardware-capabilities`,
`nodes`, plus the optional `cluster` / `strict_capability_merge` /
`migration-modes` blocks. The top-level `additionalProperties: true`
historically tolerated **consumer-local metadata** (e.g. `repo:`,
`kubeconfig:`) co-located with the cluster contract — but the schema
does NOT consume these fields, and `Makefile.lib` does NOT read them.

**Convention (v0.5.4+):** consumer-local metadata does NOT belong in
`cluster.yaml`. It belongs in a separate consumer-local file (e.g.
`.repo-meta.yaml`, `consumer.yaml`, or the consumer's own Makefile
variables). Mixing them into `cluster.yaml` makes the schema look
internally inconsistent (declared-vs-tolerated fields) and creates
friction for new consumers reading the schema as documentation.

The canonical `talos/test/cluster.yaml.example` does NOT carry such
metadata; consumer cluster.yamls SHOULD follow the same convention.
`additionalProperties: true` remains as-is for backward compatibility —
tightening it is a separate concern (see issue tracker).

## Casing convention — `hardware-capabilities` per-node alias (F21-A)

The schema declares the per-node capability list under two property
names during the v0.5.4 grace window:

- `hardware-capabilities` (kebab-case) — **canonical**, aligned with
  the top-level `hardware-capabilities` map key.
- `hardware_capabilities` (snake_case) — **deprecated alias**, still
  accepted for backward compatibility. Planned removal in v0.6.0.

The `anyOf` constraint in `$defs.node-spec` enforces that at least
one of the two is present on every node. Do NOT set both keys on the
same node — their semantics are identical and the alias is solely
for migration.

### Important — DO NOT migrate consumer cluster.yamls in v0.5.4

The schema accepts kebab-case in v0.5.4, but the Makefile.lib runtime
scripts (`argv-print.sh`, `validate-schematics.sh`,
`build-schematic-cache.sh`, `translate-legacy-cluster-yaml.sh`) read
only the snake_case key during v0.5.4. **Renaming a consumer
`cluster.yaml` to kebab-case while still on v0.5.4 produces
silent zero-capability nodes** in `make argv-print` / `make gen-configs`
— the schema validates, but every node's capability list reads as empty.

Consumer migration to kebab-case is gated on v0.6.0, which lands
the script renames + alias removal together in a single coordinated
bump. The migration command and pre-bump survey will be documented
in `RELEASE-NOTES-v0.6.0.md`.
