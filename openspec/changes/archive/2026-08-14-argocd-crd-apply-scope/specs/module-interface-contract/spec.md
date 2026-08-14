## MODIFIED Requirements

### Requirement: Seed and wiring audit outputs

The module SHALL expose secret-free audit outputs that bind the composed
patch lists to tests: the kubelet serving-cert rotation wiring per role
and the decoded rotation patch content, the cert-approver seed wiring,
namespace labels, RBAC approve scope and per-object recommended-label
gaps, the ArgoCD namespace labels, the distinct Kubernetes kinds in the
manifest the module applies after the health gate
(`argocd_day0_apply_kinds`, `[]` when `deploy_argocd = false`), and a
boolean asserting the non-sensitive base patch list is a prefix of the
final controlplane patch list. For the cert-approver seed the module SHALL
additionally expose, parsed from the rendered manifest,
`cert_approver_rbac_rules` (the decoded ClusterRole rule set, for
rule-set-closure assertions), `cert_approver_pod_security_context` (the
decoded container securityContext, for the restricted-PSA guard),
`cert_approver_container_args` and `cert_approver_env` (the decoded
arguments and `PROVIDER_*`/`BYPASS_DNS_RESOLUTION` environment, for the
config-injection and leader-election checks), and `cert_approver_replicas`
(the rendered replica count). For the Cilium seed the module SHALL
additionally expose `cilium_seed_observability_markers` — booleans
(`agent_metrics`, `operator_metrics`, `hubble`, `hubble_metrics`) decoded
from the frozen seed render's `cilium-config` ConfigMap, `{}` when
`deploy_cilium = false` — for tests binding the seed render to the
observability inputs without re-rendering the chart.

#### Scenario: Audit outputs stay secret-free

- **WHEN** the seed and wiring audit outputs are read
- **THEN** they expose booleans, label maps, decoded RBAC rules,
  securityContext, container args, environment, replica count and kind
  names only — never the seed patch lists that embed Secret material

#### Scenario: Day-0 apply kinds reflect the CRD-only projection

- **WHEN** `deploy_argocd = true`
- **THEN** `argocd_day0_apply_kinds` is exactly
  `["CustomResourceDefinition"]`, and it is `[]` when `deploy_argocd` is
  false

#### Scenario: Cilium observability markers reflect the seed render

- **WHEN** `deploy_cilium = true` and the Cilium observability inputs are
  set
- **THEN** `cilium_seed_observability_markers` decodes booleans from the
  frozen seed's `cilium-config` ConfigMap matching those inputs, without a
  second chart render
