# Changelog

## 2026-08-23

The pinned `openknowledge` CLI moved 0.5.0 -> 0.12.0, and the durable lesson is
not the version number. The pinned 0.12.0 does not read the legacy
`openknowledge.toml` name, so that file had become inert:
`link-target = "error"` and `rule-catalog = "error"` degraded back to warnings
with no signal at all. Which release introduced that is NOT recorded here,
because it could not be sourced — upstream publishes no release notes for any version in the
range (checked 0.10.0 through 0.12.0, all empty). Only 0.12.0 was measured.

Scope of the damage, since the unqualified version of that sentence is wrong:
the merge gate was in far better shape than a local run. `docs-lint.yml` runs
`task knowledge:install-cli` in the same job before validating, which installs
the PINNED version, and 0.5.0 does read the legacy name (verified 2026-07-15,
further down this file). Checked every revision of that workflow: the
install-before-validate ordering holds in all of them except one (2026-07-15,
the commit that introduced the managed block), which ran `knowledge:validate`
with no install step at all. So "CI was never degraded" is not a claim this
file can make; what it can say is that the degradation lived in LOCAL runs of
anyone who had upgraded past the pin, which is the argument for the version
guard: without one, local verification silently stops matching CI.

Three facts about 0.12.0 that changed the tooling rather than the bundle, kept
here because the next bump will need them. `rules` now lives under `prompt`,
and the old form exits 2 — inside `knowledge:rules-check` that render runs in a
pipeline, so `set -e` never sees the failure and only the empty-block assertion
catches it; the assertion now carries a comment saying so, because it reads as
redundant otherwise. `linux-arm64` joins the checksum set as a fourth platform,
verified end to end in a linux/arm64 container since it is the one arm neither
the maintainer nor CI exercises: both assets fetch, both checksums verify, the
openknowledge tarball is flat as the install line assumes, and lychee's nested
binary is found by the same `find`. And telemetry, which is on by default, is
opted out through `OPENKNOWLEDGE_TELEMETRY=off` in the Taskfile `env:` block —
correcting this entry's first draft, which claimed 0.12.0 offers no env-var
switch and only the `--no-telemetry` flag. The variable exists, is upstream's
documented process-level override (`https://openknowledge.sh/wiki/features/telemetry.html`,
which also names `DO_NOT_TRACK=1`), and is the better instrument: it is
per-invocation, writes no telemetry config and does not touch an existing one,
whereas the flag persists `enabled: false` into the operator's config and does
not exist before 0.12.0 — so it could never have covered the two version
probes, which must read a drifted binary — measured, 0.5.0 answers
`unknown command: --no-telemetry` with EMPTY output, which is what makes it
unusable there: `OK_GUARD` would then report `openknowledge '' != pinned`,
blaming version drift for a rejected flag. Measured, and NOT documented
upstream, which names only `off`: `0` and `false` work too, matching is
case-insensitive, and an unrecognised value falls back to ENABLED. The spelling
is therefore load-bearing, and `off` is the one to keep because it is the
documented one.

Where the opt-out is enforced took two attempts, and the first was wrong on a
point worth recording: an `env:` entry in `Taskfile.yml` is a DEFAULT, not an
override. Measured — `OPENKNOWLEDGE_TELEMETRY=on task knowledge:validate` sends
telemetry, the ambient value wins. So the entry alone left every target
defeatable from the environment, and because an unrecognised value means
enabled, a typo did it too. What binds is an unconditional
`export OPENKNOWLEDGE_TELEMETRY=off`: in `OK_GUARD`, which the three `knowledge:*`
CLI targets already share; in `knowledge:install-cli`, which has no `OK_GUARD`
because it installs the binary the guard checks, and whose closing `version`
echo is a fresh binary's first run; and at the top of
`scripts/verify-tools.sh`, `scripts/check-bundle-policy.sh` and
`scripts/check-knowledge-gate-bite.sh`, all three runnable outside go-task.
Unconditional rather than deferring to a caller: `${VAR:-off}` substitutes only
when the variable is unset, so it passes `on` — and every typo — straight
through to the fail-open default. An operator who wants telemetry runs the
binary outside these targets. The `env:` entry stays as the default for any
future target that runs the CLI without `OK_GUARD`, and
`OPENKNOWLEDGE_TELEMETRY_CONFIG` stays pinned into the gitignored `.work/` as a
backstop: with the export in place nothing is written there, and if the opt-out
ever stops working the write is bounded to the checkout instead of the
operator's home, where it is visible. This mirrors the `OPENSPEC_TELEMETRY`
opt-out already sitting in that block for the sibling CLI.

A control this quiet needs a detector, by the same argument as the config gate
above. `scripts/check-knowledge-gate-bite.sh` gained a seventh, two-sided
scenario: a control run with the variable empty must WRITE a telemetry config,
and only then is the `off` run's silence evidence. Both halves were mutated and
both report the right failure.

