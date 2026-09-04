# Changelog

This file follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Pending release

Entries awaiting the next tag. A by-hand release cut moves **this block only**
under the new version heading; the historical backfill below it stays put.

- **Fixed — a GitHub Release again ships its tarball, `checksums.txt`, and
  SBOM.** Release immutability freezes a release when it is **published**, and
  semantic-release published the release object the moment it tagged, before
  the assets existed — so every asset upload the publish workflow attempted was
  refused with HTTP 422. `@semantic-release/github` is removed; the publish
  workflow is now the sole creator of the release, creates it as a draft,
  attaches the three assets, and publishes it last. The published release is
  verified on the draft before it is published and read back afterwards, and
  any publish failure — including a cancelled one — opens a tracking issue
  instead of only reddening a run on a tag nobody watches. Release notes now
  come from the matching hand-cut CHANGELOG section on **every** release,
  falling back to auto-generated notes where no section exists (which is the
  common case today: no section has been cut since `v9.1.0`, tracked in #233).
  Seven already-published tags carry no assets and cannot be backfilled —
  immutability is the point of the setting. `v9.2.2`, `v9.2.3`, `v10.0.0`,
  `v11.0.0` and `v11.0.1` have intact, signed, attested OCI artifacts, so the
  `oras pull` path consumers are told to use is unaffected for them; `v9.1.2`
  and `v9.2.0` failed earlier still and have **no published artifact at all**,
  so they must not be pinned. Both groups are recorded in
  [`knowledge/workflows/verify-release.md`](knowledge/workflows/verify-release.md).
  Because release creation now happens in the job that also holds the signing
  identity, that job's five actions are pinned by commit SHA instead of a
  mutable tag, and every `run:` block there reads its values from `env:`
  rather than from a `${{ }}` interpolation the shell would parse; a check in
  the required `docs-lint` context keeps both properties, and the absence of
  the publish plugin, from regressing. `CHANGELOG.md` joins the release
  surface in `CODEOWNERS`, since its matching section is the release body.
  Fixes #251.
- **Added — a CI fence bounding what the `config_patches` escape hatch can
  actually carry, and a Talos 1.14 readiness statement.** Talos 1.14.0 went
  generally available on 2026-09-03. The base pins no Talos version, so nothing
  here forces the move — and deliberately nothing moves: the examples and
  fixtures stay on 1.13.9. What changes is that the boundary is now measured
  instead of assumed. `scripts/check-provider-document-kinds.sh`
  (`task tofu:check:provider-document-kinds`, inside `tofu:ci`) probes the
  pinned `siderolabs/talos` provider with a locally generated PKI — no cluster,
  no Image Factory — and asserts three things: a provider-registered document
  kind survives the patch path, the Talos 1.14 kinds do not, and a `v1.14.0`
  pin yields none of the 1.14 default documents. The finding it fixes is that
  the module's four opaque patch lists are an escape hatch onto the PROVIDER's
  document surface, not onto Talos': the provider decodes every patch against
  its own bundled machinery, so `SecurityProfileConfig`,
  `FilesystemTrimConfig`, `KubeNodeConfig`, `UnattendedInstallConfig` and
  `BGPInstanceConfig` are each refused with `"<kind>" "v1alpha1": not
  registered` on provider `0.11.0`. Two consequences a consumer must know
  before pinning 1.14 now live in the module README §"Talos 1.14: reachable and
  unreachable": a cluster bootstrapped at a 1.14 pin runs WITHOUT the
  workload isolation and filesystem trim Talos enables by default for new 1.14
  clusters, with no way to opt in; and `reboot` is a `*_apply_mode` value Talos
  1.14 removed from `talosctl apply-config`, whose behaviour over the provider's
  API path is unverified. The fence is an expiry alarm by construction — two of
  its cases assert a rejection, so it turns red the day a signed provider inside
  the declared `>= 0.7.0, < 1.0.0` range ships the 1.14 machinery, which is the
  signal to revisit rather than a breakage to patch out. Today only
  `0.12.0-beta.0` carries it and `tofu init` refuses it as unsigned.
  `knowledge/decisions/0026-machine-config-apply-mode.md` gains the matching
  addendum, and the follow-up — reaching the 1.14 document surface, then moving
  the pins — is tracked in
  [#252](https://github.com/Nosmoht/talos-platform-base/issues/252).
- **Fixed (BREAKING) — the OCI artifact now contains the complete runtime
  `talos-cluster` module.** The allowlist adds `cilium-values.tf`,
  `composition.tf`, `kubeconfig-refresh.tf`, `nodes.tf`, and `profiles.tf`, so a
  consumer can extract the artifact and use the vendored module without
  missing local references. CI derives the required root `.tf` set from git and
  runs `tofu init -backend=false` plus `tofu validate` against the extracted
  payload. The payload layout therefore gains five published paths; git-only
  examples and bootstrap helpers remain outside the artifact. Fixes #158.
- **Changed (BREAKING) — the `argo-cd` chart moves `9.4.5` → `10.6.0`, Argo CD
  `v3.3.2` → `v3.5.2`.** Both render paths bump together —
  `kubernetes/substrate/argocd/chart.lock.yaml` and the `argocd_chart_version`
  default the parity gate binds to it. The breaking part is a chart default the
  base does not override: `10.0.0` flipped `global.networkPolicy.create` to
  `true`, so the steady-state render AND the Day-0 seed now carry five
  `networking.k8s.io/v1` NetworkPolicies, which Cilium enforces in every
  consuming cluster. `argocd-server` keeps an open ingress rule, so a consumer
  gateway in front of it is unaffected; ingress to `argocd-repo-server` and
  `argocd-redis` is restricted to the Argo CD components that call them, and a
  workload of yours reaching either directly needs its own allow-policy. No
  policy carries an empty `podSelector`, so this is not a namespace default-deny.
  The chart also changes the reconciliation timer from a fixed `180s` to a
  `120s` base plus up to `60s` jitter. Substrate invariant **I6** asserts the
  complete posture in both paths — `apiVersion`, namespace, selectors, ingress
  peers and ports, `policyTypes`, no higher-precedence policy kind riding along,
  and every named port cross-checked against the target workload's
  `containerPort` names — and for the steady state on the kustomize-built
  component as well as on the fresh helm render, so a hand edit to the committed
  `_rendered/` tree cannot ship a weakened posture. A set that no longer matches
  is a violation, not a render-shape error. Twelve mutation-based bite tests back
  it. `argocd-applicationset-controller` is deliberately unpoliced — the chart
  gates its policy on `applicationSet.{metrics,ingress,httproute}`, none of which
  the base enables, so no policy is emitted for it and its `webhook`, `metrics`
  and `probe` ports are reachable cluster-wide — which `UPGRADING.md` now states,
  together with why enabling `applicationSet.metrics` alone is not the fix (the
  metrics rule is unconditional in the template and the webhook rule is not, so
  metrics-only default-denies the webhook port). Argo CD 3.5 is tested against
  Kubernetes v1.33-v1.36 and **drops v1.32**. Argo CD's own 3.3→3.4 and
  3.4→3.5 upgrade notes apply unchanged and are summarised, with the audit and
  validation steps, in [`UPGRADING.md`](UPGRADING.md) §`v10.0.0`. The three CRDs
  are additive at this bump (new `tagPrefix` and `hydrateTo.repoURL`, no field
  removed) and gain `argocd.argoproj.io/sync-options: ServerSideApply=true`;
  adr-0025's revisit trigger was re-run at the new pin and holds.
- **Changed — a chart-version default bump now carries a stated obligation.**
  `module-interface-contract` gains a requirement fixing the observable half:
  because the declared default is the single source of truth for the pinned chart
  and the shipped examples leave the key unset, moving it is a consumer-visible
  change — and it names exactly which paths it reaches, since the seed renders are
  frozen. A fresh bootstrap and a deliberate replacement seed the new chart; an
  already-bootstrapped consumer's machine config does not change, and the new
  chart reaches a running cluster through the steady-state sync and the
  chart-version-triggered CRD apply. The delta belongs on the capability
  describing what the pin renders or seeds. The review obligations it implies —
  no `Spec-Impact: none` for the variables file, and re-verifying the upstream
  Kubernetes support range and upgrade notes for the adopting consumer — are
  repo-internal QA and live in `knowledge/reference/manifest-pipeline.md`
  §Chart pin. Prompted by this release: the argo-cd bump's module-side commit
  claimed that escape on a change its own entry above calls BREAKING.
- **Added — the machine-config apply mode is selectable per role.**
  `controlplane_apply_mode` and `worker_apply_mode` plumb the talos provider's
  `apply_mode` to the per-node machine-config apply. Both default to `auto`, so a
  consumer that sets neither keeps the previous behaviour exactly. Setting a role
  to `staged` writes the configuration without rebooting, which turns a
  reboot-bound change to a stateful role from an unsequenced parallel reboot of
  that whole role into a deliberate operator roll: reboot out of band, one node at
  a time, under whatever health gate the workload needs. Between the staged apply
  and that reboot the state file and the node's effective configuration disagree
  and a later plan is clean — closing the window is the operator's obligation.
  `auto` stays the default because the same apply resource carries the Day-0
  install. The keys are reachable from `cluster.yaml`
  (`cluster.controlplane_apply_mode` / `cluster.worker_apply_mode`) and the
  module exposes a `node_apply_mode` output, which is the only signal that a
  window is open — it reports the configured mode, never what a node holds, and
  health stays green and the next plan is clean while a window is open.
  What the window obliges an operator to — the revert-last invariant, which roles
  a change reaches, and the Talos 1.14 behaviour change — is the module README's
  §"Staged machine-config roll (Day-2)"; the reboot sequence itself is a
  consumer-side procedure, since rehearsing it needs a cluster. See
  [`knowledge/decisions/0026-machine-config-apply-mode.md`](knowledge/decisions/0026-machine-config-apply-mode.md),
  which also records why `staged_if_needing_reboot` is documented but
  rejected — the module's validation refuses it, so setting it fails at plan
  time rather than merely being discouraged.
- **Fixed — the MAJOR-bump guard no longer blocks on files no consumer
  receives.** Its surface set moved out of `.github/workflows/release.yml` into
  `.ci-release-guard-pathspec.txt` (membership rule in that file's header), with
  `schemas/fixtures/**` excluded. Three pushes to `main` were blocked for ten
  days on a negative lint fixture and a schema description. The guard also stops
  failing open: an empty `NEXT`, a `git diff` error, a shallow checkout and a
  pathspec that matches nothing are now environment errors rather than a silent
  pass.
- **Changed — five published paths are newly guarded**, including
  `tofu/modules/talos-cluster/helm/{argocd,cilium}-values.yaml`, the shipped base
  Helm values. A change to any of them now needs a MAJOR bump or an
  `Allow-Non-Major:` attestation. Contributor-visible: the attestation is read
  from the merge commit **body**, is honoured only on a merge commit, and refuses
  a placeholder reason.
- **Changed — the release path now requires merge-commit-only**, with an empty
  default merge body and a required `Commit Lint`. These are repository settings,
  applied by the maintainer rather than by this change. `scripts/preflight-checks.sh`
  reports them, but only for a run with admin credentials: measured, the default
  CI token reads those fields back as `null`. The controls that hold regardless
  are in the guard — an attestation counts only on a merge commit, and only with
  maintainer prose above the trailer, which is what a PR-title-derived body
  cannot contain. `AGENTS.md §Issue-Interface` `state:close` gains
  the `--subject`/`--body` form — the bare `--merge` form cannot carry an
  attestation.
- **Added — a failed or blocked release now files a tracking issue**
  (ADR-0020's listed follow-up), and a `release-guard-advisory` job tells a PR
  author before merging whether their branch touches a guarded path.
- **Changed — the example and fixture versions now track Talos v1.13.9 /
  Kubernetes v1.36.3** (was v1.12.6 / v1.35.0). The base pins neither:
  `talos_version` and `kubernetes_version` are required module inputs whose
  only constraint is a version-agnostic semver regex, so this moves the values
  a consumer copies when standing up a new cluster and nothing else. Every
  extension and overlay the repo names resolves at v1.13.9 against the Image
  Factory. Existing clusters are unaffected — an OS upgrade still means
  bumping `talos_install_version`, never the bootstrap-fixed `talos_version`.
- **Changed — the worked example is a composition-coverage matrix**, not a
  deployment. `tofu/modules/talos-cluster/examples/complete/cluster.yaml` now
  carries one node per distinct composition path (6 nodes, 3 images) instead
  of a specific eight-node hardware inventory, and its images are named for
  what distinguishes them (`amd64`, `amd64-hugepages`, `arm64-sbc`). The GPU
  node now shares the plain `amd64` image and still resolves to its own
  schematic, because `nvidia-lts` contributes the extensions from the profile
  catalog — which is what ADR-0009 says should happen. Coverage is unchanged:
  mixed amd64/arm64, an SBC overlay, per-image kernel args, per-node patches,
  both role-tier patch lists, and a node holding a set of two capabilities.

### Historical backfill

> Every entry from `### Added` onward shipped in `v7.0.0` through `v9.0.0`:
> those tags were cut without a CHANGELOG section, and nothing in this block is
> awaiting release. `UPGRADING.md` headings already carry the tag each migration
> shipped in, so the two files disagree until the backfill tracked in #233 lands.

### Added

- **`talos-cluster`: `register_with_fqdn` input (bool, default `false`).** Sets
  `machine.kubelet.registerWithFQDN`. Talos splits a dotted hostname at the
  first dot and registers only the SHORT hostname with Kubernetes by default, so
  a dotted node name silently lost its domain part; the input makes FQDN node
  names actually reach Kubernetes, and dotted node keys are rejected while it is
  off. Default-off emits no machine-config change. See
  [ADR-0023](knowledge/decisions/0023-node-identity-map-key.md).

- **`talos-cluster`: two further typed Cilium observability inputs (default off).**
  `cilium_agent_metric_overrides` (the chart's `prometheus.metrics` `+metric` /
  `-metric` delta list against its default metric set) and
  `cilium_hubble_open_metrics` (`hubble.metrics.enableOpenMetrics`). Both flow
  through the same computed-values map the seed and the emitted self-management
  Application already share, so they are reachable without
  `cilium_values_override` — which the override-drop guard makes mutually
  exclusive with `cilium_self_management`. Each warns (plan-time `check`, not a
  rejection) when its prerequisite toggle is off, because a consumer may enable
  that prerequisite through `cilium_values_override`, which the module cannot
  introspect. `cilium_agent_metric_overrides` entries are format-validated: the
  chart renders them raw into `cilium-config`, which is baked into the
  controlplane machine config. **`cilium_hubble_open_metrics` changes only the
  ConfigMap and does not roll the agents** — see UPGRADING for the required
  rollout restart. Grafana dashboards stay deliberately untyped (apps-catalog
  territory — the base cannot know the consumer's Grafana sidecar label or
  namespace). See
  [ADR-0022](knowledge/decisions/0022-cilium-observability-and-argocd-self-management.md).
- **`talos-cluster`: first-class Cilium observability inputs (default off).**
  `cilium_agent_metrics`, `cilium_operator_metrics` (Cilium agent/operator
  Prometheus metrics), `cilium_hubble_enabled` + `cilium_hubble_metrics`
  (Hubble flow/metrics, metrics-only scope — no Relay/UI). Layered into the
  same computed-values map the bootstrap seed has always used, so they flow
  through the existing floor ⊕ computed ⊕ override Helm-deep-merge with no
  new data-flow. `cilium_hubble_enabled=true` forces
  `hubble.tls.enabled=false`; grounded via T1 Cilium docs that the Hubble
  metrics scrape endpoint is independent of the observer-API TLS setting, so
  this does not disable metrics export. See
  [ADR-0022](knowledge/decisions/0022-cilium-observability-and-argocd-self-management.md).
- **`talos-cluster`: opt-in Cilium ArgoCD self-management delivery mode
  (default off).** `cilium_self_management` emits a new
  `cilium_self_management_app` output — a rendered Cilium ArgoCD
  `Application` manifest — so a consumer's existing ArgoCD can adopt
  steady-state Cilium management the same way it already can for ArgoCD
  itself. The module only renders the manifest; it never applies it (no
  `kubectl`, no live-apply resource — AGENTS.md §Hard Constraints). Requires
  `deploy_argocd=true` AND `deploy_cilium=true`. **Hard-rejected at plan
  time** while `cilium_values_override` is non-empty: the emitted manifest
  does not inherit that override, so enabling self-management with a
  seed-active datapath override (BGP/L2/bpf) would otherwise silently drop
  it on adoption. `cilium_self_management_project` selects the target
  `AppProject` (default `"default"`; a scoped project is recommended
  hardening — see the module README). See
  [ADR-0022](knowledge/decisions/0022-cilium-observability-and-argocd-self-management.md).

### Changed — BREAKING

- **`argocd`: the substrate ships no identity.** `configs.rbac.policy.csv` and
  `configs.rbac.scopes` are removed from
  `kubernetes/substrate/argocd/values.yaml`, and `configs.cm.url: ""` is added
  to both render paths. The base carried a hardcoded `role:admin` binding for a
  single named principal — an organisation-specific grant on a cluster-agnostic
  floor — and a `url` derived from the chart's placeholder hostname, which fails
  at the identity provider rather than in the cluster.

  Reading the diff: the chart's `argocd-rbac-cm` template emits both RBAC keys
  unconditionally, so the render now carries `policy.csv: ""` and the
  chart-default `scopes: '[groups]'`. Removed here means empty-but-present
  there. `policy.default: ''` stays.

  **BREAKING — migration:** a consumer relying on the shipped binding loses
  access at the next sync unless their overlay supplies **both** `policy.csv`
  **and** the `scopes` value their subjects are written against, in the same
  commit as the pin bump. Carrying only `policy.csv` is the lockout path — the
  claim silently reverts to `groups`. Full procedure and recovery:
  [`UPGRADING.md`](UPGRADING.md). The wiring contract for any external OIDC
  provider is
  [`knowledge/reference/argocd-sso-contract.md`](knowledge/reference/argocd-sso-contract.md),
  with a worked overlay in `kubernetes/examples/argocd-consumer-sso/`.

- **`talos-cluster`: the Day-0 ArgoCD `kubectl apply` delivers CRDs and nothing
  else.** It previously applied the argo-cd chart's **full default render** —
  twelve kinds, bundled Dex included — with
  `kubectl apply --server-side --force-conflicts`, re-firing on every
  `kubernetes_version` change. That contradicted substrate invariants I1/I2 at
  runtime while CI reported green, overwrote the seed's own `server.insecure`
  and `kustomize.buildOptions` with chart defaults, and reset `argocd-rbac-cm`
  — which, with the identity removal above, is where a consumer's entire access
  policy now lives.

  The render is now projected to `CustomResourceDefinition` documents before
  being frozen, applied under a dedicated `--field-manager` and **without**
  `--force-conflicts`, and `kubernetes_version` leaves `triggers_replace` (the
  CRD payload is byte-identical across Kubernetes versions — measured). ArgoCD
  owns those CRDs from its first steady-state sync; the module seeds and steps
  back. Not retroactive: an existing cluster keeps the `kubectl` field-manager
  entries the old apply recorded. See
  [ADR-0025](knowledge/decisions/0025-argocd-crd-apply-scope.md).

- **`argocd`: `kustomization.yaml` now ships in the OCI artifact.** The
  component's rendered manifests were consumable from a vendored tag; the file
  that makes them a buildable unit was not.
  `scripts/check-substrate-consumability.sh` now requires it for every
  renderable component — and checks it against the resources the kustomization
  actually names, rather than a hardcoded filename list, so a component whose
  resource set changes cannot ship a kustomization pointing at a file the
  artifact omits. Additive for consumers — no action required.

### Added

- **Substrate invariants I5 and P, and the consumer-overlay E-checks.** I5
  asserts the steady-state `argocd-rbac-cm` ships no non-empty `policy.default`
  — a key with a strictly wider blast radius than `policy.csv`, since it grants
  its role to every authenticated principal with no subject at all, and the one
  key of the pair that was previously ungated. P asserts the module's
  `argocd_chart_version` default equals `chart.lock.yaml`'s version: formerly a
  documented deferral, promoted to a gate because a pin divergence now fails
  every consumer's next `tofu apply` rather than being force-resolved. The
  E-checks build the worked consumer overlay against an unpatched control build,
  so the documented SSO wiring cannot drift from what the component accepts.

- **`talos-cluster`: `nodes` is a MAP keyed by node name, not a list.** The
  per-node `hostname` field is removed — the key *is* the hostname, so a node is
  declared exactly once and a duplicate node name is no longer expressible
  rather than merely rejected. Every Talos-facing list
  (`cluster_health.{control_plane_nodes, worker_nodes, endpoints}`, the
  talosconfig `endpoints`/`nodes`, `output.controlplane_ips`) becomes a
  projection of that map ordered by node name, so declaration order is not
  observable anywhere. `schemas/cluster.schema.json` types `nodes` as an object
  with a `propertyNames` pattern constraining the FORM of node keys (it does not
  — and structurally cannot — detect a repeated YAML key, which the parser
  collapses first; the module-side map type is what makes a duplicate node
  unexpressible).
  **BREAKING — migration:** `cluster.yaml` `nodes:` becomes a mapping and the
  consumer shim maps it through; the mechanical recipe plus a
  nothing-was-lost diff is in [`UPGRADING.md`](UPGRADING.md). Runtime-neutral:
  the per-node apply resource keeps the same `for_each` keys, so an unchanged
  node set must produce a **zero-diff plan** — a non-empty plan means the
  conversion changed something and must not be applied. See
  [ADR-0023](knowledge/decisions/0023-node-identity-map-key.md).
- **`talos-cluster`: five new plan-time rejections on the node set.** Each closes
  a failure mode the list model left silent: an EVEN controlplane count (etcd
  quorum — an even membership tolerates no more failures than the odd count
  below it); a node key that is not already a canonical Kubernetes node name
  (Talos validates hostname LENGTH only, then silently rewrites the rest via
  `nodename.FromHostname` — so `NODE_01` used to arrive as `node-01`, and two
  keys could collapse onto one node); two node keys sharing a first label while
  `register_with_fqdn` is off (Talos splits the hostname at the first dot, so
  both kubelets would claim one Node object — permitted once FQDN registration
  makes the full name the Kubernetes identity); a dotted node key while
  `register_with_fqdn` is false (Kubernetes would only ever see the first
  label); and a non-canonical `node.ip` (`192.0.2.011`, `::ffff:192.0.2.11` —
  distinct strings naming one host, which used to slip past the ip-uniqueness
  check and point two apply resources at one machine).
  **BREAKING — migration:** a consumer running an even controlplane count, a
  non-canonical node name or a non-canonical IP must fix it before planning.
  Renaming a node is a real identity change — new state address, new Kubernetes
  node. Note the odd-count rule also blocks *shrinking* a control plane to an
  even count: replace a dead member's entry rather than deleting it.
- **`talos-cluster`: OpenTofu floor raised to `>= 1.9`.** The new
  cross-variable `validation` guards above require it. This applies to
  **every** consumer of the module, not only those opting into
  `cilium_self_management` — a consumer on OpenTofu `< 1.9` cannot
  `plan`/`apply` this module version at all until upgrading their OpenTofu
  binary. See [ADR-0022](knowledge/decisions/0022-cilium-observability-and-argocd-self-management.md).
- **`schemas/cluster.schema.json`: `substrate.cilium` is now closed
  (`additionalProperties: false`).** A consumer `cluster.yaml` with an
  extra or misspelled key under `substrate.cilium` now fails
  `check-jsonschema` at lint time instead of being silently dropped by the
  `try()`-based shim. Fix by removing/correcting the offending key. See
  [ADR-0022](knowledge/decisions/0022-cilium-observability-and-argocd-self-management.md).

### Changed

- **`talos-cluster`: `cilium_native_routing_cidr` is now format-validated.**
  It must be empty (derive from `pod_cidr`, unchanged) or a well-formed CIDR.
  The chart renders the value raw and unquoted into `cilium-config`, which the
  module bakes into the create-only controlplane machine config, so a value
  carrying a newline wrote arbitrary ConfigMap keys — the same corruption class
  the two Cilium metric lists already guard against, on the third input
  reaching the same document. The guard is a semantic CIDR predicate rather
  than a lexical rule, so it also rejects an address with no prefix length. A
  consumer passing a malformed value now fails at plan time (and at
  `cluster.yaml` lint time, via the schema mirror) instead of shipping it into
  the machine config.

- **New CI fence `task tofu:check:shim-key-parity`.** The worked example's
  shim reads `cluster.yaml` through `try()`, which is total: a substrate key
  the shim never reads — or reads misspelled — silently resolves to the module
  default while schema lint, `tofu validate`, `tofu plan` and the whole test
  suite stay green, so the consumer's declared value never reaches the module.
  The check asserts every key of every closed `substrate` object in
  `schemas/cluster.schema.json` is read by the shim. Carried by `task tofu:ci`;
  `.github/workflows/tofu-validate.yml` now also triggers on
  `schemas/cluster.schema.json` so a schema-only widening still runs it.

- **`kubernetes/bootstrap/cilium/values.yaml` is now gated against the pinned
  chart's schema.** Nothing in CI ever rendered this file, so a value the chart had
  REMOVED was dropped silently by Helm — exactly what happened to
  `encryption.strictMode.*` at Cilium 1.20, leaving strict-mode encryption
  unconfigured for anyone who copied it. `scripts/check-cilium-reference-values.py`
  validates every value path against the chart's own `values.schema.json` and fails
  naming each undeclared path. Wired into both `task gitops:validate` and the
  `gitops-validate.yml` validate job — same script, same verdict. It reads the chart
  version from `variables.tf`, so it cannot drift from what the module renders. Two
  stated trade-offs: a chart-registry outage SKIPS loudly rather than failing (an
  outage must not block unrelated merges, so during one a removed spelling can
  merge), and a changed DEFAULT under a spelling that still parses stays
  reviewer-enforced, since no values schema can express it. See #211.
- **`talos-cluster`: the Cilium seed's rendered `cilium-config` surface is now
  pinned.** The seed bypasses the kustomize/conftest render gate, and nothing
  asserted a single key of it — so a chart bump could move a datapath- or
  security-relevant default into the create-only machine config unnoticed. That is
  what the 1.20 bump did with `bpf-lb-algorithm-annotation`. Two layers now bind
  it: the full key set against `tests/fixtures/cilium-config-keys.txt`, and the
  values of a curated set (`bpf-lb-algorithm-annotation`,
  `kube-proxy-replacement`, `enable-host-firewall`, `enable-datapath-plugins`,
  `gateway-api-use-remote-address`). Both are needed — the key set alone would not
  have caught 1.20, since only the value moved. A future bump refreshes the fixture
  deliberately and answers the consumer-facing question in
  [UPGRADING.md](UPGRADING.md). See #212.
- **`talos-cluster`: the summed inlineManifest payload is now bounded at plan
  time.** Talos receives ONE controlplane document carrying every seed at once
  (cilium + argocd + cert-approver), and an oversized document failed at APPLY
  against real hardware after a clean plan. A precondition on
  `data.talos_machine_configuration.controlplane` now rejects it at plan, naming
  the summed byte count, the ceiling, and which seeds are enabled. The ceiling is
  **sourced**: Talos' `GRPCMaxMessageSize = 32 * 1024 * 1024`
  (`pkg/machinery/constants/constants.go` at `v1.11.0`), which caps the
  `ApplyConfiguration` message, minus headroom for the generated base document and
  the pass-2 per-node overlays. The previous `~66 KB` figure in `main.tf` had no
  source and is three orders of magnitude off — removed. See #213.
- **`talos-cluster`: the chart-version pin is now single-source, and a `null`
  input selects the base's pin.** `cilium_chart_version` and `argocd_chart_version`
  declare `nullable = false` beside their defaults, so a caller may pass `null`
  and OpenTofu substitutes the module default. The example shim now passes
  `try(local.<component>.chart_version, null)` and the shipped `cluster.yaml`
  examples leave `chart_version` commented out, which means the version literal
  exists in exactly one place per component (`variables.tf`) instead of three.
  Why it matters: previously both consumer-facing copies passed the version
  explicitly, so the module default was never consulted and a base chart bump
  could not reach an existing consumer at all. **Non-breaking** — an explicit
  value still wins; a consumer who omits the key moves from "whatever literal my
  shim was copied with" to the base's pin. The contract is per-input, not
  module-wide: no other input promises null-means-default, and passing `null` to
  one without `nullable = false` yields `null`. Adoption steps in
  [UPGRADING.md](UPGRADING.md). See #210.
- **`talos-cluster`: Cilium chart pin `1.19.4` → `1.20.0`.** Cilium 1.20.0
  (released 2026-07-29) is the base's new substrate CNI seed version. This is a
  **SEED knob**: `terraform_data.cilium_render` carries `ignore_changes` and
  Talos `inlineManifests` are create-only, so the bump does not upgrade a
  running Cilium — it applies to fresh bootstraps, and to consumers who
  deliberately sync the emitted self-management Application (whose
  `targetRevision` tracks the pin). It also does not reach an existing consumer
  by itself, because their own `cluster.yaml` and shim pin the chart and win over
  the module default — see the chart-version single-source entry below for the two
  ways to adopt it. Kubernetes is a **precondition, not a given**: the module
  does not pin `kubernetes_version`, and Cilium 1.20 lists 1.33–1.36 as
  e2e-tested, so a cluster on 1.32 or earlier needs a Kubernetes upgrade first or
  should stay on Cilium 1.19. Re-verified at the new pin: seed render
  determinism, the four
  `cilium-config` observability marker keys, and the `hubble-metrics` `:9965`
  Service all hold, and ADR-0022's `operator.prometheus.enabled` revisit
  trigger did not fire — recorded as a dated addendum in
  [ADR-0022](knowledge/decisions/0022-cilium-observability-and-argocd-self-management.md).
- **Newly tunable Gateway API knob, same behavior: `gatewayAPI.useRemoteAddress`.**
  The Helm value does not exist in chart 1.19.4 and defaults to `true` in 1.20.0
  (`gateway-api-use-remote-address: "true"` in `cilium-config`). The default
  preserves 1.19 behavior — Cilium 1.19 hardcoded the same Envoy
  `UseRemoteAddress: true` in its Gateway listener translation, and 1.20 keeps
  that literal while making it overridable. `true` means the source IP comes from
  the connection peer rather than a forwarded or proxy-protocol header, so a
  client-supplied `X-Forwarded-For` is not authoritative; `false` is the setting
  that makes a forwarded address authoritative and belongs only behind a trusted
  proxy. No action required. See [UPGRADING.md](UPGRADING.md) §2.
- **Datapath default flipped by Cilium 1.20 when Gateway API is enabled:
  `bpf-lb-algorithm-annotation` `"false"` → `"true"`.** 1.20's ConfigMap template
  forces this key on whenever `gatewayAPI.enabled`, which the base sets by
  default. Consequence: a `service.cilium.io/lb-algorithm` annotation that was
  inert now selects the per-Service load-balancing algorithm for real — audit any
  existing annotation before a fresh bootstrap or self-management sync. Rendering
  the base's default value set against both charts shows this as the **only**
  changed `cilium-config` value. See [UPGRADING.md](UPGRADING.md) §2.
- **Datapath behavior change inherited from Cilium 1.20: in-cluster NodePort
  traffic is load-balanced at the client pod.** With kube-proxy replacement on
  (the base default) and SocketLB disabled (the chart default the base does not
  override), connections from regular pods to NodePort Services are now
  load-balanced as traffic leaves the client pod instead of at the target node,
  per Cilium's 1.20 release notes. Client NetworkPolicy must now allow egress to the Service's
  backends, and backend NetworkPolicy must allow ingress from the client. No
  base value changed; this is upstream behavior every consumer on default
  settings inherits. See [UPGRADING.md](UPGRADING.md) §4.
- **Gateway API CRD floor documentation: v1.4.1 → v1.6.1.** Cilium 1.20
  requires Gateway API v1.6.1 at a minimum, because `TLSRoute` graduated from
  `v1alpha2` to `v1`. `cilium_gateway_api_crds_url` still defaults to `""`
  (CRDs remain a Day-1 GitOps concern), but its documented bundle URL and the
  module README now point at v1.6.1. TLSRoute is in the **standard** channel as
  of v1.6.1, so standard alone now satisfies the Gateway-API-only Hard
  Constraint — the previous "use the experimental bundle for TLSRoute" guidance
  is retired. Consumers carrying pre-existing `v1alpha2` TLSRoute objects must
  still use the experimental bundle: standard v1.6.1 declares `v1alpha2` but
  does not serve it. See [UPGRADING.md](UPGRADING.md).
- **`kubernetes/bootstrap/cilium/values.yaml`: `encryption.strictMode.*`
  migrated to the nested `egress.*` form.** Cilium 1.20 removed the flat
  `strictMode.{enabled,cidr,allowRemoteNodeIdentities}` keys (deprecated in
  1.19). Because Helm does not run `--strict`, the old spelling was **silently
  dropped** on chart 1.20 — strict-mode encryption would not have been
  configured, with no error. The new spelling renders identically on 1.19.x, so
  it is safe for a consumer still pinning the previous minor. This file is
  reference-only (not consumed by the seed render), but it is what a consumer
  copies into a Day-2 self-managed Application.
- **`kubernetes/bootstrap/cilium/values.yaml`: three inert keys removed.**
  `policySecrets.enabled`, `encryption.wireguard.userspaceFallback` and
  `loadBalancer.l2.enabled` are recognized by **neither** chart 1.19.4 nor
  1.20.0 — no `values.yaml` entry and no template reference in either. Verified
  inert by rendering the file against both charts before and after removal: the
  output is byte-identical, so nothing a consumer copying this file relies on
  changes. `loadBalancer.l2.enabled` was also redundant with the adjacent
  `l2announcements.enabled`, which does render.

### Fixed

- **`talos-cluster`: the Day-0 ArgoCD apply no longer pushes chart defaults over
  ArgoCD's own state.** `data.helm_template.argocd_crds` renders the chart with
  no values block, and the module applied that entire render with
  `kubectl apply --server-side --force-conflicts` — twelve kinds, not just the
  CRDs. Every provisioned cluster therefore received a bundled `argocd-dex-server`
  and `server.dex.server*` cmd-params (contradicting substrate invariants I1/I2
  at runtime while CI stayed green), had the seed's `server.insecure` and
  `kustomize.buildOptions` overwritten, and had `argocd-rbac-cm` reset to chart
  defaults. Because the trigger set includes `kubernetes_version`, a routine
  Kubernetes upgrade re-fired all of it. The render is now projected down to
  `CustomResourceDefinition` documents before the freeze and applied without
  `--force-conflicts`. **Existing clusters are not repaired retroactively** —
  `kubectl` stays a recorded field manager on what it already touched; this stops
  future applies from re-taking it. New: output `argocd_day0_apply_kinds`,
  invariant **I3** (the seed's `argocd-cm` carries no placeholder `url`), and
  `tests/argocd-crd-scope.tftest.hcl`. See
  [ADR-0025](knowledge/decisions/0025-argocd-crd-apply-scope.md).

- **Spec-staleness gate: syncing a branch with `main` no longer voids the
  `Spec-Impact: none` escape.** The gate granted the escape only when EVERY
  commit git lists for the violating file carried the trailer — and a base-sync
  merge is listed for every file both sides touched. Branch protection requires
  up-to-date branches, so that merge is forced on every PR, and the only
  remedies left were rewriting history or editing a spec the change does not
  affect. Attribution is now by CONTRIBUTION: a merge whose content for the file
  equals what a mechanical 3-way merge of its parents yields introduced nothing
  to certify and is skipped, while a hand-resolved conflict or an evil merge
  stays a contributor and must carry the trailer itself. The obvious cheaper
  test, `diff-tree --cc` emptiness, is unsound — `--cc` compresses per hunk, so
  a clean auto-merge of two edits three lines apart still prints hunks — so the
  gate re-runs the merge (`merge-tree --write-tree`, git >= 2.38) and compares
  the recorded tree entry (mode, type and object id, not the object id alone: a
  merge that flips an exec bit or turns the path into a symlink contributed
  something even when the blob is unchanged, and two spec-owned primary sources
  are shell scripts CI runs with no interpreter prefix). Anything the comparison
  cannot decide counts as a contribution, and every git call now runs under
  `GIT_LITERAL_PATHSPECS` so a source name git would otherwise read as pathspec
  magic (a leading `:`, or `*?[`) is treated as the literal path it is. Both
  failure directions are bound by `scripts/check-staleness-gate-bite.sh` from
  `task spec:validate`.
  `talos_cluster_kubeconfig.this` fetched the admin kubeconfig once at
  bootstrap and never re-fetched it: its own arguments (`node`/`endpoint =
  local.first_controlplane.ip`) are the Talos-API (talosclient, port 50000)
  dial target used only to *fetch* the kubeconfig, not the emitted
  Kubernetes `server:` — per the `siderolabs/talos` provider schema
  (`tofu providers schema -json`, `registry.opentofu.org/siderolabs/talos`)
  and the Terraform Registry docs for `talos_cluster_kubeconfig`. The
  `server:` value is Talos-derived from `var.cluster_endpoint`, which is
  baked into the machine config at `tofu/modules/talos-cluster/main.tf:674`
  (controlplane) and `:684` (worker); a later `var.cluster_endpoint` change
  (a VIP move, a DNS rename, or a control-plane node re-IP on a
  single-control-plane cluster where `cluster_endpoint` is expressed as
  that node's own IP — the seeder's `api_vip: ""` fallback is exactly this
  case, and is the strongest evidence this fix closes the #168/#186
  incident; on a VIP/DNS endpoint a plain node re-IP is correctly inert
  and does not trigger regeneration) left the resource's own arguments
  unchanged, so it
  never re-read and the module kept emitting the stale `server:`. A new
  `terraform_data.kubeconfig_endpoint_marker` (tracked `input =
  var.cluster_endpoint`) now drives `lifecycle.replace_triggered_by` on
  `talos_cluster_kubeconfig.this`, so a changed endpoint forces a re-fetch.
  - **Non-breaking, no MAJOR bump**: the emitted `server:` value is
    unchanged — it always tracked `var.cluster_endpoint` — and the trigger
    is inert until the endpoint actually changes. Adding the marker to an
    existing state (endpoint unchanged) only creates the marker; it does
    **not** replace the existing kubeconfig, so there is no first-apply
    churn on this version bump (reproduced offline with OpenTofu 1.11.8 —
    a version-specific observation, not a semver-guaranteed provider
    property).
  - **Side effect on a genuine endpoint change**: the resource is
    destroyed and recreated (state-only — it revokes nothing on the
    cluster and does not touch `talos_machine_secrets`), which rotates the
    embedded admin client certificate. The output still waits on the
    existing health gate (`depends_on = data.talos_cluster_health`) before
    emitting the refreshed kubeconfig, but that gate polls the
    control-plane **node IPs**
    (`tofu/modules/talos-cluster/main.tf:817-819`), not
    `var.cluster_endpoint`. On a cluster whose endpoint is a VIP or DNS
    name distinct from the node IPs, the gate does not verify the *new*
    endpoint is reachable: a VIP moved to a wrong or unpropagated target
    still reports healthy. The consumer is responsible for confirming the
    new endpoint is correct and propagated before relying on the emitted
    kubeconfig — this gate will not catch a wrong or unpropagated
    VIP/DNS endpoint.
  - Cosmetically different but equivalent endpoint strings (for example
    a trailing slash or case difference) count as a change and trigger
    regeneration too — no canonicalization is performed.
  - A DNS-rename regeneration depends on Talos adding the new hostname to
    the apiserver serving-cert SANs in the same apply; the apiserver
    cert-SANs update alongside `var.cluster_endpoint` on a re-apply.

## v9.1.0 — 2026-08-24

### Added

- **`talos-cluster`: `cilium_operator_replicas` input (number, default `null`).**
  Pins the Cilium operator's replica count on **both** delivery paths — the
  frozen seed and the emitted self-management Application — where
  `cilium_values_override` reaches only the seed and is hard-rejected alongside
  `cilium_self_management`. `null` derives the count from the node set; see the
  matching entry under Changed for the derivation and its rationale. Paired with
  a new `cilium_operator_replicas_effective` output reporting the resolved count
  and which of the three mechanisms produced it.

### Changed

- **`talos-cluster`: the Cilium operator's replica count now follows the node
  count, and is pinnable.** At two or more nodes the module emits
  `operator.replicas: 2` — the Cilium chart's own default — into both the
  bootstrap seed and the emitted self-management Application. At exactly one node
  nothing is emitted and the shipped floor's `1` remains effective, because the
  chart's operator `podAntiAffinity` is `requiredDuringScheduling` on
  `kubernetes.io/hostname` and a second replica would stay Pending there forever.
  The new `cilium_operator_replicas` input (`substrate.cilium.operator_replicas`)
  pins the count instead; it is the only knob that pins on **both** delivery
  paths, because `cilium_values_override` reaches the seed alone and is
  hard-rejected alongside `cilium_self_management`. A count above the declared
  node count is **rejected** at plan time — the surplus can never place against
  the per-hostname anti-affinity, and the value lands in a create-only seed that
  no later apply can walk back. The new `cilium_operator_replicas_effective`
  output reports the resolved count together with its origin (pin, node-count, or
  floor).

  Why: `2` is the chart's own default, and the floor's `1` diverged from it on
  every cluster shape while being correct on exactly one. Two consequences were
  measured against the pinned chart 1.20.0. The rolling-update strategy varies
  with the replica count — `maxUnavailable` is `100%` at one replica and `50%` at
  two — so a rollout guarantees zero available operator pods at one replica and
  one at two. And on a hard node failure a lone replica waits out the 300-second
  `unreachable` eviction plus a reschedule and a cold start, where a second
  replica is already running elsewhere.

  Two things this release does **not** claim. How fast that second instance takes
  the work over was not measured — the chart grants the leader-election lease
  RBAC at one replica too and sets no leader-election flags, so the mode and the
  timings are operator-binary behaviour. And none of this rescues a node that is
  merely `NotReady` while its operator pod is alive and reaching the API: that is
  not a failover event at all.

  Note the resource footprint: the chart sets no `operator.resources`, so both
  pods are **BestEffort**. See UPGRADING if that matters on your nodes.

  **Impact on adoption:** a multi-node cluster taking this tag gets a second
  `cilium-operator` pod. On an already-bootstrapped cluster the seed path does
  **not** deliver it — `terraform_data.cilium_render` carries `ignore_changes`
  and `inlineManifests` are create-only, so it takes a fresh bootstrap or a
  deliberate `-replace`; a control-plane join does not deliver it either. A
  self-managing consumer gets it on the next ArgoCD reconcile. See
  [ADR-0022](knowledge/decisions/0022-cilium-observability-and-argocd-self-management.md).

### Fixed

- **`schemas/cluster.schema.json`: the `operator_replicas` description said the
  node-count bound only warns.** It is a plan-time rejection. Description text
  only — no validation behaviour changed.

## v6.0.0 — 2026-07-20

### Changed — BREAKING

- **`talos-cluster`: the seeded kubelet-serving CSR approver is now
  `postfinance/kubelet-csr-approver` (was
  `alex1989hu/kubelet-serving-cert-approver`).** Same controlplane
  `inlineManifest` seed, but the manifest is now chart-rendered and templated
  with a small per-cluster config surface —
  `substrate.cert_approver.{provider_regex, provider_ip_prefixes, replicas}` — so
  the approver is **tunable** (two security knobs + a replica count) instead of
  the previous fixed, zero-config seed. The image is digest-pinned to
  `ghcr.io/postfinance/kubelet-csr-approver:v1.2.14`. postfinance adds an
  **always-on per-node DNS-SAN binding** the old approver lacked — a CSR's DNS
  SANs must be prefixed by the requesting node's hostname. The two knobs default
  so every cluster still boots and approves out-of-the-box
  (`provider_regex = ".*"`, `provider_ip_prefixes = ["0.0.0.0/0", "::/0"]` — the
  safe floor; an empty list would deny every serving CSR); a consumer tightens
  `provider_ip_prefixes` to its node subnets for an additional IP-SAN-to-subnet
  binding, and `replicas > 1` opts into HA (auto leader-election + a namespaced
  leases RBAC).
  **Consumer impact:** the approver's identity, RBAC, and pod identity all change
  — the namespace is renamed `kubelet-serving-cert-approver` →
  `kubelet-csr-approver`, the metrics port moves `9090` → `8080`, the vendored
  manifest is renamed `manifests/cert-approver.yaml` →
  `manifests/kubelet-csr-approver.yaml`, and non-conforming CSRs are now **Denied
  terminally** (a `Denied` condition) rather than left `Pending`. Anything scoped
  to the old namespace (ServiceMonitor, alerts, RBAC) must be repointed.
  **BREAKING — migration:** MAJOR OCI bump. The old approver was a create-only
  seed Talos never deletes, so after the new seed is Running the old
  `kubelet-serving-cert-approver` namespace + its cluster-scoped ClusterRoles
  (`certificates:`/`events:kubelet-serving-cert-approver`) + ClusterRoleBinding +
  a stray `events:` RoleBinding in the `default` namespace must be torn down by
  hand; config changes do not propagate to a running cluster (create-only seed);
  and a node-excluding `provider_*` value denies serving CSRs cluster-wide
  (terminal). See UPGRADING.md for the full teardown, propagation, rollback, and
  observability-migration steps. Decision:
  [`knowledge/decisions/0019-postfinance-kubelet-csr-approver.md`](knowledge/decisions/0019-postfinance-kubelet-csr-approver.md)
  (supersedes ADR-0013 §D2; ADR-0013 §D1 — rotation default-on — is unchanged).

## v5.0.0 — 2026-07-15

### Changed — BREAKING

- **`talos-cluster`: the `iommu` provisioning profile no longer bakes
  `iommu=pt`.** The profile's `intel`/`amd` variants now carry only
  `intel_iommu=on` / `amd_iommu=on` — the args the `iommu-enabled` Layer-C
  atom's `presence_predicate` actually names. `iommu=pt` is a host-DMA
  translation-policy default (kernel docs: "Equivalent to
  `iommu.passthrough=1`" → "Bypass the IOMMU for DMA"), not part of the
  capability; it entered the catalog by being copied out of a README example
  and was never a decision. **Consumer impact:** a node selecting the `iommu`
  capability gets a new schematic content hash → new installer URL →
  **re-image**, and its host-owned devices revert from passthrough-by-default
  to **lazy DMA translation** (Talos builds `CONFIG_IOMMU_DEFAULT_DMA_LAZY=y`
  with `CONFIG_IOMMU_DEFAULT_PASSTHROUGH` unset, verified across the v1.10 —
  v1.12 kernel configs, amd64 and arm64 — so `iommu=pt` was doing real work
  and this is not a no-op).
  Passthrough itself is unaffected — a device bound to `vfio-pci` is isolated
  by its own VFIO domain regardless of `iommu=pt`, so the `iommu-enabled`
  atom still delivers what it promises; what changes is host-owned-device DMA
  translation (a possible throughput cost on the host, in exchange for DMA
  protection the bypass removed). **There is no way to keep the previous
  behavior in this tag:** the schematic kernel-arg sink is fed exclusively by
  profile `kernel_args`, the module exposes no consumer kernel-arg input, and
  `config_patches` reach `machine.install.extraKernelArgs`, which is a no-op
  under the Talos v1.10+ UKI/systemd-boot default. A consumer needing
  `iommu=pt` must wait for the consumer kernel-arg path (#169). Decision:
  [`knowledge/decisions/0016-capability-profiles-predicate-only.md`](knowledge/decisions/0016-capability-profiles-predicate-only.md).

- **`task bootstrap:argocd` now rejects `cluster.yaml` identity values that it
  previously rendered.** The bootstrap-identity values (`cluster.name`,
  `repo.url`, `cluster.overlay`, `cluster.target_revision`) are refused when
  empty, whitespace-only, line-break-bearing, not a string, or carrying YAML
  syntax that means something else once substituted. `cluster.overlay` is
  additionally bound to a single kustomize directory name
  (`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`) — the schema now carries the same
  pattern.

  **Consumer impact — read this even if your `cluster.yaml` passes lint, and
  especially if you have never run it:** `scripts/lint-cluster-yaml.sh` does
  NOT run on the render path, so a file that never passed the schema could
  still render before. Two classes are affected:
  - **Was already schema-invalid, rendered anyway:** a non-string identity
    value. `target_revision: 2024` or `1.5` parse as int/float — the schema
    types all four as `string`, so these never passed lint, but the render
    accepted them (`1.10` silently rendered as `targetRevision: 1.1`). Quote
    them: `target_revision: "2024"`.
  - **Was schema-valid, rendered, and should not have:** an `overlay` that is
    not a plain directory name, and any line-break- or YAML-syntax-bearing
    value. See §Security.

  A `cluster.yaml` that passes the updated schema renders byte-identically to
  before. Every rejection names the offending value.

### Security

- **The App-of-Apps bootstrap render no longer lets a `cluster.yaml` value
  escape its YAML position.** Two shipped defects, both reachable from a
  schema-valid file, both closed:
  - A value containing a **line break** was substituted verbatim by `envsubst`,
    so its trailing lines became sibling YAML. A `repo.url` of
    `"https://ok\n    - '*'"` rendered an AppProject with
    `sourceRepos: ['https://ok', '*']` — ArgoCD's RBAC boundary widened to
    every repository, from a diff that reads as a URL change. `repo.url` and
    `target_revision` carry no schema pattern (`cluster.name` does), and no
    lint gate runs on the render path. Both YAML line breaks are rejected: a
    lone `\r` broke the rendered document just as `\n` did.
  - An **empty** `cluster.overlay` rendered `path: kubernetes/overlays/` on a
    root Application with `prune: true` + `selfHeal: true` — pointing it at the
    entire overlay tree. A **whitespace-only** overlay reached the same state
    (YAML strips the trailing space), and `overlay: ".."` reached a **worse**
    one: `path: kubernetes/overlays/..` is `kubernetes/`, handing that
    self-healing, pruning Application the whole tree including
    `kubernetes/bootstrap/`. `overlay` is now bound to a plain directory name
    in both the schema and the render.
  - A value that is a well-formed string and still **means** something else:
    `repo.url: "'*'"` rendered `sourceRepos: ['*']` — the AppProject trusting
    every repository, with no line break, no `$`, and the correct type. Values
    must now survive a YAML round-trip as themselves.

  Non-string values (a mapping serializing its subtree into the value) are
  rejected for the same class of reason. Additionally: `ENV` is now bound
  through go-task's `env:` block rather than interpolated into the command
  string. Quoting alone was **not** sufficient — go-task renders `{{.ENV}}` as
  raw text before the shell parses it, and command substitution expands inside
  double quotes, so `ENV='$(cmd)'` still executed `cmd` (verified). The render
  also aborts explicitly via `set -e` rather than relying on the runner's shell
  default, and renders to a temp dir so a failure cannot leave a half-populated
  `_out/` for `kubectl apply -f`.

  Behaviour is normative in `openspec/specs/argocd-day-zero-bootstrap/` and
  asserted per-guard by `task bootstrap:check-render` (in `task gitops:validate`
  and CI). Known residual, stated rather than implied: these guards bound the
  four identity values. They are not a general YAML-injection defense for the
  templates, and they do not validate values semantically — a well-formed but
  wrong repo URL renders happily.

### Added

- **The bootstrap render's spec scenarios are now mechanically bound**
  (`scripts/check-bootstrap-render.sh`, `task bootstrap:check-render`, in the
  `hardware-features-check` CI job). Offline — the render is `yq` + `envsubst`
  and contacts no cluster. Removing any single guard turns it red. Also
  **`task tofu:check:readme-parity`** (in `task tofu:ci`): every module
  variable and output must appear in its hand-maintained README table, which
  is what keeps the module README from silently drifting now that the second
  copy of the interface under `knowledge/reference/` is gone.

- **`task bootstrap:render-root` is now a public target** (was `internal:`) —
  renders the two root manifests from `cluster.yaml` without contacting a
  cluster. Useful as a dry-run; it is also what makes the render testable.

- **The provisioning-profile catalog's kernel arguments are now pinned by a
  test** (`tofu/modules/talos-cluster/tests/profile-predicate-only.tftest.hcl`):
  set equality on the `iommu` variants, and no kernel argument on a profile
  that provides no atom. It runs offline against the real catalog via a
  fixture that symlinks the shipped `profiles.tf`/`composition.tf`, so the new
  `tofu:test:offline` target carries it inside `task tofu:ci` — the shipped
  catalog is now checked by the offline chain, not only by the
  network-dependent `tofu:test`. Previously no test asserted the literal
  argument set, so a profile silently re-acquiring host tuning was visible
  only through a schematic content hash.
- **OpenSpec adopted as the behavioral-requirements surface**
  (`knowledge/decisions/0015-openspec-adoption.md`). `openspec/specs/`
  carries specs for the 14 enumerated substrate capabilities (backfilled
  from the implementation by explicit owner decision); future behavior
  changes travel as spec deltas via `openspec/changes/`. New `spec:*`
  task namespace (`validate` incl. bite-check + source-partition assert,
  `check-regen`, `check-staleness`, `install-cli`, `update`),
  `docs:lint`/`docs:install-cli`, and `dev:verify-pins`; `docs-lint.yml`
  now runs exactly these Taskfile targets, so the local validation chain
  equals the remote one (pins live in `.tool-versions`, the Taskfile
  vars block, and — for the npm-distributed tools — `package.json` +
  `package-lock.json` with integrity hashes). The OCI tarball payload is
  unchanged — `openspec/` and the tool trees stay outside the allowlist.
- **Spec staleness gate, CI-enforced**: a PR whose diff touches a spec's
  `primary` source without touching the owning spec fails
  `docs-lint.yml` (`task spec:check-staleness`,
  `scripts/check-spec-staleness.py`). Escape for verified
  no-behavior-change diffs: the `Spec-Impact: none` trailer on every
  commit touching the file (per-commit scope), judged by the PR
  reviewer.
- **The OKF bundle's maintenance contract is now rendered into `AGENTS.md`.**
  `knowledge/rules/talos-base-bundle.md` states the bundle's authoring
  conventions (closed `type` vocabulary, the `timestamp`/`sources` staleness
  contract, the link rule, the `log.md` vs `CHANGELOG.md` split), and
  `openknowledge rules apply` renders them into a managed block in `AGENTS.md`
  alongside the built-in `docs`, `decisions`, and `schemas` rules. Previously
  the contract lived only in `CONTRIBUTING.md`, which is outside the
  `AGENTS.md` load chain an agent reads. `task knowledge:rules-apply`
  regenerates the block; `task knowledge:rules-check` fails on drift and runs
  in `docs-lint`. The block is generated — hand-edits fail the check.
- `knowledge/openknowledge.toml` raises `rule-catalog` to `error`, so a
  malformed rule document fails validation instead of warning.

### Fixed

- **`docs-lint` never actually gated merges.** Branch protection required the
  context `docs-lint`, but the workflow's job reported as `markdownlint` — no
  check run by that name ever existed, so the required context stayed pending
  and merges relied on admin bypass. The job now declares `name: docs-lint`.
  markdownlint, OKF validation, and the link gate were running and passing;
  they simply were not blocking anything. `scripts/preflight-checks.sh` gained
  the context, which catches a recurrence when a maintainer runs it locally —
  in CI that check still skips, because the default `GITHUB_TOKEN` cannot read
  branch protection.
- Documentation of the required-check set corrected against the
  branch-protection API in three places that disagreed with it and with each
  other: `CONTRIBUTING.md` §Required (CI) omitted `docs-lint` and `preflight`;
  `AGENTS.md` claimed `hard-constraints-check` was "not yet" required; and
  `knowledge/project/openssf-self-assessment.md` recorded two required
  contexts where there are five.
- **conftest ArgoCD policy — chart-omission evasion hardened**
  (`policies/conftest/argocd.rego`): every Application source must set
  `repoURL` and be explicitly classifiable (`chart`, `path`, `ref`, or a
  `plugin` block); a `helm:` block requires `chart` or `path` (a
  throwaway `ref` no longer dodges classification); and the literal
  floating markers (`latest`, `*`, `HEAD`) are denied as
  `targetRevision` on EVERY source independent of classification.
  Previously a source omitting `chart` fell through to the weaker
  git-source rules and skipped all Helm pinning checks; the textual
  chart-omission rule that could never fire (dead code) is removed.
  Disclosed residual: a chart-less source carrying `path` is classified
  as a git source — helm-vs-git repoURL discrimination is not
  mechanically decidable, and the floating deny catches only the literal
  markers; a mutable branch/tag name on a git-classified source stays a
  review concern. The denies are bound red-green by a committed negative
  fixture in `task gitops:validate`.
- **Duplicate hardware-feature ids are now rejected**:
  `scripts/lint-hardware-features.sh` gained a mechanical duplicate-id
  gate; the former schema-level `uniqueItemProperties` keyword (an
  AJV-only extension that `check-jsonschema` silently ignores) is
  removed from `schemas/hardware-features.schema.json`.
- **Version patterns fully anchored** in `schemas/cluster.schema.json`
  and the mirrored `tofu/modules/talos-cluster` validations:
  `talos.version`, `talos.install_version`, and `kubernetes.version` now
  reject trailing text after the PATCH segment (a `-`/`+` pre-release or
  build suffix stays accepted). **Consumer note (validation
  tightening):** values the former start-anchored patterns accepted —
  for example `v1.13.0.4` or `v1.13.0_hardened` — are now rejected at
  lint and plan time; such values never resolved to a valid Talos/Kubernetes
  release, but a consumer carrying one must fix it before upgrading.
  Bound red-green by `schemas/fixtures/cluster.invalid.yaml` (CI) and
  the offline `tests/input-validation.tftest.hcl` suite.
- **OCI publish membership gate is fail-closed**: a missing
  `.ci-oci-tarball-expected.txt` now aborts the publication instead of
  skipping the diff with a notice (parity with
  `task supply-chain:oci-allowlist`).
- **Bootstrap manifests carry the full recommended label set**: both
  `kubernetes/bootstrap/argocd/*.tmpl` templates gained
  `app.kubernetes.io/version`, set to a label-safe form of the rendered
  `target_revision` (sanitized/truncated — a slash-bearing branch name
  stays valid; `spec.source.targetRevision` keeps the raw value).

### Changed

- **The base now commits tool-generated AI artifacts**
  (`knowledge/decisions/0014-ship-ai-tool-artifacts.md`): the OpenSpec
  skill/command trees for Claude Code and Codex are committed
  (regenerable via `task spec:update`); operator scratch under
  `.claude/` stays gitignored via selective negation. Hand-authored
  harness primitives remain external. This reverses the former
  "ships no `.claude/` tree" policy in `CLAUDE.md`/`AGENTS.md`.
- `knowledge:validate` gained the two `tofu/modules/talos-cluster` READMEs
  that the former inline CI step already checked.
- `docs-lint.yml` pins `arduino/setup-task` by commit SHA and bounds the job
  with `timeout-minutes: 10`.
- `CODEOWNERS` covers `knowledge/rules/` and `knowledge/openknowledge.toml`:
  their content reaches `AGENTS.md` verbatim, so they are reviewed at that
  file's bar rather than a docs file's.

## v4.0.0 — 2026-07-11

### Changed

- **Documentation replaced by an Open Knowledge Format (OKF v0.1) bundle at
  `knowledge/` — the `docs/` tree is deleted (BREAKING for path consumers).**
  All prose documentation was regenerated from repository source (or, for
  decision records and project docs, migrated with per-claim verification)
  into `knowledge/` — architecture, reference, workflows, `decisions/`
  (the 13 ADRs, MADR frontmatter mapped to OKF), glossary. Entry point:
  `knowledge/index.md`. `openknowledge validate` (link-target raised to
  error via `knowledge/openknowledge.toml`) plus an offline lychee
  link-resolution pass gate the bundle in `docs-lint.yml` and locally via
  `task knowledge:validate`.
- **Machine-consumed contracts relocated out of `docs/` (BREAKING — OCI
  tarball layout changed).** `docs/platform-hardware-features.yaml` →
  `platform-hardware-features.yaml` (repo root);
  `docs/schemas/*` → `schemas/*`; `docs/primitive-contract.md` →
  `contracts/primitive-contract.md`. Both JSON Schema `$id` URLs updated
  accordingly. Consumers vendoring the tarball must repoint the two moved
  member paths; external harnesses reading the primitive contract at its
  hardcoded `docs/` path must repoint to `contracts/`. Migration table:
  `UPGRADING.md` §v4.0.0.

### Added

- **`knowledge:*` task namespace + pinned validation toolchain.**
  `task knowledge:validate` (OKF validate + offline link check),
  `task knowledge:new` (concept scaffold), `task knowledge:install-cli`
  (sha256-verified install of `openknowledge` 0.5.0 + `lychee` 0.24.2,
  pinned in `.tool-versions` and mirrored in `docs-lint.yml`).

## v3.0.0 — 2026-07-01

<!-- Backfilled 2026-07-11: these entries accrued under "Unreleased" and were
     released as v3.0.0, but the heading was never renamed — which is also why
     the v3.0.0 GitHub Release fell back to auto-generated notes. -->

### Added

- **Cilium Gateway API honors Service `appProtocol: kubernetes.io/h2c` (#132, #133).**
  `gatewayAPI.enableAppProtocol: true` is now set in the computed Gateway-API
  Helm layer, gated on `var.cilium_gateway_api`, and the rendered `argocd-server`
  Service advertises `appProtocol: kubernetes.io/h2c` on its http (80) port (the
  https/443 port is untouched). This lets the Cilium Gateway route argocd's gRPC
  (CLI/UI API) over h2c instead of de-framing it to HTTP/1.1 — which argocd
  answers with 404. **Versioning: this is a MINOR, not a MAJOR, change.** It is
  additive and gated: `enableAppProtocol` is a no-op until a Service opts in via
  `appProtocol`, and post-v2.0.0 only `argocd` renders a Service in the substrate,
  so there is no base-side blast radius beyond argocd.
- **Existing-cluster caveat (Day-2).** The Cilium config is delivered by a frozen
  `terraform_data.cilium_render` seed (`lifecycle.ignore_changes`), so on an
  already-seeded cluster `tofu plan` shows **no diff** for it — a merge looks live
  while Cilium's behavior is unchanged until a forced re-render/re-seed. Confirm
  the running state with
  `kubectl -n kube-system get cm cilium-config -o jsonpath='{.data.enable-gateway-api-app-protocol}'`
  (expect `"true"`). See UPGRADING.md.
- **Kubelet serving-cert rotation is default-on for every cluster + cert-approver
  is now a base-delivered substrate seed (adr-0013).** The `tofu/modules/talos-cluster`
  module injects `machine.kubelet.extraConfig.serverTLSBootstrap: true` on ALL nodes
  (the non-deprecated KubeletConfiguration field, not the deprecated
  `--rotate-server-certificates` flag), placed FIRST so a consumer can opt out via
  `config_patches`. cert-approver (`alex1989hu/kubelet-serving-cert-approver` v0.11.0,
  image digest-pinned) ships as a controlplane `inlineManifest` seed (namespace +
  signer-restricted RBAC + restricted-PSA Deployment), replacing the former
  namespace-only `kubernetes/base/infrastructure/cert-approver/` stub — no consumer
  wiring of the upstream remote. Net effect: trusted kubelet serving certs
  out-of-the-box (metrics-server / `kubectl logs|exec|top` without
  `--kubelet-insecure-tls`). SAN-to-node CSR validation is a documented
  consumer-cluster Kyverno defense-in-depth obligation (the base ships no admission
  policy).

### Changed — BREAKING

- **cert-approver relocated from a `kubernetes/base/infrastructure/` component to a
  Talos controlplane `inlineManifest` seed (adr-0013); kubelet serving-cert rotation
  default-on.** Existing-cluster impact: adopting this tag re-pushes machine config
  (reconciled) → rotation turns on and kubelets emit `kubernetes.io/kubelet-serving`
  CSRs, but the create-only approver seed does NOT land on an already-bootstrapped
  cluster → rotation-on-without-approver unless the approver is ensured present. See
  UPGRADING.md `v3.0.0` for the required migration (incl. double-management resolution
  for consumers who already wired the upstream approver Application).
  `.ci-renderable-components.txt` is now `argocd` only.

- **Single task runner — the `Makefile` is retired; go-task is the only runner
  (#113).** Every former `make <target>` folds into a namespaced task in
  `Taskfile.yml`: `tofu:*` (OpenTofu validation — the CI-invoked `task tofu:ci`
  / `task tofu:test`), `gitops:*` (`validate`, `render-component`, `render-all`,
  `verify-rendered`), `bootstrap:*` (`argocd`, `argocd-password`),
  `cluster:init-yaml`, `supply-chain:oci-allowlist`, `mcp:*`, `dev:*`. Run
  `task --list` for the full set. `chart-pull` and `grafana-dashboards-check`
  are **dropped** with no replacement (the former is a `helm pull` + `shasum`
  one-liner; the latter scanned a consumer overlay path absent in the base).
  `devbox.json` gains `yq-go` + `gettext` + `ripgrep` (not `gnumake`). A `Makefile`
  deprecation stub remains for one release cycle: any `make <target>` prints the
  migration mapping and exits non-zero. **Contributor / consumer impact:**
  day-zero runbooks or scripts invoking `make <target>` must switch to
  `task <target>`. Decision:
  [`docs/adr-makefile-retirement.md`](docs/adr-makefile-retirement.md)
  (supersedes [`docs/adr-task-runner-consolidation.md`](docs/adr-task-runner-consolidation.md)).

- **Day-zero bootstrap decoupled from the ArgoCD helm double-install (#113).**
  ArgoCD is delivered as a Talos `inlineManifest` seed by the
  `tofu/modules/talos-cluster` module (`deploy_argocd`, default true) since
  #102, but the bootstrap path still helm-installed it on top — a
  double-install. The redundant helm install is **removed**; `tofu apply` seeds
  the ArgoCD controller, namespace, and CRDs, and the consumer day-zero runs
  only `task bootstrap:argocd` to apply the consumer-identity App-of-Apps root
  (root-project + root-application), which the module does **not** deliver.
  Skipping `task bootstrap:argocd` yields a healthy-looking but inert cluster.
  `task bootstrap:argocd` now waits for both root CRDs (`applications`,
  `appprojects`) to establish and for argocd-server to become available before
  applying the root, restoring the cross-exec-context ordering barrier the
  removed step provided. See [`docs/day-zero-pattern.md`](docs/day-zero-pattern.md)
  and UPGRADING.md.

### Fixed

- **Module-seeded `argocd` namespace now carries the PSA floor + recommended
  labels itself (#113).** With `kubernetes/bootstrap/argocd/namespace.yaml`
  retired, the module is the sole creator of the `argocd` namespace; the
  create-only `inlineManifest` seed now sets `pod-security.kubernetes.io/enforce:
  baseline` (+ audit/warn restricted) and the six `app.kubernetes.io/*`
  recommended labels (AGENTS.md §Hard Constraints), so the namespace is never
  delivered PSA-unenforced. A `tofu test` run asserts the floor + labels
  (red-green bound to the seed bytes).

## v2.0.0 — 2026-06-22

### Changed — BREAKING

- **Substrate-only base (next MAJOR / v2.0.0).** All non-substrate components
  were removed from `kubernetes/base/infrastructure/` — it now ships only
  `argocd` + `cert-approver`. The PNI / capability-first network-trust contract
  dissolved from the base (per [`docs/adr-substrate-only-base.md`](docs/adr-substrate-only-base.md))
  into apps-CI Conftest + consumer-cluster Kyverno. Every other platform
  component (monitoring, vault, cert-manager, nvidia, kubevirt, loki, dex,
  multus, piraeus, tetragon, external-secrets, …) now lives in the
  `talos-platform-apps` catalog as signed OCI artifacts; consumers re-source
  them from there via a Multi-Source Application. `make validate-kyverno-policies`,
  the Layer-A capability-index scripts/docs, and the PNI ADRs were removed. The
  Layer-C hardware-features registry + node-capability composition stay (the
  `tofu/modules/talos-cluster` module depends on them). See UPGRADING.md.
- **ArgoCD `server.certificate` disabled by default (substrate self-containment).**
  The substrate `argocd` no longer renders a `cert-manager.io/v1 Certificate`
  (`server.certificate.enabled: false`) — with cert-manager removed from the base
  it would otherwise render against an absent CRD/issuer. argocd-server already
  runs `server.insecure=true` (serves plaintext at the pod; terminate TLS at your
  gateway/ingress). Consumers fronting ArgoCD with cert-manager-issued TLS
  re-enable `server.certificate` in a values overlay and provide the issuer
  (and set `server.insecure=false` for pod-served TLS). See UPGRADING.md.
- **talos-cluster: `var.classes` / `node.class` removed (#135).** Use
  `var.images` + `var.hardware_capabilities` and `node.image` +
  `node.hardware_capabilities`. A node sits on one base `image` and holds a SET
  of composable `hardware_capabilities` resolved via a base-owned
  provisioning-profile catalog — no more hand-authored monolithic classes. The
  `installer_images` output is now keyed by hostname (was per class). Nodes whose
  kernel-arg provisioning is corrected (for example, IOMMU) re-image once. See UPGRADING.md
  and [`docs/adr-node-capability-composition.md`](docs/adr-node-capability-composition.md).

### Added

- **Render-determinism regression fence (`scripts/check-render-determinism.sh`, wired into
  `task ci`).** Derives every helm render from the module and asserts each is consumed only
  via its frozen `terraform_data` (per-resource `ignore_changes`), and that CRD renders
  carry `triggers_replace` — so the #123 decoupling cannot silently regress.

### Changed

- **Releases are now conventional-commit-driven (semantic-release + approval
  gate).** A push to `main` computes the next version from the commit history
  and, on one manual approval in the `release` GitHub Environment, tags it; the
  existing signed-OCI publish (`oci-publish.yml`) runs unchanged on the tag push.
  A commit-lint check gates PR titles. **Contributor impact:** a MAJOR bump now
  requires a real `BREAKING CHANGE:` footer (or `type!:`) — prose `**BREAKING**`
  in a body is not recognised. `CHANGELOG.md` stays human-curated; the
  auto-generated GitHub Release notes are the canonical per-release record. See
  [`docs/release-automation.md`](docs/release-automation.md).

### Fixed

- **talos-cluster: inlineManifest + ArgoCD-CRD renders frozen in state, decoupled from
  `talos_machine_configuration_apply` (#123).** `data.helm_template.{cilium,argocd,argocd_crds}`
  are re-evaluated every plan and are not byte-stable (Sprig `genCA` at template time;
  helm-provider ordering). Consumed directly, every `tofu plan` / Crossplane reconcile
  re-pushed a fresh machineConfig — constant drift plus a self-eviction risk on single-node
  control planes. Each render is now captured once via `terraform_data` with
  `lifecycle { ignore_changes = [input] }`; the ArgoCD-CRD render additionally carries
  `triggers_replace` (a Day-2 kubectl convergence that must re-apply on an intended chart/
  version bump). Completes the structural half #122/v1.2.0 left open (which fixed only the
  Hubble default trigger). No interface change; empty-render postconditions added so a
  partial render is not frozen.

## v1.2.0 — 2026-06-11

### Changed

- **Cilium seed: Hubble disabled by default (`hubble.enabled: false`).** The
  Cilium chart's default `hubble.tls.auto.method=helm` regenerates the Hubble CA
  + server TLS on every `helm template` render, making the Cilium inlineManifest
  seed — and thus the rendered Talos machineConfig — non-deterministic: every
  `tofu plan` produced a new `machine_configuration` hash, so every apply / in-
  cluster Crossplane reconcile re-pushed machineConfig to the node. **BREAKING**
  for consumers who relied on seed-default Hubble: Hubble is now Day-2 — re-enable
  via `cilium_values_override` (`hubble.enabled: true`; prefer
  `tls.auto.method=cronJob` to keep the render deterministic) or Cilium ArgoCD
  self-management. **Partial fix (Refs #121, default trigger only):** the
  structural coupling — a live `data.helm_template` consumed by
  `talos_machine_configuration_apply` with no `lifecycle { ignore_changes }`,
  affecting both the Cilium and ArgoCD renders — is unaddressed; a future chart
  bump / override can reproduce the drift. Tracked in #123.

## v1.1.0 — 2026-06-07

### Removed

- **Consumer-side Cilium render path retired.** `scripts/render-cilium-bootstrap.sh`
  is deleted — the `talos-cluster` module delivers Cilium as a controlplane
  `inlineManifest` seed (since `v1.0.0`), so the render → `cluster.extraManifests`-URL
  recipe is obsolete. The deleted script is dropped from the OCI tarball allowlist
  (`.ci-oci-tarball-{include,expected}.txt`) and the `oci-publish.yml` renderer
  exec-bit check is removed with it. `kubernetes/bootstrap/cilium/{values,extras}.yaml`
  stay in the repo **and** in the OCI artifact as the Cilium values / GatewayClass
  reference (only the dead script leaves the artifact). **Migration:** a consumer that
  still invoked the renderer adopts the module-delivered Cilium seed (`deploy_cilium`,
  default `true`); the reference values are unchanged.

### Changed

- **Module plan-time validation hardened.**
  - `dual_stack` is now guarded **bidirectionally**: `dual_stack = true` requires
    `pod_cidr` AND `service_cidr` to each carry an IPv4 and an IPv6 CIDR, and
    `dual_stack = false` requires each to be IPv4-only. Previously a single-family
    CIDR with `dual_stack = true` — and the reverse, a v6 CIDR with
    `dual_stack = false` — both silently mismatched Talos (which carries the full
    subnet list) against the Cilium seed (which enables ipv6 only on the flag).
  - `pod_cidr`/`service_cidr` entries are now CIDR-format-validated (`cidrhost`),
    rejecting malformed values at `tofu validate` time.
  - `sops_age_key` must now start with `AGE-SECRET-KEY-1` (not merely `!= ""`), and
    the complete example root drops the `sops_age_key` default so a copied example
    cannot silently `tofu apply` a non-functional ksops key — it must supply a real
    key via `TF_VAR_sops_age_key`.
- **Cilium-delivery docs corrected** to describe the module `inlineManifest` seed
  (`day-zero-pattern.md` Layer-1, `AGENTS.md`, `kubernetes/AGENTS.md`) instead of the
  retired render path.

### Fixed

- **`talos-cluster` bakes the exact declared extension set (#119).** The
  `officialExtensions` comprehension resolved names from the
  `talos_image_factory_extensions_versions` data source, whose `filters.names`
  matches by **substring/prefix** — so a class declaring `siderolabs/gvisor`
  also pulled in `siderolabs/gvisor-debug`. Resolved names are now intersected
  with the declared set, and a `precondition` fails loudly when a declared
  extension does not resolve **exactly** (non-canonical / typo input), instead
  of silently baking a partial or empty set. Because the Image Factory schematic
  ID is a SHA256 over the whole schematic, the prior behaviour silently changed
  the content-addressed ID and the installed extension set on every gvisor-class
  node. Closes #118.
- **Adoption-proof harness runs on bash 3.2 (#117).**
  `test/run-adoption-proof.sh` aborted under `set -u` on macOS's default
  `/bin/bash` (3.2) before the first import, because a bare `"${PT[@]}"` over an
  empty array is an unbound-variable error pre-bash-4.4. The pass-through tofu
  flags now use the empty-safe `${PASSTHRU[@]+"${PASSTHRU[@]}"}` idiom at all
  three call sites; the dead `PT` mirror is removed. Closes #116.

## v1.0.0 — 2026-06-06

### Changed — BREAKING

- **`talos-cluster` module delivers Cilium as the CNI and disables the Talos
  default Flannel (`deploy_cilium` defaults to `true`).** Cilium is Layer-1
  substrate (Talos + Cilium + ArgoCD); the module now disables the bundled CNI
  (`cluster.network.cni.name: none`) + kube-proxy and bakes a locally-rendered
  Cilium chart into the controlplane `cluster.inlineManifests` as a create-only
  bootstrap **seed** — the same `data.helm_template` → inlineManifest pattern as
  ArgoCD (`cilium_chart_version` is a SEED knob, not an upgrade knob). A fresh
  cluster therefore comes up on Cilium, **not Flannel**. `cni:none` is applied in
  both the config-generation and per-node apply passes, so a caller patch cannot
  resurrect Flannel. New inputs: `deploy_cilium`, `cilium_chart_version`,
  `cilium_chart_repository`, `cilium_namespace`, `cilium_values_override`,
  `cilium_routing_mode`, `cilium_native_routing_cidr`, `cilium_kube_proxy_replacement`,
  `cilium_mtu`, `cilium_encryption` (`none|wireguard|ipsec`), `cilium_ipsec_key`
  (sensitive), `cilium_gateway_api`, `cilium_gateway_api_crds_url`, plus first-class
  `pod_cidr`, `service_cidr` (fed to BOTH Talos subnets AND Cilium), `dual_stack`,
  and `allow_scheduling_on_controlplanes`. The base ships a minimal,
  cluster-agnostic Cilium floor (`helm/cilium-values.yaml`); per-cluster install-time
  config rides the typed inputs + `cilium_values_override`. Decision + validation:
  `docs/adr-cluster-yaml-sot.md`.

  **BREAKING — migration:** a caller that previously relied on the Talos-default
  Flannel plus its own `cluster.extraManifests`-URL Cilium recipe must either adopt
  the module-delivered Cilium (drop the extraManifests recipe) or set
  `deploy_cilium = false` to keep the prior behaviour. Next OCI tag is a MAJOR bump.

- **`cluster.yaml` is now the full declarative cluster Source-of-Truth.** It
  carries the complete cluster definition (identity, Talos/Kubernetes versions,
  endpoint, pod/service CIDR, dual-stack, scheduling, nodes, classes,
  machine-config patches, and the `substrate.{cilium,argocd}` config). The
  consumer's OpenTofu root becomes a thin `yamldecode` shim that maps the file
  onto the `talos-cluster` module's typed interface — tofu is the executor, not
  the SoT. Machine-config patches are declared as structured YAML maps (the shim
  `yamlencode`s them onto the module's `list(string)` interface). Secrets
  (`sops_age_key`, `cilium_ipsec_key`) have no slot in `cluster.yaml`; they are
  supplied via tfvar/env. `cluster.yaml.example` and the
  `tofu/modules/talos-cluster/examples/complete` root are rebuilt to this shape.
  Realizes `docs/adr-cluster-yaml-sot.md` decision 3; corrects the OpenTofu-cutover
  ADR's "node/class definitions live in the consumer's OpenTofu root" stance.

  **BREAKING — migration:** the `cluster.yaml` schema and the consumer
  OpenTofu-root shape change. A consumer on the post-#82 slim `cluster.yaml`
  re-expands it to the full schema and replaces its hand-written HCL root with the
  thin `yamldecode` shim (see the rebuilt complete example). Next OCI tag is a
  MAJOR bump.

### Added

- **Cilium Gateway API controller** enabled by default (`cilium_gateway_api`),
  satisfying the "Gateway API only" Hard Constraint at the mechanism layer. The
  Gateway API CRDs (Cilium 1.19 → Gateway API v1.4.1 standard channel) are a Day-1
  GitOps / apps-catalog concern by default; bootstrap seeding via
  `cluster.extraManifests` is **opt-in** (`cilium_gateway_api_crds_url`), because a
  failed `extraManifests` fetch is not graceful (it crashloops Talos'
  ExtraManifestController and blocks clean bootstrap).
- **Plan-time guards** in the module: a SecureBoot-installer substring guard over
  all caller `config_patches` (the no-SecureBoot Hard Constraint, in code — a
  consumer's patches escape the repo's `tofu/**` CI grep) and a clear
  undefined-`node.class` failure.

### Fixed

- **OCI release tarball now ships the module `helm/` values dir**
  (`argocd-values.yaml`, `cilium-values.yaml`). The allowlist previously omitted
  it, so a consumer using the published OCI artifact as the tofu module source hit
  a file-not-found at plan time for both ArgoCD and Cilium. The `git::` source path
  was unaffected.

## v0.8.0 — 2026-06-03

### Changed — BREAKING

- **`talos-cluster` module delivers ArgoCD as a Talos `inlineManifest`
  (`deploy_argocd` defaults to `true`).** ArgoCD is Layer-1 substrate in the C4
  layer model (Talos + Cilium + ArgoCD = three co-equal substrate pillars), so
  the module now seeds the bootstrap install: the `argo-cd` chart is rendered
  locally via `data.helm_template` (new `hashicorp/helm` provider, used for
  rendering **only** — no `helm_release`/apply against a computed kubeconfig) and
  baked into the controlplane `cluster.inlineManifests` as namespace →
  `sops-age-key` Secret (for the ksops repoServer) → ArgoCD app. The three
  ArgoCD CRDs (~1.8 MB) are too large for an inlineManifest, so the module
  applies them via `kubectl` server-side after the health gate (new
  `hashicorp/local` + `hashicorp/null` providers; requires `kubectl` on the
  apply host). New inputs: `deploy_argocd` (default `true`), `sops_age_key`
  (sensitive, **required** when `deploy_argocd`), `argocd_namespace`,
  `argocd_chart_version` (seed-only), `argocd_values_override` (merged, not
  replaced). Steady state (TLS cert, RBAC, OIDC, app-of-apps) is ArgoCD
  self-management in the consumer repo.

  **BREAKING — migration:** existing callers must either set
  `deploy_argocd = false` to keep prior behaviour, or supply `sops_age_key`
  (else `tofu plan` hard-fails on the precondition). The default-`true` is the
  correct Vision statement (ArgoCD is constitutive), so this is a deliberate
  breaking change, not an additive one.

- **Module waits until the cluster is healthy.** `data.talos_cluster_health`
  blocks `tofu apply` after bootstrap until etcd quorum + nodes Ready + apiserver
  reachable (new `cluster_health_timeout`, default `10m`). The
  `kubeconfig`/`talosconfig` outputs and a new `cluster_health` output
  `depends_on` it, so credentials are only emitted for an online cluster. NOTE:
  the gate verifies cluster reachability, NOT the ArgoCD rollout.

## v0.7.0 — 2026-06-02

### Changed — BREAKING

- **OpenTofu module is the sole Talos cluster-lifecycle path.** The entire
  `talos/Makefile.lib` + `argv-print.sh` + 5-axis `cluster.yaml` generator is
  removed and replaced by the `tofu/modules/talos-cluster` OpenTofu module
  (machine secrets → per-class Image-Factory installer → machine config → apply
  → bootstrap → kubeconfig). Node roles are `controlplane`/`worker` only;
  hardware specialisation is a per-node `class` selecting an Image-Factory +
  patch profile (`architecture` incl. arm64/SBC `overlay`, `extensions`,
  `config_patches`); per-node `config_patches` carry genuinely per-node values
  (for example, NIC binding). `cluster.yaml` is slimmed to the ArgoCD-bootstrap identity
  (`cluster.{name,overlay,target_revision}` + `repo.url`); Talos node/class
  definitions move to the consumer's OpenTofu root. Local tooling is pinned via
  devbox; `task ci` (fmt-check + validate + lint) is the validation entrypoint
  and a new `tofu-validate` CI workflow enforces it. Decision + consequences:
  [`docs/adr-opentofu-cluster-lifecycle.md`](docs/adr-opentofu-cluster-lifecycle.md).
  **Migration:** see [`UPGRADING.md`](UPGRADING.md). Adopting an already-running
  cluster (PKI import, no re-bootstrap) is a tracked follow-up — the module is
  greenfield-safe today.

### Removed

- `talos/` in full (`Makefile.lib`, `scripts/*`, `patches/*`, `schemas/`,
  `test/`, `versions.mk`, RELEASE-NOTES-v0.5.x/v0.6.0, `AGENTS.md`), the
  `.github/workflows/role-patches-canonical.yml` workflow, and the 5-axis
  sections of `cluster.yaml`. The `EMIT=content` shared-render-artifact work
  (`adr-shared-render-artifact.md`) is superseded — the OpenTofu provider
  renders machine config directly, so the cross-frontend render bridge is no
  longer needed.

- **`feat(oci): ship Cilium recipe + inputs in OCI artifact (symmetric to
  Talos)`** — the OCI tarball now also carries
  `kubernetes/bootstrap/cilium/{extras,values}.yaml` and
  `scripts/render-cilium-bootstrap.sh`, mirroring the existing `talos/`
  surface. Additive only: no render-mechanic, schema, or Consumer-side
  change; a consumer cluster continues consuming Cilium via Git
  Multi-Source. Closes #84.

- **Repo-wide shellcheck gate** — adds `shellcheck -S warning` over all
  tracked `*.sh` to both pre-commit (local hook, `repo: local`) and CI
  (`gitops-validate.yml` `shellcheck` job, parallel to `secret-scan`).
  Fixes the two pre-existing findings: SC2034 (unused `src` in
  `scripts/render-capability-index.sh:309`) and SC2038 (`find|xargs`
  replaced with `-exec sh -c … +` in `scripts/verify-rendered.sh:19–21`).
  Both fixes are behavior-preserving; enumeration output is byte-identical.
  Closes #94.

- **`feat(cilium): render script accepts CILIUM_VALUES_OVERLAY + CILIUM_OUTPUT_FILE for Consumer overrides`**
  — `scripts/render-cilium-bootstrap.sh` gains two optional env vars; Helm `-f`
  list-replace caveat documented in the script header. Additive only; overlay-unset
  render is byte-identical. Closes #85.

Next release is the v1.0.0 substrate split per
[`docs/adr-substrate-only-base.md`](docs/adr-substrate-only-base.md).

## v0.6.0 — 2026-05-28

This is the coordinated MAJOR release that turns the v0.5.x 5-axis
preview into the only supported `cluster.yaml` path and folds the
remaining PNI policy name/behaviour cleanup. Engineering rationale per
item lives in [`talos/RELEASE-NOTES-v0.6.0.md`](talos/RELEASE-NOTES-v0.6.0.md);
consumer migration recipe in [`UPGRADING.md` §`v0.6.0`](UPGRADING.md).
The substrate split (PNI + 19 other components move to a new
`talos-platform-apps` repo) is **not** in this release — see
[`docs/adr-substrate-only-base.md`](docs/adr-substrate-only-base.md)
for the v1.0.0 plan.

### Changed (breaking)

- **Cluster identity field renames** — `cluster.api_vip` →
  `cluster.vip`; `cluster.gateway_vip` removed. A cluster has exactly
  one Kubernetes API VIP; Gateway / LoadBalancer VIPs belong with the
  respective Gateway-API manifests, not cluster identity.
- **NTP servers as a list** — `cluster.ntp_server` (string) →
  `cluster.ntp_servers` (array, minItems 1, per-element charset
  validation). Single-NTP was a SPOF: outage → clock drift → etcd
  cert validation failure. Talos `machine.time.servers` is natively
  a list; ≥2 servers now recommended for redundancy.
- **`hardware-platforms.nvidia-gpu-node` removed.** Axis 4 names the
  CPU mainboard / chassis class only. GPU presence is captured on
  Axis 5 via the `gpu-nvidia` capability; the Axis-4 entry was a
  duplicate contract. GPU nodes now declare
  `hardware-platform: intel-generic` plus capability `gpu-nvidia`.
- **gVisor removed from `hardware-capabilities`.** Workload-runtime-class
  labels (`platform.io/gvisor`) are not hardware predicates
  per ADR Three-Layer §D7. `worker-gvisor.yaml` now lives in
  `roles.<role>.patches[]` per the slot ladder in
  `talos/AGENTS.md §Patch slots`. `translate-legacy-cluster-yaml.sh`
  no longer emits a `gvisor` entry in the rendered
  `hardware-capabilities` block.
- **`hardware_capabilities` underscore alias removed.** The v0.5.4
  grace-window alias is gone from the schema, `argv-print.sh`, and
  `validate-schematics.sh`. Use canonical kebab-case
  `hardware-capabilities` everywhere. Schema's `required` list now
  hard-includes the kebab field; underscore-only documents fail with
  `'hardware-capabilities' is a required property`.
- **`hardware-capabilities[*].patches[].file` is now auto-composed.**
  Was declarative-only in v0.5.x. `argv-print.sh` emits cap-patches
  as `--config-patch` after role-patches (later-wins per talosctl
  merge semantics). Audit for accidental duplication with
  `roles.<role>.patches[]` — the same patch listed in both is
  emitted twice (harmless for identical content; cap wins on
  divergence).
- **Legacy `talos/Makefile` deleted** — the 439-LOC pattern-rule
  generator is gone. Consumers MUST include
  `$(BASE_DIR)/Makefile.lib` from their `talos/Makefile`.
- **Kyverno ClusterPolicies renamed (PNI name/behaviour cleanup).**
  Two policies that were missed by the v0.5.0 rename (#40):
  `pni-capability-validation-audit` →
  `pni-capability-validation-enforce`;
  `pni-reserved-labels-audit` → `pni-reserved-labels-enforce`.
  Rule names, validation messages, and behaviour unchanged. File
  names already matched the new policy names — only the
  `metadata.name` field was renamed. Migration is identical to the
  v0.5.0 `pni-contract` rename.

### Added

- **`talos/RELEASE-NOTES-v0.6.0.md`** — engineering rationale per
  breaking change above.
- **`UPGRADING.md §v0.6.0`** — consumer migration recipe (nine steps,
  in order).

### Added (Layer-A / Layer-C work, pre-cutover)

- **Layer-A entry classification (issue #62).** New required `kind:`
  field on every entry in `docs/platform-capability-index.yaml` —
  enum `tool-capability | network-primitive`. Four entries
  reclassified as `network-primitive` (`internet-egress`,
  `controlplane-egress`, `gateway-backend`, `external-gateway-routes`)
  per the Round-2 layer-audit
  (`.work/issues/layer-audit/cleanup-scope.md` Q1) — these have
  legitimately empty `composition[]` because the Cilium/Kyverno rule
  itself IS the dataplane. The remaining 32 entries are
  `tool-capability`. Hybrid case: `s3-object` keeps `kind:
  tool-capability` (has `minio-operator` real tool); its `external-s3`
  implementation gains a per-impl `external_network_attachment: true`
  flag. Mechanism decision recorded in
  `.work/issues/p5-network-primitives-lift/decision.md`.
  `scripts/lint-capability-index.sh` enforces the kind enum + per-impl
  flag; `scripts/check-capability-index-refs.sh` skips the
  empty-composition violation for `kind: network-primitive` entries.
  `scripts/render-capability-index.sh` surfaces `kind:` in the summary
  table and per-entry header. `docs/capability-architecture.md` gains
  a "Layer A entries: tool-capability vs network-primitive"
  subsection.

- **Three-Layer Capability Architecture (issue #61).** New ADR
  `docs/adr-three-layer-capability-architecture.md` (status: accepted)
  supersedes the Two-Layer ADR. Introduces **Layer C — Hardware Features
  Registry** at `docs/platform-hardware-features.yaml` with 7 atomic
  feature entries (`nvidia-gpu`, `vt-x-or-amd-v`, `kvm-kernel-module`,
  `drbd-kernel-module`, `local-nvme-block-device`, `iommu-enabled`,
  `ebpf-capable-kernel`) plus draft-2020-12 JSON Schema at
  `docs/schemas/hardware-features.schema.json`. Six Layer-A entries
  (`gpu-runtime`, `vm-runtime`, `block-storage-replicated`,
  `block-storage-local`, `secondary-network-attachment`,
  `cluster-provisioning`) gain `requires_hardware_features[]` referencing
  Layer-C ids. `node-feature-discovery` removed from
  `gpu-runtime.composition[]` (Layer-C producer-tooling, not Layer-A);
  `gpu-runtime.independence_test.alt_impls_exist` stays `false` (entry
  is NVIDIA-pinned by name + contract + `requires_hardware_features`;
  AMD ROCm / Intel Gaudi are sibling Layer-A capabilities, not
  alt-impls of this entry); `independent_lifecycle` re-evaluated to
  `true` post-NFD-removal (device-plugin and DCGM-exporter have
  separate version trains).
- **Composite Capability Convention.** ADR §Composite capability
  convention documents the CNCF-Platforms-White-Paper two-tier model:
  Layer C holds atomic features; composite capabilities (for example,
  `compute-virt`, `compute-gpu-nvidia`) are downstream-defined in
  consumer `cluster.yaml` `hardware-capabilities:` blocks via
  `requires_features[]`. Composite labels emit
  `platform.io/hardware-capability.<cap>=true` via Talos
  `machine.nodeLabels`. The base ships no composite-capability registry.
- **`scripts/lint-hardware-features.sh`** — sibling lint script that
  validates `docs/platform-hardware-features.yaml` against the JSON
  Schema (uses `check-jsonschema`; falls back to `uvx` for local dev).
- **`scripts/render-capability-index.sh`** extended to dispatch to
  Layer A + Layer C rendering. New `--layer {a,c,all}` flag (default
  `all`); `--check` verifies both rendered MD files.
- **`scripts/check-capability-index-refs.sh`** extended with Layer-C
  resolution (`requires_hardware_features[]` ids must resolve to Layer-C
  registry) and orphan-infra-dir advisory detection (`WARN:
  orphan-infra-dir <path>` for dirs under
  `kubernetes/base/infrastructure/` not referenced by any Layer-A
  composition[] and not in the Layer-C producer-tooling allow-list).
- **CI job `capability-index-check`** reordered: Layer-C schema lint
  runs before Layer-A refs-check (ordering matters — Layer-A
  cross-references depend on Layer-C ids resolving). Job renamed to
  `Capability-index validation (Layer A + Layer C)`.
- **Kyverno ClusterPolicy `pni-reserved-labels-enforce`** extended with
  new rule `reserved-layer-c-hardware-labels`: denies tenant-set
  `platform.io/hardware-feature.*` and `platform.io/hardware-capability.*`
  labels on standard-workload kinds (Pod, Deployment, StatefulSet,
  DaemonSet, ReplicaSet, ReplicationController, Job, CronJob, Service,
  Namespace), checking BOTH the resource's own `metadata.labels` AND
  workload-template paths (`spec.template.metadata.labels`,
  `spec.jobTemplate.spec.template.metadata.labels`). Closes the
  controller-mediated propagation attack surface identified in Round-1
  team-red review (`.work/reviews/r1/team-red.md` CRITICAL). Per-CRD
  enforcement (KubeVirt `VirtualMachine`, CNPG `Cluster`, and other
  consumer-installed CRDs) is out-of-scope and tracked as a follow-up
  issue per ADR §Enforcement scope (intentional limits).

### Changed

- **`AGENTS.md` §"Reserved-label rule"** extended for Layer C: the two
  new namespaces (`platform.io/hardware-feature.*`,
  `platform.io/hardware-capability.*`) are documented; upstream-owned
  namespaces (`feature.node.kubernetes.io/*`, `nvidia.com/*`) are
  documented as convention-not-policy.
- **`ARCHITECTURE.md`** updated to reference the three-layer model
  (replacing the two-layer description) and to link to the new ADR.
- **`docs/capability-architecture.md`** gains a "Where this document
  sits in the three-layer model" section explicitly naming Layer C
  alongside Layer A and Layer B.
- **`docs/README.md`** index updated: links to
  `platform-capability-index.md` (Layer A), `platform-hardware-features.md`
  (Layer C), and the new Three-Layer ADR; the Two-Layer ADR entry is
  marked superseded.
- **`docs/adr-two-layer-capability-architecture.md`** frontmatter
  flipped to `status: superseded` with `superseded_by:
  adr-three-layer-capability-architecture.md`. Body preserved verbatim
  for decision history; a top-of-document blockquote calls out the
  supersession.

### Changed (pre-existing)

- **README.md surfaces the Day-Zero invariant in the lead section.**
  One paragraph between "Why this exists" and "The idea" names the
  load-bearing rule ("the base ships Talos plus the minimum needed for
  ArgoCD to take over; everything else is GitOps-reconciled") and
  links to `docs/day-zero-pattern.md`. Prevents the reader from having
  to reconstruct the pattern from `ARCHITECTURE.md`, `AGENTS.md`, and
  the root `Makefile`.
- **README.md rewritten around the repo's vision (#58).** Reorganised
  from a feature-listing into a problem-and-answer narrative: why this
  base exists (three pain points: per-cluster drift, tool lock-in via
  network policy, vendor-the-tarball trust), the idea that closes each
  pain (immutable OCI artifact, capability-first PNI, cosign + SLSA +
  SBOM), what consumers receive, how to consume it (Day-0 vendor +
  Day-2 ArgoCD Multi-Source stanza), how to verify it before vendoring,
  honest status (single maintainer, pre-1.0, first consumer
  established), and a routing table to the rest of the docs. Body now
  matches the Talos / Crossplane / FluxCD pattern for operator-audience
  base repos; component listings, validation-command reference, and
  full structure tree moved to `ARCHITECTURE.md` / `CONTRIBUTING.md` /
  `docs/` where they belong.

### Added

- **Day-Zero pattern explanation (`docs/day-zero-pattern.md`).** Single
  canonical write-up of the three-layer bootstrap path: Talos (OS +
  bundled Kubernetes + Cilium CNI via `extraManifests`) → ArgoCD
  self-bootstrap (the five `kubectl apply` / `helm` invocations
  contained behind `make argocd-bootstrap`, each with a stated
  reason) → ArgoCD-reconciled day-two (the 22 components under
  `kubernetes/base/infrastructure/`, sync-wave -2 / -1 / 0 / 1
  ordering preserved). Includes the canonical end-to-end command
  sequence a consumer-cluster operator runs, plus the explicit
  statement that nothing outside the documented bootstrap exceptions
  may be `kubectl apply`-ed. Linked from `docs/README.md §Explanation`
  and from the tutorial's *Where to go next* table.
- **Human-maintained component dependency graph
  (`docs/component-dependencies.md`).** Mermaid graph of cross-component
  edges in `kubernetes/base/infrastructure/`. Hard edges sourced from
  `values.yaml` service-DNS references, `ClusterIssuer` names, and
  CRD producer / consumer relationships; soft edges sourced from
  ADR-documented namespace co-tenancy and App-of-Apps deploy
  provenance. PNI `provide.<cap>` / `consume.<cap>` labels are
  deliberately **not** the source — they are an admission contract,
  not a dependency declaration. `CONTRIBUTING.md` mandates an update
  on component add / remove / rename or service-DNS / Issuer
  cross-reference changes. A render-script-based approach was
  evaluated via multi-perspective review and an empirical research
  pass and rejected as overengineering at the current scale
  (22 components, 3 documented cross-references) per CNCF Platforms
  White Paper TVP guidance; re-evaluate when cross-reference count
  exceeds ~50.
- **Vale prose linter + Google Developer Documentation Style (#57).**
  `.vale.ini` configures Vale 3.14.2 with the Google style package,
  scoped to root-level Markdown files (`README`, `ARCHITECTURE`,
  `AGENTS`, `CONTRIBUTING`, `SECURITY`, `MAINTAINERS`, `UPGRADING`,
  `CHANGELOG`). Conservative initial ruleset: opts out of Headings,
  EmDash, LyHyphens, Spelling, Units, WordList, Will, Acronyms (each
  with a documented reason); enforces `Latin`, `Periods`, `Quotes`,
  `Slang`, `We`, plus `Vale.Avoid` and `Vale.Repetition`. New `vale`
  CI workflow (pinned by SHA per Scorecard convention) blocks on
  every error.
  Spec: [vale.sh](https://vale.sh) +
  [Google Developer Docs Style](https://developers.google.com/style).
- **arc42 narrative scaffolding in ARCHITECTURE.md (#56).** Adds arc42
  sections 1 (Introduction & Goals), 2 (Architecture Constraints), 4
  (Solution Strategy), 10 (Quality Requirements), 11 (Risks &
  Technical Debt), 12 (Glossary) around the existing C4 L1+L2 views.
  arc42 §5 (Building Block View) and §6 (Runtime View) remain covered
  by C4 L2 and "Key flows"; §9 (Architecture Decisions) is the ADR
  set. Spec: [arc42.org](https://arc42.org/).
- **MADR 3.0 frontmatter on every ADR (#55).** All four ADRs migrated
  from plain-Markdown `**Status:** …` / `**Date:** …` headers to
  structured YAML frontmatter (`status`, `date`, `deciders`,
  `consulted`, `informed`, `supersedes`, `related`). New
  [`docs/adr-template.md`](docs/adr-template.md) is the source for
  future ADRs. Spec:
  [MADR 3.0](https://adr.github.io/madr/) ([adr.github.io](https://adr.github.io)).
- **OpenSSF Best Practices self-assessment (#54).** New
  [`docs/openssf-best-practices.md`](docs/openssf-best-practices.md)
  maps every Passing-level criterion to a load-bearing artefact in
  this repo (Apache-2.0 + REUSE for licensing, cosign + SLSA + SBOM
  for secure release, `SECURITY.md` + `security.txt` for vulnerability
  reporting, conftest + kubeconform for static analysis). External
  enrolment at <https://www.bestpractices.dev> is a manual maintainer
  step; the badge appears in README only after the project ID is
  assigned. Spec:
  [bestpractices.dev/criteria/0](https://www.bestpractices.dev/criteria/0).
- **OpenSSF Scorecard CI workflow + README badge (#53).** Weekly
  scheduled supply-chain risk analysis via
  `ossf/scorecard-action@v2.4.3` (SHA-pinned). SARIF results uploaded
  to GitHub code-scanning + published to the public OpenSSF Scorecard
  API at `api.scorecard.dev`. The README badge reflects the latest
  scheduled run. Spec:
  [github.com/ossf/scorecard](https://github.com/ossf/scorecard).
- **CycloneDX 1.6 SBOM attached to every OCI artifact (#52).** Generated
  by Syft via `anchore/sbom-action@v0.17.9` during the publish workflow
  and attached as a cosign attestation (`--type cyclonedx`) keyed to the
  OCI artifact digest. Consumers verify via
  `cosign verify-attestation --type cyclonedx …` (see
  [`docs/oci-artifact-verification.md`](docs/oci-artifact-verification.md)
  step 3). Spec: [CycloneDX 1.6](https://cyclonedx.org/specification/overview/).
- **REUSE 3.3 licensing compliance (#51).** `REUSE.toml` + `LICENSES/`
  layout with aggregate Apache-2.0 annotation; `LicenseRef-UpstreamHelm`
  marks rendered Helm output (project does not own the copyright). New
  `reuse-compliance` CI job enforces compliance on every PR.
- **RFC 9116 `.well-known/security.txt` (#50).** Machine-readable
  security contact metadata complementing `SECURITY.md`. Indexed by
  OpenSSF Scorecard and security scanners.

## v0.5.0 — 2026-05-18

> This release bundles four concurrent work streams: (a) the
> capability-first v2 refactor (PRs B / C / D / E), (b) the documentation
> overhaul (root-level OSS-hygiene files + Diátaxis-organised `docs/`),
> (c) the late-cycle PNI policy rename (#40), and (d) the
> production-readiness wave that makes the base consumable by a second
> cluster (#31 cluster-agnostic refactor, #33 Layer-A validation tooling,
> #35 per-component READMEs).

### Added

- **PNI policy rename (#40).** `ClusterPolicy/pni-contract-audit` is now
  named `pni-contract-enforce`, matching its filename and its
  `validationFailureAction: Enforce` semantics. Rule names and validation
  messages are unchanged. See [`UPGRADING.md` §v0.5.0](UPGRADING.md) for
  the consumer-side migration steps.
- **Layer-A capability-index validation tooling (#33).**
  - `scripts/lint-capability-index.sh` — schema lint (required fields,
    kebab-case ids, ISO-8601 dates, enum validity for stability /
    deployment_topology / swap_class / implementation status). Uses
    `yq has()` instead of `// "missing"` to distinguish a missing field
    from an explicit `false` boolean.
  - `scripts/check-capability-index-refs.sh` — cross-reference check:
    `composition[]` resolves to a `kubernetes/base/infrastructure/<comp>/`
    directory or is marked external; `replaced_by` / `split_into` /
    `composed_of` resolve to Layer A ids; `pni_capability_id` is null or
    resolves to a Layer B id.
  - `scripts/render-capability-index.sh` — deterministic, idempotent
    YAML → Markdown renderer. `--check` mode for CI drift detection.
  - `scripts/test/capability-index-broken-fixture.yaml` — negative-test
    fixture (lint must exit non-zero on it).
  - `docs/platform-capability-index.md` — committed render of the
    802-line YAML source.
  - `.github/workflows/gitops-validate.yml` — new `capability-index-check`
    CI job runs all four checks (positive, negative-test, refs, render
    drift).
  - `docs/adr-two-layer-capability-architecture.md` — status promoted
    from `proposed` to `accepted` now that the two-artifact invariant
    (Layer A id-set ⊇ Layer B id-set; cross-references resolve;
    generated MD matches YAML) is mechanically enforced across PRs.
- **Per-component READMEs (#35).** All 22 directories under
  `kubernetes/base/infrastructure/<comp>/` now ship a README answering:
  what the component is for (one sentence), upstream chart + pinned
  version, declared PNI capabilities (provider + consumer), repo-specific
  Helm-value overrides, and known upgrade gotchas.
  `scripts/render-component-readmes.sh` is the deterministic generator
  with hand-curated Purpose + Gotchas maps and auto-extracted chart /
  namespace / PNI / values fields. bash 3.2 compatible (uses case-
  statement functions, not associative arrays).
- **Root-level OSS-hygiene documents.**
  - `ARCHITECTURE.md` — root-level C4 L1/L2 architecture document with
    Mermaid diagrams (System Context, Container view, release flow,
    capability-admission flow).
  - `SECURITY.md` — disclosure channel, supported-versions matrix,
    supply-chain (cosign + SLSA + immutable tags), threat-model summary,
    in/out-of-scope table, hardening notes.
  - `CONTRIBUTING.md` — scope, conventional-commits, PR expectations,
    capability-first design rules, file-placement rules, sensitive-data
    policy.
  - `MAINTAINERS.md` — active maintainer list + decision authority.
  - `CODEOWNERS` — review routing per path.
  - `UPGRADING.md` — cumulative migration guide for OCI-vendored
    consumers; per-tag template for future MAJOR/MINOR notes; pending-
    sunset table (`storage-csi`, `monitoring-scrape-provider`).
- **Diátaxis-organised `docs/` set.**
  - `docs/README.md` — Diátaxis-organised doc index.
  - `docs/capability-architecture.md` — canonical architecture
    explanation for the capability-first v2 contract.
  - `docs/pni-cookbook.md` — concrete consumer + producer + CCNP recipes.
  - `docs/tutorial-first-consumer-cluster.md` — Diátaxis tutorial
    quadrant (vendor + verify + render).
  - `docs/harness-plugin-integration.md` — specification of what the
    harness plugin should provide for the v2 contract;
    explicit rationale why this base ships no `.claude/`.
- **Lint + CI for docs.** `.markdownlint.yaml` + `.markdownlintignore` +
  CI gate in `.github/workflows/docs-lint.yml` (markdownlint + auto-
  regen freshness check on `docs/capability-reference.md`).
- **PNI policy — instanced-suffix audit (PR D).**
  `kyverno-clusterpolicy-pni-instanced-suffix-required.yaml` — new
  audit-mode ClusterPolicy that emits a PolicyReport advisory when a
  namespace declares bare `platform.io/consume.<cap>` for a capability
  marked `instanced: true` in the PNI registry. Audit-mode by
  intentional design: per-instance enforcement (generate+mutate) is
  consumer-overlay responsibility, not base. The advisory signals the
  vocabulary smell without blocking platform-internal consumers
  (`cert-manager`, `external-secrets`) whose specific Vault KV mount
  is overlay-configured.
- **Producer pod labels on operator pods (PR C).**
  - `vault-operator` (bank-vaults): pod retains
    `capability-provider.monitoring-scrape`. No `admission-webhook`
    label — bank-vaults vault-operator does NOT ship a
    ValidatingAdmissionWebhook (verified by grep of chart templates).
  - `vault-config-operator` (Red Hat): pod gains
    `capability-provider.{admission-webhook,monitoring-scrape}` via a
    kustomize strategic-merge patch. The upstream chart does NOT expose
    a `podLabels` value (hardcoded selectorLabels helper), so the patch
    is the right altitude.
  - `piraeus-operator`: pod gains
    `capability-provider.{admission-webhook,monitoring-scrape}` via the
    base `values.yaml`. NOTE: the base ships only `namespace.yaml` for
    piraeus-operator; the consumer overlay deploys the Helm chart and
    must merge the base `values.yaml` into the release.
- **Namespace trust anchors (PR C).**
  - `vault` namespace (declared by both vault-operator and
    vault-config-operator): adds `provide.admission-webhook`. The two
    `namespace.yaml` files are kept identical so whichever ArgoCD app
    applies last produces a consistent label set.
  - `piraeus-datastore` namespace: adds
    `provide.{admission-webhook,monitoring-scrape}`.
- **Producer-side labels on 4 components (PR B).**
  - `cert-manager`: webhook pod and Service carry
    `capability-provider.tls-issuance` + endpoint/protocol annotations;
    controller pod carries `capability-provider.monitoring-scrape`;
    `cert-manager` namespace carries `provide.{tls-issuance,monitoring-scrape}`.
  - `loki` (SimpleScalable write tier): write pods and Service carry
    `capability-provider.logging-ship` + endpoint/protocol annotations;
    `monitoring` namespace (declared by loki + kube-prometheus-stack)
    carries `provide.{logging-ship,monitoring-scrape}`.
  - `metrics-server` (relocated, see Changed): pod and Service carry
    `capability-provider.{hpa-metrics,monitoring-scrape}` + endpoint/
    protocol annotations; `metrics-server` namespace carries
    `provide.{hpa-metrics,monitoring-scrape}`.
  - `local-path-provisioner`: pod carries
    `capability-provider.block-storage-local` (set in base values.yaml);
    consumer overlay must host the deployment in a dedicated
    `local-path-storage` namespace carrying
    `provide.block-storage-local: "true"` (documented in values.yaml).
- **Existing-producer namespace-label migration (PR B).**
  - `vault` namespace: `provide.monitoring-scrape`.
  - `external-secrets` namespace: `provide.monitoring-scrape`.

- **Root-level OSS-hygiene documents.**
  - `ARCHITECTURE.md` — root-level C4 L1/L2 architecture document with
    Mermaid diagrams (System Context, Container view, release flow,
    capability-admission flow).
  - `SECURITY.md` — disclosure channel, supported-versions matrix,
    supply-chain (cosign + SLSA + immutable tags), threat-model summary,
    in/out-of-scope table, hardening notes.
  - `CONTRIBUTING.md` — scope, conventional-commits, PR expectations,
    capability-first design rules, file-placement rules, sensitive-data
    policy.
  - `MAINTAINERS.md` — active maintainer list + decision authority.
  - `CODEOWNERS` — review routing per path.
  - `UPGRADING.md` — cumulative migration guide for OCI-vendored
    consumers; per-tag template for future MAJOR/MINOR notes; pending-
    sunset table (`storage-csi`, `monitoring-scrape-provider`).
- **Diátaxis-organised `docs/` set.**
  - `docs/README.md` — Diátaxis-organised doc index.
  - `docs/capability-architecture.md` — canonical architecture
    explanation for the capability-first v2 contract.
  - `docs/pni-cookbook.md` — concrete consumer + producer + CCNP recipes.
  - `docs/tutorial-first-consumer-cluster.md` — Diátaxis tutorial
    quadrant (vendor + verify + render).
  - `docs/harness-plugin-integration.md` — specification of what the
    harness plugin should provide for the v2 contract;
    explicit rationale why this base ships no `.claude/`.
- **Lint + CI for docs.** `.markdownlint.yaml` + `.markdownlintignore` +
  CI gate in `.github/workflows/docs-lint.yml` (markdownlint + auto-
  regen freshness check on `docs/capability-reference.md`).
- **PNI policy — instanced-suffix audit (PR D).**
  `kyverno-clusterpolicy-pni-instanced-suffix-required.yaml` — new
  audit-mode ClusterPolicy that emits a PolicyReport advisory when a
  namespace declares bare `platform.io/consume.<cap>` for a capability
  marked `instanced: true` in the PNI registry. Audit-mode by
  intentional design: per-instance enforcement (generate+mutate) is
  consumer-overlay responsibility, not base. The advisory signals the
  vocabulary smell without blocking platform-internal consumers
  (`cert-manager`, `external-secrets`) whose specific Vault KV mount
  is overlay-configured.
- **Producer pod labels on operator pods (PR C).**
  - `vault-operator` (bank-vaults): pod retains
    `capability-provider.monitoring-scrape`. No `admission-webhook`
    label — bank-vaults vault-operator does NOT ship a
    ValidatingAdmissionWebhook (verified by grep of chart templates).
  - `vault-config-operator` (Red Hat): pod gains
    `capability-provider.{admission-webhook,monitoring-scrape}` via a
    kustomize strategic-merge patch. The upstream chart does NOT expose
    a `podLabels` value (hardcoded selectorLabels helper), so the patch
    is the right altitude.
  - `piraeus-operator`: pod gains
    `capability-provider.{admission-webhook,monitoring-scrape}` via the
    base `values.yaml`. NOTE: the base ships only `namespace.yaml` for
    piraeus-operator; the consumer overlay deploys the Helm chart and
    must merge the base `values.yaml` into the release.
- **Namespace trust anchors (PR C).**
  - `vault` namespace (declared by both vault-operator and
    vault-config-operator): adds `provide.admission-webhook`. The two
    `namespace.yaml` files are kept identical so whichever ArgoCD app
    applies last produces a consistent label set.
  - `piraeus-datastore` namespace: adds
    `provide.{admission-webhook,monitoring-scrape}`.
- **Producer-side labels on 4 components (PR B).**
  - `cert-manager`: webhook pod and Service carry
    `capability-provider.tls-issuance` + endpoint/protocol annotations;
    controller pod carries `capability-provider.monitoring-scrape`;
    `cert-manager` namespace carries `provide.{tls-issuance,monitoring-scrape}`.
  - `loki` (SimpleScalable write tier): write pods and Service carry
    `capability-provider.logging-ship` + endpoint/protocol annotations;
    `monitoring` namespace (declared by loki + kube-prometheus-stack)
    carries `provide.{logging-ship,monitoring-scrape}`.
  - `metrics-server` (relocated, see Changed): pod and Service carry
    `capability-provider.{hpa-metrics,monitoring-scrape}` + endpoint/
    protocol annotations; `metrics-server` namespace carries
    `provide.{hpa-metrics,monitoring-scrape}`.
  - `local-path-provisioner`: pod carries
    `capability-provider.block-storage-local` (set in base values.yaml);
    consumer overlay must host the deployment in a dedicated
    `local-path-storage` namespace carrying
    `provide.block-storage-local: "true"` (documented in values.yaml).
- **Existing-producer namespace-label migration (PR B).**
  - `vault` namespace: `provide.monitoring-scrape`.
  - `external-secrets` namespace: `provide.monitoring-scrape`.

### Changed

- **Cluster-agnostic refactor (#31, PR #44).** Every reference to a
  specific consumer-cluster repo name has
  been removed from the live documentation surface: `README.md` "How
  consumers use this," `AGENTS.md` "Repository Purpose," the
  `ARCHITECTURE.md` L1 System-Context diagram, `docs/mcp-setup.md`
  install hint, and the `cert-manager/kustomization.yaml` comment now
  speak only about generic "consumer cluster repos." The cluster-
  agnostic invariant is now visible in the docs, not just in the
  filesystem. `CHANGELOG.md` deliberately retains the historical
  references as per-release record; the rewrite scope is current
  architecture only.
- **ADR `docs/adr-multi-repo-platform-split.md` rewritten cluster-
  agnostic.** The ADR now describes the three repo *roles* (platform
  base, Claude-Code harness, consumer cluster repo) without naming
  individual repos. The phase-by-phase migration plan (Phases 1, 1.5,
  2, 3A, 3B) is dropped — every phase is long complete and the
  per-release history lives in this CHANGELOG. Net: 343 → 174 lines.
- **AGENTS.md / CLAUDE.md / README.md / .gitignore — capability-first v2 docs.**
  - `AGENTS.md` §"Platform Network Interface (PNI) Rules" rewritten to v2:
    capability-first vocabulary (5-site producer/consumer table),
    namespace-anchored trust, instanced suffix, reserved-label rule,
    out-of-scope note (per-instance enforcement is consumer-overlay
    scope).
  - `AGENTS.md` §"Hard Constraints" gains two v2-specific invariants:
    capability-selectors only for new CCNPs, namespace-anchored producer
    trust.
  - `AGENTS.md` §"Key Terms" expanded with capability, instanced
    capability, producer/consumer symmetry, namespace-anchored trust.
  - `CLAUDE.md` §"Context Architecture" gains a "Knowledge Map" pointing
    at the new docs.
  - `README.md` adds a capability-first pitch in the lead and a
    comprehensive doc-map table.
  - `.gitignore` adds `.claude/` (harness runtime dir) and `.work/`
    (harness scratchpad) — both runtime artefacts, never committed.
- **CCNP selector switched from tool-name to capability (PR E).**
  - `ccnp-pni-monitoring-scrape-consumer-egress.yaml` source selector
    rewritten from `app.kubernetes.io/name: prometheus` (tool-selector)
    to `platform.io/capability-consumer.monitoring-scrape: "true"`
    (capability-selector). A Prometheus → Victoria-Metrics swap is now
    a label move on the consumer pod, not a CCNP edit.
  - `kube-prometheus-stack` values.yaml:
    `prometheus.prometheusSpec.podMetadata.labels` gains
    `platform.io/capability-consumer.monitoring-scrape: "true"` so the
    new CCNP source selector matches the Prometheus pod.
- **BREAKING — `metrics-server` relocated from `kube-system` to dedicated
  `metrics-server` namespace (PR B).** Consumer overlays that referenced
  `kube-system/metrics-server` directly (ServiceMonitor targets, manual
  kubectl wiring) must update to `metrics-server/metrics-server`. The
  `v1beta1.metrics.k8s.io` APIService is re-pointed automatically; HPA
  and `kubectl top` survive the change after one ArgoCD reconcile
  (~10–30s gap during the prune-and-replace window).
- **BREAKING — `pni-reserved-labels-audit` ClusterPolicy refactored (PR B).**
  The hardcoded `app.kubernetes.io/component: rabbitmq` and
  `redis_setup_type` trust signatures are removed. Trust now derives
  from a single namespace-anchored rule that requires
  `platform.io/provide.<cap>[.<inst>]: "true"` on the workload's
  namespace. Consumer overlays that currently deploy broker pods
  (RabbitmqCluster, RedisFailover, CnpgCluster instances) carrying
  `platform.io/capability-provider.<cap>.<instance>` MUST ensure the
  hosting namespace carries the matching `provide.<cap>.<instance>`
  label. Without that label, broker pods will be denied at admission
  after upgrade. The Kyverno generate-policies that automate this for
  CRD-managed instances ship in PR D; for the PR B → PR D gap, consumer
  overlays must add the namespace labels by hand.
- **ADR extensions (decision-grade record).**
  - ADR `adr-capability-producer-consumer-symmetry.md` extended with
    §"Per-instance enforcement is consumer-overlay responsibility"
    (PR D). Verification documented: the base ships only operators for
    instanced capabilities; data-plane instances (CNPG `Cluster`,
    `RabbitmqCluster`, `RedisFailover`, `Kafka`, `Vault` server,
    `LinstorCluster`) are consumer-overlay-deployed. Shipping
    speculative generate/mutate for tools the base does not deploy
    would violate the right-altitude principle.
  - ADR `adr-capability-producer-consumer-symmetry.md` extended with
    §"Namespace-anchored producer trust" (PR B) — locks the invariant
    that trust derives from namespace labels and that kube-system
    residents must be relocated, not exempted.

### Removed

- **BREAKING — Tool-name CCNPs for non-base-deployed operators (PR E).**
  - `ccnp-pni-cnpg-operator-dataplane-egress.yaml`. The CCNP used
    hardcoded tool-name selectors (`app.kubernetes.io/name:
    cloudnative-pg`, `cnpg.io/cluster`) and referenced an operator
    (cloudnative-pg in the `cnpg-system` namespace) that the base does
    NOT deploy. Tool-specific operator→broker CCNPs belong with the
    tool — consumer overlays that deploy CNPG must ship their own copy
    (cap-selector form recommended for tool-swap resilience).
  - `ccnp-pni-strimzi-operator-dataplane-egress.yaml`. Same rationale —
    the `strimzi-cluster-operator` is not base-deployed; the
    tool-specific operator-dataplane CCNP belongs in the consumer
    overlay that owns Strimzi.
- **Docs cleanup.**
  - `docs/claude-code-guide.md` — described a `.claude/` skill set that
    does not exist in this base. Inconsistent with `CLAUDE.md` policy
    ("this base ships no `.claude/` directory").
  - `docs/claude-code-stack-audit.md` — internal audit log of a
    *different* repository that was historically copied here.

### Notes (out-of-scope deliberate decisions; for context, not Changelog history)

- **PR E — deliberately kept.**
  `ccnp-pni-monitoring-dns-visibility.yaml` uses namespace-scoped source
  and tool-name target (`k8s-app: kube-dns`). kube-dns is a
  cluster-singleton; this is plumbing, not a capability binding.
  `ccnp-pni-{redis,rabbitmq}-operator-dataplane-egress.yaml` use
  capability-selectors, so they are tool-agnostic substrate even though
  the base does not deploy redis/rabbitmq operators.
- **PR D — verified scope.** Kyverno generate/mutate policies for
  `cnpg-postgres`, `redis-managed`, `rabbitmq-managed`, `kafka-managed`,
  `s3-object`, and per-instance generate/mutate for `vault-secrets`
  remain consumer-overlay scope.
- **PR C — deferred to PR D.** LINSTOR controller / satellite pods
  (created dynamically by piraeus-operator from a `LinstorCluster` CR)
  require a Kyverno mutate-policy to label operator-managed pods at
  admission. Per-instance scoping for `vault-secrets` KV mounts is
  likewise PR D scope.

## v0.1.0 — 2026-05-01

Initial release of `talos-platform-base`. Cluster-agnostic snapshot
extracted from a private upstream cluster repository, filtered to
retain only cluster-agnostic content per
`docs/adr-multi-repo-platform-split.md`, then post-cleanup-mutated to
remove residual cluster-specificity and add release machinery.

### Components (22 standalone-renderable)

All 22 base infrastructure components are standalone-renderable via
`kubectl kustomize --enable-helm kubernetes/base/infrastructure/<comp>/`.
The CI pipeline asserts this against `.ci-renderable-components.txt` —
a frozen ground-truth set; any drift between rendered components and
listed components fails the gate.

| Component | Pattern | Output |
| --- | --- | --- |
| alloy | helm (Grafana 1.6.0) | namespace + chart manifests (monitoring) |
| argocd | helm (argoproj 9.4.5) | namespace + chart manifests (argocd) |
| cert-approver | resources only | namespace (kubelet-serving-cert-approver). Upstream is kustomize-from-git; consumer adds via Application CR. |
| cert-manager | resources only | namespace (cert-manager) |
| dex | resources only | namespace (dex) |
| external-secrets | resources only | (existing pattern preserved) |
| kube-prometheus-stack | helm (prometheus-community 81.6.1) | namespace + chart manifests (monitoring) |
| kubevirt | resources only | (existing pattern preserved) |
| kubevirt-cdi | resources only | (existing pattern preserved) |
| kyverno | helm (kyverno 3.7.1) | namespace + chart manifests (kyverno) |
| local-path-provisioner | empty resources | (no-op render). Upstream is helm-from-git path; consumer adds via Application CR multi-source. |
| loki | helm (Grafana 6.53.0) | namespace + chart manifests (monitoring) |
| metrics-server | helm (kubernetes-sigs 3.12.2) | chart manifests (kube-system, no namespace declared) |
| multus-cni | resources only | crd + rbac + daemonset (kube-system) |
| node-feature-discovery | helm (kubernetes-sigs 0.17.4) | namespace + chart manifests (node-feature-discovery) |
| nvidia-dcgm-exporter | resources only | namespace (nvidia-dcgm-exporter, monitoring) |
| nvidia-device-plugin | helm (nvidia 0.17.4) | chart manifests (kube-system, no namespace declared) |
| piraeus-operator | resources only | namespace (piraeus-datastore) |
| platform-network-interface | resources only | PNI Kyverno policies + capability CCNPs |
| tetragon | helm (Cilium 1.6.1) | namespace + chart manifests (tetragon) |
| vault-config-operator | helm (redhat-cop v0.8.38) | namespace + chart manifests (vault) |
| vault-operator | helm (bank-vaults 1.23.4 OCI) | namespace + chart manifests (vault) |

### Talos artefacts

- Machine-config patches: common, controlplane (no extraManifests — consumer overlay supplies the URL list), drbd, worker-{gpu,gvisor,kubevirt,pi}, cluster.yaml.tmpl
- `talos/Makefile` with `cluster.yaml`-driven multi-cluster generation, including:
  - **CP_NODES non-empty guard**: errors if `cluster.yaml` parse yields no control-plane entries (catches yq-2>/dev/null silent failures).
  - **WORKER_NODES non-empty guard**: errors if `workers:` is empty (gpu_workers/pi_nodes remain optional).
  - **Node-name input validation**: rejects names with whitespace, `$`, `:`, `=`, `#`, `*` — these break the `IP_<name>` Make-variable map.
  - **Bootstrap rebuild guard**: refuses `make bootstrap` if `talosctl etcd members` returns members on the target node, requiring `BOOTSTRAP_FORCE=1` to override (prevents accidental quorum-destroying re-bootstrap).
  - **Bootstrap-node resolution**: `BOOTSTRAP_NODE := $(firstword $(CP_NODES))` reads from `cluster.yaml` instead of hardcoding a name.

### CI / repo hygiene

- `.github/workflows/gitops-validate.yml` — kustomize-render + kubeconform + conftest + Kyverno-policy validation; **set-based predicate against `.ci-renderable-components.txt`** to catch membership drift.
- `.github/workflows/hard-constraints-check.yml` — server-side enforcement of §Hard Constraints (no Ingress, no Endpoints).
- `.github/workflows/oci-publish.yml` — publishes the OCI artifact to `ghcr.io/nosmoht/talos-platform-base:<tag>` (and `:latest`) on every `v*` tag push.
- `.pre-commit-config.yaml` — codex-config + MCP-portability checks + gitleaks. SOPS hooks deferred to consumer (no `*.sops.yaml` in base).
- Branch protection on `main` (configured via `gh api PUT`): required status checks `validate` + `Secret Scan (gitleaks)`, `enforce_admins=false` initially.
- Repo-level secret-scanning + push-protection: enabled.
- All commits + the `v0.1.0` tag are SSH-signed.

### Release machinery

- `LICENSE` (Apache-2.0)
- `CHANGELOG.md` (this file)

### Removed from the upstream source

- All cluster-specific kustomize overlays
- All per-node Talos config inputs (per-node config, schematics, talosconfig, encrypted secrets bundle)
- Cluster-specific Talos patches and node-topology definitions
- Cluster-specific docs (hardware analyses, debug logs, environment-specific ADRs, postmortems, runbooks, upgrade reports)
- Cluster-specific operational scripts
- Cluster-specific CI workflows
- `.claude/`, `.codex/`, `Plans/` (tooling dirs; Claude-Code-specific primitives ship via the harness plugin)
- `.sops.yaml` (contained the upstream cluster's age recipient — cluster-specific identifier; would have created a cross-cluster privilege-escalation path if a different consumer adopted base and committed `*.sops.yaml`)
- Trivy ignore-list (`.trivyignore.yaml`) — scoped to cluster overlay paths
- Cluster-specific dev tooling (`package.json`/`package-lock.json`)

### Mutated post-filter

- `talos/patches/controlplane.yaml`: `extraManifests:` block removed. Consumer cluster repos layer their own controlplane patch with the appropriate Cilium-bootstrap URL (which carries cluster-specific Hubble TLS certificates).
- `talos/patches/worker-pi.yaml`: `registerWithTaints[].key` generalised from a cluster-specific label namespace to `platform.io/pi-reserved`. **Breaking change** for any consumer's public-ingress deployment if/when adopted; migration is consumer-side. A cluster-specific label namespace does not belong in base.
- `kubernetes/bootstrap/cilium/extras.yaml`: gateway-config name generalised to `cluster-gateway-config`.
- `kubernetes/bootstrap/argocd/namespace.yaml`: `instance`/`part-of` labels generalised to `argocd`/`gitops`.
- `Makefile`: dropped `argocd-oidc` and `migrate-cluster-yaml`; added `init-cluster-yaml`; `grafana-dashboards-check` now uses `OVERLAY_PATH` resolved from `cluster.yaml`; `validate-gitops` no longer references the dropped scripts.
- `AGENTS.md`, `CLAUDE.md`, `README.md`, `kubernetes/AGENTS.md`: rewritten for platform-base perspective.
- `docs/claude-code-guide.md`: per-node example references generalised to `<source-node>`/`<target-node>`. *(File removed in the docs-cleanup PR — see Unreleased section.)*
- `LICENSE`: prepended an Apache-2.0 copyright header.

### Added (post-cleanup)

- `kubernetes/base/infrastructure/<comp>/kustomization.yaml` for the 12 previously inputs-only components (alloy, argocd, cert-approver, kube-prometheus-stack, kyverno, local-path-provisioner, loki, metrics-server, node-feature-discovery, nvidia-device-plugin, tetragon, vault-config-operator, vault-operator). Where applicable, `helmCharts:` references the upstream chart with version pinned to the value used in the upstream source as of the source-state pin.
- `kubernetes/base/infrastructure/<comp>/namespace.yaml` for components whose target namespace is non-system (alloy, argocd, cert-approver, kube-prometheus-stack, kyverno, loki, node-feature-discovery, tetragon, vault-config-operator, vault-operator). System-namespace components (kube-system targeted: local-path-provisioner, metrics-server, nvidia-device-plugin) deliberately do not declare a namespace.
- `.ci-renderable-components.txt` — frozen ground-truth set of standalone-renderable base components.

### Known limitations

- `cert-approver` and `local-path-provisioner` cannot use `helmCharts:` in their base `kustomization.yaml` because their upstream distributions are kustomize-from-git (cert-approver: `github.com/alex1989hu/kubelet-serving-cert-approver, path: deploy/standalone, ref: v0.10.3`) and helm-from-git (local-path-provisioner: `github.com/rancher/local-path-provisioner, path: deploy/chart/local-path-provisioner, ref: v0.0.34`) — neither pattern is supported by `kustomize helmCharts:`. Consumer cluster repos add the upstream chart/kustomization via their ArgoCD Application CR's source spec.
- The 9 "resources only" components (cert-manager, dex, external-secrets, kubevirt, kubevirt-cdi, multus-cni, nvidia-dcgm-exporter, piraeus-operator, platform-network-interface) do not currently use `helmCharts:` in their base kustomization. Folding helmCharts: for these, where applicable, is tracked as a future v0.x evolution and is not a v0.1.0 acceptance criterion.

### Source-state pin

The base was extracted from a pinned commit of a private upstream cluster
repository. The upstream repository is **never modified** by base creation or
maintenance work; this is verified at every release-time gate via SHA
equality between captured pre-state and observed post-state.
