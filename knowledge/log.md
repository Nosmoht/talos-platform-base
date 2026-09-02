# Changelog

## 2026-09-02

- `reference/manifest-pipeline.md`: the I6 entry records that the steady-state
  assertion also runs on the kustomize-built component, and that a non-matching
  policy set is a violation rather than a render-shape error.
- `reference/argocd-sso-contract.md`: the cited invariant range is I1-I6.
- `reference/manifest-pipeline.md`: the I6 entry records the apiVersion/namespace
  and named-port bindings, the foreign-policy-kind rejection, the corrected reason
  the steady-state assertion runs on the kustomize build, and that
  `argocd-applicationset-controller` is deliberately unpoliced.
- `decisions/0025-argocd-crd-apply-scope.md`: addendum — the revisit trigger the
  record sets was discharged at argo-cd chart `10.6.0`; the CRD templates' directive
  list and the byte-identical cross-`--kube-version` render both still hold.
- `reference/manifest-pipeline.md`: refresh the ArgoCD substrate-invariant
  inventory through I6/P and record the NetworkPolicy posture bite-check.
- `architecture/day-zero-bootstrap.md`: refresh the two-render-path invariant
  inventory through I6/P after the NetworkPolicy gate was strengthened.
- `reference/argocd-sso-contract.md`: include the `policy.default` I5 guard in
  the identity-free substrate invariant range.
- `reference/tasks.md`: refresh the local `gitops:validate` sequence with the
  NetworkPolicy bite-check and the existing bootstrap/Cilium tail checks.

## 2026-08-28

- `workflows/issue-lifecycle.md`: `generated.at 2026-08-28`. The session-start
  ritual now lists the `gh` commands the root AGENTS.md declares, with the MCP
  server named as the optional accelerator it is.
- `project/harness-plugin-contract.md`: `generated.at 2026-08-28`. The
  no-hand-authored-primitives statement is attributed to `AGENTS.md` §Tool Notes,
  where it now lives.
- `architecture/substrate.md`, `architecture/day-zero-bootstrap.md`,
  `glossary.md`: `verified 2026-08-28` — read against their `AGENTS.md` source
  after that file was restructured; no claim in them moved.
- `rules/talos-base-bundle.md`: three trigger bullets added — when to update a
  concept, when to record a decision, when to document a schema. They carry the
  content of the three built-in `openknowledge` rules the Taskfile no longer
  renders, so the maintenance mandate stays stated.
- `rules/talos-base-bundle.md`: `generated.at 2026-08-28`. The config file
  the link-target convention names is spelled `knowledge/.openknowledge.toml`;
  the bare basename read as a repo-root path in the rendered AGENTS.md block.
- `decisions/0026-machine-config-apply-mode.md`: new. Records the per-role
  `apply_mode` inputs, why the default is `auto` rather than a staging mode, why
  `staged_if_needing_reboot` was rejected, and why `talos_machine` cannot carry
  the same capability.

## 2026-08-27

- `workflows/release-process.md`: `generated.at 2026-08-27`. §Commit gate no
  longer states that the PR-title lint is a required status check or that
  squash-merge is disabled; both describe settings that are not applied. It now
  names the outstanding branch-protection change and the check that fails until
  it lands.
- `decisions/0020-automated-release-no-approval-gate.md`: the §Amendment clause
  claiming Check 4 blocks the amending change from merging is removed; the
  paragraph two sentences later already records that Check 4 is a local-admin
  gate, not a CI gate.
- `decisions/0020-automated-release-no-approval-gate.md`: §Amendment gains the
  paragraph recording why `_rendered-overlay/kustomization.yaml` is deliberately
  outside the guarded set and what the two `:(glob)` entries do; the reasoning
  moved here out of `.ci-release-guard-pathspec.txt`'s header.

## 2026-08-25

- `decisions/0020-automated-release-no-approval-gate.md`: added a `history:` key
  and an `## Amendment (2026-08-25)`. The amendment corrects the surface set
  (`kubernetes/base/**` -> the committed pathspec file), supersedes the
  squash-merge sentence in §Decision 3, records the guard's departures from its
  original logic and three residuals, and marks the notification follow-up
  shipped. The Decision section is unchanged.
- `workflows/release-process.md`: `generated.at 2026-08-25`. The §MAJOR-bump
  guard bullet now points at `.ci-release-guard-pathspec.txt` instead of listing
  the set; both squash-merge sentences are rewritten; §Commit gate states what
  the PR-title lint actually buys; a new §When the release is blocked carries the
  recovery procedure and is named the authoritative copy, with subsections for a
  `guard error` verdict and for reverting the guard itself; §CHANGELOG contract
  describes the `### Pending release` / historical-backfill split. `sources:`
  gains `scripts/release-major-bump-guard.sh`, `scripts/release-guard-lib.sh`
  and `.ci-release-guard-pathspec.txt`.
- `reference/tasks.md`: the `supply-chain:*` heading widens to "OCI artifact +
  release-gate verification" and gains the `supply-chain:check-release-guard`
  row.

## 2026-08-23

Two changes, one day: the pinned `openknowledge` CLI moved 0.5.0 -> 0.12.0, and
the bundle moved from OKF v0.1 field style to v0.2. Why each thing was done is
in the commit that did it; this list is what changed, per concept.

