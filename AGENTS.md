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

## Codex CLI Operating Rules (Important)
- Treat `README.md` and `CLAUDE.md` hard constraints as authoritative for all edits.
- Never `kubectl apply` Argo CD-managed resources for rollout; commit to git and let Argo CD reconcile.
- The only normal direct-apply exception is bootstrap content under `kubernetes/bootstrap/`.
- Do not introduce Kubernetes `Ingress`; use Gateway API resources.
- Do not introduce deprecated `Endpoints`; use `EndpointSlice`.
- Keep secrets encrypted in `*.sops.yaml`; never add plaintext secret material to git.
- For Talos operations, use explicit node endpoint flags (`talosctl -n <node-ip> -e <node-ip>`) when running commands manually.
- Do not use `metal-installer-secureboot` or add `debugfs=off` boot args in Talos changes.
- Keep one taint policy on GPU node `node-gpu-01`: `nvidia.com/gpu=present:NoSchedule`; avoid broad tolerations beyond documented patterns.

## Validation Checklist For Codex Changes
- For overlay/root changes, run:
  - `kubectl kustomize kubernetes/overlays/homelab`
  - `kubectl apply -k kubernetes/overlays/homelab --dry-run=client`
- For Talos config changes, run:
  - `make talos-gen-configs`
  - `make -C talos dry-run-all` (or affected node dry-run target)
- If editing kustomizations that use KSOPS generators, validate with plugin-enabled kustomize (`--enable-alpha-plugins --enable-exec`) where required.
- Include runtime verification evidence for network policy/monitoring changes (Argo CD sync status, scrape success, policy-drop checks).

## Cilium Bootstrap/Talos Nuance
- `kubernetes/bootstrap/cilium/cilium.yaml` is tied to Talos `extraManifests`; avoid ad-hoc `kubectl apply` drift fixes.
- Reconcile Cilium bootstrap changes via Talos workflow (`make talos-upgrade-k8s`) so control plane `extraManifests` stay consistent.
- If this file contains generated TLS artifacts (for example Hubble cert secrets), track expiry and rotate before expiration as part of planned maintenance.
