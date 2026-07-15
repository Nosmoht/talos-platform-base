---
okf_version: "0.1"
---

# talos-platform-base — Knowledge Bundle

Deep reference for the cluster-agnostic Talos + Cilium + ArgoCD substrate,
as an [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog) v0.1
bundle. Orientation and governance stay at the repository root (`README.md`,
`ARCHITECTURE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `SECURITY.md`,
`UPGRADING.md`, `MAINTAINERS.md`); everything deeper lives here.

Contracts a consumer parses — the machine-readable interface of a release —
live outside this bundle by design: `platform-hardware-features.yaml` (repo
root), `schemas/`, `contracts/`. The bundle itself ships in no release
artifact: the OCI tarball allowlist (`.ci-oci-tarball-include.txt`) names no
path under `knowledge/`.

`knowledge/rules/` holds contracts the bundle's own tooling reads, and only
those — `openknowledge` renders them into the `AGENTS.md` Open Knowledge
Maintenance block. The criterion for admitting a file here is that the
bundle's tooling consumes it and no release consumer parses it;
`openknowledge.toml` has always met the same test. This is a narrow carve-out
for tooling config, not a general licence to move contracts into the bundle.

## Architecture

- [Capability Composition](architecture/capability-composition.md) - How per-node hardware capabilities compose Layer-C atoms, the base-owned provisioning-profile catalog, deduplicated schematics, and node labels in the talos-cluster module.
- [Day-Zero Bootstrap](architecture/day-zero-bootstrap.md) - How a set of Talos maintenance-mode nodes becomes a GitOps-managed cluster — module-seeded inlineManifests, the bootstrap sequence, the App-of-Apps root seed, and the handoff to steady state.
- [Substrate Boundary](architecture/substrate.md) - What talos-platform-base is and ships — the three-pillar substrate, the base/apps/consumer layer model, the tracked repo layout, and the fail-closed OCI artifact allowlist.

## Reference

- [cluster.yaml — Declarative Cluster SoT](reference/cluster-yaml.md) - The two consumers of the declarative cluster.yaml Source-of-Truth, its secret-handling rules, and how CI wires the schema lint gate red-green.
- [Manifest Pipeline](reference/manifest-pipeline.md) - How the rendered-manifests pattern is implemented — chart pinning, two-stage render, drift fences, and the gitops:validate pipeline with its CI mapping.
- [Task Runner Surface](reference/tasks.md) - Complete go-task target inventory with per-task purpose, preconditions, and the Makefile deprecation stub behavior.

## Workflows

- [First Consumer Cluster](workflows/first-consumer-cluster.md) - End-to-end walk-through from verifying a published base release to a reconciling App-of-Apps root on a freshly provisioned Talos cluster.
- [Issue Lifecycle](workflows/issue-lifecycle.md) - The GitHub issue state machine — status labels, guarded transitions via the issue-state script, and the session-start ritual that gates agent work.
- [MCP Setup](workflows/mcp-setup.md) - Installing and verifying the three MCP servers, and the wrapper security model that keeps the GitHub token out of shell environments.
- [Release Process](workflows/release-process.md) - How a release moves from conventional commit through the semantic-release approval gate to a signed OCI artifact on ghcr.io.
- [Spec-Driven Development (OpenSpec)](workflows/spec-driven-development.md) - How behavioral requirements are maintained in the OpenSpec surface — the change lifecycle, the scope demarcation against knowledge/, and the pinned-tool upgrade procedure.
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

## Rules

- [Bundle Conventions](rules/talos-base-bundle.md) - Repo-specific OKF bundle conventions layered on top of the built-in maintenance rules, rendered into the AGENTS.md managed block.

## Bundle conventions (repo convention on top of OKF v0.1)

OKF v0.1 requires only `type` in concept frontmatter. The conventions this
bundle adds on top are **normatively stated in
[Bundle Conventions](rules/talos-base-bundle.md)** — the closed `type`
vocabulary, the `title`/`description`/`tags`/`timestamp`/`sources` field set,
the staleness contract, the link rule, and the `log.md` maintenance rule. That
file is the source of truth, and `openknowledge` renders it into `AGENTS.md`
so an agent reading only that file still sees the contract.

What follows is the reasoning behind those rules, for a human reader. It is
**not normative** — when this section and the rule document disagree, the rule
document wins:

- Most of the contract is enforced by review discipline, NOT by
  `openknowledge validate`. A green validation run means links resolve and
  frontmatter parses; it is not evidence that a concept is still true.
- `timestamp` is the date of the last *substantive verification*, not the last
  typo fix. Bumping it for a wording change silently resets the staleness
  clock, which is the failure this contract exists to prevent.
- `sources` is what makes staleness checkable at all: it names the paths a
  concept was derived from, so a reader can compare them against `timestamp`.
  Nothing does this mechanically yet — it is a reading discipline.
- `description` is reused verbatim as the link description in this index, so
  it is written as one self-contained sentence.
- The link rule has teeth: `openknowledge.toml` raises `link-target` to error,
  so a link escaping the bundle fails validation rather than rotting quietly.
