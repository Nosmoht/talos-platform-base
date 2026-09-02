---
type: decision
title: "ADR: The Day-0 ArgoCD kubectl apply delivers CRDs and nothing else"
description: "The module's post-health-gate kubectl apply is projected down to CustomResourceDefinition documents and loses --force-conflicts, ending a Day-2 convergence that pushed chart defaults over ArgoCD's own state and force-took field-manager ownership of argocd-cm and argocd-rbac-cm."
status: stable
id: base:argocd-crd-apply-scope
decided: "2026-08-14T00:00:00Z"
deciders:
  - maintainer
consulted: []
informed: []
supersedes: []
superseded_by: []
related:
  - /decisions/0024-argocd-substrate-relocation.md
  - /decisions/0006-opentofu-cluster-lifecycle.md
tags: [adr, argocd, talos-cluster, day-zero, field-manager]
---

# ADR: The Day-0 ArgoCD kubectl apply delivers CRDs and nothing else

## Context and Problem Statement

The three ArgoCD CRDs are ~1.8 MB and blow the Talos inlineManifest size budget,
so the seed ships the application without them and the module applies them
separately with `kubectl` after the cluster health gate.

The data source behind that apply renders the argo-cd chart with **no values
block** — only `crds.install = true`. Everything it produces beyond the CRDs is
therefore pure chart defaults. Until this decision the module applied that whole
render with `kubectl apply --server-side --force-conflicts`, and its own comment
described the non-CRD half as intentional: it would "converge the app the
inlineManifest seeded at boot".

It converged it onto the wrong values, and did so authoritatively. Measured
against the pinned chart, the render carries twelve kinds — `ServiceAccount`,
`ConfigMap`, `ClusterRole`, `ClusterRoleBinding`, `Role`, `RoleBinding`,
`Service`, `Deployment`, `StatefulSet`, `Job`, `Secret` alongside the CRDs — so
the apply:

- delivered a bundled `argocd-dex-server` and `server.dex.server*` cmd-params on
  every provisioned cluster, contradicting substrate invariants I1 and I2 at
  runtime while CI reported green (the invariants gate reads the two values
  files, which this path does not use);
- overwrote the seed's own `server.insecure` and `kustomize.buildOptions` with
  chart defaults;
- reset `argocd-rbac-cm` to chart defaults.

The trigger set (`argocd_chart_version`, `argocd_namespace`,
`kubernetes_version`) means this is not a one-time Day-0 event: a routine
Kubernetes upgrade re-fires it. `--force-conflicts` made the apply take
field-manager ownership rather than error on conflict, so it won each time.

The last consequence is the load-bearing one. The base is about to stop shipping
an RBAC binding, which makes `argocd-rbac-cm` the home of every consumer's access
policy. Leaving a routine `tofu apply` able to reset it would convert a cosmetic
defect into an outage primitive.

## Decision Drivers

- ArgoCD self-management is this platform's convergence mechanism for the ArgoCD
  application itself (adr-0024). A second, force-applying convergence path
  competes with it rather than complementing it.
- A gate that reports green on a property the running cluster does not have is
  worse than no gate.
- The consumer's own overlay must be able to own `argocd-cm` and
  `argocd-rbac-cm` without a scheduled `tofu apply` taking them back.
- The CRDs genuinely do need an out-of-band apply — that part of the design is
  sound and stays.

## Considered Options

1. **Pass the shipped seed values into the data source.** Fixes the *values* the
   apply converges onto, but keeps the ownership conflict: `argocd-rbac-cm` would
   still be force-reset to the seed's (chart-default) RBAC on every re-fire.
2. **Drop `--force-conflicts` only.** The apply would then error on conflict
   instead of winning, turning a silent overwrite into a failed `tofu apply` —
   trading data loss for a broken pipeline, and still applying chart-default
   workloads on a cluster with no prior owner.
3. **Project the render down to CRDs and drop `--force-conflicts`.**

## Decision Outcome

Chosen option: **3**, as a **seed-then-hand-off** path.

The module projects the frozen render to documents whose `kind` is
`CustomResourceDefinition` and applies that with
`kubectl apply --server-side --field-manager=talos-platform-base-day0`, without
`--force-conflicts`.

**Ownership, stated correctly.** An earlier draft of this decision justified
dropping the force flag with "nothing else co-owns those three CRDs". That is
false in this repository: `kubernetes/substrate/argocd/kustomization.yaml` ships
`_rendered/crds.yaml` — the same three CRDs — and the root Application syncs that
component with `ServerSideApply=true`. `argocd-controller` is therefore a
co-owner from the first steady-state sync onward, by design.

