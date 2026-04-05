# Linear Session-Restart Playbook

Use this sequence at the start of every Claude Code session to rehydrate full
plan context from Linear without reading any repo markdown files.

## Quick reference

- **Linear project:** Talos Homelab (`e359028e-d800-4f5f-8170-1a3460cee121`)
- **Team:** Nosmoht (`8bf51b7b-b2e5-48c7-96a6-c5cc1bdd295c`)
- **Linear URL:** https://linear.app/nosmoht/project/talos-homelab-e359028e

## Rehydration sequence

### Step 1 — Load project + milestones

```
mcp__linear__get_project(id="e359028e-d800-4f5f-8170-1a3460cee121")
mcp__linear__list_milestones(projectId="e359028e-d800-4f5f-8170-1a3460cee121")
```

Milestones (phase order):
1. P0 — Gating PoCs
2. P1 — Layer 0 Buildout
3. P2 — Admin-tenant Bootstrap
4. P3 — Workload Tenant Validation (runs before P2.8)
5. Ongoing — Scheduled Checks + Drift

### Step 2 — Load architecture documents

```
mcp__linear__list_documents(projectId="e359028e-d800-4f5f-8170-1a3460cee121")
```

Key documents:
- `Architecture — Two-Layer Cluster Design` (id: 8ae08813) — diagram, hardware, bootstrap chain
- `Architectural Decisions D1–D8` (id: f26d03d5) — closed decisions, consequences
- `Risk Register R1–R16` (id: 55b88c1e) — severity, mitigations
- `Review Findings Consolidated` (id: 9605a073) — RV-B*/H*/C*/A*, RF-B*, V-13..16, DEP-1..10
- `Session-Restart Playbook` (id: b31fbf63) — this document in Linear form

### Step 3 — Load open issues

```
mcp__linear__list_issues(
  projectId="e359028e-d800-4f5f-8170-1a3460cee121",
  filter={stateType: ["unstarted", "started", "backlog"]}
)
```

Issue label taxonomy:
- `phase/P0-gating-pocs` … `phase/ongoing` — milestone grouping
- `risk/R1` … `risk/R16` — risk register traceability
- `decision/D1` … `decision/D8` — decision traceability
- `backlog/network-phase-2` … `backlog/tech-debt` — backlog source
- `severity/blocker`, `severity/high`, `severity/medium`, `severity/low`
- `bug`, `skill-gap`, `invariant-gap`, `generalization`, `documentation`

### Step 4 — Check blockers

P0 gates block all P1/P2 work:
- P0.2 (machineconfig injection) blocks P1 + P2
- P0.3 (live-migration PoC) blocks P1.3 (linstor-vm-live SC) + P2.1
- P1.1 (cert-manager) blocks P1.2 (CAPI controllers)
- P1.9 (VLAN 110+120 rolling apply) blocks P2.1 + P3.2
- P1.11 (host CCNP + Kyverno guard) blocks P2.8
- P3.3 (isolation validation) blocks P2.8
- P2.7 (etcd DR drill) blocks P2.8

## Key architectural constants

| Constant | Value |
|---|---|
| Talos version | v1.12.6 (frozen — CABPT v0.6.x ceiling) |
| Kubernetes version | v1.35.0 |
| Cilium version | 1.19.2 |
| CAPI core | v1.8.x (v1beta1) |
| CAPK | v0.10.x (v1beta1) |
| CABPT | v0.6.11 (v1beta1) |
| CACPPT | v0.5.12 (v1beta1) |
| Admin-tenant VLAN | 110 |
| customer-sim-01 VLAN | 120 |
| L0 ingress-front IP | 192.168.2.70 |

## Status gate

Linear `Backlog` state = proposed (`[~]` equivalent) — never start without asking.
Linear `Todo` state = agreed (`[ ]` equivalent) — ready for work.

## What is NOT in Linear

- The full plan text: `Plans/eventual-soaring-thompson.md` (read-only historical reference)
- Research artifacts: `Plans/eventual-soaring-thompson-agent-*.md`
- These are attached to the Linear project as attachments; fetch via `mcp__linear__get_attachment`.
