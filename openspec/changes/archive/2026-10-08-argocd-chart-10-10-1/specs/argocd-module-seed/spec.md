## MODIFIED Requirements

### Requirement: Seeded namespace labels and PSA floor

The module SHALL seed the `argocd` namespace with the six recommended
labels (`app.kubernetes.io/managed-by: opentofu`, version set to the chart
version) and a pod-security floor of `enforce: baseline` with `audit` and
`warn` at `restricted` (label set normative: AGENTS.md §Hard Constraints —
Kubernetes recommended labels on all resources), matching the PSA floor the
steady-state component asserts so ownership transfer carries no PSA change.

The namespace manifest is NOT part of the frozen seed render: its
`app.kubernetes.io/version` label follows `argocd_chart_version` on every plan,
so moving that input changes every controlplane's machine configuration while
the frozen render stays unchanged. Talos' inline-manifest controller creates
missing resources only, so the changed label does not reach a running
cluster's namespace.

#### Scenario: Namespace never delivered unlabeled

- **WHEN** the seeded namespace manifest is inspected
- **THEN** it carries the six `app.kubernetes.io/*` labels and the
  `baseline`-enforce / `restricted`-audit-and-warn pod-security labels

#### Scenario: A chart-version change moves the namespace label

- **WHEN** `argocd_chart_version` changes on an already-bootstrapped module state
- **THEN** the seeded namespace manifest's `app.kubernetes.io/version` label
  carries the new value and the controlplane machine configuration changes,
  while `terraform_data.argocd_render`'s frozen output does not