The correct reasoning is ownership, not exclusivity. Kubernetes recommends that
controllers force conflicts **on objects they own and manage**, precisely because
they cannot resolve a conflict interactively. After Day 0 this module owns
nothing here — Argo CD does, and Argo CD's own Server-Side Apply design states it
forces on the objects it owns. Forcing from the module would strip Argo CD's
ownership entries and roll a GitOps-managed CRD schema back to the older seed
pin: silent data loss, and the failure this ADR set out to end rather than
relocate. So the module seeds and steps back.

Three properties make that safe rather than merely principled:

- The **first** apply lands CRDs that do not yet exist, so it cannot conflict.
- `kubernetes_version` leaves `triggers_replace`, because the payload does not
  depend on it. **Corrected mechanism:** an earlier draft justified this with
  "Helm copies `crds/` through verbatim". That is false for this chart — argo-cd
  has no `crds/` directory; its three CRDs live in `templates/crds/` and are
  rendered as templates. The real, narrower justification is that every
  Go-template directive in those three files interpolates
  `.Values.crds.{install,keep,annotations,additionalLabels}` and nothing else —
  no `.Capabilities`, no `.Release` (verified against the pinned 9.4.5 tarball;
  the many `KubeVersion` strings in them are prose inside the CRDs' own schema
  descriptions, not template references). The measurement agrees: byte-identical
  render under `--kube-version` 1.31.0 and 1.35.0.

  Because they *are* templates, a future chart version **can** reach
  `.Capabilities.KubeVersion` there. That makes this a revisit trigger at every
  `argocd_chart_version` bump, not a structural guarantee — recorded as such in
  the freeze's comment.

  Keeping the trigger made a routine Kubernetes upgrade re-fire an apply against
  CRDs Argo CD owned by then, with no payload change to justify the risk — and
  since the apply no longer forces, such a conflict now fails the apply outright.
  What remains is a deliberate `argocd_chart_version` bump, where a conflict is
  the true statement "the steady state has moved past this pin" and deserves an
  operator decision.
- A dedicated `--field-manager` replaces kubectl's generic `kubectl` default,
  which an operator's ad-hoc apply also uses. Upstream gave kubectl's own
  subcommands distinct manager names for exactly this reason, and Argo CD's SSA
  design explicitly refuses to inherit the default. `managedFields` now
  distinguishes the module's writes from a human's.

The projection sits **before** the freeze, so the frozen bytes, the trigger hash
and the applied file are the same thing, and so the property stays visible at
plan time — a `terraform_data` output is unknown until apply, which would defer
both the guard and any test to apply time.

Three plan-time preconditions guard it, and the split matters. **Completeness**:
the projection carries all three ArgoCD CRDs *by name* — an earlier draft of this
decision said "at least three surviving documents", which is the count-based form
the spec explicitly rejects, since three wrong documents satisfy it.
**Exclusivity**: every surviving document is a `CustomResourceDefinition` — the
name check is a containment test, so deleting the kind filter yields the full
twelve-kind render and passes it, which is the original defect. **Parseability**:
no non-blank document in the *source* split fails `yamldecode`. The kind filter
uses `try(..., "")`, so an unparseable document drops out silently; that is right
for a stray document and wrong for a CRD cut in half by a `\n---\n` inside its
own `openAPIV3Schema`, where the head fragment still decodes with a valid kind
and name, is kept, and is applied as a truncated schema.

`scripts/check-argocd-day0-apply-shape.sh` asserts all of it statically, plus the
kind filter itself and the absence of `kubernetes_version` from the trigger set,
so the properties have a blocking gate rather than resting on the network-gated
projection test. The `argocd_day0_apply_kinds` output exposes the surviving kinds
as the binding point for `tests/argocd-crd-scope.tftest.hcl`.

`scripts/check-render-determinism.sh` gained a second accepted capture shape for
this: the live render may be referenced once inside a `locals` block whose value
the freeze captures. The #123 property is unchanged — one live read, every
apply-path consumer through the freeze.

### Consequences

- Positive: the seeded app is no longer overwritten with chart defaults; consumer
  ownership of `argocd-cm` / `argocd-rbac-cm` survives a `tofu apply`; substrate
  invariants I1 and I2 stop being runtime-false; less state is frozen.
