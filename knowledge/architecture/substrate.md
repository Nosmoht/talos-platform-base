---
type: architecture
title: Substrate Boundary
description: What talos-platform-base is and ships — the three-pillar substrate, the base/apps/consumer layer model, the tracked repo layout, and the fail-closed OCI artifact allowlist.
tags: [substrate, layer-model, oci-artifact, boundaries]
timestamp: 2026-07-15
sources:
  - .ci-oci-tarball-include.txt
  - .ci-oci-tarball-expected.txt
  - .ci-renderable-components.txt
  - Taskfile.yml
  - .github/workflows/oci-publish.yml
  - tofu/modules/talos-cluster/main.tf
  - tofu/modules/talos-cluster/manifests/cert-approver.yaml
  - kubernetes/base/infrastructure/argocd/kustomization.yaml
  - kubernetes/base/infrastructure/argocd/values.yaml
  - AGENTS.md
---

# Substrate Boundary

`talos-platform-base` is the cluster-agnostic **substrate** of the
Talos-on-Kubernetes deployment family: the floor every cluster needs, and
nothing else. It is not a runnable cluster — it carries no cluster identity,
no node IPs, and no secrets. Consumers pin a released version of this base
and layer their own identity on top (see
[first-consumer-cluster](../workflows/first-consumer-cluster.md)).

## Three co-equal pillars, plus one piece of glue

The substrate core is **Talos + Cilium + ArgoCD**, and the code treats all
three as constitutive:

- **Talos** — the `tofu/modules/talos-cluster` module (see
  [talos-cluster-module](../reference/talos-cluster-module.md)) is the sole
  cluster-lifecycle path: machine secrets, per-node composed Image-Factory
  installer, config apply, bootstrap, kubeconfig.
- **Cilium** — delivered by the same module as a controlplane
  `cluster.inlineManifests` seed (`deploy_cilium`, default `true`), which
  simultaneously disables the Talos default CNI (`cni: none`) and, with
  kube-proxy replacement, `proxy.disabled`.
- **ArgoCD** — the GitOps engine is substrate, not a Day-2 app. It is also
  delivered by the module as an inlineManifest seed (`deploy_argocd`,
  default `true`), so it comes up with the bootstrap — opt-out, never an
  opt-in add-on.

The only addition is **cert-approver** (`kubelet-serving-cert-approver`) —
Talos serving-cert glue, not a fourth pillar. The module enables kubelet
serving-cert rotation on all nodes (`serverTLSBootstrap: true`) and
unconditionally seeds a vendored static manifest
(`tofu/modules/talos-cluster/manifests/cert-approver.yaml`) that approves the
resulting `kubernetes.io/kubelet-serving` CSRs. Its RBAC `approve` verb is
signer-restricted to that one signer, and its namespace carries a
PSA-`restricted` floor. Without it the cluster still boots (client-kubelet
CSRs auto-approve), but metrics-server and `kubectl logs|exec|top` need the
approved serving certs. Decision:
[0013-kubelet-serving-cert-rotation](../decisions/0013-kubelet-serving-cert-rotation.md).

## The base / apps / consumer layer model

The layering is binary — a component is substrate or it is not:

- **`talos-platform-base` (this repo)** — the substrate: the three pillars,
  the cert-approver glue, and the validation pipeline around them.
- **`talos-platform-apps`** — the central catalog: every platform component
  that is *not* substrate lives there as independently versioned, signed OCI
  artifacts.
- **Consumer cluster repos** — compose: pin a base release for the substrate
  and reference exactly the catalog components they need. Identity (nodes,
  networks, versions) lives in the consumer's `cluster.yaml`
  ([cluster-yaml](../reference/cluster-yaml.md)).

Routing rule: if it is not substrate, it belongs in the apps catalog, never
in base. The substrate-only shape is the result of a deliberate ablation —
see [0004-substrate-only-base](../decisions/0004-substrate-only-base.md).

## Tracked repo layout

Enumerated via `git ls-files` (untracked local residue is not part of the
base — see the note below):

```text
.                            governance + policy docs (README, AGENTS.md,
                             ARCHITECTURE, SECURITY, UPGRADING, CHANGELOG, ...)
.github/workflows/           CI: gitops-validate, hard-constraints-check,
                             tofu-validate, oci-publish, release, lint gates
contracts/                   primitive-contract.md
knowledge/                   this OKF bundle (architecture, reference,
                             workflows, decisions, glossary, rules)
kubernetes/base/infrastructure/argocd/
                             the ONE base kustomize component (namespace +
                             committed _rendered/ manifests + values.yaml)
kubernetes/bootstrap/argocd/ root-project / root-application *.tmpl seeds
kubernetes/bootstrap/cilium/ reference values.yaml + extras.yaml (GatewayClass)
policies/conftest/           Rego policies for rendered manifests
schemas/                     cluster.schema.json, hardware-features.schema.json
scripts/                     validation / render / helper scripts
tofu/modules/talos-cluster/  the cluster-lifecycle module (+ helm values,
                             vendored cert-approver manifest, tests)
platform-hardware-features.yaml   Layer-C hardware-feature vocabulary (root)
cluster.yaml.example         declarative cluster-SoT template
Taskfile.yml                 the single task runner
```

