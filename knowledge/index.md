---
okf_version: "0.1"
---

# talos-platform-base — Knowledge Bundle

Deep reference for the cluster-agnostic Talos + Cilium + ArgoCD substrate,
as an [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog) v0.1
bundle. Orientation and governance stay at the repository root (`README.md`,
`ARCHITECTURE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `SECURITY.md`,
`UPGRADING.md`, `MAINTAINERS.md`); everything deeper lives here.

Machine-consumed contracts live OUTSIDE this bundle by design:
`platform-hardware-features.yaml` (repo root), `schemas/`, `contracts/`.

## Architecture

- [Capability Composition](architecture/capability-composition.md) - How per-node hardware capabilities compose Layer-C atoms, the base-owned provisioning-profile catalog, deduplicated schematics, and node labels in the talos-cluster module.
- [Day-Zero Bootstrap](architecture/day-zero-bootstrap.md) - How a set of Talos maintenance-mode nodes becomes a GitOps-managed cluster — module-seeded inlineManifests, the bootstrap sequence, the App-of-Apps root seed, and the handoff to steady state.
- [Substrate Boundary](architecture/substrate.md) - What talos-platform-base is and ships — the three-pillar substrate, the base/apps/consumer layer model, the tracked repo layout, and the fail-closed OCI artifact allowlist.

## Reference

- [cluster.yaml — Declarative Cluster SoT](reference/cluster-yaml.md) - Shape, consumers, secret-handling rules, and lint gate of the declarative cluster.yaml Source-of-Truth a consumer cluster maintains.
- [Manifest Pipeline](reference/manifest-pipeline.md) - How the rendered-manifests pattern is implemented — chart pinning, two-stage render, drift fences, and the gitops:validate pipeline with its CI mapping.
- [talos-cluster Module Interface](reference/talos-cluster-module.md) - Typed variable and output contract of the tofu/modules/talos-cluster OpenTofu module, plus the invariants the module enforces in code.
- [Task Runner Surface](reference/tasks.md) - Complete go-task target inventory with per-task purpose, preconditions, and the Makefile deprecation stub behavior.

## Workflows

- [First Consumer Cluster](workflows/first-consumer-cluster.md) - End-to-end walk-through from verifying a published base release to a reconciling App-of-Apps root on a freshly provisioned Talos cluster.
- [Issue Lifecycle](workflows/issue-lifecycle.md) - The GitHub issue state machine — status labels, guarded transitions via the issue-state script, and the session-start ritual that gates agent work.
- [MCP Setup](workflows/mcp-setup.md) - Installing and verifying the three MCP servers, and the wrapper security model that keeps the GitHub token out of shell environments.
- [Release Process](workflows/release-process.md) - How a release moves from conventional commit through the semantic-release approval gate to a signed OCI artifact on ghcr.io.
- [Verify a Base Release](workflows/verify-release.md) - Fail-closed verification of a published talos-platform-base OCI artifact — signature, provenance, SBOM attestation, and checksums — before vendoring.

## Project

- [Harness Plugin Contract](project/harness-plugin-contract.md) - The contract this base expects a Claude Code harness plugin to satisfy, stated from the base's side.
- [OpenSSF Best Practices Self-Assessment](project/openssf-self-assessment.md) - Self-assessment against the OpenSSF Best Practices Passing-level criteria, serving as the source of truth for the external enrolment answers.
- [Vision](project/vision.md) - Forward-looking design anchors the schema was built to accommodate — explicitly not roadmap, commitments, or shipped features.

## Decisions

- [Decisions index](decisions/index.md) - Status-grouped index of all architecture decision records plus the authoring convention.

## Vocabulary

- [Glossary](glossary.md) - Cross-domain vocabulary; cite this file when a term first appears.
- [Changelog](log.md) - Date-grouped bundle change history.

## Bundle conventions (repo convention on top of OKF v0.1)

OKF v0.1 requires only `type` in concept frontmatter. This bundle
additionally standardizes — enforced by review discipline, NOT by
`openknowledge validate`:

- Closed `type` vocabulary: `architecture`, `reference`, `workflow`,
  `decision`, `glossary`, `project`. A new type is added by editing this
  section in the same PR.
- `title`, `description` (one sentence; reused verbatim as the link
  description in this index), `tags`, `timestamp` (date of last
  substantive verification, not last typo fix).
- `sources:` — the repo-relative paths a concept was generated from. This
  is the staleness contract: re-verify a concept when its sources changed
  since `timestamp`.
- Links: files inside the bundle are linked relatively; files outside the
  bundle are cited as inline code spans (`openknowledge.toml` raises
  `link-target` to error, so escaping links fail validation).
- Maintenance: every PR touching the bundle appends one bullet per changed
  concept to [log.md](log.md) under today's date; ADR status transitions
  and concept additions/removals are always logged.