- Negative: the module no longer repairs a drifted ArgoCD installation at all.
  That was never reliable — it repaired *towards chart defaults* — but the
  fallback is now explicitly ArgoCD self-management plus, in the worst case, a
  re-bootstrap.
- **Existing clusters are not retroactively repaired.** `kubectl` remains a
  recorded field-manager entry on the ConfigMaps it already touched; this change
  only stops future applies from re-taking them.

  Expected consumer action: **none**, but the reasoning below is corrected from
  an earlier draft that had its default backwards. That draft argued the residual
  was inert because "Argo CD applies its desired state client-side by default"
  and treated server-side apply as the exceptional case a consumer must
  self-check. For anyone who bootstrapped with the shipped root Application, the
  exception *is* the default: `kubernetes/bootstrap/argocd/root-application.yaml.tmpl`
  sets `ServerSideApply=true` (and `selfHeal: true`).

  So the actual path is: `argocd-controller` applies server-side, negotiates
  ownership with the stale `kubectl` manager, and — per Argo CD's SSA design,
  which forces on the objects it owns — takes the contested fields. The stale
  entry stops being written to and decays into bookkeeping; a consumer who wants
  it gone can drop it from `metadata.managedFields`. A consumer who deliberately
  syncs the argocd component client-side is the case that now needs its own
  check.

  Flagged as reasoning from apply semantics, not an observation: no cluster is
  available to this repository, so neither the ownership hand-over nor the
  inertness of the residual entry is verified here.
- Verification is render-level and plan-level. No cluster is available to this
  repository, so "the apply now lands only CRDs" is proven by the plan-time
  preconditions, the static fence, and the projection test — not by an observed
  apply.
- **A conflict now fails `tofu apply` rather than being steamrolled.** That is
  the intended trade (it is why Option 2 was rejected only for *also* applying
  chart-default workloads), but it is a real operational cost: the failing
  `local-exec` sits behind the health gate in the same graph, so an unrelated
  apply fails too. `UPGRADING.md` carries the triage and the `tofu state rm`
  unblock. A dedicated opt-out input for the Day-0 CRD apply was considered and
  deferred as interface growth this change does not need.
- **The safety argument now depends on seed/steady-state chart-pin parity**,
  which was previously "maintained by review, not mechanically gated". A
  divergence used to be silently forced; it would now fail every consumer's next
  apply. `scripts/check-argocd-substrate-invariants.sh` asserts the parity as of
  this decision. Version-string only: a same-version upstream republish still
  slips through on the module side.
- **Deferred (named, not silently dropped): byte-level Kubernetes-version
  independence of the CRD payload.** The trigger set omits `kubernetes_version`
  on the strength of a measurement (byte-identical render under `--kube-version`
  1.31.0 and 1.35.0) plus the verified fact that the three CRD templates
  interpolate only `.Values.crds.*`. The test binds the **structural** half —
  same three CRDs, same single kind, at a Kubernetes version far from the suite
  default — so a chart that renders its CRDs into a different document set fails
  loudly. A templating change that alters bytes without altering that structure
  would slip through: OpenTofu has no cross-run output reference, so two renders
  cannot be digest-compared inside one test suite. Because the CRDs already ARE
  templates, re-check the directive list at every chart bump.

## Addendum to adr-0024

adr-0024 records as a decision driver that "on a live cluster `argocd-controller`
is the sole field-manager owner of `argocd-cm.url`, `argocd-cm.oidc.config`,
`argocd-rbac-cm.*` … byte-matching the committed render". That was never true:
the `--force-conflicts` apply described above has been a co-owner of exactly
those keys since the module gained it. The conclusion adr-0024 drew from the
driver — do not fold the steady-state layer into the create-only seed — is
unaffected and stands; only its stated evidence was wrong.

## Addendum — revisit trigger discharged at chart 10.6.0 (2026-09-02)

The revisit trigger this record sets — re-check the CRD templates' directive
list at every `argocd_chart_version` bump — was run for `9.4.5` → `10.6.0`. It
holds: every Go-template directive in the three `templates/crds/` files still
interpolates `.Values.crds.{install,keep,annotations,additionalLabels}` and
nothing else, with no `.Capabilities` and no `.Release`, and the render is
byte-identical under `--kube-version` 1.31.0, 1.35.0 and 1.36.3. The decision
and its residual are unchanged; only the version the measurement was taken at
moves, and the trigger stands for the next bump.
