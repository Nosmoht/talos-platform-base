## MODIFIED Requirements

### Requirement: Opt-in emitted self-management Application for Day-2 delivery

The module SHALL, when `cilium_self_management = true` (guarded by the
`module-interface-contract` cross-variable validations), expose an
`argoproj.io/v1alpha1` `Application` manifest — via the
`cilium_self_management_app` output, never applied by the module — as the
Day-2 delivery path for a Cilium config change (including the observability
inputs) on an already-bootstrapped cluster, complementing the frozen
create-only bootstrap seed above and the pre-existing static
`kubernetes/bootstrap/cilium/values.yaml` reference file.

The emitted Application SHALL take one of two shapes, selected by
`cilium_self_management_values_source`:

**Single-source (values source unset, the default).**
`spec.source.helm.valuesObject` SHALL be the bounded, module-controlled merge
of the floor and computed-values layers only, and `cilium_values_override` SHALL
NOT reach it. Configuring or not configuring a values source SHALL NOT move this
document AT ONE BASE REVISION. It is not a promise across revisions: a floor or
computed-layer change moves it for every consumer on this arm, deliberately.
Such a change is consumer-visible on this arm and SHALL carry an `UPGRADING.md`
note and a deliberate golden refresh; its release class follows ADR-0029 —
row 12, MINOR with that note although this arm has no opt-out, and the higher
class only if row 9 applies.

**Multi-source (values source set).** `spec.sources` SHALL carry exactly two
entries: a `ref`-only source for the consumer's values repository (no `path`,
no `chart` — it generates no manifests and exists so `$values/<path>`
resolves at all), and the Cilium chart source whose
`helm.valueFiles` SHALL be the module-set layer FIRST and
`cilium_values_override` SECOND, with `helm.ignoreMissingValueFiles`
explicitly `false`. The ORDER of that list is the precedence mechanism: Helm
merges later files over earlier ones at arbitrary depth, which is why the
merge belongs to Helm and not to the module — the override is an opaque YAML
document and HCL has no generic recursive merge. The override entry SHALL be
absent when the override is empty. The module SHALL NOT place the override in
`valuesObject`: that slot is applied after every `valueFiles` entry, and it
is where the module re-asserts its own keys.

`helm.valuesObject` on the multi-source shape SHALL carry the joint keys of
`module-interface-contract`'s override joint-key guard — `kubeProxyReplacement`
always, plus `k8sServiceHost` and `k8sServicePort` when
`cilium_kube_proxy_replacement` is true — and nothing else. Those keys are
produced by the computed layer alone, never by the floor file, so on this
shape they live only in a file the consumer commits; any state in which that
file resolves empty would otherwise render a Cilium that does not replace
kube-proxy while Talos already carries `cluster.proxy.disabled`, leaving a
running cluster with no ClusterIP datapath and no cluster DNS that the
create-only seed cannot repair. Re-asserting them as the last layer SHALL NOT
constitute the module overwriting a consumer value, because the override is
forbidden to name them.

The module SHALL additionally expose the module-set layer as
`cilium_self_management_values`, a YAML document for the consumer to commit at
the values source's `values_path`, empty on the single-source shape. The
emitted Application SHALL carry a
`talos-platform-base.io/values-digest` annotation over that layer, matching a
digest recorded in the document's own header, so a stale committed values file
is detectable — the two artifacts are committed independently and ArgoCD
compares neither. The annotation SHALL be absent on the single-source shape,
which has no such file.

The Application SHALL carry `spec.project = var.cilium_self_management_project`
(default `"default"`, the base's sole permissive AppProject; a scoped
consumer-created project is recommended hardening and, on the multi-source
shape, MUST list both the values repository and the chart repository in
`sourceRepos`) and SHALL carry no `syncPolicy`, so the consumer controls sync
timing for the graceful-restart-gated DaemonSet roll that enabling Hubble
triggers.

#### Scenario: Emitted Application carries the module-set values only

- **WHEN** `cilium_self_management = true` and
  `cilium_self_management_values_source` is unset
- **THEN** the emitted Application carries `spec.source` (not `spec.sources`),
  its `valuesObject` equals the floor ⊕ computed-values merge, the manifest
  carries no `syncPolicy` and no values-digest annotation, and
  `cilium_self_management_values` is the empty string

#### Scenario: The consumer override reaches Day-2 as the last values layer

- **WHEN** `cilium_self_management = true`, `cilium_values_override` is
  non-empty, and `cilium_self_management_values_source` is set
- **THEN** the emitted Application carries `spec.sources` and no
  `spec.source`; `sources[0]` is the `ref` source named `values` at the
  configured repository and revision; and `sources[1].helm.valueFiles` is
  exactly the module-set layer's path followed by the override's path, so
  Helm applies the override last

#### Scenario: The joint keys survive a missing or stale values file

- **WHEN** the emitted Application is multi-source
- **THEN** `sources[1].helm.valuesObject` carries `kubeProxyReplacement` and,
  with the kube-proxy replacement on, `k8sServiceHost` and `k8sServicePort` —
  applied after both `valueFiles`, so the kube-proxy-replacement pairing with
  Talos' `cluster.proxy.disabled` holds even when the committed values file is
  absent or stale, and `ignoreMissingValueFiles` is `false` so a wrong path is
  a loud sync error rather than a silent render against chart defaults

#### Scenario: The override entry is absent when there is no override

- **WHEN** `cilium_self_management_values_source` is set and
  `cilium_values_override` is empty
- **THEN** `sources[1].helm.valueFiles` carries the module-set layer alone,
  never a `$values/` path to a file the consumer never wrote

#### Scenario: Emitted Application targets the default AppProject unless scoped

- **WHEN** `cilium_self_management_project` is left at its default
- **THEN** the emitted Application's `spec.project` is `"default"` — the
  base's only pre-existing AppProject — functional out-of-the-box, with a
  dedicated scoped project as documented, recommended hardening

#### Scenario: A values source on the permissive project warns

- **WHEN** `cilium_self_management_values_source` is set while
  `cilium_self_management_project` is still `"default"`
- **THEN** the plan warns, because that project's `sourceRepos: ['*']` accepts
  any repo the manifest names and the multi-source arm is the first shape whose
  manifest names a values repo of its own — so the state where an edit to one
  string decides where a privileged DaemonSet's Helm values come from is not the
  silent one

#### Scenario: The joint keys are a precedence the override file cannot beat

- **WHEN** the file committed at `override_path` names `kubeProxyReplacement`,
  `k8sServiceHost` or `k8sServicePort`
- **THEN** the emitted Application's `valuesObject` still decides those three,
  because it is applied after every `valueFiles` entry — the module's key
  rejection covers the `cilium_values_override` INPUT and cannot cover a file
  the module never reads, so the generated values document's own header SHALL
  disclose the precedence and name the typed inputs that set both halves
