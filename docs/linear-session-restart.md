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

Milestones (thematic — phase sequencing via blockedBy + phase/* labels):
1. M1 — Network Foundation
2. M2 — Storage HA
3. M3 — VM Runtime
4. M4 — Tenant Platform
5. M5 — Observability & Compliance
6. M6 — Security Hardening
7. M7 — Platform Reliability
8. M8 — Skills & Generalization
9. M9 — Validation & Runbooks

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

Phase sequencing is encoded as Linear `blockedBy` relations. Key backbone:
- NOS-13 (CAPK injection) → blocks NOS-17 (CAPK e2e)
- NOS-17 → blocks NOS-22 (CAPI core), NOS-33 (admin-tenant CAPI)
- NOS-16 (DRBD PoC) → blocks NOS-24 (LINSTOR SCs), NOS-49 (virtctl smoke)
- NOS-30 (VLAN 110+120 rolling apply) → blocks NOS-33, NOS-43
- NOS-44 (isolation validation) → blocks NOS-40 (L0 decommission)
- NOS-46 (onboarding runbook) → blocks NOS-40

Filter by `label:phase/P0` … `label:phase/P3` for phase-ordered views across themes.

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

- The architecture reference: `Plans/eventual-soaring-thompson.md` (Context + Diagram + Core Decisions + M1–M9 index, ~120 lines)
- Research artifacts: `Plans/eventual-soaring-thompson-agent-*.md`
- These are attached to the Linear project as attachments; fetch via `mcp__linear__get_attachment`.