**Only `argocd/` is a tracked component.** `git ls-files` shows exactly one
directory under `kubernetes/base/infrastructure/`, and the renderable-component
fixture `.ci-renderable-components.txt` contains the single line `argocd`. Any
other directory found there on a working copy is untracked local chart
residue, not shipped content. Post-ablation there is therefore no base
component-dependency graph left: ArgoCD is the only kustomize component, and
Cilium is not a kustomize component at all — it ships inside the tofu module.

The substrate floor is also dependency-self-contained: the steady-state
ArgoCD values disable the chart's `server.certificate` block (no cert-manager
coupling — the render must not reference a CRD/issuer the substrate does not
ship) and run `argocd-server` with `server.insecure: true`, plaintext at the
pod. A consumer that wants cert-manager-issued TLS re-enables
`server.certificate` in an overlay and provides the issuer from the apps
catalog — only then does a base-to-catalog edge exist.

## What ships in the OCI artifact

On every `v*` tag push, `.github/workflows/oci-publish.yml` packages a
tarball and pushes it to `ghcr.io/<owner>/talos-platform-base:<tag>`
(cosign-signed keyless, with SLSA build provenance and a CycloneDX SBOM
attestation — verification workflow:
[verify-release](../workflows/verify-release.md)).

Membership is **allowlist-driven and fail-closed**: only paths listed in
`.ci-oci-tarball-include.txt` are packaged, and the tarball listing is diffed
against the committed fixture `.ci-oci-tarball-expected.txt` — any divergence
fails the publish. The same check runs locally via
`task supply-chain:oci-allowlist`. The allowlist is the authoritative record
of what ships; prose "what ships" summaries elsewhere are non-normative.

The 15 shipped entries:

```text
kubernetes/bootstrap/cilium/extras.yaml
kubernetes/bootstrap/cilium/values.yaml
platform-hardware-features.yaml
schemas/hardware-features.schema.json
tofu/modules/talos-cluster/README.md
tofu/modules/talos-cluster/helm/argocd-values.yaml
tofu/modules/talos-cluster/helm/cilium-values.yaml
tofu/modules/talos-cluster/main.tf
tofu/modules/talos-cluster/manifests/cert-approver.yaml
tofu/modules/talos-cluster/outputs.tf
tofu/modules/talos-cluster/test/README.md
tofu/modules/talos-cluster/test/pki-reconcile-microtest.sh
tofu/modules/talos-cluster/test/run-adoption-proof.sh
tofu/modules/talos-cluster/variables.tf
tofu/modules/talos-cluster/versions.tf
```

That is: a talos-cluster module subset (four of its `.tf` files, the helm
value floors, the vendored cert-approver seed, the adoption/PKI proof
scripts), the Cilium Day-2 reference values + GatewayClass extra, and the
hardware-capability vocabulary (`platform-hardware-features.yaml` at the
repo root plus its schema under `schemas/`). Note the allowlist does NOT
ship `composition.tf` and `profiles.tf`, although `main.tf` requires locals
defined there — the tarball-vendored module tree alone does not
`tofu validate`; consumers currently need the git checkout at the pinned
tag for a runnable module (tracked as a maintainer follow-up). The
vocabulary's equivalence with the module's provisioning catalog is enforced
by a CI cross-reference gate, not read by the module at plan time
([capability-composition](capability-composition.md)).

### What stays git-only

Everything else is repo content, not artifact content — notably the CI
workflows, `policies/conftest/`, `scripts/`, the
`kubernetes/base/infrastructure/argocd/` component with its committed
`_rendered/` manifests ([manifest-pipeline](../reference/manifest-pipeline.md)),
the `kubernetes/bootstrap/argocd/*.tmpl` root seeds, `Taskfile.yml`
([tasks](../reference/tasks.md)), `schemas/cluster.schema.json`, and
`cluster.yaml.example`.

### What never ships anywhere

- **Secrets** — there is no `*.sops.yaml` in this repo, and the module's
  secret inputs (`sops_age_key`, `cilium_ipsec_key`) are variables the
  consumer supplies at apply time; `cluster.yaml` has no schema slot for
  secret material.
- **Cluster identity** — `cluster.yaml` is gitignored in the base; only the
  RFC5737-placeholder `cluster.yaml.example` is tracked, and it is excluded
  from the artifact.

## Boundary invariants

- One component directory per ArgoCD Application, named identically.
- One Application owns each namespace; `argocd` is the only chicken-and-egg
  exception
  ([0002-namespace-ownership-rendered-manifests](../decisions/0002-namespace-ownership-rendered-manifests.md)).
- Hard constraints (no SecureBoot installer, no `debugfs=off`, Gateway API
  only, EndpointSlices only) are enforced in module code and by the
  `hard-constraints-check` CI gate — see
  [0011-substrate-hard-constraints](../decisions/0011-substrate-hard-constraints.md).
- Day-zero delivery mechanics for all three pillars:
  [day-zero-bootstrap](day-zero-bootstrap.md).
