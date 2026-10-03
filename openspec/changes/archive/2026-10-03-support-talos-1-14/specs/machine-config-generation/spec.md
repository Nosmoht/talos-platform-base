## ADDED Requirements

### Requirement: Native document patches

For schema pins from 1.14 the module SHALL use native documents for its network, kubelet, node registration, install and manifest settings. It SHALL remove Flannel when Cilium is enabled and emit kube-proxy configuration only on control planes. Caller patches SHALL retain their order and contents; consumers MUST use compatible document forms. The per-node installer SHALL use the node's non-SecureBoot Factory URL before caller node overrides.

#### Scenario: A native controlplane enables Cilium and scheduling

- **WHEN** a native controlplane enables Cilium and scheduling
- **THEN** Flannel is absent, the module-controlled proxy setting is applied and only the control-plane taint is removed
