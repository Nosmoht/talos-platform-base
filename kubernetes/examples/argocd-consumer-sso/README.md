# Example: attaching an external OIDC provider

A complete, buildable overlay showing what a consumer supplies to turn the
substrate's **identity-free** ArgoCD into one that authenticates and authorizes
real people. The prose contract — mechanism, trust boundaries, PKCE caveats,
cut-over predicate, recovery — is
[`knowledge/reference/argocd-sso-contract.md`](../../../knowledge/reference/argocd-sso-contract.md).

```bash
kustomize build kubernetes/examples/argocd-consumer-sso/
```

## Two deliberate differences from a real consumer overlay

**The base is a local path, not a remote base.**
`resources: ../../substrate/argocd` keeps the CI gate offline. A real overlay
lives in the consumer's own repo and pins this component as a Kustomize remote
base at a tag. Copy the remote-base form from the contract, not the path here.

(The example sits under `kubernetes/examples/` rather than inside the component
for a mechanical reason: kustomize refuses to build a root that contains its own
overlay — "cycle detected".)

**The client-secret Secret is absent.** It carries real credential material and
belongs in the consumer's SOPS-encrypted tree. The overlay references it through
the `$argocd-oidc:clientSecret` indirection; creating it, labelled
`app.kubernetes.io/part-of: argocd`, is the consumer's step. There is no
`*.sops.yaml` anywhere in this base by design.

## What CI proves about this example

`scripts/check-argocd-substrate-invariants.sh` builds it, and — this is the part
that makes the assertions worth anything — builds the **unpatched** component
first as a control. Comparing the two is what shows the patches do something; a
one-sided check would pass just as happily against patches that silently no-op.

It then asserts that the merged `argocd-cm` carries a non-empty `url` and a
parseable `oidc.config`, that `argocd-rbac-cm` carries a non-empty `policy.csv`,
that every `.data` key the base ships is still present after the merge (a
JSON6902 or `$patch: replace` patch would drop them), and that the whole build
passes `kubeconform -strict`.
