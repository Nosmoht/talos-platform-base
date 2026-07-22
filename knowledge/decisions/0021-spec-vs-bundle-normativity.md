---
type: decision
title: "ADR: OpenSpec specs are the sole normative artifact for schema and module-interface contracts"
description: "openspec/specs/cluster-yaml-sot and openspec/specs/module-interface-contract are the sole normative artifacts for cluster.yaml schema shape and talos-cluster module variable/output contracts, per the owner's issue #177 decision, while the OKF reference concepts thin to narrative pointers and one hand-maintained duplication (the module README) remains, gated only at name level."
status: accepted
id: base:spec-vs-bundle-normativity
timestamp: 2026-07-22
deciders:
  - repo owner
supersedes:
  - "/decisions/0015-openspec-adoption.md §SoT map vs knowledge/reference/ and §Ownership model (the doc→spec map's reference-doc targets, the terraform-docs exemption, and the zero-restatement clause — scoped, see below)"
related:
  - base:openspec-adoption
  - base:cluster-yaml-sot
  - base:opentofu-cluster-lifecycle
tags: [adr, spec-driven-development, governance]
---

# ADR: OpenSpec specs are the sole normative artifact for schema and module-interface contracts

## Context and Problem Statement

The pre-merge review of #168 found that ADR-0015's claim — "Specs are normative for requirements; reference docs stay narrative" — did not hold for two overlapping content classes: `cluster.yaml` schema keys/patterns/enums, and the `talos-cluster` module's variable and output contracts. `knowledge/reference/cluster-yaml.md` restated schema-normative content already stated as Requirements in `openspec/specs/cluster-yaml-sot/spec.md`, with no mechanism holding the two copies in sync — a PR could satisfy `task spec:check-staleness` and leave the reference copy stale indefinitely. Issue #177 asked for a decision: which artifact is normative for each class, and, for whatever duplication is deliberately kept, which mechanism (if any) keeps the copies honest.

## Decision Drivers

- Dual maintenance of the same normative content, asymmetrically enforced (one copy CI-gated via `task spec:check-staleness`, the other governed only by a manual bundle-convention re-verify), is a standing staleness risk in a single-maintainer repo.
- The owner's 2026-07-21 decision on issue #177 fixed the direction: the OpenSpec spec becomes the sole normative artifact per overlapping class; the OKF reference concepts thin to genuine narrative. Blessing the duplication and adding a new freshness gate over `knowledge/reference/` are both explicitly foreclosed by that decision.
- Decision history in this bundle is append-only (`AGENTS.md` §Open Knowledge Maintenance → Decisions rules): ADR-0015's accepted text is scoped by this record, never rewritten.

## Considered Options

1. Accept and record the duplication, naming a mechanism (existing or new) that keeps every copy honest.
2. Make the OpenSpec spec the sole normative artifact per overlapping content class, thinning the OKF reference concepts to narrative pointers.
3. Leave ADR-0015's claim as stated and change nothing.

## Decision Outcome

Chosen option: **2**, by the owner's 2026-07-21 decision on issue #177. `openspec/specs/cluster-yaml-sot/spec.md` and `openspec/specs/module-interface-contract/spec.md` are the sole normative artifacts for the two overlapping content classes named in §"Normative ownership by content class" below; `knowledge/reference/cluster-yaml.md` is thinned to point at them instead of restating their content. One duplication remains and is deliberately kept: `tofu/modules/talos-cluster/README.md`'s hand-maintained Inputs/Outputs tables, gated only at name level — see §Validation for the mechanism's force and scope.

### Consequences