- `.openknowledge.toml`: renamed from `openknowledge.toml` — 0.12.0 reads the config only under the dotfile name and only from inside the bundle, so the old file was inert and both raises had degraded to warnings. `"okf-0.2-metadata"` and `okf-version` raised to error; `link-target` and `rule-catalog` unchanged; `markdown-syntax` stays at warn.
- `architecture/capability-composition.md`: `generated.at 2026-07-15`, `verified 2026-08-14`. Git: the 2026-08-14 commit changed only the `timestamp:` line. The only row with no corroborating log bullet.
- `architecture/day-zero-bootstrap.md`: `generated.at 2026-08-14`, `verified 2026-08-12`. Content change under 2026-08-14; the 2026-08-12 re-verification is kept although it predates it.
- `architecture/substrate.md`: `generated.at 2026-08-14`, `verified 2026-07-17`. §What ships in the OCI artifact corrected under 2026-08-14; re-verified against the implemented branch under 2026-07-17.
- `glossary.md`: `generated.at 2026-08-14`, `verified 2026-07-17`. The `helm_template` freeze wording changed on 2026-08-14; same 2026-07-17 re-verification bullet as `substrate.md`.
- `project/harness-plugin-contract.md`: `generated.at 2026-07-13`, no `verified`. The "ships no `.claude/`" statements were rewritten under 2026-07-13 without bumping the key, so the old 2026-07-11 value was stale and moves forward.
- `project/openssf-self-assessment.md`: `generated.at 2026-07-15`, no `verified`. Created 2026-07-15, no later entry.
- `project/vision.md`: `generated.at 2026-07-11`, no `verified`. Created with the bundle, no later entry.
- `reference/argocd-sso-contract.md`: `generated.at 2026-08-14`, no `verified`. New concept under 2026-08-14; nothing has read it back since.
- `reference/cluster-yaml.md`: `generated.at 2026-08-14`, `verified 2026-08-14`. Both on the same day and both recorded: a new §How CI binds the schema to the shim, and "re-verified against the widened `schemas/cluster.schema.json`".
- `reference/manifest-pipeline.md`: `generated.at 2026-08-14`, no `verified`. §ArgoCD substrate invariants updated under 2026-08-14.
- `reference/tasks.md`: `generated.at 2026-08-23`, no `verified`. Rewritten again in this change — the `knowledge:validate` and `knowledge:new` rows — so the 2026-08-23 reading recorded earlier in this section no longer covers its content. Also re-read against its sources and corrected: the rules-apply row named the pre-0.12 command, the `knowledge:validate` row now describes all three gates and the version precondition, and the openknowledge/lychee pin values are replaced by the Taskfile variable names.
- `rules/talos-base-bundle.md`: `generated.at 2026-08-23`, no `verified`. Nine bullets become fifteen here; authoring is never verifying, so the file does not certify its own edit. Its re-verification criterion was also narrowed to "a change that lands inside what the concept describes", and it gained the rule to invoke the CLI through the `knowledge:*` targets rather than bare.
- `workflows/first-consumer-cluster.md`: `generated.at 2026-08-14`, `verified 2026-08-12`. Day-2 narration changed under 2026-08-14; the 2026-08-12 re-verification is kept although it predates it.
- `workflows/issue-lifecycle.md`: `generated.at 2026-07-11`, no `verified`. Created with the bundle, no later entry.
- `workflows/mcp-setup.md`: `generated.at 2026-07-11`, no `verified`. Created with the bundle, no later entry.
- `workflows/release-process.md`: `generated.at 2026-07-29`, no `verified`. Content changed 2026-07-29 without bumping the key, so the old 2026-07-21 value was stale and moves forward.
- `workflows/spec-driven-development.md`: `generated.at 2026-08-12`, `verified 2026-08-23`. Content change under 2026-08-12; "re-read against its sources ... needed no edit beyond the date" earlier in this section. Re-read against its sources at the CLI bump; no edit was needed beyond the date.
- `workflows/verify-release.md`: `generated.at 2026-07-11`, no `verified`. Created with the bundle, no later entry.
- `decisions/0001-multi-repo-platform-split.md`: `decided 2026-04-27`. Its own `history:` first entry; the old `timestamp` of 2026-05-18 was the third amendment.
- `decisions/0002-namespace-ownership-rendered-manifests.md`: `decided 2026-05-18`. Its body: "2026-05-18 initial: Architecture C accepted".
- `decisions/0003-three-layer-capability-architecture.md`: `decided 2026-05-23`. `history:` "2026-05-23 proposed + accepted".
- `decisions/0004-substrate-only-base.md`: `decided 2026-05-27`. `history:` "2026-05-27 accepted"; the 2026-05-26 entry is the proposal, not the decision.
- `decisions/0005-shared-render-artifact.md`: `decided 2026-05-29`. `history:` "2026-05-29 initial (accepted...)". Status also moves to `deprecated`.
- `decisions/0006-opentofu-cluster-lifecycle.md`: `decided 2026-06-02`. No `history:` and no log statement; the old `timestamp` stands.
- `decisions/0007-cluster-yaml-sot.md`: `decided 2026-06-06`. Old `timestamp`.
- `decisions/0008-task-runner-consolidation.md`: `decided 2026-06-07`. `history:` "2026-06-07 initial (accepted...)". Status also moves to `deprecated`.
- `decisions/0009-node-capability-composition.md`: `decided 2026-06-20`. Old `timestamp`.
- `decisions/0010-composition-logic-placement.md`: `decided 2026-06-20`, status `draft`. Its §Decision Outcome line stays "**Deferred (proposed).**" — that is the MADR state it records, not a frontmatter citation. Only the header line at the top, which cites the frontmatter explicitly, follows the field.
- `decisions/0011-substrate-hard-constraints.md`: `decided 2026-06-21`, status `stable`. The maintainer decision its 2026-07-11 verification banner deferred, taken here and recorded in a dated addendum; the banner's own `status: proposed` citation is untouched.
- `decisions/0012-makefile-retirement.md`: `decided 2026-06-22`. Old `timestamp`.
- `decisions/0013-kubelet-serving-cert-rotation.md`: `decided 2026-06-30`. Old `timestamp`. Its frontmatter comment stating the partial-supersession convention now says the status stays `stable`.
- `decisions/0014-ship-ai-tool-artifacts.md`: `decided 2026-07-13`. Old `timestamp`.
- `decisions/0015-openspec-adoption.md`: `decided 2026-07-13`. Old `timestamp`. Same partial-supersession comment change as 0013. A dated clarification is appended saying the config file is now `knowledge/.openknowledge.toml`; the record text above it, including the legacy filename, is untouched.
- `decisions/0016-capability-profiles-predicate-only.md`: `decided 2026-07-15`. Old `timestamp`.
- `decisions/0017-consumer-image-kernel-args.md`: `decided 2026-07-15`. Old `timestamp`.
- `decisions/0019-postfinance-kubelet-csr-approver.md`: `decided 2026-07-17`. Old `timestamp`.
- `decisions/0020-automated-release-no-approval-gate.md`: `decided 2026-07-21`. Old `timestamp`.
- `decisions/0021-spec-vs-bundle-normativity.md`: `decided 2026-07-22`. Old `timestamp`.
- `decisions/0022-cilium-observability-and-argocd-self-management.md`: `decided 2026-07-22`. This file states under 2026-08-14 that its `timestamp` was "left at 2026-07-22 — it records the decision date"; the 2026-08-15 addendum bumped it anyway, against that stated convention. The only ADR whose `timestamp` had drifted off its decision date.
- `decisions/0023-node-identity-map-key.md`: `decided 2026-07-26`. Old `timestamp`.
- `decisions/0024-argocd-substrate-relocation.md`: `decided 2026-07-29`. Old `timestamp`.
- `decisions/0025-argocd-crd-apply-scope.md`: `decided 2026-08-14`. Old `timestamp`.
- `decisions/template.md`: the `timestamp: YYYY-MM-DD` placeholder is retired with no replacement key — a placeholder is a value a copy can ship with, and a date-typing parser chokes on it. The instruction moves into the template's body comment. Status `draft`.
- `decisions/index.md`: new §Status vocabulary with the MADR-to-OKF mapping, the `decided` contract, and why a decision concept carries no `generated` or `verified`. The group headings and the per-entry `(word)` suffixes keep the MADR words and are now stated to be the record rather than a duplicate of the field; 0011 moves to §Accepted. §Authoring convention names `decided`.
- `index.md`: `okf_version: "0.2"`, and the non-normative reasoning section loses its `timestamp` bullet for the two-field explanation plus the two `verified` findings above. The v0.1 label is also corrected in `README.md`, `ARCHITECTURE.md`, `AGENTS.md` and `CLAUDE.md`, which had said v0.1 while `okf_version` said otherwise. The tooling-config carve-out also now states that the placement inside the bundle is mandatory rather than tidy.

