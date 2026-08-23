---
type: decision
title: "ADR: Consumer-supplied schematic extra_kernel_args, cross-source-scoped"
description: "Adds an optional per-image extra_kernel_args input reaching the Image-Factory schematic's UKI-correct kernel-arg sink, and re-scopes the kernel-arg conflict guard to cross-source collisions only, closing a consumer footgun without a bottomless key allowlist."
status: stable
id: base:consumer-image-kernel-args
decided: "2026-07-15T00:00:00Z"
deciders:
  - platform-maintainer
consulted: []
informed: []
supersedes: []
superseded_by: []
related:
  - "[Capability profiles carry only their presence_predicate args (the profile-side ownership this input frees)](./0016-capability-profiles-predicate-only.md)"
  - "[Node Capability Composition (the composition model this input extends)](./0009-node-capability-composition.md)"
  - "[Module-delivered Cilium + cluster.yaml as the declarative cluster SoT (the declarative path this input must reach)](./0007-cluster-yaml-sot.md)"
tags: [adr, talos, capability, schematic]
---

# ADR: Consumer-supplied schematic extra_kernel_args, cross-source-scoped

## Context and Problem Statement

A consumer cluster has no supported way to set custom kernel command-line
arguments on nodes that boot via UKI / systemd-boot (the Talos v1.10+ default
for fresh metal UEFI installs). `tofu/modules/talos-cluster` builds the
Image-Factory schematic field `customization.extraKernelArgs` — the
UKI-correct sink — but feeds it exclusively from the base-owned
`provisioning_profiles` catalog. The only consumer escape hatch,
`config_patches`, is a machine-config patch and cannot reach the schematic:
the schematic is built from `images` + `hardware_capabilities` before, and
independently of, the per-node machine config.

**Root cause (Tier-1, Talos upstream).** On systemd-boot/UKI,
`machine.install.extraKernelArgs` is ignored — kernel args are embedded in the
UKI and can only change by upgrading the UKI (Sidero Docs, Talos v1.12
Boot Loader page). Maintainer `@smira` on the endorsed path: "you would use
Image Factory all the way" (siderolabs/talos#11145). `grubUseUKICmdline` is
GRUB-scoped and provides no path for an sd-boot node. A consumer that
relocates kargs into `machine.install.extraKernelArgs` today hits
`install.extraKernelArgs and install.grubUseUKICmdline can't be used
together` at `talosctl upgrade` and cannot roll the node.

