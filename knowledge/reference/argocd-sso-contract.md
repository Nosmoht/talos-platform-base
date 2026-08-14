---
type: reference
title: ArgoCD SSO Wiring Contract
description: What a consumer cluster must supply to attach any external OIDC identity provider to the substrate's identity-free ArgoCD, and the mechanism that carries it across the base/consumer repo boundary.
tags: [argocd, sso, oidc, rbac, consumer-contract]
timestamp: 2026-08-14
sources:
  - kubernetes/substrate/argocd/values.yaml
  - kubernetes/substrate/argocd/_rendered/manifests.yaml
  - kubernetes/examples/argocd-consumer-sso/kustomization.yaml
  - scripts/check-argocd-substrate-invariants.sh
---

# ArgoCD SSO Wiring Contract

The substrate ships ArgoCD with **no identity**: no bundled Dex, no OIDC
connector, no base URL, and no RBAC policy naming any principal. That is a
deliberate floor property — an access policy names principals of a specific
organisation, which a cluster-agnostic base cannot know — and it is gated in CI
(invariants I1–I4, see the component README `kubernetes/substrate/argocd/README.md`).

The cost of that property is a contract: the cluster does not authenticate
anyone until the consumer supplies the missing half. This page is that contract.

## What the base ships, and what it leaves to you

| Key | Shipped state | Owner |
|---|---|---|
| `argocd-cm` `url` | absent | consumer |
| `argocd-cm` `oidc.config` | absent | consumer |
| `argocd-cm` `admin.enabled` | `"true"` | consumer cuts it over |
| `argocd-rbac-cm` `policy.csv` | `""` (present, empty) | consumer |
| `argocd-rbac-cm` `scopes` | `'[groups]'` (chart default) | consumer, **if** the IdP needs another claim |
| `argocd-rbac-cm` `policy.default` | `''` | base pins; consumer may widen |

Two of these are present-but-empty rather than absent, because the chart's
`argocd-rbac-cm` template emits both keys unconditionally. Reading the rendered
manifest as "the base ships a policy" misreads an empty string for a value.

Until the contract is fulfilled the local `admin` account is the only working
access path. ArgoCD documents it as an unrestricted superuser, so an empty
policy is not a locked-down cluster — it is a cluster with exactly one, fully
privileged, shared credential.

## The mechanism: a Kustomize remote base

The consumer's Application is **single-source over their own repo**. The base
enters as a Kustomize *remote base*: a git URL in `resources:`, which the
repo-server fetches at build time using the Application's own credentials.

```yaml
# consumer-repo: kubernetes/overlays/<cluster>/argocd/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - github.com/<owner>/talos-platform-base//kubernetes/substrate/argocd?ref=<tag>

patches:
  - path: argocd-cm.yaml
  - path: argocd-rbac-cm.yaml
```

**Why not a Multi-Source Application.** ArgoCD resolves the `$ref` source
reference only inside `helm.valueFiles` and `helm.fileParameters`. Kustomize
cannot reference a sibling source in a Multi-Source Application — that is an
open upstream enhancement request, not a configuration mistake. A consumer who
tries `$base/...` from a `kustomization.yaml` gets a build error, so the
remote-base form is the mechanism, not one option among two.

**Pin the ref to a tag.** ArgoCD's own security guidance notes that a writable
trusted repository can read out-of-tree files on the repo-server, and remote
bases are fetched over the network at build time. A floating `ref=main` makes
every base commit a live input to your cluster's reconciliation. Pin the tag you
vendored, bump it deliberately.

## Patching the two ConfigMaps

A strategic-merge patch merges into `.data`, so a patch naming only the keys you
own leaves the shipped ones intact:

```yaml
# argocd-cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  url: https://argocd.<your-domain>
  oidc.config: |
    name: <IdP display name>
    issuer: https://<issuer-host>/<realm-or-tenant>
    clientID: <client-id>
    clientSecret: $argocd-oidc:clientSecret
    requestedScopes: ["openid", "profile", "email", "groups"]
```

A **JSON6902** patch, or a strategic-merge patch carrying `$patch: replace`,
does *not* merge — it replaces the whole `.data` map, silently dropping every
key the base ships (`kustomize.buildOptions`, `resource.exclusions`, the
compare options). Use strategic merge unless you specifically intend a
replacement, and assert the merged key set is a superset of the shipped one.

`url` is required as soon as SSO is configured: ArgoCD derives the OIDC redirect
URI from it. This is why the base ships no placeholder — a wrong `url` does not
fail in the cluster, it fails at the identity provider on a human's first login,
which is a much worse place to discover it.

## The client secret

Create the Secret **outside** the shipped `argocd-secret` and reference it with
the `$<secret-name>:<key>` indirection:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: argocd-oidc
  namespace: argocd
  labels:
    app.kubernetes.io/part-of: argocd