## 2026-08-15

- `decisions/0022-cilium-observability-and-argocd-self-management.md`: addendum —
  the Cilium operator's replica count is derived from the node set (2 at two or
  more nodes, the floor's 1 at exactly one) and pinnable via the new
  `cilium_operator_replicas` input. Rewritten TWICE after adversarial review, and
  the second pass is the one worth recording: the first correction fixed the
  narrative files but left the retracted failover claim verbatim in
  `helm/cilium-values.yaml` and a test comment, so the repo contradicted itself
  instead of being uniformly wrong. Treating a claim defect as a CLASS, not as
  the documents it was reported in, is the transferable lesson; the rationale now
  lives in exactly one place (`local.cilium_operator_replicas`) and both copies
  point at it rather than restating it.
  Three claims were retracted against measurement: the operator tolerates
  `not-ready` but NOT `unreachable`, which is the taint a hard node failure
  carries; two replicas are leader-elected rather than active-active; and the
  operator is the `agent-not-ready` taint SETTER as well as its remover, so a
  wedged operator makes new nodes schedulable too early rather than never. Two
  more were narrowed in the second pass: the rollout claim is a change in
  GUARANTEED availability (0 → 1 pod), not "the incumbent goes down first" — 25%
  of one replica rounds up to a surge pod — and the failover-latency comparison
  now stops at "a warm instance exists", because the leases RBAC is granted at
  one replica too and the lease timings are unmeasured operator-binary behaviour.
  What survives: de-divergence from the chart's own default, plus those two
  narrowed consequences.
  The over-count tier flipped from WARN to REJECT. Its warn rationale ("breaks
  nothing") was contradicted twelve lines away in the same record, `var.nodes` IS
  the cluster the module builds, and the value lands in a create-only seed no
  later apply can walk back — which also bounds a previously unbounded input.
  `scripts/check-cilium-operator-replicas-key.sh` is new and is the BLOCKING
  layer for the Helm key spelling: the render assertions live in the composition
  suite, whose CI job is advisory by design, so crediting them with closing the
  key-spelling residual was wrong. The floor's `operator.replicas: 1` is now
  documented as load-bearing three ways so it does not get "cleaned up" — with it
  gone, a dropped computed key renders the chart's default of 2 and the >= 2-node
  render assertion passes on the mutation it exists to catch.
  New residuals recorded: the shrink direction has no delivery path and no drift
  signal, both operator pods are BestEffort (the chart sets no
  `operator.resources`), and a two-node cluster trips `ProgressDeadlineExceeded`
  on every drain longer than the 600s default. Every mutant was run; the chart
  facts were read off a local `helm template` of the pinned 1.20.0. The two
  render assertions themselves were NOT executed — the Image Factory was
  unreachable — and their predicate was verified out-of-band instead.

## 2026-08-14

Second pass, after a five-lens independent review. Corrections to load-bearing
claims are listed first because they change what the record asserts, not just
how it reads:

- `decisions/0025-argocd-crd-apply-scope.md`: three corrections. (1) The
  mechanism behind removing `kubernetes_version` from `triggers_replace` was
  wrong — this chart has no un-templated `crds/` directory; its CRDs live in
  `templates/crds/` and ARE rendered as templates. The conclusion survives on a
  narrower, verified basis: every directive in those three files interpolates
  `.Values.crds.*` only. Recorded with a revisit trigger, since a future chart
  version can reach `.Capabilities` there. (2) "A plan-time precondition requires
  at least three surviving documents" described the count-based form the spec
  explicitly rejects; the guard is by-name, and two further preconditions
  (exclusivity, parseability) were added. (3) The residual-field-manager
  reasoning had its default inverted: it argued from "ArgoCD applies client-side
  by default", but the shipped root Application sets `ServerSideApply=true`, so
  server-side is the default path for anyone using it.
- `reference/argocd-sso-contract.md`: the remote-base fetch is no longer
  described as using "the Application's own credentials" — an unverified claim
  about credential handling. It is stated as what it is for a public base: an
  anonymous, unverified fetch that bypasses the repo's cosign/SLSA/SBOM posture,
  with a commit SHA recommended over a mutable tag and the verified vendored
  path named as the stronger alternative. The Secret trust boundary gains its
  read side (`server.secretkey` makes `get secrets` in the namespace
  superuser-equivalent); the `server.insecure` caveat is re-scoped from the
  break-glass credential to every SSO session token on the same hop; the
  cut-over gains an explicit SSO-session step and the retirement of
  `argocd-initial-admin-secret`; the PKCE recipe points at the version-specific
  Argo CD switch instead of implying registration alone suffices.

- `reference/argocd-sso-contract.md`: new. The consumer-facing half of the
  identity removal — what the base ships versus what the consumer owns, the
  Kustomize remote-base mechanism (ArgoCD resolves `$ref` only in
  `helm.valueFiles`, so a Multi-Source `$base/...` kustomization cannot work),
  the external-Secret trust boundary, the PKCE caveats, the flat Casbin subject
  namespace, and a cut-over whose predicate is authorization rather than login.
- `architecture/substrate.md`: §What ships in the OCI artifact corrected. Its
  entry list had drifted — it claimed 15 entries and omitted the three argocd
  ones the allowlist has carried for some time, while §What stays git-only
  listed the whole component as repo-only. Both are now accurate, and the fourth
  argocd entry (`kustomization.yaml`) is recorded with the reason it ships: the
  rendered manifests alone are not a buildable unit.
- `workflows/first-consumer-cluster.md`: the Day-2 narration now names the
  remote-base mechanism and points at the SSO contract for the identity step.
  `timestamp` bumped.
- `decisions/0025-argocd-crd-apply-scope.md`: new. The module's post-health-gate
  `kubectl apply` is projected down to CustomResourceDefinition documents and
  loses `--force-conflicts`. Records what the full-render apply actually did —
  twelve kinds, bundled Dex included, force-taking field-manager ownership of
  `argocd-cm` and `argocd-rbac-cm` on every re-fire — why passing the seed values
  in was rejected as the fix, and the residuals (existing clusters are not
  repaired retroactively; verification is render- and plan-level because no
  cluster is available to this repo).
- `decisions/0024-argocd-substrate-relocation.md`: dated correction appended to
  the second decision driver. Its "argocd-controller is the sole field-manager
  owner" claim was never true — the force-apply co-owned those keys all along.
  The conclusion it supported is unaffected. `timestamp` left at the decision
  date per the bundle's decision-concept rule.
- `architecture/day-zero-bootstrap.md`: §The direct-apply exception now states
  the apply's real former scope and its new CRD-only one; the invariant list
  gains I3 (shared across both render paths) and I4 (steady-state only), and
  corrects I1's SSO wording from a Helm-values path to a patch on the
  `argocd-cm` ConfigMap. `timestamp` bumped — `main.tf` and
  `check-argocd-substrate-invariants.sh`, both declared sources, changed.
- `reference/manifest-pipeline.md`: §ArgoCD substrate invariants now carries
  I1-I4 with I3 shared across both paths, the presence-anchor rationale for the
  name-scoped ones, and the consumer-overlay E-checks with their control build.
  `timestamp` bumped — its declared source `check-argocd-substrate-invariants.sh`
  changed.

- `decisions/0022-cilium-observability-and-argocd-self-management.md`: dated
  addendum recording the two further typed metric-set inputs
  (`cilium_agent_metric_overrides`, `cilium_hubble_open_metrics`). Nothing is
  superseded — both are layered into both engines, so §(d) holds, and the floor∩computed
  collision count in §(f) is still one. What the addendum adds is a second
  collision LEVEL for §(f)'s invariant (intra-computed, where a shallow
  `merge()` term replaces a sibling with no floor to preserve), the `check`
  versus `validation` guard tier and why the override escape hatch forces it,
  the measured raw-render injection vector behind the format validation, the
  measured no-DaemonSet-roll behaviour of the OpenMetrics flag, and the declined
  Grafana-dashboard scope with its 60 268 → 587 208 byte figure. `timestamp`
  left at 2026-07-22 — it records the decision date, and no decision changed.
  Residual stated in the addendum: chart-key spelling for both Helm paths is
  bound only by the network-dependent, CI-advisory composition suite.
  Revised after adversarial review, all three corrections measured against the
  pinned chart rather than reasoned: the OpenMetrics key turned out to sit under
  the same gate as `hubble-metrics-server`, so it is inert with an empty metrics
  list and the effectiveness check had been written on the wrong precondition;
  `cilium_hubble_metrics` carried the identical raw-render injection vector the
  addendum documents for the new input, so the guard obligation is recorded as
  binding the input CLASS rather than one member; and "reaches both engines" is
  now qualified as a data-flow statement, since the frozen seed means neither
  input reaches an already-bootstrapped cluster without self-management, a fresh
  bootstrap, or a deliberate `-replace`.
