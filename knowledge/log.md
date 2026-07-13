# Changelog

## 2026-07-13

- ADR-0014 added (`decisions/0014-ship-ai-tool-artifacts.md`, accepted):
  reverses the "ships no `.claude/` tree" policy for tool-generated,
  regenerable artifacts.
- ADR-0015 added (`decisions/0015-openspec-adoption.md`, accepted):
  OpenSpec adoption with directly-authored backfill of 14 substrate
  capability specs; scope principle and SoT-ownership map.
- New workflow concept `workflows/spec-driven-development.md`: OpenSpec
  change lifecycle, demarcation against this bundle, pinned-tool upgrade
  procedure.
- `reference/talos-cluster-module.md` and `reference/cluster-yaml.md`:
  pointer notes added — normative behavioral requirements now live in the
  owning OpenSpec specs (SoT map in ADR-0015); the reference docs stay
  narrative.

## 2026-07-11

- Initial OKF v0.1 bundle. Replaces the retired `docs/` tree: architecture,
  reference, workflow, and glossary concepts regenerated from repository
  source; 13 ADRs migrated to `decisions/` with MADR frontmatter mapped to
  OKF and present-tense claims re-verified against code;
  `component-dependencies.md` dissolved into `architecture/substrate.md`;
  `oci-artifact-verification.md` merged into `workflows/verify-release.md`;
  machine-consumed contracts relocated outside the bundle
  (`platform-hardware-features.yaml`, `schemas/`, `contracts/`).
