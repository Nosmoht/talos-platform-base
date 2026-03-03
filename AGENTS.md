# Repository Guidelines

## Project Structure & Module Organization
- `kubernetes/base/infrastructure/`: base Helm values and namespace/kustomization manifests per infrastructure component.
- `kubernetes/overlays/homelab/`: environment-specific Argo CD Applications, project definitions, Gateway API resources, and app/infrastructure overlays.
- `kubernetes/bootstrap/argocd/`: bootstrap manifests applied before GitOps reconciliation.
- `talos/`: Talos machine config inputs (`nodes/`, `patches/`), generated outputs, and Talos lifecycle automation.
- `docs/`: operational runbooks, reviews, and hardware/kernel notes.

## Build, Test, and Development Commands
- `make argocd-install`: installs Argo CD and required SOPS key secret.
- `make argocd-bootstrap`: installs Argo CD, then applies root project/application.
- `make talos-gen-configs`: delegates to `talos/Makefile` to generate node configs.
- `make talos-apply-all`: applies generated Talos configs to all nodes.
- `make -C talos dry-run-all`: validates Talos config application without changing nodes.
- `make -C talos schematics`: creates Talos Image Factory schematic IDs.

Example flow:
```bash
make talos-gen-configs
make talos-apply-node-01
make argocd-bootstrap
```

## Coding Style & Naming Conventions
- Use YAML with 2-space indentation; keep keys and list nesting consistent with existing manifests.
- Prefer one component per directory (`.../component/{application.yaml,kustomization.yaml,values.yaml}`).
- Name commits and change scopes by subsystem (`argocd`, `dex`, `monitoring`, `cilium`, `talos`).
- Keep secrets in `*.sops.yaml`; do not commit decrypted secret material.

## Testing Guidelines
- There is no formal unit-test framework in this repo; validation is manifest and apply focused.
- Before opening a PR, run relevant dry-runs and reconcile checks:
  - `make -C talos dry-run-all`
  - `kubectl kustomize kubernetes/overlays/homelab` (or equivalent local render)
- For monitoring/network policy/dashboard changes, include evidence from runtime validation (e.g., Argo CD sync state or scrape success).

## Commit & Pull Request Guidelines
- Follow the observed Conventional Commit style: `type(scope): short imperative summary` (e.g., `fix(dex): remove hostedDomains to avoid hd claim failures`).
- Keep commits focused and logically grouped; avoid mixing Talos, bootstrap, and app changes without a clear reason.
- PRs should include:
  - what changed and why,
  - impacted paths/components,
  - rollout/verification steps,
  - linked issue (if applicable),
  - screenshots only for UI/visual dashboard changes.
