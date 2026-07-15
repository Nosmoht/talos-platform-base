---
sources:
  primary:
    - tofu/modules/talos-cluster/manifests/cert-approver.yaml
  secondary:
    - tofu/modules/talos-cluster/main.tf
references:
  - knowledge/decisions/0013-kubelet-serving-cert-rotation.md
---

# cert-approver-seed

## Purpose

The kubelet-serving-cert-approver is delivered unconditionally as a
controlplane Talos `cluster.inlineManifests` seed: it approves the
`kubernetes.io/kubelet-serving` CSRs that the module's default-on kubelet
serving-cert rotation triggers. The cluster boots without it; metrics-server
and `kubectl logs|exec|top` need the approved serving certificates.

## Requirements

### Requirement: Unconditional controlplane inlineManifest seed

The module SHALL always bake the cert-approver into the controlplane machine
configuration as two `cluster.inlineManifests` entries — the
`kubelet-serving-cert-approver` Namespace first, then the vendored manifest
(ServiceAccount, ClusterRoles, bindings, Service, Deployment) — with no
module variable to disable it.

#### Scenario: Seed present regardless of substrate toggles

- **WHEN** the module plans with any combination of `deploy_cilium` and
  `deploy_argocd` values
- **THEN** the controlplane config patches include the
  `kubelet-serving-cert-approver-namespace` and
  `kubelet-serving-cert-approver` inlineManifest entries in that order

### Requirement: Pairs with default-on kubelet serving-cert rotation

The module SHALL enable kubelet serving-cert rotation on all nodes via an
overridable machine-config patch setting
`machine.kubelet.extraConfig.serverTLSBootstrap: true` on both the
controlplane and worker patch lists, placed before caller `config_patches`
so a consumer can opt out; the seeded approver then approves the resulting
`kubernetes.io/kubelet-serving` CSRs from all nodes.

#### Scenario: Rotation patch applied to both node roles

- **WHEN** the module renders machine configurations
- **THEN** both the controlplane and worker patch lists contain
  `serverTLSBootstrap: true` under `machine.kubelet.extraConfig`, ordered
  before caller-supplied patches

### Requirement: Signer-restricted approval RBAC

The vendored manifest SHALL scope the approver's `approve` permission on
`signers` to the resource name `kubernetes.io/kubelet-serving` only, so the
ServiceAccount cannot approve CSRs for any other signer.

#### Scenario: Approve verb bound to one signer

- **WHEN** the vendored ClusterRole granting `approve` is inspected
- **THEN** its `signers` rule lists exactly
  `kubernetes.io/kubelet-serving` under `resourceNames`

### Requirement: Vendored, digest-pinned static manifest

The seed SHALL use the vendored-static-manifest pattern: the pinned upstream
manifest is committed at
`tofu/modules/talos-cluster/manifests/cert-approver.yaml` and read via
`file()`, with a header recording the upstream source URL, tag, upstream
file SHA-256, and the applied modifications; the container image is
digest-pinned with `imagePullPolicy: IfNotPresent`.

#### Scenario: Image immutability without registry round-trips

- **WHEN** the Deployment in the vendored manifest is inspected
- **THEN** its container image reference carries an `@sha256:` digest and
  `imagePullPolicy: IfNotPresent`

#### Scenario: Provenance recorded for re-vendoring

- **WHEN** the vendored file's header is read
- **THEN** it names the upstream repository, the pinned tag, the upstream
  file's SHA-256 checksum, and the list of local modifications

### Requirement: Restricted namespace floor and recommended labels

The module SHALL seed the `kubelet-serving-cert-approver` Namespace with
pod-security labels at `restricted` (enforce, audit, and warn) plus the
recommended label set, and the vendored manifest SHALL carry the
recommended labels on every object and on the pod template (normative:
AGENTS.md §Hard Constraints — Kubernetes recommended labels on all
resources); the Deployment's pod satisfies the restricted profile
(non-root, all capabilities dropped, read-only root filesystem, runtime
default seccomp).

#### Scenario: Namespace enforces restricted PSA

- **WHEN** the seeded Namespace manifest is inspected
- **THEN** it carries `pod-security.kubernetes.io/enforce: restricted` and
  the six `app.kubernetes.io/*` recommended labels with
  `app.kubernetes.io/managed-by: opentofu`

#### Scenario: Workload passes the restricted profile

- **WHEN** the Deployment's pod spec is inspected
- **THEN** it sets `runAsNonRoot: true`, drops all capabilities, uses a
  read-only root filesystem, and sets a `RuntimeDefault` seccomp profile
