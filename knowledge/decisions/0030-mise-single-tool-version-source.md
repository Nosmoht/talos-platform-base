---
type: decision
title: "ADR: mise is the single committed source of every binary tool version"
description: "Replaces .tool-versions, devbox.json and the per-workflow env/with version pins with one mise.toml plus a checksum lockfile that jdx/mise-action reads unchanged in CI; npm-distributed Node tooling stays in package-lock.json because mise's --locked enforcement exempts the npm backend."
status: draft
id: base:mise-single-tool-version-source
decided: "2026-09-06T00:00:00Z"
deciders:
  - maintainer
consulted: []
informed: []
supersedes: []
superseded_by: []
related:
  - /decisions/0012-makefile-retirement.md
  - /decisions/0014-ship-ai-tool-artifacts.md
  - /decisions/0015-openspec-adoption.md
tags: [adr, tooling, version-pinning, ci, supply-chain]
---

# ADR: mise is the single committed source of every binary tool version

## Context and Problem Statement

Twenty-two tools are pinned across forty-five places in six files. `.tool-versions`
carries twelve and declares itself the source of truth; `devbox.json` carries nine
via `@latest`, which pins nothing and lets `devbox.lock` drift; the workflows carry
seventeen literal version values, with `tofu` and `task` written twice each in
`.github/workflows/tofu-validate.yml`; `Taskfile.yml` carries `openknowledge`,
`lychee`, eight hand-transcribed SHA256 constants and three MCP-server versions;
`.pre-commit-config.yaml` carries `gitleaks`; `package.json` carries four npm
packages. Three further SHA256 constants live in the workflows themselves
(`gitops-validate.yml` for `kustomize` and `gitleaks`, `vale.yml` for `vale`).

The drift this produces is measured, not hypothetical. On 2026-09-05 the devbox
resolution stood at `opentofu` 1.11.8 against CI's 1.12.1, `go-task` 3.48.0 against
the pinned 3.53.1, `yq` 4.53.3 against 4.53.6, and `markdownlint-cli` 0.48.0 against
0.49.1. Two further tools are pinned nowhere near `.tool-versions` and have gone
stale unnoticed: `gitleaks` at 8.24.3 against an upstream 8.30.1, and `vale` at
3.14.2 against 3.20.0. A third is pinned nowhere at all: `shellcheck` runs as a
`language: system` pre-commit hook (`.pre-commit-config.yaml:18-22`) at whatever
version the machine happens to carry — and it is the tool whose upstream added
seven new warning codes in a single minor release.

The existing defence is a set of drift-check steps in `gitops-validate.yml` and
`docs-lint.yml` that fail when a workflow `env:` value disagrees with
`.tool-versions`. They work, and they are the reason `task` has not drifted. They
also only cover the copies someone remembered to gate: `devbox.json` has no gate at
all, which is exactly where every drift above sits.

## Decision Drivers

- A tool version should be maintained in one place; today a bump means editing up to four files and remembering which.
- Local and CI must install the same binary, not merely agree on a version string. Today only two assertions check the *binary* rather than the file — `scripts/verify-tools.sh` and the `OK_GUARD` block at `Taskfile.yml:115` — and both are relative to a file pin.
- `devbox.json` pins with `@latest`, so it is not a pin — it is a resolution that moves on the next `devbox update`.
- The eight SHA256 constants in `Taskfile.yml` and the three in the workflows are transcribed by hand from upstream checksum files and re-verified by hand; that is supply-chain-relevant work a lockfile does mechanically.
- The repo has neither `renovate.json` nor `.github/dependabot.yml`, so every one of the forty-five sites is maintained by hand today.
- The base ships no hand-authored agent harness (`AGENTS.md` §Tool Notes), so a contributor's environment must be reproducible from committed files alone.

## Considered Options

1. **mise as the single manifest** — `mise.toml` + `mise.lock`, read unchanged by `jdx/mise-action` in CI.
2. **aqua as the single manifest** — `aqua.yaml` + `aqua-checksums.json`, read by `aquaproj/aqua-installer`.
3. **Generate the copies from `.tool-versions`** — keep every file, add a generator and a regeneration fence.
4. **Automate the bumping instead** — adopt Renovate with custom regex managers over the existing copies, leaving the duplication in place.
5. **Reduce the set of pinned tools** — pin only what demonstrably changes output.
6. **Status quo** — keep three pin classes and the partial drift gates.

