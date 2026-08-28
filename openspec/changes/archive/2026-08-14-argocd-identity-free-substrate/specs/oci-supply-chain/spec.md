## MODIFIED Requirements

### Requirement: Steady-state ArgoCD consumables ship in the payload

Per ADR-0024 (`knowledge/decisions/0024-argocd-substrate-relocation.md`), the
steady-state ArgoCD component's consumable files SHALL be in the payload:
`kubernetes/substrate/argocd/namespace.yaml`,
`kubernetes/substrate/argocd/_rendered/manifests.yaml`,
`kubernetes/substrate/argocd/_rendered/crds.yaml`, and
`kubernetes/substrate/argocd/kustomization.yaml` appear in
`.ci-oci-tarball-include.txt`.

`kustomization.yaml` is a consumable, not an authoring input: it is what makes
the other three a buildable unit, and without it the component's own
"consumable as a single kustomization" requirement holds in the repository only.
The remaining authoring inputs (`values.yaml`, `chart.lock.yaml`,
`_rendered-overlay/`) stay outside the payload — consumers receive the render
and the means to build it, not the render pipeline.

#### Scenario: Consumer can source the steady-state render from the artifact

- **WHEN** the published tarball's contents are listed
- **THEN** `kubernetes/substrate/argocd/namespace.yaml`,
  `kubernetes/substrate/argocd/_rendered/manifests.yaml`,
  `kubernetes/substrate/argocd/_rendered/crds.yaml` and
  `kubernetes/substrate/argocd/kustomization.yaml` are present, and no other
  `kubernetes/substrate/` path is

#### Scenario: A renderable component missing its kustomization fails the gate

- **WHEN** a component listed in `.ci-renderable-components.txt` has no
  `kustomization.yaml` entry in `.ci-oci-tarball-include.txt`
- **THEN** `scripts/check-substrate-consumability.sh` fails, naming the
  component
