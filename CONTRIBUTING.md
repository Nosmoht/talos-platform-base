# Contributing to talos-platform-base

Thanks for considering a contribution. Read this whole file before
opening a PR; the validation pipeline is strict and a few patterns
have hard rules.

## Scope and audience

This repository is the **cluster-agnostic platform base** for the
Talos-on-Kubernetes deployment family. Contributions that fit this
scope:

- New cluster-agnostic Helm-base components.
- Improvements to the validation pipeline (kustomize, conftest,
  kubeconform, Kyverno).
- PNI capability schema and policy improvements.
- Talos machine-config patches that apply to *all* clusters.
- Documentation.

Contributions that do NOT fit (open them in a consumer cluster repo
instead):

- Cluster identity (node IPs, FQDNs, SOPS keys, OIDC issuers).
- Per-cluster overlays or patches.
- Application-workload manifests.
- Per-instance Kyverno generate/mutate machinery for tools the base
  does not deploy — see [ADR][adr] §"Per-instance enforcement is
  consumer-overlay responsibility".

[adr]: docs/adr-capability-producer-consumer-symmetry.md

## Before you start

1. **Read [`AGENTS.md`](AGENTS.md)**. It is the canonical SOT and lists
   hard constraints that fail PR checks if violated.
2. **Read [`ARCHITECTURE.md`](ARCHITECTURE.md)** for the L1/L2 view.
3. **Read [`docs/capability-architecture.md`](docs/capability-architecture.md)**
   if your change touches network policy, namespace labels, or the
   capability registry.
4. **Read the relevant ADRs** in `docs/adr-*.md`.

## Issue → PR workflow

Issues are the primary entry point. State-machine and labels are
described in [`docs/issue-workflow.md`](docs/issue-workflow.md).

- Pick up `status: ready` issues only — these have passed R1–R5 readiness.
- Open a draft PR early; mark `Ready for review` once `make validate-gitops`
  passes locally.

## Conventional commits

Subject line:

```text
type(scope): short imperative summary
```

`type` ∈ {`feat`, `fix`, `chore`, `docs`, `test`, `refactor`, `ci`}.
`scope` ∈ component or subsystem (e.g. `pni`, `talos`, `cilium`,
`kyverno`, `loki`, …).

Body MUST explain the *why* and stay readable without an issue tracker.
Cross-link with `Closes:`, `Refs:`, `Fixes:` trailers using public URLs;
bare opaque IDs (`NOS-123`) are forbidden.

## PR expectations

### Required (local) before opening

```bash
make validate-gitops             # kustomize + conftest + kubeconform
make validate-kyverno-policies   # server-side ClusterPolicy test
```

For changes touching a single component:

```bash
kubectl kustomize --enable-helm kubernetes/base/infrastructure/<comp>/
```

For changes touching the PNI registry:

```bash
scripts/render-capability-reference.sh
git diff docs/capability-reference.md   # expect committed regen
```

### Required (CI) before merge

| Check | Why |
|---|---|
| `gitops-validate` | full render+lint+policy pipeline |
| `hard-constraints-check` | no Ingress/Endpoints kinds, etc. |
| `secret-scan` (gitleaks) | last-backstop on bypassed pre-commit |
| `oci-publish` dry-run (on tag PRs only) | confirms signing path works |

These are required PR checks and will block merge.

### Capability-first design rules

Any CCNP, Kyverno policy, or namespace label that involves cross-namespace
reachability MUST follow these rules (see [ADR][adr]):

- CCNP `endpointSelector` uses `capability-provider.<cap>` or `capability-consumer.<cap>` — never `app.kubernetes.io/name: <tool>`.
- New producer component ships its own `namespace.yaml` carrying matching `provide.<cap>` labels.
- No central tool-signature whitelist additions.
- No `kube-system` (or other shared system namespace) producer placements — relocate to a dedicated namespace.
- Instanced capabilities require the `.<inst>` suffix on consumer/producer labels.

## Documentation expectations

If your change touches a public interface (Helm values, registry schema,
CCNPs, hard constraints), update **at minimum**:

- `CHANGELOG.md` (Unreleased section — Added / Changed / Deprecated / Removed / Fixed / Security).
- Either an ADR (decision-grade) or the matching `docs/*.md` reference.
- Auto-generated docs that drift (`scripts/render-capability-reference.sh --check` must pass in CI).

## File placement rules

- Component directory name MUST equal the ArgoCD Application name.
- File-naming: `cnp-<component>.yaml`, `ccnp-<description>.yaml`.
- One component per directory: `<comp>/{application,kustomization,values}.yaml`.
- Repository-wide SOT belongs at the repo root or `docs/`, never under tool-namespaced directories like `.claude/`, `.cursor/`, `.vscode/`.

## Sensitive data

- No literal secrets, tokens, or credentials in any file (including
  `.example` variants). Pre-commit gitleaks blocks this; CI re-runs
  gitleaks as a backstop.
- No internal RFC1918 IPs in committed files; use placeholders
  (`<API-VIP>`, `<NODE-IP>`).
- No hardcoded user-home paths in committed artifacts — use `$HOME`
  for shell/JSON/YAML and `~` for tilde-expanding contexts only.

## Code of conduct

Be excellent to each other. Disagree with ideas, not people. The
maintainers reserve the right to lock issues or PRs and remove comments
that violate this norm.

## License

By contributing, you agree your work is licensed under the project's
Apache-2.0 [LICENSE](LICENSE) and that you have the right to submit it.
