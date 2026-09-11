## ADDED Requirements

### Requirement: Component NetworkPolicies in the seed

The slim Day-0 seed SHALL carry the same per-component NetworkPolicy set and
selector/ingress posture as the steady-state render, so a freshly bootstrapped
cluster is policed from the inlineManifest apply onward rather than from Argo
CD's first self-management sync. The seed values SHALL NOT disable the chart's
NetworkPolicy creation.

#### Scenario: The seed render carries the component policies

- **WHEN** the seed render is inspected
- **THEN** it contains the same five `networking.k8s.io/v1` NetworkPolicy
  documents and exact component-selector/caller/port posture the steady-state
  render carries, and it stays within the Talos inlineManifest size budget