## Decision Outcome

Chosen option: **mise as the single manifest**, because every binary the repository
uses was measured installing from it at the exact pinned version — including the one
that is in no public registry — and because its GitHub Action takes no per-tool
version inputs at all, which is what removes the workflow copies rather than merely
keeping them synchronised.

Scope of the decision:

- `mise.toml` becomes the sole committed source for every binary tool version, and `mise.lock` its checksum record. `.tool-versions` and `devbox.json`/`devbox.lock` are deleted. Tools are written in backend-qualified form (`aqua:helm/helm`, `github:owner/repo`), never as registry short names.
- CI installs via `jdx/mise-action`, itself pinned by commit SHA and by its own `version:` input — the one version input that stays, because it pins the resolver of every other version.
- The `setup-opentofu`, `setup-tflint`, `setup-task`, `setup-helm`, `setup-conftest`, `setup-kubeconform`, `action-kustomize` and `setup-oras` steps, the `cosign-release` input on `cosign-installer`, their `env:` version and SHA256 blocks, the two `TASK_VERSION` drift-check steps and the hand-rolled `wget` installs for `yq`, `gitleaks` and `vale` all go away.
- **The `.pre-commit-config.yaml` `gitleaks` hook is in scope**: it becomes a `repo: local` hook calling the mise-managed binary, so `gitleaks` is pinned once. `AGENTS.md` §Tool-Agnostic Safety Invariants names this hook as the authoring-time credential control, so the change carries a two-direction bite-check — non-zero on a planted fixture credential, zero on a clean file — wired into CI, matching how this repository gates its other guards.
- **`shellcheck` and `python3` enter the managed set.** `shellcheck` is a pre-commit hook resolved from PATH at no pinned version today; `python3` backs four gates. Both are named in the manifest, or explicitly exempted with a stated reason.
- The npm-distributed Node tooling — `semantic-release` with its plugins and the `conventionalcommits` preset, `@fission-ai/openspec`, `markdownlint-cli` — **stays** in `package.json` + `package-lock.json`. Two reasons, and the first is decisive: mise's `--locked` enforcement explicitly skips the `npm`, `pipx`, `cargo` and `asdf` backends, so moving these into `mise.toml` would trade integrity-hashed installs for unverified ones. Second, `semantic-release` resolves its plugins from `node_modules`, which a per-binary installer does not provide.
- **`openspec/specs/oci-supply-chain/spec.md` is amended by an `openspec/changes/` delta.** Its requirement "The signing tool's version is pinned and the pin reaches the runner" mandates that the version be declared in `.tool-versions` and passed explicitly to the installing action. This decision repeals both halves and replaces them with a manifest-plus-lockfile mechanism, so the requirement is rewritten rather than silently falsified. `Spec-Impact: none` is not available for this change. The delta must also be **applied** in the same PR: `scripts/check-spec-staleness.py:262` clears the violation only when `openspec/specs/oci-supply-chain/spec.md` itself is in the diff, and that spec lists `oci-publish.yml` as a `primary` source, so a proposal left unapplied leaves a required check red.
- **`shellcheck`, `jq` and `node` receive their first pin.** None of the three is pinned anywhere today, so for them this is not a move but a choice, and each is argued rather than assumed: `shellcheck` is a pre-commit hook and a CI job resolved from PATH (with an `apt-get` fallback that must go, or the job cannot fail closed); `jq` is executed by six committed gates; `node` is written twice as `node-version: 22` in `release.yml`, the workflow that cuts releases, and is the last literal duplicate the change would otherwise leave standing.

Renovate is **not** part of this decision. Once `mise.toml` is the single manifest,
the goal — maintain a version once — is met by hand, and automating the *making* of
that edit is a separate capability that also requires a GitHub App installed on the
repository. It is recorded as a follow-up, and the consolidated layout makes it
cheap: Renovate's native `mise`, `npm` and `pre-commit` managers would cover
everything, with no custom regex manager needed.

