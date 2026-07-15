# Changelog

## 2026-07-15

- `reference/talos-cluster-module.md` REMOVED. Every section of it was
  already carried elsewhere: the variable/output/version tables and the
  module-enforced invariants by their owning OpenSpec specs, and the
  fresh-PKI adoption warning, the schema-pin/install-pin Day-2 pattern and
  the examples entry point by `tofu/modules/talos-cluster/README.md`, which
  sits next to the code. Its inbound links now point at whichever of those
  two carries the content.
- `decisions/0015-openspec-adoption.md`: dated correction appended to the
  §SoT map. The accepted text exempted the module README's tables as
  "terraform-docs-generated (inject mode)"; verified false — the README has
  no `BEGIN_TF_DOCS` markers and `task tofu:docs` swallows the miss with
  `|| true`, so the tables are hand-maintained and the contract was carried
  by hand three times.
- `reference/cluster-yaml.md`: §Two consumers now cites
  `openspec/specs/argocd-day-zero-bootstrap/` for the bootstrap-identity
  subset instead of carrying it. The subset and the two envsubst containment
  guards moved into that spec via the first `openspec/changes/` proposal
  (archived `2026-07-15-spec-bootstrap-identity-subset`) — they were shipped
  behavior that only this doc described, on a Taskfile fragment the staleness
  gate already watches.
- `reference/cluster-yaml.md`: schema-shape section removed — all eight
  `openspec/specs/cluster-yaml-sot/` requirements were re-checked against it
  first, `substrate` included, and they carry every point normatively from
  the same `schemas/cluster.schema.json` this doc cited. Kept what no
  requirement carries: the two-consumer subsets, where secrets go instead of
  the file, the authoring notes the schema cannot express, and the CI
  red-green wiring of the lint gate. `sources` and `timestamp` re-derived
  from what remains.
- `index.md`: `reference/talos-cluster-module.md` entry dropped;
  `reference/cluster-yaml.md` description re-synced.
- `specs/hardware-capability-composition` (OpenSpec, outside this bundle)
  gained the predicate-only profile-karg requirement, and ADR-0016 gained the
  Talos `CONFIG_IOMMU_DEFAULT_PASSTHROUGH` lookup it had declined to make
  (unset — so `iommu=pt` was doing real work) plus the mechanical check that
  now pins the catalog. `reference/tasks.md`: `tofu:test:offline` documented,
  `tofu:ci` scope corrected; re-verified against `Taskfile.yml`.
- `decisions/0016-capability-profiles-predicate-only.md` added: removes
  `iommu=pt` from the `iommu` provisioning profile. A profile karg is
  base-owned and consumer-unoverridable, so it must carry only what the
  provided atom's `presence_predicate` names; `iommu=pt` is host-DMA tuning
  that reached the catalog by being copied from a README example. Kernel-doc
  wording verified at the primary source.
- `decisions/index.md`: 0014 listed under §Accepted.
- `architecture/capability-composition.md`: shipped-catalog description no
  longer claims the `iommu` profile carries `iommu=pt`; re-verified against
  `profiles.tf`.
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
