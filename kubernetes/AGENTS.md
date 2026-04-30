# Kubernetes Scope — Codex CLI Context
# Root scope: @../AGENTS.md (inherits §Hard Constraints, §MCP servers)

This file is loaded by Codex CLI when editing files under `kubernetes/`. It
provides path-scoped context approximating Claude Code's `paths:`
auto-loading.

## Directory Map

| Path | Purpose |
|------|---------|
| `kubernetes/base/infrastructure/<app>/` | Shared Helm values and base Kustomize manifests (cluster-agnostic) |
| `kubernetes/bootstrap/argocd/` | Parameterized templates (`*.tmpl`) — do NOT hand-edit `_out/`; managed by Makefile targets |
| `kubernetes/bootstrap/cilium/` | Cilium Helm values + `extras.yaml`; `cilium.yaml` is rendered consumer-side |

Component directory names must match their ArgoCD Application name exactly
(e.g. `kube-prometheus-stack/`, not `monitoring/`).

## Domain Rules

Domain rules with `paths:` frontmatter live in the `kube-agent-harness`
plugin. When the plugin is installed in a consumer repo (or its rules are
vendored), Claude Code auto-loads them at edit time. See the harness repo for
the rule catalogue.

## Hard Constraints (inline summary — canonical in `../AGENTS.md §Hard Constraints`)

- **No `kind: Ingress`** — use `HTTPRoute`/`TLSRoute` (Gateway API)
- **No `kind: Endpoints`** — use `EndpointSlice`
- **No `kubectl apply` on ArgoCD-managed resources** — commit to git, push, let ArgoCD sync
- **Labels**: all resources must carry `app.kubernetes.io/{name,instance,component,part-of,managed-by}`
- **CNP naming**: `cnp-<component>.yaml` (namespace-scoped), `ccnp-<description>.yaml` (clusterwide)
- **PNI first**: new consumer-to-platform connectivity must use PNI labels before ad-hoc CNPs
  - Required: `platform.io/network-interface-version: v1` + `platform.io/network-profile: restricted|managed|privileged`
