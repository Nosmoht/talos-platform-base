## ADDED Requirements

### Requirement: Cert-approver replica-separation audit outputs

For the cert-approver seed the module SHALL also expose, parsed from the
rendered manifest, `cert_approver_affinity` (the Deployment's decoded
pod-template affinity, `{}` when none renders) and
`cert_approver_pod_disruption_budgets` (every PodDisruptionBudget in the seed
as `api_version`, `name`, `namespace` and `spec`).

#### Scenario: Replica-separation outputs feed the seed guards

- **WHEN** the seed's tests read the two outputs
- **THEN** at the default replica count the affinity is `{}` and the list is
  empty, and at `cert_approver_replicas = 2` they carry the anti-affinity term
  and the one PodDisruptionBudget the cert-approver seed requires