- `reference/cluster-yaml.md`: re-verified against the widened
  `schemas/cluster.schema.json` and the example shim in its `sources`; the prose
  claims (no `schema_version`, unvalidated patch content, the secret-exclusion
  rules) all still hold, so only `timestamp` moved to 2026-08-14. The enumerated
  `substrate.cilium` key set lives in `openspec/specs/cluster-yaml-sot/` and was
  updated there, not here.
- `reference/cluster-yaml.md`: new §How CI binds the schema to the shim, and
  `scripts/check-shim-key-parity.sh` added to `sources`. The file already
  documented how CI binds the schema to a `cluster.yaml`; what it did not
  document is that lint proves conformance and not arrival — the shim's `try()`
  reads are total, so an unmapped or misspelled substrate key resolves to the
  module default with nothing anywhere reporting it. The violation count in the
  lint-gate section was also stale at six; the fixture now carries ten.
- `reference/tasks.md`: `tofu:check:shim-key-parity` added to the inventory and
  to the `tofu:ci` aggregate line; `timestamp` bumped, since `Taskfile.yml` — a
  listed source — changed.

## 2026-08-12

- `workflows/spec-driven-development.md`: §Validation's staleness-gate
  description corrected — the `Spec-Impact: none` escape is scoped to the
  commits that CONTRIBUTED to the violating file, not to every commit git lists
  for it, so a base-sync merge (which branch protection forces before merging)
  no longer voids it while a hand-resolved conflict still certifies itself.
  Names the bite-check that binds both directions. `scripts/check-spec-staleness.py`
  added to `sources` — the section describes that script's behavior and had no
  freshness link to it; `timestamp` bumped for the re-verification.