stringData:
  clientSecret: <supplied out-of-band, e.g. via SOPS>
```

The label is not decorative — it is how ArgoCD decides a Secret is readable for
value indirection.

**Do not patch `argocd-secret` itself.** `argocd-server` writes `server.secretkey`
into it at runtime; a declarative overlay that owns that object fights the server
for it.

**Trust boundary, stated plainly.** `app.kubernetes.io/part-of: argocd` is the
only scoping control on this mechanism, and the shipped `argocd-secret` already
carries it. Anyone who can create Secrets in the `argocd` namespace can therefore
supply values that ArgoCD configuration references — that permission is
equivalent to ArgoCD configuration authority. The base's own `root-bootstrap`
AppProject is already narrow (its `namespaceResourceWhitelist` admits only
`AppProject` and `Application`), so this warning is about **consumer-defined**
projects and consumer-side RBAC, not about the shipped one.

## PKCE, if you would rather not hold a secret

PKCE removes the client secret. It does not remove the need for care:

- the IdP client is **public** — it holds no secret, so the redirect URI is the
  only thing binding the flow to your cluster;
- register `<url>/pkce/verify` with **exact** matching. A wildcard redirect URI
  on a public client is an open redirector into your ArgoCD;
- `cliClientID` must be a **dedicated** client. ArgoCD's default
  `allowedAudiences` folds `clientID` and `cliClientID` together, so any client
  id placed there becomes a second, fully privileged trust anchor — a token
  minted for it is accepted for the web UI too.

## RBAC and the subject-namespace hazard

```yaml
# argocd-rbac-cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
    g, <group-id-from-your-idp>, role:admin
```

Casbin subjects live in **one flat, unprefixed namespace**: usernames and group
values are not distinguished. `g, alice, role:admin` matches a local user named
`alice` *and* anyone whose `groups` claim contains the value `alice`. ArgoCD
documents the local-user collision case explicitly.

Binding against **immutable group IDs** rather than display names avoids both
the collision and the silent re-grant when someone renames a group upstream.
Label this as it is: sound hygiene, not an ArgoCD-documented recommendation.

**`scopes` selects which claim the subjects are read from.** The chart default is
`'[groups]'`. If your subjects are usernames, you must set the matching claim
(for example `'[preferred_username]'`) in the same commit as the policy —
carrying `policy.csv` over without `scopes` is the documented lockout path,
because the policy is then matched against a claim it was never written for.

**Group claims that are not in the ID token.** Some providers omit `groups` from
the ID token. `requestedIDTokenClaims` asks for them explicitly;
`enableUserInfoGroups` with `userInfoPath` fetches them from the UserInfo
endpoint instead. `userInfoCacheExpiration` is then a **revocation-latency
bound**, not a performance knob: it is how long a removed user keeps their
groups.

## Cut-over: the predicate is authorization, not login

`policy.default: ''` means an unmatched principal authenticates **successfully**
and can do nothing. So "SSO login works" is not evidence that the policy works,
and disabling `admin` on that evidence locks everyone out of a cluster whose
GitOps engine still reconciles.

The gate is an authorization check for a real SSO principal:

```bash
argocd account can-i update applications '*/*'
# expect: yes
```

Only once that returns `yes`:

```yaml
# argocd-cm.yaml
data:
  admin.enabled: "false"
```

**Recovery.** Correct the overlay in git and let self-heal reconcile — that is
the supported path. A `kubectl patch` on `argocd-cm` is a deliberate break-glass
exception to the "never `kubectl apply` ArgoCD-managed resources" constraint, and
ArgoCD will revert it on the next sync, so use it to regain access and then fix
git. Re-enabling the local account additionally requires a bcrypt `admin.password`
in `argocd-secret`: `admin.enabled: "true"` alone does not restore a password
that was cleared.

**One caveat on the break-glass credential.** The substrate ships
`server.insecure: true` — argocd-server serves plaintext at the pod and the
consumer terminates TLS at their gateway. The admin credential therefore crosses
the gateway→pod hop in cleartext. Rotate it promptly, and treat a long
admin-enabled window as the risk it is.

## Worked example

`kubernetes/examples/argocd-consumer-sso/` is a complete, buildable
overlay of everything above. It is asserted in CI by
`scripts/check-argocd-substrate-invariants.sh`: the build is compared against a
control build without the patches, so the assertions prove the patches *do*
something rather than passing vacuously. It uses a local `resources:` path so
the gate runs offline — the remote-base form above is the one to copy.

## See also

- [Manifest Pipeline](manifest-pipeline.md) — how the component is rendered
- [First Consumer Cluster](../workflows/first-consumer-cluster.md) — where this fits in the bring-up
- [ADR: ArgoCD substrate relocation](../decisions/0024-argocd-substrate-relocation.md)
- [ADR: the Day-0 apply delivers CRDs and nothing else](../decisions/0025-argocd-crd-apply-scope.md)