- Positive: a reader comparing the two files the issue named against the owning specs now finds a single normative artifact per content class, with the reference doc pointing rather than restating.
- Negative: the module README's hand-maintained duplication persists, ungated for content; per-variable defaults are stated exhaustively only there.
- Negative: two further bundle concepts outside this record's boundaries still restate spec-owned content, and the `emits_label` prefix constraint is stated normatively in two specs at once — both named in §Named residuals below.
- Follow-up: [issue #190](https://github.com/Nosmoht/talos-platform-base/issues/190) — `knowledge/reference/tasks.md`'s `tofu:*` inventory omits `tofu:check:readme-parity` and `tofu:check:kubeconfig-endpoint-regen`.
- Follow-up: [issue #191](https://github.com/Nosmoht/talos-platform-base/issues/191) — `knowledge/architecture/capability-composition.md` restates schema- and module-interface-normative content this record assigns to the owning specs.
- Follow-up: [issue #192](https://github.com/Nosmoht/talos-platform-base/issues/192) — `knowledge/reference/manifest-pipeline.md` restates the conftest policy rules owned by `openspec/specs/platform-invariants/spec.md`.
- Follow-up: [issue #193](https://github.com/Nosmoht/talos-platform-base/issues/193) — `knowledge/decisions/0003-three-layer-capability-architecture.md` cites gitignored, host-local audit-trail paths as its evidence; this record does not repeat that citation pattern.
- Follow-up: [issue #194](https://github.com/Nosmoht/talos-platform-base/issues/194) — the `emits_label` prefix constraint is normative in both `cluster-yaml-sot` and `module-interface-contract` at once; closing it needs an `openspec/changes/` delta, outside this issue's non-goals.

## Normative ownership by content class

| Content class | Normative artifact | Duplication kept? | Honesty mechanism |
|---|---|---|---|
| `cluster.yaml` schema keys, patterns and enums — RFC-1123 `cluster.name`, the `https://` endpoint pattern, v-prefixed semver, the `cpu_vendor` enum, the `emits_label` prefix, the closed `substrate` object | `openspec/specs/cluster-yaml-sot/spec.md` | yes — `tofu/modules/talos-cluster/README.md` §Inputs | `task tofu:check:readme-parity` |
| `talos-cluster` module variable types and validation constraints, plus the module output contract | `openspec/specs/module-interface-contract/spec.md` | yes — `tofu/modules/talos-cluster/README.md` §Inputs/§Outputs | `task tofu:check:readme-parity` |

The normative artifact wins over a narrative bundle concept or a module README on conflict. It is normative for the requirement's shape and observable outcome — it does not override `AGENTS.md` §Hard Constraints, and where a spec itself attributes normativity upward to an ADR or to §Hard Constraints, that attribution stands: `openspec/specs/cluster-yaml-sot/spec.md` §"Requirement: Untyped escape hatches and structural secret exclusion" names `knowledge/decisions/0007-cluster-yaml-sot.md` as normative for the secret exclusion, and `openspec/specs/module-interface-contract/spec.md` and `openspec/specs/platform-invariants/spec.md` each defer upward to `AGENTS.md` §Hard Constraints for the substrate invariants they touch (SecureBoot, recommended labels). An unqualified rule would make a spec edit sufficient to override a Hard Constraint's stated authority.

## Named residuals

Overlaps the delivered state still carries, each with what it would take to close it:

- The `emits_label` prefix constraint is normative in **two** specs simultaneously: `openspec/specs/cluster-yaml-sot/spec.md` §"Requirement: Composite capability entries" (schema level) and `openspec/specs/module-interface-contract/spec.md` §"Requirement: Capability label namespace validation" (module-validation level). Neither Requirement cross-references the other — the nearby mirror sentence in the module spec belongs to its §"Requirement: Image kernel-argument input validation" and is about kernel-argument validation, not the capability-label namespace. Closing the overlap means demoting one copy to a reference via `openspec/changes/`; filed as [issue #194](https://github.com/Nosmoht/talos-platform-base/issues/194).
- `tofu/modules/talos-cluster/README.md` is the copy that **ships** in the OCI release artifact (`.ci-oci-tarball-include.txt`), where neither `knowledge/` nor `openspec/` appears — for a vendoring consumer it is the only copy in hand, and it is name-level-gated only.
- Per-variable **defaults** are stated exhaustively only in that README's §Inputs Default column; `openspec/specs/module-interface-contract/spec.md` documents defaults only for a partial subset — the cert-approver tuning knobs, the cluster-health timeout, and the `talos_install_version` fallback — not the exhaustive per-variable set. Ungated for content.
- **Two bundle concepts outside this issue's boundaries still restate spec-owned content and are ungated:** `knowledge/architecture/capability-composition.md` (schema-normative content, including the module-validation framing of the `emits_label` namespace this record assigns to `module-interface-contract`) and `knowledge/reference/manifest-pipeline.md` (the conftest policy rules owned by `openspec/specs/platform-invariants/spec.md`). Closure deferred; filed as [issue #191](https://github.com/Nosmoht/talos-platform-base/issues/191) and [issue #192](https://github.com/Nosmoht/talos-platform-base/issues/192).
- One half of ADR-0015's §Ownership-model claim does not hold as written — see §"How this record scopes ADR-0015's §Ownership model" below: a spec may declare a markdown path under `sources: primary:` (`argocd-substrate` does), so "code/config paths only" is scoped by this record rather than true as stated. Nothing gates it.
- ADR-0015's recorded cost stands: the module README is a primary source of no spec, so `task spec:check-staleness` never fires on it. Only ADR-0015's "tracked as follow-up work" clause is overtaken, and only by the advisory, name-level check named in §Validation below — the cost itself is not resolved.

## How this record scopes ADR-0015's §Ownership model

ADR-0015's §Ownership-model paragraph carries three claims. Each is dispatched below.

(a) Claim 3, the zero-restatement clause — "Normative statements stay in `AGENTS.md` §Hard Constraints and the ADRs; specs cite them and describe observable outcomes" — reads true for **platform invariants and decisions**: those stay upward-referenced in `AGENTS.md` and the ADRs, and the specs that touch them cite rather than restate them (see §"Normative ownership by content class" above for the conflict-resolution rule this record adds on top; it is not restated here).

(b) The clause is **scoped by this record** for **schema shape and module-interface requirements** — the two content classes this record is about — which are spec-owned and stated directly in the owning spec, not restated from an ADR.

(c) Claim 2 — that no spec lists an ADR or `AGENTS.md` under `sources:` — **holds today and is asserted by no gate**. A spec that declared an ADR or `AGENTS.md` path under `sources:` would pass every check `scripts/check-spec-partition.py` makes: the script builds its owner map from every declared primary source with no extension filter, so such a path becomes an ownership key like any other. The exclusivity assertion would stay silent because it would be declared by exactly one spec, and the dangling-source assertion would stay silent because the file exists; the completeness assertion also stays silent, but for a different reason — it only walks an enumerated code/config universe that a markdown or ADR path is never part of. The property holds by construction of today's specs, not because any check would catch a violation of it.

(d) Claim 1 — that spec frontmatter lists `sources:` as "code/config paths only" — **does not hold as written**, and this record says so rather than repeating it as true. `openspec/specs/argocd-substrate/spec.md` declares `kubernetes/base/infrastructure/argocd/README.md` under `sources: primary:` — a markdown documentation path. `scripts/check-spec-partition.py` classifies markdown as documentation and subtracts it from the completeness universe, but that subtraction does not exempt a declared markdown source from ownership: it is checked for exclusivity and existence like every other declared source, and `argocd-substrate` is the sole declarer of a path that exists, so no check objects. This record therefore scopes the clause: `sources:` lists the paths whose change should age the owning spec — normally code and config — with `argocd-substrate`'s README as the one declared exception in the tree at authoring time. Whether `task spec:check-staleness` treats a markdown primary source as staleness-triggering was not observed, and this record asserts nothing about it. Fixing or blessing that exception is outside issue #177's boundaries.

(e) The divergence from the owner's direction, stated plainly. The owner's issue #177 comment directed that ADR-0015's §Ownership-model claim be "made true against the delivered state rather than amended," quoting as that claim the sentence "Specs are normative for requirements; reference docs stay narrative" — which is in fact the opening of ADR-0015's §"SoT map vs `knowledge/reference/`" paragraph, not §Ownership model (whose own three claims are dispatched in (a)–(d) above). Both paragraphs now carry an inline pointer to this record. Making either paragraph unconditionally true against the delivered state is not achievable within issue #177's own non-goals: the release-shipped module README keeps both overlapping content classes' duplication, the `emits_label` prefix constraint stays normative in two specs at once (§Named residuals above), and claim 1 above reads false against a spec this issue may not edit. This record therefore scopes both paragraphs rather than declaring them retroactively true, and states the difference here rather than leaving it implicit.

## Pros and Cons of the Options

### Option 1 — accept and record the duplication

- Pro: no rewrite of the reference docs; lowest short-term effort.
- Con: explicitly foreclosed by the owner's 2026-07-21 decision — the review that opened #177 found this reads as blessing a staleness risk rather than removing it.

### Option 2 — spec is sole normative artifact (chosen)

- Pro: matches ADR-0015's original intent once §Ownership model is scoped honestly; removes the discovered duplication everywhere issue #177's boundaries permit editing it.
- Con: the module README's ungated duplication survives regardless, because the README is outside this issue's boundaries — see §Named residuals above.

### Option 3 — no change

- Pro: no effort.
- Con: leaves ADR-0015's §Ownership-model claim false against the tree; the staleness risk #177 was opened to close stays open.

## Validation

`scripts/check-module-readme-parity.sh` (run as `task tofu:check:readme-parity`) asserts name-level parity in the `.tf` → README direction only, per the script's own §"Scope, honestly" header: it catches an added or renamed module variable or output that never reached `tofu/modules/talos-cluster/README.md`, but it does not catch a README row surviving a deleted declaration, nor a stale default or a tightened validation whose prose no longer describes the thing. It runs via `task tofu:ci` inside the `tofu-validate` GitHub Actions workflow, which is path-filtered to `tofu/**` and `Taskfile.yml` and is **advisory** — observed 2026-07-22 via the required-status-checks API for this repository's default branch, `tofu-validate` is not among the required contexts. Content-level staleness of the kept module-README duplication is therefore accepted; no sentence in this record implies the check blocks a merge.

This decision is wrong if the ownership table above stops matching the tree — the trigger to revisit is a spec edit that adds or drops a Requirement without a corresponding update to `knowledge/reference/cluster-yaml.md`'s pointers, or discovery of a further class of content overlapping between a spec and a bundle concept.

## Links

- [issue #177](https://github.com/Nosmoht/talos-platform-base/issues/177) — the decision this record resolves.
- Spillover follow-ups: [issue #190](https://github.com/Nosmoht/talos-platform-base/issues/190), [issue #191](https://github.com/Nosmoht/talos-platform-base/issues/191), [issue #192](https://github.com/Nosmoht/talos-platform-base/issues/192), [issue #193](https://github.com/Nosmoht/talos-platform-base/issues/193), [issue #194](https://github.com/Nosmoht/talos-platform-base/issues/194) — see ### Consequences → Follow-up above for what each closes.
- [0015-openspec-adoption](./0015-openspec-adoption.md) — the record this ADR partially supersedes.
