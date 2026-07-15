# Contributing to talos-platform-base

Thanks for considering a contribution. Read this whole file before
opening a PR; the validation pipeline is strict and a few patterns
have hard rules.

## Scope and audience

This repository is the **substrate-only platform base** for the
Talos-on-Kubernetes deployment family. The substrate is Talos + Cilium +
ArgoCD (three co-equal pillars) plus `cert-approver` as serving-cert glue (a
Talos `inlineManifest` seed, not a rendered component — adr-0013);
`kubernetes/base/infrastructure/` ships only `argocd/`. Contributions that fit
this scope:

- Improvements to the substrate components (`argocd/` rendered component; the
  `cert-approver` seed at `tofu/modules/talos-cluster/manifests/`).
- Improvements to the OpenTofu cluster-lifecycle module
  (`tofu/modules/talos-cluster`).
- Improvements to the validation pipeline (kustomize, conftest,
  kubeconform).
- Layer-C node-capability / hardware-feature work
  (`platform-hardware-features.yaml`, the provisioning-profile
  catalog, `scripts/lint-hardware-features.sh`,
  `scripts/check-provisioning-catalog-refs.sh`).
- Talos machine-config patches that apply to *all* clusters.
- Documentation.

Contributions that do NOT fit:

- Non-substrate platform components (observability, storage, the PNI /
  capability-network contract, application-supporting services) — these
  live in the [`talos-platform-apps`][apps] catalog as independently
  versioned, signed OCI artifacts. See [`knowledge/decisions/0004-substrate-only-base.md`][ablation].
- Cluster identity (node IPs, FQDNs, SOPS keys, OIDC issuers) — open in a
  consumer cluster repo instead.
- Per-cluster overlays or patches.
- Application-workload manifests.

[apps]: https://github.com/devobagmbh/talos-platform-apps
[ablation]: knowledge/decisions/0004-substrate-only-base.md

## Before you start

1. **Read [`AGENTS.md`](AGENTS.md)**. It is the canonical SOT and lists
   hard constraints that fail PR checks if violated.
2. **Read [`ARCHITECTURE.md`](ARCHITECTURE.md)** for the L1/L2 view.
3. **Read [`knowledge/decisions/0009-node-capability-composition.md`](knowledge/decisions/0009-node-capability-composition.md)**
   and [`knowledge/decisions/0003-three-layer-capability-architecture.md`](knowledge/decisions/0003-three-layer-capability-architecture.md)
   if your change touches per-node provisioning, Layer-C hardware
   features, or the `tofu/modules/talos-cluster` interface.
4. **Read the relevant decision records** in `knowledge/decisions/` (index:
   [`knowledge/decisions/index.md`](knowledge/decisions/index.md)).

## Issue → PR workflow

Issues are the primary entry point. State-machine and labels are
described in [`knowledge/workflows/issue-lifecycle.md`](knowledge/workflows/issue-lifecycle.md).

- Pick up `status: ready` issues only — these have passed R1–R5 readiness.
- Open a draft PR early; mark `Ready for review` once `task gitops:validate`
  passes locally.

## Conventional commits

Subject line:

```text
type(scope): short imperative summary
```

`type` ∈ {`feat`, `fix`, `perf`, `chore`, `docs`, `test`, `refactor`, `ci`}.
`scope` ∈ component or subsystem (for example `talos`, `cilium`,
`argocd`, `cert-approver`, …).

Body MUST explain the *why* and stay readable without an issue tracker.
Cross-link with `Closes:`, `Refs:`, `Fixes:` trailers using public URLs;
bare opaque IDs (`NOS-123`) are forbidden.

Releases are computed from these commits by semantic-release, so the
*type* and breaking markers drive the version bump (`feat` → MINOR,
`fix`/`perf` → PATCH). **A MAJOR bump requires a real `BREAKING CHANGE:`
footer or a `type!:` marker** — a prose `**BREAKING**` line in the body is
*not* recognised by the release tool. This matters for the AGENTS.md Hard
Constraint that a breaking change to base Helm values bumps MAJOR: add the
footer, or the change ships as a non-breaking release. See
[`knowledge/workflows/release-process.md`](knowledge/workflows/release-process.md).

## PR expectations

### Required (local) before opening

```bash
task gitops:validate             # kustomize + conftest + kubeconform
task spec:validate               # when openspec/ or a spec's primary source changed
task spec:check-staleness        # primary-source diff must touch the owning spec
                                 # (escape for no-behavior-change diffs:
                                 #  'Spec-Impact: none' trailer on EVERY commit
                                 #  touching the file)
```