- `reference/tasks.md`: `spec:validate` and `spec:check-staleness` rows updated
  for the same attribution rule and the new bite-check step. `timestamp` left at
  2026-07-22 — one row was re-verified, not the inventory. The
  `spec:check-staleness` row was then thinned to the practical consequence plus
  a pointer to the workflow concept: a task-inventory row restating a mechanism
  and both its failure directions is out of altitude, and the bundle's own rule
  prefers source pointers over copied code-derived truth. Independent
  simplicity review counted six prose restatements of one rationale; two of
  those (both in `CONTRIBUTING.md`) carry only the consequence and stay, and
  `CHANGELOG.md` stays self-contained by genre.

- `decisions/0022-cilium-observability-and-argocd-self-management.md`: dated
  addendum recording the re-verification at the Cilium `1.20.0` chart bump. All
  §Validation claims established against 1.19.4 still hold — the
  `hubble-metrics` `:9965` Service, all four `cilium-config` observability
  marker keys, and seed render determinism — and the ADR's explicit
  `operator.prometheus.enabled` revisit trigger did not fire (still defaults to
  `true`), so the audit-only caveat on
  `cilium_seed_observability_markers.operator_metrics` stands. Nothing
  superseded. The addendum also inventories the new default-on 1.20 surface in
  the seed, re-measured by diffing the FULL rendered `cilium-config` map in both
  directions rather than scanning for added keys: 12 added, 0 removed, and one
  changed value (`bpf-lb-algorithm-annotation` `"false"` → `"true"`, forced by
  `gatewayAPI.enabled`). Two corrections to the first pass of that inventory:
  `enable-drift-checker` is NOT new (`configDriftDetection` exists in 1.19.4 and
  the key renders `"true"` in both), and `envoy-node-locality-enabled` was
  missing. The `gateway-api-use-remote-address` row is corrected from "genuine
  new default-on behavior" to behavior-PRESERVING — Cilium 1.19 hardcoded the
  same Envoy field, so 1.20 adds the knob, not a new posture.
