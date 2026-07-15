# Changelog

## 2026-07-15

- `rules/talos-base-bundle.md` added: the bundle's authoring conventions as an
  OKF Rule document, rendered into the `AGENTS.md` managed block by
  `openknowledge rules apply`. It is the source of truth for them.
- `index.md`: `## Rules` section added; §Bundle conventions reduced to a
  pointer at the rule document plus the non-normative reasoning behind it. The
  bundle-boundary statement now says what it always meant — contracts a
  tarball or schema consumer resolves BY PATH live outside, and the bundle
  ships in no release artifact — with `knowledge/rules/` as the named
  exception for bundle-tooling contracts. `openknowledge.toml` always met the
  same test.
- `openknowledge.toml`: `rule-catalog = "error"`. Verified against v0.5.0 that
  `knowledge/rules/` is the CLI's default rule path, so no `[rules]` section
  is needed.
- `reference/tasks.md`: `knowledge:rules-apply` + `knowledge:rules-check`
  documented, `knowledge:validate` scope corrected; re-verified against
  `Taskfile.yml`.
- `architecture/substrate.md`: repo layout re-verified; `knowledge/rules/`
  added to the bundle's contents.

Pre-flight verification of the rules mechanism against openknowledge v0.5.0
(recorded here because it decided the design): custom rules render from the
default `rules/` path without `[rules].paths`; `rule-catalog = "error"` via
the TOML fails a rule document missing `rule_id`; `rules apply --dry-run`
output is byte-identical between macOS/arm64 and linux/amd64; the block is
first written at end-of-file and a one-time manual move survives later
regeneration, including one that changes the block's length. The renderer
emits only a bullet's first physical line, so rule bullets are written
unwrapped.

## 2026-07-13

- ADR-0015 follow-ups closed: spec staleness gate is CI-enforced
  (`spec:check-staleness` + `scripts/check-spec-staleness.py`;
  `Spec-Impact: none` trailer escape) and the npm-distributed gate tools
  (`openspec`, `markdownlint-cli`) install lockfile-based via
  `npm ci --ignore-scripts` (pins in `package.json`, integrity hashes in
  `package-lock.json`); `workflows/spec-driven-development.md`,
  `reference/tasks.md`, `workflows/release-process.md` updated.
- Toolchain defects from the spec content review fixed (specs updated in
  the same change): conftest source-classifiability deny replaces the
  dead chart-omission rule; duplicate hardware-feature-id gate;
  fully-anchored version patterns (schema + module); fail-closed OCI
  expected-fixture; `app.kubernetes.io/version` on bootstrap templates.
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
- `reference/tasks.md`: `spec:*` and `docs:*` namespaces added to the task
  inventory (validate incl. bite-check + partition assert, check-regen,
  install-cli, update; repo-wide markdownlint) plus `dev:verify-pins` —
  `docs-lint.yml` now runs exactly these Taskfile targets (local CI chain
  == remote CI chain).
- `project/harness-plugin-contract.md`: "ships no `.claude/`" statements
  scoped to hand-authored primitives — the committed OpenSpec-generated
  trees (ADR-0014) are the regenerable exception.
- `workflows/spec-driven-development.md`: upgrade procedure now frames
  regenerated tool trees as security-relevant review surface; CI
  regeneration-parity gate documented.

## 2026-07-11

- Initial OKF v0.1 bundle. Replaces the retired `docs/` tree: architecture,
  reference, workflow, and glossary concepts regenerated from repository
  source; 13 ADRs migrated to `decisions/` with MADR frontmatter mapped to
  OKF and present-tense claims re-verified against code;
  `component-dependencies.md` dissolved into `architecture/substrate.md`;
  `oci-artifact-verification.md` merged into `workflows/verify-release.md`;
  machine-consumed contracts relocated outside the bundle
  (`platform-hardware-features.yaml`, `schemas/`, `contracts/`).