### What "one source" does and does not mean here

After this change a maintainer edits **one** file to bump a binary — `mise.toml` —
and **one** to bump a Node package — `package.json`. No tool is named in both.
Three files still carry version data and are deliberately not that single source:
`mise.lock` and `package-lock.json` are generated records rather than edit sites,
and the three `MCP_*_VERSION` constants in `Taskfile.yml` are left to a follow-up
because `task mcp:verify` is not a CI gate. The last of those is a carve-out from
the goal, not a consequence of it, and is named here rather than absorbed into the
claim.

### Consequences

- Positive: one edit per bump. Forty-five sites become one manifest plus one npm manifest.
- Positive: the eleven hand-maintained SHA256 constants and the by-hand re-verification they require are replaced by `mise.lock`. Measured 2026-09-06: a generated lockfile carries seven platform entries per tool (`linux-arm64`, `linux-arm64-musl`, `linux-x64`, `linux-x64-musl`, `macos-arm64`, `macos-x64`, `windows-x64`), each with checksum and resolved URL, produced on a darwin-arm64 host — so the record is not limited to the platform that generated it, and the four-platform support of the current `knowledge:install-cli` is not reduced. The four `openknowledge` checksums it produced are byte-identical to the four constants currently in `Taskfile.yml`.
- Positive: `MISE_LOCKED=1` fails the install when an entry is missing for the current platform instead of falling back to a live lookup.
- Positive: for the `github:` backend, lock entries additionally carry `provenance = "github-attestations"`, and the measured `openknowledge` install reported that the upstream project's GitHub artifact attestations verified — a check the current `curl` plus hand-transcribed-SHA256 path does not perform. This is a property of the `github:` backend and of that upstream's attestations, not of this repository's own, and it is not established for the `aqua:` backend, whose signature verification aqua documents as optional.
- Positive: the *file-versus-file* drift-check steps in `gitops-validate.yml` and `docs-lint.yml` become unnecessary and are deleted, because there is no second copy left to disagree with.
- Negative, and the sharpest one: the *binary-versus-pin* assertions are a different control and are **not** obsoleted. `scripts/verify-tools.sh` and `Taskfile.yml`'s `OK_GUARD` check what PATH actually resolves; a manifest declares what was installed. Deleting them without a replacement would leave a runner-preinstalled or `~/.local/bin` binary free to shadow the pinned one with every file-state check still green. The replacement — asserting that each gate's binary resolves under mise's root at the manifest version — is part of the implementation, not an optional extra.
- Negative: the direnv config activates the environment with a single `eval "$(devbox generate direnv --print-envrc)"`, so it is rewritten in the same change; until it is, every direnv-using contributor gets a failing eval on `cd`. It is a committed file — `.gitignore` excludes the generated `.devbox/` and `.direnv/` caches but not the config itself — so this is a repo edit, not a per-contributor one. Its three comment lines (what it does, that direnv plus a shell hook are prerequisites, and that first activation needs `direnv allow`) are today the **only** onboarding instructions in the repository, since neither `CONTRIBUTING.md` nor `README.md` mentions the toolchain at all. The rewrite carries their mise equivalents rather than dropping them.
- Positive, found while sizing the manifest: `yamllint` is dropped rather than pinned. Its entire footprint was one line in `tofu:lint:yaml`, a task nothing invoked, running `-d relaxed` with stderr discarded and the exit code swallowed by `|| true`, against no config file. It gated nothing, so deleting the task costs no coverage and removes the `pipx` backend — the one backend `--locked` would have exempted from checksum enforcement — from the manifest entirely. The same task's second line duplicated `docs:lint`, which already lints `**/*.md` repo-wide in CI.
- Negative: the repository gains a dependency on the aqua registry's package definitions and on mise itself. Backend-qualified names remove the *name-resolution* half of that trust; the *content* half remains, and it reaches `oci-publish.yml`, the workflow that signs releases.
- Negative, and the bound on the headline claim: four actions ship a tool inside themselves, pinned only by the action's commit SHA and invisible to the manifest — `actions/attest-build-provenance` (`oci-publish.yml:176`), `anchore/sbom-action`, i.e. syft (`:190`), `fsfe/reuse-action` (`gitops-validate.yml:354`) and `ossf/scorecard-action` (`scorecard.yml:47`). Two sit on the release path. Bringing them onto the manifest means replacing each action with a direct binary invocation, which is its own change. So the claim is: every tool **this repository installs itself** is named once. An action SHA is still a pin; it is just not this one.
- Negative: deleting `devbox.json` also deletes the only thing that was floating. Nine of its entries are `<name>@latest`, and `devbox.lock`'s divergence from the hand-written pins is what produced this ADR's own drift evidence. After the change every version is a frozen literal, the repository has no bot (no `renovate.json`, no `dependabot.yml`), and the measurement channel that detected staleness is gone. The Renovate follow-up is therefore not polish: this decision closes a duplication problem and, in the same move, closes the detector for the staleness problem the Context leads with.
- Negative: contributors install mise where they previously installed devbox. Neither `CONTRIBUTING.md` nor `README.md` documents the current devbox onboarding — the mechanism is `.envrc` — so this change writes that onboarding down for the first time rather than editing an existing section.
- Follow-up: adopt Renovate on the consolidated layout. Follow-up: the three `MCP_*_VERSION` constants. Follow-up: ADR-0012's Validation predicate (`devbox.json` carries `yq-go` plus `gettext` and not `gnumake`) becomes unsatisfiable once `devbox.json` is deleted, and needs the bundle's partial-supersession form — a dated banner in 0012 plus a section-qualified `supersedes` here — when this ADR leaves draft.
- Follow-up: seven knowledge-bundle locations describe the deleted artifacts as current state (`reference/manifest-pipeline.md:128`, `reference/tasks.md:34`, `:174`, `:175`, `workflows/spec-driven-development.md:117`, `:125`, `decisions/0015-openspec-adoption.md:229`), as do `scripts/render-component.sh:28`, `scripts/lint-hardware-features.sh:39` and `Makefile:31`.

