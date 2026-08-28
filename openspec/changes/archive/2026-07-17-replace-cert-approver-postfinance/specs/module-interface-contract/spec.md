## MODIFIED Requirements

### Requirement: Grouped typed input surface

The module SHALL expose its inputs as typed variable groups: cluster
identity (`cluster_name`, `cluster_endpoint`); versions (`talos_version`
as the machine-config schema pin fixed at bootstrap,
`talos_install_version` as the installer pin defaulting to the schema
pin, `kubernetes_version`); topology (`nodes`, `images`,
`hardware_capabilities`); machine-config patches (all-nodes, per-role and
per-node lists); substrate delivery (the ArgoCD and Cilium toggles with
their chart-version, namespace, values-override and secret-material
knobs, plus a chart-repository knob for Cilium only — the ArgoCD chart
repository is hardcoded in `main.tf` — together with the always-on
cert-approver seed's three tuning knobs: `cert_approver_provider_regex`
(default `".*"`), `cert_approver_provider_ip_prefixes` (default
`["0.0.0.0/0", "::/0"]`, non-empty), and `cert_approver_replicas` (default
`1`); the seed itself has no disable toggle); cluster network (`pod_cidr`,
`service_cidr`, `dual_stack`, `allow_scheduling_on_controlplanes`); and
the cluster health timeout. Because `deploy_argocd` defaults to true and
a plan-time precondition requires `sops_age_key` to be a valid age
private key whenever ArgoCD is deployed, `sops_age_key` is de-facto
required under the default toggles.

#### Scenario: Optional groups fall back to documented defaults

- **WHEN** a caller supplies only the required inputs (identity,
  versions, nodes, images) together with either a valid `sops_age_key`
  or `deploy_argocd = false`
- **THEN** the plan succeeds with the documented defaults: any substrate
  toggle left unset defaults to enabled, the network CIDRs default to
  the Talos defaults, `talos_install_version` falls back to
  `talos_version`, and the health timeout defaults to `"10m"`

### Requirement: Seed and wiring audit outputs

The module SHALL expose secret-free audit outputs that bind the composed
patch lists to tests: the kubelet serving-cert rotation wiring per role
and the decoded rotation patch content, the cert-approver seed wiring,
namespace labels, RBAC approve scope and per-object recommended-label
gaps, the ArgoCD namespace labels, and a boolean asserting the
non-sensitive base patch list is a prefix of the final controlplane patch
list. For the cert-approver seed the module SHALL additionally expose,
parsed from the rendered manifest, `cert_approver_rbac_rules` (the decoded
ClusterRole rule set, for rule-set-closure assertions),
`cert_approver_pod_security_context` (the decoded container securityContext,
for the restricted-PSA guard), `cert_approver_container_args` and
`cert_approver_env` (the decoded arguments and `PROVIDER_*`/`BYPASS_DNS_RESOLUTION`
environment, for the config-injection and leader-election checks), and
`cert_approver_replicas` (the rendered replica count).

#### Scenario: Audit outputs stay secret-free

- **WHEN** the seed and wiring audit outputs are read
- **THEN** they expose booleans, label maps, decoded RBAC rules,
  securityContext, container args, environment and replica count only —
  never the seed patch lists that embed Secret material
