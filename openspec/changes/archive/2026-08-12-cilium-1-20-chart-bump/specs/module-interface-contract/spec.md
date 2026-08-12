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
`1`); the seed itself has no disable toggle; and the Cilium observability +
self-management group: `cilium_agent_metrics`, `cilium_operator_metrics`
(independent Prometheus toggles, default `false`), `cilium_hubble_enabled`
(default `false`; forces the observer-API server TLS off in the computed
values — metrics-only scope), `cilium_hubble_metrics` (a string list,
default `[]`), `cilium_self_management` (default `false`, guarded by the
cross-variable validations below), and `cilium_self_management_project`
(default `"default"`)); cluster network (`pod_cidr`, `service_cidr`,
`dual_stack`, `allow_scheduling_on_controlplanes`); and the cluster health
timeout. Because `deploy_argocd` defaults to true and a plan-time
precondition requires `sops_age_key` to be a valid age private key
whenever ArgoCD is deployed, `sops_age_key` is de-facto required under the
default toggles.

`cilium_gateway_api_crds_url` carries a cross-component version coupling the
module cannot validate at plan time: Cilium's Gateway API support requires a
minimum Gateway API CRD bundle version that changes across Cilium minors, and
the input is an opaque URL that Talos applies verbatim. Its documentation
SHALL therefore state the Gateway-API CRD floor required by the Cilium chart
version currently pinned by `cilium_chart_version`, together with the channel
(standard vs experimental) that satisfies the platform's Gateway-API-only
Hard Constraint — so a `cilium_chart_version` bump cannot leave the documented
CRD floor silently stale.

#### Scenario: Optional groups fall back to documented defaults

- **WHEN** a caller supplies only the required inputs (identity,
  versions, nodes, images) together with either a valid `sops_age_key`
  or `deploy_argocd = false`
- **THEN** the plan succeeds with the documented defaults: any substrate
  toggle left unset defaults to enabled, the network CIDRs default to
  the Talos defaults, `talos_install_version` falls back to
  `talos_version`, the health timeout defaults to `"10m"`, and the
  Cilium observability + self-management group defaults to all-off /
  empty

#### Scenario: Gateway API CRD floor tracks the pinned Cilium chart

- **WHEN** the `cilium_gateway_api_crds_url` input documentation is read at
  any pinned `cilium_chart_version`
- **THEN** it names the minimum Gateway API bundle version that pinned Cilium
  version requires, and states which channel to seed — including when the
  experimental channel is required instead of standard