## Pros and Cons of the Options

### Option 1 — mise

- Pro: `jdx/mise-action`'s inputs (`version`, `install`, `install_args`, `cache`, `bootstrap`) govern mise itself; no input carries a target-tool version, so CI has nothing to keep in sync.
- Pro: the backend set covers every distribution shape this repo needs — `aqua:` for the registry tools, `github:` for arbitrary GitHub-release binaries (the deprecated `ubi:` backend's successor), `npm:` and `pipx:` for the rest.
- Pro: `mise.lock` records per-platform checksum plus resolved URL for every platform the tool publishes, and `MISE_LOCKED=1` fails closed when an entry is absent.
- Pro: Renovate has a native `mise` manager, so the follow-up automation needs no hand-written regex.
- Pro: mise-action caches installed tools by default.
- Con: `--locked` does not enforce checksums for the `npm`, `pipx`, `cargo` and `asdf` backends — they are skipped rather than failed. This is why the Node tooling stays on npm. No other manifest entry uses those backends.
- Con: the version-manager layer becomes a dependency of every local workflow and every CI job, including the release-signing one.

### Option 2 — aqua

- Pro: `aquaproj/aqua-installer` likewise takes no target-tool versions as inputs.
- Pro: the strongest verification story of the candidates — `aqua-checksums.json` plus optional per-package Cosign, SLSA-provenance and GitHub-attestation verification, and a fail-closed `aqua-policy.yaml`.
- Con: no first-class npm or pipx distribution type was found in its configuration reference, so the Node tooling could not be expressed there even if the `--locked` gap did not exist.
- Con: whether Renovate has a native `aqua.yaml` manager was not confirmed; if it does not, the manifest becomes hand-maintained again.
- Note: mise reaches aqua's registry through its `aqua:` backend, so choosing mise keeps most of aqua's package coverage without adopting a second manifest format.

### Option 3 — generate the copies from one source

- Pro: keeps devbox for contributors who prefer nix, and needs no new runtime in CI.
- Con: every copy still exists on disk; a reader still has to know which file is authoritative.
- Con: the generator and its regeneration fence are themselves new artifacts to maintain, and the failure mode — a stale generated file — is the one being solved.

### Option 4 — automate the bumping (Renovate over the existing copies)

- Pro: solves the stated goal literally — one maintainer action per bump — without restructuring anything.
- Pro: Renovate has native managers for `.tool-versions` (`asdf`), `mise.toml` (`mise`) and `devbox.json` (`devbox`).
- Con: Renovate's `github-actions` manager extracts `with:` version inputs only for a curated list of roughly twenty-five known actions. `opentofu/setup-opentofu`, `terraform-linters/setup-tflint` and `hashicorp/setup-terraform` are **not** on it, and no hand-written `env: KUSTOMIZE_VERSION:` pin is. Those need custom regex managers — hand-written matchers that can drift from the actions they target when an input is renamed.
- Con: grouping a native manager's update and a regex manager's update into one PR requires both to extract the same `depName`. A mismatched `matchStrings` desynchronises one copy silently, with no error — the same failure class as today, with more machinery.
- Con: it keeps the version written N times, so nobody can answer "which kustomize does this repo pin" from one file, and it does nothing about a tool pinned nowhere (`shellcheck`) or pinned only as a checksum.
- Note: Dependabot cannot do this at all. It has no regex or custom-manager primitive and cannot read `.tool-versions`, `mise.toml`, `devbox.json` or a hand-written CI version literal.

### Option 5 — pin fewer tools

- Pro: the cheapest change available; a tool whose version cannot affect a committed artifact or a CI verdict does not need managing.
- Con: the exemption is narrower than it looks, and the reason is qualitative rather than arithmetic. `shellcheck` v0.11.0 added seven new warning codes (SC2327–SC2332, SC3062), any of which turns a previously green run red. HashiCorp documents that `terraform fmt`'s canonical format changes between minor versions and states this is deliberately not treated as a breaking change; the same code path backs `tofu fmt`. Conftest's default Rego syntax version changed across releases, which moves policy verdicts with no policy edit. These are the tools this repository's gates rest on, so the exemption cannot reach them.
- Con: after removing what is genuinely exempt — `ripgrep`, `curl`, `envsubst` — the saving is three tools, so it does not address the maintenance cost. Their exemption is from *pinning*, not from *provisioning*, and the two are easy to conflate: `scripts/render_kustomize_safe.sh:9-13` exits 2 without `rg` because ksops detection would otherwise fail open and render an encrypted manifest as plaintext, and `scripts/check-bootstrap-render.sh:34` fails closed without `envsubst`. Which version runs does not matter; that one runs does. `devbox.json` is their only provisioner today and macOS ships no `envsubst`, so deleting it without a replacement breaks `task gitops:validate` on a maintainer's own machine.
- Con: it also cannot reach the tool it looks most likely to exempt. `shellcheck` has no pin to reduce — it is pinned nowhere today — so this option leaves it floating rather than shrinking anything. Measured 2026-09-06 on darwin-arm64: `shellcheck` 0.11.0 under the exact CI invocation (`git ls-files -z '*.sh' | xargs -0 -r shellcheck -S warning`) exits 0 over all forty-four tracked scripts, so adopting the newest release as its first pin does not turn the job red — the seven new codes do not fire on this tree.
- Note: two motivations for pinning are in play and the literature names neither as a pair. One is reproducibility, where the tool writes an artifact whose bytes are compared (`tofu fmt`, `helm template`, `kustomize build`). The other is gate stability, where the tool emits findings and an upgrade adds new ones (`shellcheck`, `markdownlint`, `conftest`). SLSA v1.0 does separate "pinned dependencies" from "Hermetic", but that is build-input control versus network isolation — a different axis. This ADR keeps both motivations explicit rather than adopting a coined term for the distinction.

### Option 6 — status quo

- Pro: no work, and the existing drift gates do hold the sites they cover.
- Con: they cover the sites someone remembered to gate. Every measured drift sits outside them, and one tool is pinned nowhere at all.

### Rejected without a full comparison

`proto`, `hermit` and `asdf` each have a first-party action that reads a committed
manifest, and `devbox` has `jetify-com/devbox-install-action`. For the first three
the decisive property could not be confirmed: whether the manifest can declare a
goreleaser-style binary published only as a GitHub Release asset. For devbox the
answer is determined locally and is no — `devbox search openknowledge` returns no
results, because nixpkgs does not carry it, and the npm-distributed tools have no
devbox expression either. asdf carries an additional signal rather than a
disqualification: at least one large downstream project has moved off it to mise
citing maintenance overhead, which is ecosystem drift and not a statement by the
asdf project.

## Rollback

The change deletes forty-five pin sites, two CI gates, `scripts/verify-tools.sh`,
the tool-pin half of `dev:verify-pins` and a four-platform installer. Backing out
after merge means restoring them from git history, and `devbox.lock`'s resolutions
will have fallen further behind by then.

The exit is cheap but not free. The change lands as a merge commit — `AGENTS.md`
§Tool-Agnostic Safety Invariants records `merge_commit_message=BLANK` with squash
and rebase merges disabled — so backing it out is `git revert -m 1`, and re-landing
later means reverting the revert. For fifteen of the eighteen manifest entries the
restore is mechanical, because `mise.toml` carries the same version strings the
deleted files carried; for `shellcheck`, `jq` and `node` it is a deletion, since
those three had no prior pin anywhere.

Triggers, all post-merge, since the pre-merge measurements simply block the merge:
a release that cannot be signed or verified through the manifest-installed `cosign`;
a gate whose verdicts moved under the new binaries and cannot be reconciled; or
contributors unable to bootstrap on a supported platform. The pre-merge condition —
the install-cost budget below — is not a rollback trigger.

## Validation

Measured 2026-09-06 on darwin-arm64 against an isolated `MISE_DATA_DIR`: every tool
this repository pins today installed at its exact pinned version — eighteen
binaries, not a sample. This measures mise's *backend coverage* across today's whole
inventory; it is not the future `mise.toml` membership set. Three entries differ
deliberately: `npm:@fission-ai/openspec` is measured here but **stays** in
`package.json` per the Decision Outcome; `pipx:yamllint` was measured before the
tool was dropped, so it is backend evidence and not a manifest entry; and `node` is
in the manifest but has no prior pin to install at, so the implementation PR
measures it instead.

- `github:openknowledge-sh/openknowledge@0.12.0` — installed, selected the `darwin_arm64` asset, reported the upstream project's GitHub artifact attestations as verified, and `openknowledge version` printed `0.12.0`. This is the binary that is in no public registry and the one that decides the whole option.
- `aqua:` backend — `helm/helm@4.2.4`, `kubernetes-sigs/kustomize@5.8.1` (whose upstream tag form is `kustomize/vX.Y.Z`), `sigstore/cosign@3.1.3`, `oras-project/oras@1.3.4`, `open-policy-agent/conftest@0.69.0`, `yannh/kubeconform@0.8.0`, `mikefarah/yq@4.53.6`, `lycheeverse/lychee@0.24.2`, `vale-cli/vale@3.14.2`, `gitleaks/gitleaks@8.24.3`, `opentofu/opentofu@1.12.1`, `terraform-linters/tflint@0.61.0`, `go-task/task@3.53.1`, `terraform-docs/terraform-docs@0.22.0`, `koalaman/shellcheck@0.11.0`, `jqlang/jq@1.8.1` — all installed.
- `npm:@fission-ai/openspec@1.11.0` — installed. (`pipx:yamllint@1.37.1` was measured too, before the tool was dropped; the measurement stands as backend evidence and the entry does not enter the manifest.)
- A generated `mise.lock` carried seven platform entries per tool with checksums and URLs, and its four `openknowledge` checksums matched the four constants in `Taskfile.yml` byte for byte.

**Not yet verified, and gating the implementation PR:**

- The same installs on `ubuntu-latest`, through `jdx/mise-action` rather than a local `mise install`, asserting exit 0 and the exact version for every manifest entry.
- That each gate's binary resolves under mise's install root at the manifest version, asserted by `mise which` rather than by `command -v` — a shim path is the same string whichever version it dispatches to, so it carries no version information. The assertion runs in **every** job that executes a pinned tool, `oci-publish.yml` included, and locally as a dependency of the gate targets, because the `OK_GUARD` it replaces was a local in-shell control. One step in one job is not the same control.
- That the pins still hold their artifacts stable. The primary evidence is already mechanical and already required: `scripts/verify-rendered.sh` fails on any drift from the committed `_rendered/` bytes, and `tofu:fmt:check` plus `tofu:check:render-determinism` cover the OpenTofu side — their "before" bytes are in git, so no hand-run baseline is needed. Only the non-committed kustomize render set needs a manual `sha256sum` before and after. The reference side is *the versions this PR pins, installed by today's mechanism*, so pre-existing version drift is excluded by construction rather than surfacing as a false difference. Process stdout stays the wrong comparand — three of the four validation targets emit host- and network-dependent text.
- That the release path still signs. `oci-publish.yml` triggers on tag push only, so no branch CI run exercises it; the evidence is a pre-release tag against a throwaway registry, with `cosign verify` succeeding on the produced digest.
- That the `gitleaks` pre-commit hook still bites in both directions after becoming a local hook.
- What the aqua registry's package definition for `sigstore/cosign` actually resolves to. This change replaces `sigstore/cosign-installer` — a first-party installer maintained by the signing project — with `aqua:sigstore/cosign@3.1.3` plus one `mise.lock` checksum, on the workflow that signs releases. The lock pins the bytes once recorded, but whoever can land a package definition in the aqua registry chooses the URL the next lock regeneration fetches from. Read the definition before the lock is committed.
- The CI install cost, measured **per job** — mise installs once per job, while today's `setup-*` steps are spread across parallel jobs, so a single cross-workflow sum corresponds to no observable wall clock. For each job: the `jdx/mise-action` step's duration against the summed duration of the `setup-*` steps it replaces *in that same job*, both sides cache-miss, median of three runs, read from the run's step durations. The baseline must be captured on `main` before the deletion lands; afterwards it is unrecoverable. **The decision is wrong** if any job exceeds 1.5×.

This ADR is `draft` and stays draft until the list above is observed. The option
comparison is settled and the mechanism is measured — that is what makes the record
worth writing now — but one open item is decision-level rather than
implementation detail: the per-job install-cost budget is this decision's stated
falsification condition. Marking the ADR `stable` while it is unmeasured would
assert more than has been observed, which is the failure this section exists to
prevent.

## Links

- Issue [#259](https://github.com/Nosmoht/talos-platform-base/issues/259) — the implementation this decision authorises
- `AGENTS.md` §Build, Test, and Development Commands — the task surface this changes
- `openspec/specs/oci-supply-chain/spec.md` — the requirement this decision repeals and replaces
- [ADR-0012](0012-makefile-retirement.md) — the prior consolidation, whose devbox-based Validation predicate this decision retires
- [ADR-0015](0015-openspec-adoption.md) — the spec-delta obligation this change triggers
- mise backends — <https://mise.jdx.dev/dev-tools/backends/>
- mise lockfile — <https://mise.jdx.dev/dev-tools/mise-lock.html>
- `jdx/mise-action` — <https://github.com/jdx/mise-action>
- aqua-installer — <https://aquaproj.github.io/docs/products/aqua-installer/>
- Renovate `github-actions` manager, including the curated `with:`-input list — <https://docs.renovatebot.com/modules/manager/github-actions/>
- Renovate custom (regex) managers — <https://docs.renovatebot.com/modules/manager/regex/>
- Dependabot supported ecosystems — <https://docs.github.com/en/code-security/dependabot/ecosystems-supported-by-dependabot/supported-ecosystems-and-repositories>
- `terraform fmt` canonical-format drift across minors — <https://developer.hashicorp.com/terraform/cli/commands/fmt>
- ShellCheck releases (v0.11.0 new warning codes) — <https://github.com/koalaman/shellcheck/releases>
