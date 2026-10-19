## MODIFIED Requirements

### Requirement: Generation-pass patch order

The module SHALL compose each role's generation-pass patch list in this
order: the overridable base cluster patch (pod/service subnets,
controlplane scheduling) and the overridable kubelet rotation patch first,
then all-nodes caller patches (`config_patches`), then the role-specific
caller patches, and only after all caller patches the authoritative CNI
patch; the controlplane list additionally appends its seed patches.

#### Scenario: Caller patch overrides the base cluster patch

- **WHEN** a caller config patch sets a value also set by the base
  cluster patch
- **THEN** the caller value takes effect, because the base patches are
  placed first and later patches win

#### Scenario: Caller patch cannot resurrect the default CNI

- **WHEN** `deploy_cilium` is true and a caller patch carries a
  `cluster.network.cni` stanza
- **THEN** the module's CNI patch (`cni: none`, plus `proxy.disabled`
  when kube-proxy replacement is enabled), placed after all caller
  patches, takes effect

#### Scenario: Controlplane list appends the seed patches last

- **WHEN** the controlplane generation-pass patch list is composed
- **THEN** it additionally appends the opt-in Gateway API CRDs patch and
  the cert-approver seed patch, in that listed order
- **AND** last, the ArgoCD and Cilium inline-manifest seed patches