The first version of that scenario went red on CI and green locally, which
turned up the fact the whole opt-out should be read against: a truthy `CI`
suppresses the write on its own (measured — `CI=true` and `CI=1` do, `CI=false`
and `GITHUB_ACTIONS=true` alone do not). So the runner was never sending
telemetry, the opt-out is a LOCAL-run control, and the scenario was measuring
the runner rather than the variable — failing its control there and passing its
assertion for the wrong reason. Both halves now drop `CI` from the environment,
and removing that is one of the three mutants the scenario is bound against.
Same shape as the config-filename finding at the top of this entry: the
degradation lived locally, and the argument for a guard is that local
verification stops matching CI without one.

What an event carries, measured with
`openknowledge telemetry show-payload` so the residual can be sized without
re-deriving it: schema version, event name and id, timestamp, surface,
installation id, app version, OS, arch, command name, outcome, and a duration
bucket. No paths, no content, no repository or user identity. The remaining
uncovered path is a bare `openknowledge` invocation, which the built-in rule
text in the `AGENTS.md` managed block still tells agents to make; the bundle
conventions gained a bullet saying to go through the `knowledge:*` targets and
to prefix a bare run, and it renders ten lines above that instruction.

- `.openknowledge.toml`, renamed from `openknowledge.toml`: the rename is the
  fix, and the severity set is unchanged. Measured against 0.12.0 that the file
  must be BOTH a dotfile AND inside the bundle directory — a copy at the
  repository root is not discovered — and that discovery is bundle-relative, so
  the answer does not change with the working directory. Not measured, so not
  claimed: whether a user-level config or an explicit flag can also supply
  policy. Telling whether the file is in effect is no longer prose:
  `OPENKNOWLEDGE_TELEMETRY=off openknowledge validate --format json knowledge/`
  prints `policy.configPath`
  and the overrides when it is read and an empty `policy` when it is not, and
  `scripts/check-bundle-policy.sh` now asserts that the RESOLVED path is this
  bundle's own file and that each named rule sits at the named severity — the
  path value, not merely the presence of a `configPath` key, so a config
  supplied from anywhere else cannot satisfy it. It parses the JSON with
  `python3` for the reason `dev:verify-pins` states: `jq` is not pinned. A run
  that fails for any other reason reproduces the CLI's own stderr instead of
  blaming discovery; an unknown rule name, for instance, is rejected at
  config-parse time with exit 2 and no JSON at all (measured).
  `scripts/check-knowledge-gate-bite.sh` proves that checker still
  discriminates, across six scenarios including a conforming one, and both run
  from `knowledge:validate` — the pairing `spec:validate` already uses for the
  staleness gate. A detector for a silent failure is worth nothing without one.
- `index.md`: the tooling-config carve-out now says the placement is mandatory
  rather than merely tidy, since 0.12.0 reads the file only from inside the
  bundle and only under the dotfile name, and the link-rule bullet names the
  dotfile. The carve-out itself is unchanged — it is still narrow.
- `reference/tasks.md`: re-read against its sources and it had drifted, which
  is the whole argument for re-verifying rather than re-dating. Its rules-apply
  row named the pre-0.12 command; its `knowledge:validate` row now describes
  the two new gates and the version precondition; and its tool-pin bullets
  stopped quoting the openknowledge and lychee VALUES, naming the Taskfile
  variables instead. A copied version is a second place to go stale, and this
  one had: it still read 0.5.0 in the change that bumps the pin. Those two are
  safe to reduce to a pointer because `dev:verify-pins` asserts them against
  `.tool-versions`. The three MCP values in the same list are asserted against
  nothing, so a pointer would leave no record at all; they stay written out,
  with a clause saying why they differ from their neighbours.
- `rules/talos-base-bundle.md`: the re-verification criterion is narrowed to
  "a change that lands inside what the concept describes", not "a listed source
  file was touched". Twelve concepts list `Taskfile.yml` and this change edits
  it; dating all twelve would record reviews that did not happen, which is the
  false freshness the rule exists to prevent. The narrowing is a maintainer
  decision on the record, not a side effect — the discarded alternative was to
  keep the literal rule and re-verify all twelve. Its link-rule bullet also
  names the dotfile, and it gained one: invoke the CLI through the
  `knowledge:*` targets, never bare. This entry's first draft said the file
  needed no edit, which was wrong on its own terms — the narrowing is that
  edit.
- `workflows/spec-driven-development.md`: re-read against its sources for the
  same reason and needed no edit beyond the date.
- `decisions/0015-openspec-adoption.md`: a dated clarification is appended
  saying the file is now `knowledge/.openknowledge.toml` and that recreating
  the old name would silently do nothing. The record text above it is
  untouched, including the legacy filename in its parenthesis — that is the
  name the CLI used at the time.

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

## 2026-07-11

- Initial OKF v0.1 bundle. Replaces the retired `docs/` tree: architecture,
  reference, workflow, and glossary concepts regenerated from repository
  source; 13 ADRs migrated to `decisions/` with MADR frontmatter mapped to
  OKF and present-tense claims re-verified against code;
  `component-dependencies.md` dissolved into `architecture/substrate.md`;
  `oci-artifact-verification.md` merged into `workflows/verify-release.md`;
  machine-consumed contracts relocated outside the bundle
  (`platform-hardware-features.yaml`, `schemas/`, `contracts/`).