For changes touching a single component:

```bash
kubectl kustomize --enable-helm kubernetes/base/infrastructure/<comp>/
```

For Layer-C hardware-feature / provisioning-catalog changes:

```bash
scripts/lint-hardware-features.sh
scripts/check-provisioning-catalog-refs.sh
```

For `tofu/modules/talos-cluster` changes:

```bash
task tofu:ci   # tofu fmt -check + tofu validate + tflint
```

### Required (CI) before merge

| Check | Why |
|---|---|
| `gitops-validate` | full render+lint+policy pipeline |
| `hard-constraints-check` | no Ingress/Endpoints kinds, etc. |
| `secret-scan` (gitleaks) | last-backstop on bypassed pre-commit |
| `docs-lint` | tool-pin drift, markdownlint, OKF bundle validation, offline link gate, AGENTS.md managed-block drift, OpenSpec strict validate (incl. bite-check + source-ownership partition), regeneration parity of the committed tool trees, and spec staleness (escape: a `Spec-Impact: none` trailer on every commit touching the file) |
| `preflight` | asserts the required-check contexts are wired |
| `oci-publish` dry-run (on tag PRs only) | confirms signing path works |

These are required PR checks and will block merge.

> The PNI / capability-first network-trust contract no longer lives in
> this base — it dissolved out of the substrate (see
> [`knowledge/decisions/0004-substrate-only-base.md`][ablation]) and is now realized by
> apps-CI Conftest plus consumer-cluster Kyverno, with the catalog in
> [`talos-platform-apps`][apps]. Cross-namespace reachability rules
> belong there, not in a base PR.

## Documentation expectations

If your change touches a public interface (Helm values, the
`tofu/modules/talos-cluster` interface, Layer-C hardware-feature schema,
hard constraints), update **at minimum**:

- `CHANGELOG.md` (Unreleased section — Added / Changed / Deprecated / Removed / Fixed / Security).
- Either a decision record (decision-grade, `knowledge/decisions/`) or the
  matching `knowledge/` concept.
- The owning OpenSpec spec (`openspec/specs/`) when the change alters
  platform behavior — as a spec delta via `openspec/changes/`; see
  [`knowledge/workflows/spec-driven-development.md`](knowledge/workflows/spec-driven-development.md).

The bundle's own authoring conventions — the closed `type` vocabulary, the
`timestamp`/`sources` staleness contract, the link rule, and the `log.md`
maintenance rule — are stated in `knowledge/rules/talos-base-bundle.md`. Read
that file rather than this section for them; it is the source of truth and is
rendered into `AGENTS.md` for agents.

The `## Open Knowledge Maintenance` block in `AGENTS.md` is generated from
`knowledge/rules/` and sits between `openknowledge:rules` markers. Regenerate
it with `task knowledge:rules-apply` after changing a rule document — do not
hand-edit it, or `task knowledge:rules-check` (a required CI gate) fails.

If your change adds, removes, or renames a component in
`kubernetes/base/infrastructure/`, or changes a service-DNS or
`ClusterIssuer` cross-reference between components, also update
[`knowledge/architecture/substrate.md`](knowledge/architecture/substrate.md).
The graph is human-maintained — no render script enforces it; PR
reviewers flag stale graphs.

## File placement rules

- Component directory name MUST equal the ArgoCD Application name.
- File-naming: `cnp-<component>.yaml`, `ccnp-<description>.yaml`.
- One component per directory: `<comp>/{application,kustomization,values}.yaml`.
- Repository-wide SOT belongs at the repo root, `knowledge/`, `schemas/`, or `contracts/`, never under tool-namespaced directories like `.claude/`, `.cursor/`, `.vscode/`.

## Sensitive data

- No literal secrets, tokens, or credentials in any file (including
  `.example` variants). Pre-commit gitleaks blocks this; CI re-runs
  gitleaks as a backstop.
- No internal RFC1918 IPs in committed files; use placeholders
  (`<API-VIP>`, `<NODE-IP>`).
- No hardcoded user-home paths in committed artifacts — use `$HOME`
  for shell/JSON/YAML and `~` for tilde-expanding contexts only.

## Code of conduct

This project follows the [Contributor Covenant Code of Conduct, v2.1](CODE_OF_CONDUCT.md).
By participating, you are expected to uphold its terms. Reports go to
`thomas.krahn.tk@gmail.com`.

## License

By contributing, you agree your work is licensed under the project's
Apache-2.0 [LICENSE](LICENSE) and that you have the right to submit it.
