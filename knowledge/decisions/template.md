---
type: decision
title: "ADR: <Short, decision-shaped title>"
description: "<One sentence stating the decision outcome factually.>"
status: proposed
id: base:<short-kebab-id>
deciders:
  - <name or role>
consulted: []
informed: []
supersedes: []
superseded_by: []
related: []
tags: [adr, template]
---

<!-- Copy this file when authoring a new ADR. Rename to the next free
     `NNNN-<short-kebab-id>.md` and fill in every frontmatter field
     above. Delete this comment block from the new file.

     Add a `decided:` key carrying the date the decision was made, as a
     quoted ISO 8601 datetime — `decided: "2026-08-23T00:00:00Z"`. It is
     absent here on purpose: a placeholder date is a date a copy can ship
     with, and the validator does not type this producer-defined key.
     `generated` and `verified` do NOT belong on a decision concept; see
     `index.md` §Status vocabulary for why. -->

# ADR: <Short, decision-shaped title>

## Context and Problem Statement

<!-- Two-to-five sentences. What forces are at play? What problem are
     we solving? Cite specific files, incidents, or constraints — do not
     re-derive context from first principles. -->

## Decision Drivers

- <!-- driver 1 — e.g., "supply-chain auditability mandated by SLSA L3 target" -->
- <!-- driver 2 — e.g., "single-maintainer repo, cannot afford per-PR human review overhead" -->

## Considered Options

1. <!-- option A — name + 1-line description -->
2. <!-- option B -->
3. <!-- option C -->

## Decision Outcome

Chosen option: **\<option name\>**, because \<one or two sentences
explaining the winning tradeoff\>.

### Consequences

- Positive: <!-- positive consequence -->
- Negative: <!-- compromise consequence -->
- Follow-up: <!-- work this decision creates -->

## Pros and Cons of the Options

### Option A

- Pro: <!-- pro -->
- Con: <!-- con -->

### Option B

- Pro: <!-- pro -->
- Con: <!-- con -->

## Validation

How will we know this decision is wrong? What mechanical check or
follow-up review confirms it stays correct? Cite the CI job, the
metric, or the next-review date.

## Links

- <!-- link to PR / issue / external standard that drives this decision -->