- `decisions/0022-cilium-observability-and-argocd-self-management.md`: the
  summed-inlineManifest residual is CLOSED (issue #213). Records the sourced
  ceiling — Talos `GRPCMaxMessageSize = 32 * 1024 * 1024`
  (`pkg/machinery/constants/constants.go` at `v1.11.0`) — the removal of the
  unsourced `~66 KB` figure, and why the gate is a precondition over the patch
  locals rather than a postcondition over `machine_configuration` (the latter is
  unknown on a first plan and defers to apply; measured, not assumed). Two
  residuals stay open: nothing proves a tighter limit does not bind first, and the
  gate has no permanent test because binding it needs a synthetic ~32 MiB seed.
- `decisions/0007-cluster-yaml-sot.md`: Gateway API CRD floor updated v1.4.1 →
  v1.6.1 (Cilium 1.20 minimum; `TLSRoute` joined the standard channel at
  v1.6.1), and the chart-provenance residual re-verified —
  `cilium-1.20.0.prov` is HTTP 404 like its predecessor, so the deferred
  digest-pinning finding is unchanged.
- `architecture/day-zero-bootstrap.md`: re-verified at the Cilium `1.20.0`
  bump — two of its `sources` changed (`cluster.yaml.example`,
  `kubernetes/bootstrap/cilium/values.yaml`). Its claims are version-agnostic
  (`*_chart_version` are seed knobs, not upgrade knobs; the Gateway-API CRD
  boot-seed is opt-in) and needed no edit; `timestamp` bumped to record the
  verification.
- `reference/cluster-yaml.md`: re-verified at the same bump — its
  `cluster.yaml.example` source changed (`substrate.cilium.chart_version`). It
  asserts no chart version, so no edit; `timestamp` bumped.
- `workflows/first-consumer-cluster.md`: re-verified at the same bump — three
  of its `sources` changed (`cluster.yaml.example`,
  `examples/complete/{main.tf,cluster.yaml}`). It asserts no chart version, so
  no edit; `timestamp` bumped.

Note on the two decision concepts above: their `timestamp` is deliberately
NOT bumped. `decisions/index.md` makes frontmatter canonical for dates, so for
a `decision` concept `timestamp` is the decision date; decisions also omit
`sources`, so the re-verify-on-source-change rule cannot apply to them. The
dated `## Addendum 2026-08-12` heading inside ADR-0022 carries the freshness
signal instead, which is also what "append clarifications, do not rewrite
decision history" requires.

## 2026-07-26

- `decisions/0023-node-identity-map-key.md` added (issue #204): `var.nodes`
  becomes a map keyed by node name, every Talos-facing list becomes a
  name-ordered projection of it, and the identity gaps the list model hid
  become plan-time validations — node-key canonicality (Talos validates
  hostname length only and then silently rewrites the rest), first-label
  collisions (Talos splits at the first dot), FQDN registration
  (`register_with_fqdn`), and an odd controlplane count (etcd quorum).
  Indexed under Accepted.

## 2026-07-22

- `reference/tasks.md`: the remaining task-namespace tables audited against
  `Taskfile.yml` (issue #199). `bootstrap:*` gains rows for
  `bootstrap:render-root` and `bootstrap:check-render` at their
  `Taskfile.yml` definition-order positions, each citing
  `openspec/specs/argocd-day-zero-bootstrap/` for the field-level contract
  it deliberately does not restate, with the `Details of ...` lead-in
  retitled to cover the render → apply path; the `spec:*` table's
  `spec:check-regen` row moved below `spec:install-cli` to match
  definition order. Two Purpose cells corrected — both cases where the row
  agreed with the task's `desc:` and disagreed with its `cmds:`:
  `gitops:validate` now enumerates all eight stages it runs (added the
  conftest bite-check and `scripts/check-bootstrap-render.sh`), and
  `spec:validate` now names the `spec_lib` parser self-test
  (`scripts/test/test_spec_lib.py`). The wider step-6 sweep — every
  remaining Purpose cell against `desc:` and `cmds:`, the six per-table
  prose notes, the lead-in/convention prose, and the `Makefile`-derived
  stub prose against `Makefile`'s `RETIRED_MSG` — found two further such
  divergences, corrected concept-side: `tofu:test:offline` omitted the
  kubeconfig-endpoint-marker regression (issue #186) it runs, and
  `dev:verify-pins` omitted the `package-lock.json` registry-provenance
  guard it runs. One exemption is now recorded: `dev:npm-ci`, via a
  `Deliberately absent from this table:` marker paragraph beneath the
  `dev:*` table — the fixed lead-in the planned inventory-parity fence
  (#200) will read exemption lists from. The issue's asserted `bootstrap:*`
  exemption was re-derived as inapplicable: the bootstrap details prose
  withholds the render's field-level contract, not the two tasks'
  inventory rows, so both were backfilled as rows instead. `timestamp`
  bumped to 2026-07-22, now attesting every namespace table's row set, row
  order and Purpose cell, the six per-table prose notes, the
  lead-in/convention/`Makefile`-stub prose, the `Makefile` mapping table,
  and `package.json` (newly declared in `sources:`) plus the
  `package-lock.json` integrity-hash half of the pin claim (read by hand,
  left undeclared — it churns on every transitive dependency bump).
  Residual, not attested by this bump: `knowledge/openknowledge.toml`'s
  `link-target`/`rule-catalog` severity claim, derived from a source this
  audit does not inspect — follow-up to be filed. Scope: `Taskfile.yml`
  and `Makefile` are unchanged; the CI fence binding this inventory to
  them is #200.

- `decisions/0003-three-layer-capability-architecture.md`: removed eight
  gitignored session-scratch path citations (status blockquote, §Context,
  §Enforcement scope, §NFD placement, §Single-source convention,
  §References) per issue #193; each citation's substance (the Layer-C
  necessity verdict, the three load-bearing facts, the scope limits, the
  NFD producer-tooling verdict, the label-drift hazard, and the
  Round-1/Round-2 audit findings) is now stated as historical record in
  body prose with no dangling path.

- `decisions/0021-spec-vs-bundle-normativity.md` ADDED (accepted). Records
  `openspec/specs/cluster-yaml-sot/spec.md` and
  `openspec/specs/module-interface-contract/spec.md` as the sole normative
  artifacts for `cluster.yaml` schema shape and the `talos-cluster` module's
  variable/output contracts (issue #177), with the module README's
  hand-maintained duplication kept and gated only at name level
  (`task tofu:check:readme-parity`, advisory). Named residuals: the
  `emits_label` prefix constraint stays normative in two specs at once,
  two further bundle concepts still restate spec-owned content, and per-variable
  defaults remain exhaustive only in the README. Five spillover follow-ups
  filed (issues #190–#194).
- `decisions/0015-openspec-adoption.md`: dated partial-supersession banner
  below the H1, a pointer sentence inside §Ownership model, a pointer
  sentence inside §"SoT map vs `knowledge/reference/`", and a frontmatter
  comment above `superseded_by: []` — all insert-only; the accepted text and
  the 2026-07-15 Correction block are untouched.
- `decisions/index.md`: added the ADR-0021 row to §Accepted; annotated the
  ADR-0015 row with the partial-supersession qualifier.
- `reference/cluster-yaml.md`: the module-interface pointer now names
  `openspec/specs/module-interface-contract/` as normative (the README is
  the release-shipped copy); §"What must never be in it" points at
  `openspec/specs/cluster-yaml-sot/`'s secret-exclusion Requirement instead
  of restating it; §"How CI binds the lint gate" drops the enumerated
  six-rule list and the exit-code contract in favor of a spec pointer;
  `sources:` justification comment trimmed to the two claims that still
  derive from the file; `timestamp` bumped.
- `decisions/0022-cilium-observability-and-argocd-self-management.md` ADDED
  (accepted). Records first-class default-off Cilium observability inputs
  (`cilium_agent_metrics`, `cilium_operator_metrics`, `cilium_hubble_enabled`,
  `cilium_hubble_metrics`) and an opt-in emitted-Application ArgoCD
  self-management delivery mode (`cilium_self_management`,
  `cilium_self_management_project`) — module renders, never applies, per
  AGENTS.md §Hard Constraints. Documents the bounded floor⊕computed merge
  (`operator` sub-merge) + two-engine-drift invariant, the override-drop
  hazard + hard-reject `validation` guard, the bootstrap-window datapath gap
  tension, the Hubble TLS-off/metrics-independence grounding (T1 Cilium
  docs), the `spec.project` posture + supply-chain note, the ArgoCD-adoption
  runtime caveat, and the five schema-contract-parity decisions for the now
  CLOSED `substrate.cilium` schema. Two consumer-visible compatibility
  breaks: the module's OpenTofu floor bumped to `>= 1.9` (cross-variable
  `validation` blocks) and `substrate.cilium` closed
  (`additionalProperties: false`).
- `decisions/index.md`: 0022 added under Accepted.
- `reference/tasks.md`: the `tofu:*` inventory table gains rows for
  `tofu:check:readme-parity` and `tofu:check:kubeconfig-endpoint-regen`,
  inserted at their `Taskfile.yml` definition-order positions, and the
  `tofu:ci` row now enumerates all seven member tasks instead of five
  (issue #190). Scope: only the `tofu:*` table was re-verified row-for-row
  against `Taskfile.yml`; the other namespace tables were not audited here.
  Residual: `Taskfile.yml`'s `tofu:ci` `desc:` string still names five
  members, and this concept points readers at `task --list`, which renders
  exactly that string — out of scope per the issue's §Non-Goals. `timestamp`
  stays `2026-07-15` by maintainer decision: this concept's `sources:` cover
  all ten namespace tables and only the `tofu:*` one was re-verified, so
  bumping would claim a concept-wide freshness that was not established.
- `reference/tasks.md` (record correction — the concept file itself is
  unchanged): the residual recorded in the `reference/tasks.md` bullet above is
  closed. `Taskfile.yml`'s `tofu:ci` `desc:` now enumerates all seven member
  tasks in the same wording as the concept's `tofu:ci` row, so `task --list` —
  which this concept points readers at — and the inventory table agree.
  `timestamp` stays `2026-07-15` for the reason recorded above.

## 2026-07-21

- `decisions/0020-automated-release-no-approval-gate.md` ADDED (accepted).
  Records removing the `environment: release` manual-approval gate so a merge to
  `main` releases unattended, and replacing the gate's one mechanical function
  (MAJOR-vs-MINOR backstop) with a blocking, `will-release`-gated MAJOR-bump
  guard in `release.yml`'s `plan` job (surface set = tarball allowlist +
  `schemas/**` + `platform-hardware-features.yaml` + `contracts/**` + base
  `values.yaml`), with an `[allow-non-major]` HEAD-commit override. No
  commit-back to `main`; CHANGELOG stays hand-cut in the releasing PR.
  Accepted trade-offs recorded (unattended = no eyeball; guard replaces only the
  MAJOR half; surface set non-exhaustive). Auto-cut via bot-PR deferred to a
  follow-up.
- `decisions/index.md`: 0020 added under Accepted.
- `workflows/release-process.md`: rewritten from "human approval gate" to the
  automated flow — overview, §Commit gate backstop sentence, §Plan and release
  (job `release` renamed approval-gated → unattended, MAJOR-bump guard
  documented), and the frontmatter `description`; `timestamp` bumped to
  2026-07-21. `index.md` release-process link description updated to match.
- `architecture/day-zero-bootstrap.md`: added a "Kubeconfig regenerates on an
  endpoint change" note to §Key properties (issue #186 —
  `talos_cluster_kubeconfig.this` now carries a `lifecycle.replace_triggered_by`
  keyed on a `terraform_data` marker tracking `var.cluster_endpoint`);
  `timestamp` bumped to 2026-07-21.
- `architecture/day-zero-bootstrap.md` (PR #187 review follow-up): corrected
  the kubeconfig-regeneration note — the existing health gate polls
  control-plane node IPs, not the advertised endpoint, so it does not verify
  a VIP/DNS endpoint's reachability; reworded the node-re-IP trigger
  condition to state plainly it applies only when the endpoint IS a
  control-plane node's own IP; and noted the DNS-rename serving-cert-SAN
  dependency for a re-fetched kubeconfig to be usable.

## 2026-07-17

- `decisions/0019-postfinance-kubelet-csr-approver.md` ADDED (accepted). Records
  the swap from alex1989hu/kubelet-serving-cert-approver to
  postfinance/kubelet-csr-approver v1.2.14, delivered as the same controlplane
  inlineManifest seed but chart-rendered + `templatefile()`-parameterized
  (`manifests/kubelet-csr-approver.yaml`, namespace renamed
  `kubelet-csr-approver`), with a three-knob `substrate.cert_approver` config
  surface (`provider_regex` / `provider_ip_prefixes` / `replicas`), the
  source-verified postfinance-vs-alex1989hu security check table (default-on
  per-node DNS-SAN binding as the gain; `HasPrefix`-not-exact + IP-only-CSR
  residuals named), the breaking-change list, and the tftest + homelab-deny-path
  validation. Supersedes ADR-0013 §D2.
- `decisions/0013-kubelet-serving-cert-rotation.md`: dated partial-supersession
  banner added below the H1; `superseded_by` set to the §D2-qualified 0019 path.
  §D1 (rotation default-on) STANDS; §D2's approver identity + seed mechanism are
  superseded.
- `decisions/index.md`: 0019 added under Accepted; the 0013 row annotated with
  the §D2 partial supersession.
- `architecture/substrate.md`, `architecture/day-zero-bootstrap.md`,
  `glossary.md`: re-verified against the implemented branch and updated —
  approver identity alex1989hu → postfinance, manifest filename
  `cert-approver.yaml` → `kubelet-csr-approver.yaml`, chart-rendered
  `templatefile()` seed, "no knobs" → the three-knob `substrate.cert_approver`
  config surface, and the default-on per-node DNS-SAN binding. `timestamp`
  bumped to 2026-07-17.
- `workflows/first-consumer-cluster.md`: manifest-filename reference in the
  tarball-membership list corrected `cert-approver.yaml` →
  `kubelet-csr-approver.yaml` (filename-only; `timestamp` left at 2026-07-15).

## 2026-07-15

- `reference/talos-cluster-module.md` REMOVED. Its requirement-bearing
  sections (variable/output/version tables, module-enforced invariants,
  the provisioning-profile catalog) are carried by the owning OpenSpec
  specs; its narrative sections (fresh-PKI adoption warning,
  schema-pin/install-pin Day-2 pattern, examples entry point) by
  `tofu/modules/talos-cluster/README.md`, which sits next to the code and
  ships in the release artifact where this bundle does not. Two sections did
  NOT survive the first attempt and were restored to the README as part of
  this change: the full output list (the README carried 11 of 19) and the
  catalog enumeration. The known cost is recorded in the ADR-0015 correction:
  no spec owns a README, so no staleness gate fires on it — `task
  tofu:check:readme-parity` (new, in `tofu:ci`) is the compensating gate, and
  it reproduces the 8-output gap when the fix is reverted.
- `decisions/0015-openspec-adoption.md`: dated correction block added below
  the accepted §SoT map, which is left standing verbatim. It records two
  errors: the exemption of the module README's tables as
  "terraform-docs-generated (inject mode)" is false (no `BEGIN_TF_DOCS`
  markers — the tables are hand-maintained), and a first correction's claim
  that `task tofu:docs` is "a no-op that swallows the miss" is **also**
  false. Verified by running it: terraform-docs v0.22.0 APPENDS a 114-line
  generated block and exits 0, leaving two competing table sets. `tofu:docs`
  now refuses on a marker-less README instead of corrupting it.
- `reference/tasks.md`: `tofu:docs` row rewritten to its true behavior;
  `bootstrap:argocd` input-subset bullet now cites
  `openspec/specs/argocd-day-zero-bootstrap/` instead of restating the
  subset — it was a second un-gated copy of the same contract, which the
  spec-gap proposal originally missed.
- `reference/cluster-yaml.md`: §Two consumers now cites
  `openspec/specs/argocd-day-zero-bootstrap/` for the bootstrap-identity
  subset instead of carrying it. The subset and the value-containment guards
  moved into that spec via the first `openspec/changes/` proposal (archived
  `2026-07-15-spec-bootstrap-identity-subset`). Review of that proposal
  surfaced two shipped defects the docs had described as covered — a
  schema-valid newline injecting YAML into the rendered AppProject, and an
  empty overlay rendering the whole overlay tree — both now closed in the
  render and bound by `task bootstrap:check-render`.
- `reference/cluster-yaml.md`: schema-shape section removed — all eight
  `openspec/specs/cluster-yaml-sot/` requirements were re-checked against it
  first, `substrate` included, and they carry every point normatively from
  the same `schemas/cluster.schema.json` this doc cited. Kept what no
  requirement carries: the two-consumer subsets, where secrets go instead of
  the file, the notes behind the schema's choices, and the CI red-green
  wiring of the lint gate. `schemas/cluster.schema.json` STAYS in `sources`
  — the surviving prose still derives from it, so dropping it would have
  removed the bundle's re-verify trigger in the very change arguing that
  ungated copies rot.
- `workflows/spec-driven-development.md`: third lane documented —
  "spec-gap backfill", for an `ADDED`-only delta against already-shipped
  behavior, with the four conditions that keep an empty apply phase from
  becoming a way to narrate a review that never happened.
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

Issue #169 (consumer-supplied schematic `extra_kernel_args`) — a new
per-image kernel-cmdline input reaching the UKI-correct schematic sink, and
the kernel-arg conflict guard re-scoped to cross-source (profile-vs-image)
collisions only:

- `decisions/0017-consumer-image-kernel-args.md` NEW: the UKI root cause, the
  two rejected alternatives, the cross-source guard-scoping decision and its
  accepted consumer-vs-consumer residual, and the schema-mirror rationale.
  Added to `decisions/index.md`.
- `architecture/capability-composition.md`: §Consumer composites documents the
  image's fourth axis (`extra_kernel_args`); §The composition pipeline
  documents the schematic karg sink as the image's args UNION the profiles';
  §Plan-time guards documents the cross-source scoping; §Base-owned catalog
  gains the consumer-args counterpart to the hard-constraints-grep sentence;
  §Module tests documents the new `image-kernel-args.tftest.hcl` suite and the
  conflict-guards additions.
- `reference/cluster-yaml.md`: §Authoring notes corrected — boot kernel args
  are no longer routed through `config_patches` prose (that sink is a no-op
  under UKI); they go to `images.<id>.extra_kernel_args`. The CI lint-gate
  wiring section documents the six-way (was two-way) invalid-fixture red-green
  binding and the new `examples/complete/cluster.yaml` lint step.
- `glossary.md`: **Schematic** term's image side gains `extra_kernel_args`.
- `workflows/first-consumer-cluster.md`: the OpenTofu-root bullet enumerating
  what the full `cluster.yaml` definition carries now names the `images`
  sub-attributes, including `extra_kernel_args`.
- `architecture/day-zero-bootstrap.md`: re-verified against the changed
  `cluster.yaml.example`; no claim went stale.
- `reference/tasks.md`: `tofu:test:offline` row now names the fourth offline
  suite (the consumer image-kernel-arg oracles).
- `AGENTS.md` §Key Terms **Schematic** bullet: image side gains
  `extra_kernel_args`, mirroring the glossary term.
- `reference/manifest-pipeline.md`: the `hardware-features-check` CI-mapping
  row now names the module's `examples/complete/cluster.yaml` lint step
  alongside the existing `cluster.yaml.example` one (mechanical re-verify
  check per the plan's scoping principle: this file enumerates the
  schema-lint job's steps, and this change adds one).

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

## 2026-08-31

- `decisions/0020-automated-release-no-approval-gate.md`: second amendment —
  the merge settings are unreadable under the audit App token, so Check 4 falls
  back to checking the merge effect on `main`.
- `decisions/0020-automated-release-no-approval-gate.md`: amendment recording
  that the merge-method settings landed, that `merge_commit_title` is
  `PR_TITLE`, and that Check 4 now runs in CI under an App token.
- `project/openssf-self-assessment.md`: new dated verification of the required
  contexts — `lint-pr-title` added, `preflight` removed with its workflow.
- `workflows/release-process.md`: the title lint is required; the merge subject
  is the PR title.
- `decisions/0015-openspec-adoption.md`: the repo-internal CI list names
  `policy-audit` where it named the deleted `preflight`.
- `workflows/verify-release.md`: the tag-reassignment paragraph no longer
  credits a GHCR tag-immutability setting, which does not exist. Digest pinning
  is named as the only protection for the image; repository release
  immutability is described for what it does cover.

## 2026-07-11

- Initial OKF v0.1 bundle. Replaces the retired `docs/` tree: architecture,
  reference, workflow, and glossary concepts regenerated from repository
  source; 13 ADRs migrated to `decisions/` with MADR frontmatter mapped to
  OKF and present-tense claims re-verified against code;
  `component-dependencies.md` dissolved into `architecture/substrate.md`;
  `oci-artifact-verification.md` merged into `workflows/verify-release.md`;
  machine-consumed contracts relocated outside the bundle
  (`platform-hardware-features.yaml`, `schemas/`, `contracts/`).