**Issue #171 (merged the same day) is the direct predecessor**: it removed
`iommu=pt` — host-DMA tuning, not part of the `iommu-enabled` contract — from
the `iommu` profile, explicitly deferring its replacement to this issue (its
own §Consequences: "#169 ... is the supported path to re-add `iommu=pt` as an
explicit consumer choice"). Before #171, the profile-kernel-argument sink was
total base ownership (`0016-capability-profiles-predicate-only.md`,
`hardware-capability-composition` spec's now-superseded "the module exposes no
consumer kernel-argument input at all"); this ADR is the change that ends that
total ownership.

## Decision Drivers

- Per-image granularity matches the schematic's own composition unit; a
  per-node override is a separately-scoped future concern (issue §Non-Goals).
- Shipping the union alone, without re-scoping the conflict guard, is a
  silent-corruption bug: a consumer arg colliding with a profile arg would
  land on the cmdline *alongside* it with no error and no hint, and the
  kernel picks arbitrarily between two values for one key.
- Kernel-arg repeat semantics are defined per parameter handler, not by a
  single global rule — the class of legitimately-repeatable keys
  (`hugepagesz=`/`hugepages=` per huge-page size, `acpi_osi=`, …) is
  open-ended, so a key-list solution to the guard-scoping problem does not
  terminate.
- A consumer owns their own repo; a typo confined to a consumer's own arg list
  is not this base's defect class to guard.

## Considered Options

1. **Union the image's `extra_kernel_args` into `node_effective.kernel_args`,
   and re-source the conflict guard onto that UNIONED set** (the issue body's
   original proposal).
2. **Union the input, and scope the conflict guard to cross-source collisions
   only** — a key is checked only when a selected profile contributes it AND
   the image sets a differing value (chosen).
3. **Union the input with no guard change at all** — rejected outright: the
   silent-corruption bug this issue exists to close.

## Decision Outcome

Chosen option: **2 — cross-source-scoped guard**, because option 1 constructs
a new false-positive class: re-sourcing the guard onto the whole unioned set
groups every arg on a node by key, including two args from the SAME
consumer list. `extra_kernel_args = ["hugepagesz=2M", "hugepages=512",
"hugepagesz=1G", "hugepages=8"]` — a legitimate multi-huge-page-size
idiom per `Documentation/admin-guide/kernel-parameters.txt` ("The pair
hugepagesz=X hugepages=Y can be specified once for each supported huge page
size") — would hard-fail the plan under option 1, with an error naming
provisioning profiles as a possible source when no profile touches those keys
at all. This failure is *constructed by the change*: pre-change, the guard
reads profile-resolved args only, so no consumer arg could ever reach it.
Extending the multi-value exemption list is not a fix, because the
repeatable-key class is open-ended (confirmed above); a key allowlist is a
bottomless denylist-by-inversion.

### Consequences

1. **The guard must read both sources, or a collision lands both args on the
   cmdline.** Shipping the union (`node_effective.kernel_args`) without the
   guard change is the silent-corruption bug this issue exists to close; they
   ship in the same commit.
2. **The guard is cross-source-scoped — profile-contributed keys only.**
   Checked only when a selected profile contributes a key AND the image's
   `extra_kernel_args` sets it to a differing value. This is a deliberate
   choice over the issue body's original union-set proposal, made because the
   kernel's repeatable-key class is open-ended, so a key allowlist would be a
   bottomless denylist-by-inversion. Recorded on issue #169's blocking-lens
   findings (2026-07-15) and mechanically bound by
   `tests/conflict-guards.tftest.hcl`'s `consumer_only_key_is_not_guarded` run,
   which reds under exactly the union-set mutant this decision replaced.
3. **Accepted residual**: a consumer typo confined to their OWN
   `extra_kernel_args` list (e.g. `["intel_iommu=on", "intel_iommu=off"]` on a
   node selecting no `iommu` capability) is not guarded. A consumer owns their
   repo; this is not this base's defect class.
4. **The four multi-value keys (`console`, `module_blacklist`,
   `initcall_blacklist`, `blacklist`) coexist across sources by design**: the
   exemption applies whenever a selected profile contributes one of these
   keys, regardless of whether the image also contributes a value for it.
5. **AC9's four lexical rules (no whitespace, no removal-spelling prefix, no
   empty key, no `debugfs` key) are guardrails against a documented footgun,
   not a security boundary** — a consumer owns their repo. They close the
   spellings that defeat the guard's `=`-keying (a whitespace-joined element
   smuggles a second arg past the guard; a leading `=` or the bare empty
   string both key as `""`). They do **not** close cross-key semantic override:
   `iommu=pt` beside a profile's `intel_iommu=on` keys differently, so no
   guard fires — that is a different key entirely, correctly outside this
   guard's scope. The whitespace rule is deliberately ASCII-scoped
   (`[[:space:]]`, not a Unicode `\s`): the kernel splits the cmdline on ASCII
   space/tab, so a non-breaking space (U+00A0) stays inside its token and is
   not a cmdline-smuggle vector — the narrower class is the *correct* scope,
   not a gap.
6. **The schema (`schemas/cluster.schema.json` `$defs.image.properties.
   extra_kernel_args.items`) MIRRORS the four lexical rules**, following the
   in-repo precedent `tests/input-validation.tftest.hcl` already records for
   the version patterns (mirrored and bound red-green via
   `schemas/fixtures/cluster.invalid.yaml` in `gitops-validate.yml`). Rationale:
   `.github/workflows/hard-constraints-check.yml` scopes its diff to
   `kubernetes/**`/`tofu/**`, so the repo-root `cluster.yaml.example` — the
   template `task cluster:init-yaml` seeds every consumer from — sits outside
   every hard-constraint gate; the schema mirror is the only gate that reads a
   `cluster.yaml`-shaped file for this input. The module-side validation stays
   necessary regardless — it guards every caller, including one wiring the
   module interface by hand, bypassing `cluster.yaml` entirely. **Named
   residual**: both sides are red-green bound independently (a one-sided
   relaxation reds its own gate), but nothing binds the two rule sets *to each
   other* — a semantic divergence between them (e.g. the module side changing
   to a Unicode-aware whitespace class) is caught only by review, not by a
   gate.
7. **`check-jsonschema` is installed unpinned** in `gitops-validate.yml`
   (`python3 -m pip install --user check-jsonschema`, no version constraint).
   This change triples the repo's exposure to that tool's instance-path output
   format (two pinned `grep -qF` literals become six). An upstream reporter
   change could red the required check on an unrelated PR with a message
   asserting a schema regression that did not occur; the cheapest-looking
   green in that situation is deleting the new literals, which would silently
   unbind the schema mirror. Not fixed here (pinning the dependency is an
   unrelated CI change, out of this issue's scope) — named so the next reader
   of an unexplained red on this step checks the tool version before touching
   the fixture.
8. Positive: a consumer on UKI/systemd-boot now has a supported path for boot
   kernel-arg tuning (perf/security flags, huge pages, `iommu=pt` as explicit
   consumer choice post-#171) without the drift-prone hand-baked
   Image-Factory-URL alternative.
9. Negative: none for an existing consumer setting no `extra_kernel_args` — the
   type's `optional(list(string), [])` default composes byte-identically to
   pre-change (bound by AC6).
10. Follow-up: none identified. The declarative `cluster.yaml` path and the
    programmatic module-interface path are both reachable as of this change.

## Pros and Cons of the Options

### Option 1 — re-source the guard onto the unioned set

- Pro: simplest possible read — one iteration source instead of two.
- Con: constructs a false-positive class over the multi-huge-page-size idiom
  and any other legitimately-repeatable key, confirmed by kernel
  documentation (see §Validation).
- Con: the false-positive's error message would name provisioning profiles as
  a possible source when no profile is involved at all — actively misleading.

### Option 2 — cross-source scoping (chosen)

- Pro: closes the silent-corruption bug (a profile/image collision still
  fails the plan) without inventing a new false-positive class.
- Pro: the repeatable-key problem dissolves — a key no profile touches is by
  definition not a profile/image collision, so no allowlist is needed for it.
- Con: a consumer-vs-consumer typo on a key no profile touches is not caught
  (accepted residual, §Consequences item 3).

### Option 3 — union with no guard change

- Con: rejected outright — this is the silent-corruption bug the issue names,
  not a considered trade-off.

## Validation

**Kernel-semantics evidence (Tier-1, kernel.org):**

- `Documentation/admin-guide/kernel-parameters.txt`: "The pair hugepagesz=X
  hugepages=Y can be specified once for each supported huge page size."
- kernel.org v4.14 admin-guide: this option "can be specified multiple times
  interleaved with hugepages= to reserve huge pages of different sizes"
  (x86-64 and powerpc).
- `docs.kernel.org/admin-guide/mm/hugetlbpage.html`: the uniqueness
  constraint is per huge-page **size**, not per key.
- No general duplicate-key rule exists: repeat semantics are defined per
  parameter handler. `acpi_osi=` is a further Tier-1-confirmed repeatable key
  beyond the four already-exempted ones.

**Mechanical checks:**

- `tests/conflict-guards.tftest.hcl` — `image_karg_conflicting_with_a_profile_
  karg_fails_the_plan` (AC3) and `image_karg_restating_a_profile_karg_is_not_a_
  conflict` (AC4) bind the cross-source collision and its verbatim-restatement
  non-collision; `consumer_only_key_is_not_guarded` binds the guard scoping
  itself against the union-set mutant this decision replaced;
  `an_exempt_multivalue_key_coexists_across_sources` binds the multi-value
  exemption's cross-source coexistence.
- `tests/image-kernel-args.tftest.hcl` — binds the union's order/dedup
  mechanics (`sort()`, both `concat` legs), an existing shipped-catalog
  consumer's schematic hash staying unchanged when `extra_kernel_args` is
  unset (AC6), and a changed `extra_kernel_args` changing the schematic hash
  (AC2).
- `tests/composition.tftest.hcl` — `image_extra_kernel_args_land_in_the_
  rendered_schematic` (AC1, network) binds the actual rendered
  `customization.extraKernelArgs` containing both the image's and the
  profile's args.
- `tests/input-validation.tftest.hcl` — four isolated runs (AC9) plus a
  well-formed positive control bind the module-side lexical rules.
- `schemas/fixtures/cluster.invalid.yaml` + `gitops-validate.yml` — six-way
  red-green binding for the schema mirror (role enum, version pattern, and one
  fixture per kernel-arg lexical rule).

**How we would know this decision is wrong:** a future consumer reports a
cross-source collision that this guard's scoping does not catch despite
involving a selected profile's karg (a defect in the scoping logic, not the
accepted consumer-vs-consumer residual) — that would mean re-deriving the
cross-source predicate. A future OpenTofu/Terraform release changing tuple-vs-
list equality semantics (see the implementation summary's noted deviation) or
a `check-jsonschema` release changing its instance-path format (§Consequences
item 7) are the two named tooling residuals to check first when a bound test
reds without an accompanying code change.

## Links

- Sidero Docs — Boot Loader (Talos v1.12) —
  https://docs.siderolabs.com/talos/v1.12/platform-specific-installations/bare-metal-platforms/bootloader
- siderolabs/talos#11145 (maintainer guidance: "Image Factory all the way") —
  https://github.com/siderolabs/talos/issues/11145
- Kernel command-line parameters —
  https://www.kernel.org/doc/html/latest/admin-guide/kernel-parameters.html
- HugeTLB Pages admin guide —
  https://docs.kernel.org/admin-guide/mm/hugetlbpage.html
- Issue #169 (this decision's tracker record, including the owner's
  cross-source-scoping decision comment)
- Issue #171 / `0016-capability-profiles-predicate-only.md` (the direct
  predecessor this ADR's follow-up closes)
