# Security Policy

## Reporting a vulnerability

**Do not open a public GitHub issue for security reports.**

Email: `thomas.krahn.tk@gmail.com` with subject prefix
`[talos-platform-base][security]`.

Include:

- The repository tag (or commit SHA) affected.
- The component or path under suspicion (e.g. a specific PNI Kyverno
  policy, a Talos patch, a Helm value default).
- Reproduction steps and expected vs observed behaviour.
- Whether you are willing to be credited in the eventual fix commit.

### Response SLA

- **Acknowledgement**: within 5 business days of receipt.
- **Initial triage**: within 10 business days.
- **Fix or mitigation timeline**: communicated after triage; depends on
  severity (CVSS-style). The base maintains no formal CVD program but
  follows responsible-disclosure norms.

## Supported versions

Only the most recent **MINOR** tag receives security backports. Older
MINORs are unsupported once a successor MINOR is published. Patch
upgrades within a MINOR are non-breaking; consumers should adopt them
promptly.

| Tag stream | Status |
|---|---|
| `v0.1.x` (current) | supported |
| pre-`v0.1.0` | unsupported — historical only |

## Supply chain

Every OCI artifact pushed to
`ghcr.io/<owner>/talos-platform-base:<tag>` is:

1. **Signed by cosign with keyless GitHub OIDC** — no long-lived signing
   keys, no key rotation. Identity = the GitHub Actions workflow that
   built it.
2. **Accompanied by SLSA build provenance**
   (`actions/attest-build-provenance@v1`) — proves the artifact was
   built by this workflow, in this repository, at this commit SHA.
3. **Pushed under an immutable tag** (GHCR's tag-immutability policy).

Consumers MUST verify both signature and provenance before vendoring.
See [`docs/oci-artifact-verification.md`](docs/oci-artifact-verification.md)
for the verification recipe (cosign + `cosign verify-attestation`).

The verification gate gives downstream consumers a cryptographic chain
back to this repository's commit at the time of release.

## Threat model summary

The base ships:

- Helm values + namespace declarations.
- ArgoCD bootstrap templates (parameterized; rendered with envsubst).
- Talos machine-config patches.
- Kyverno ClusterPolicies + conftest Rego.
- 16 Cilium CCNPs (capability-selector form).

It does NOT ship secrets, IPs, FQDNs, OIDC issuers, or cluster
credentials.

### In scope for a security report

| Threat | Surface |
|---|---|
| **Reserved-label forgery** — tenant manifest claims `provide.<cap>` or `capability-provider.<cap>` it should not have | PNI Kyverno policies (`pni-reserved-labels-enforce`, `pni-reserved-annotations-enforce`) |
| **Cross-tenant L4 reachability** — namespace mis-declares `consume.<cap>` (e.g. without instance suffix on instanced cap) and gains L4 reach across tenants | PNI registry + audit-mode advisory; CCNP `endpointSelector` |
| **Capability-discovery forgery** — Service-level annotation forged to shadow real producers | `pni-reserved-annotations-enforce` |
| **Secret leak in committed file** | `.github/workflows/gitops-validate.yml` `secret-scan` job (gitleaks); pre-commit gitleaks hook |
| **Talos boot-loop trigger** in a patch (`debugfs=off`, `secureboot` installer) | AGENTS.md §Hard Constraints + `hard-constraints-check.yml` |
| **Forbidden Kubernetes kind** (`Ingress`, `Endpoints`) | `hard-constraints-check.yml` |
| **OCI artifact tampering** in transit or at rest | cosign + SLSA (see above) |

### Out of scope

| Out-of-scope concern | Owner |
|---|---|
| Application-layer authentication (Vault tokens, Postgres roles, OIDC scopes, Kafka ACLs) | application repo |
| Consumer-cluster identity, secrets, SOPS keys, OIDC issuer config | consumer cluster repo |
| Per-instance L4 enforcement for tools the base does not deploy | consumer cluster repo's overlay (see ADR §"Per-instance enforcement is consumer-overlay responsibility") |
| Live cluster RBAC misconfiguration | cluster operator |
| SPIFFE / identity-aware policy | deferred (see ADR §"Network-layer isolation scope") |

## Hardening notes

If you operate a consumer cluster against this base:

1. **Pin and verify** the OCI tag before each vendoring (see OCI-verification doc).
2. **Run `scripts/capability-deprecation-scan.sh`** in your CI to catch
   sunset breakage before the next OCI tag flip.
3. **Watch `kubectl get policyreport -A`** for `pni-instanced-suffix-required-audit`
   advisories — they signal vocabulary smells before a multi-tenant L4 gap
   becomes exploitable.
4. **Do not relax the namespace-anchored producer rule**. If a producer
   "needs" to live in a system namespace, relocate it.

## References

- [`docs/oci-artifact-verification.md`](docs/oci-artifact-verification.md)
- [`docs/capability-architecture.md`](docs/capability-architecture.md) §"Enforcement summary"
- [`AGENTS.md`](AGENTS.md) §"Hard Constraints" + §"Tool-Agnostic Safety Invariants"
- [`docs/adr-capability-producer-consumer-symmetry.md`](docs/adr-capability-producer-consumer-symmetry.md)
