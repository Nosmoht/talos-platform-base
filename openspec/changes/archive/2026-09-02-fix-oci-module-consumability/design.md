## Context

See `proposal.md`. The explicit, fail-closed allowlist remains the artifact
membership authority. The defect is that allowlist/fixture equality says
nothing about whether the selected files form a usable module.

## Goals / Non-Goals

**Goals:**

- Preserve explicit artifact membership while making the module complete.
- Catch both a missing future module file and a semantically invalid extracted
  module before release.
- Keep bootstrap tooling and worked examples git-only.

**Non-Goals:**

- Package the whole repository or the module's authoring/test tree.
- Change the module interface or provisioning behavior.
- Replace the existing signed OCI publication mechanism.

## Decisions

1. Keep explicit file entries instead of packaging the whole module directory.
   This preserves the existing auditable, fail-closed payload boundary.
2. Extend the existing substrate-consumability gate to derive the required
   root-level `.tf` set from tracked files. This catches future omissions
   without duplicating a hand-maintained filename list.
3. Validate the extracted allowlist-built tarball in `tofu:ci`. Static coverage
   gives a fast deterministic failure, while real `tofu validate` proves that
   the consumer-visible module composes successfully.
4. Correct prose to point at the allowlist as source of truth and explicitly
   separate artifact content from checkout-only bootstrap helpers.

## Risks / Trade-offs

- Provider initialization needs registry access → reuse the existing OpenTofu
  validation job, which already initializes the same providers.
- Explicit membership still requires an allowlist edit for new implementation
  files → the derived completeness gate fails loudly until that reviewable edit
  is made.
- The payload layout changes → use a breaking PR title so the release guard
  produces a new major version.

## Migration Plan

Publish the next major release. Consumers re-vendor that release; no state or
module-input migration is required because only previously missing
implementation files are added.
