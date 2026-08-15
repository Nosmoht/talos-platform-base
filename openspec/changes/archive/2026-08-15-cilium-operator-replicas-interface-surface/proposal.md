# The operator replica count on the two interface specs

## Why

`cilium_operator_replicas` and `cilium_operator_replicas_effective` widen two
contracts the Cilium-delivery change did not touch: the module's typed
input/output surface (`module-interface-contract`, whose primary sources are
`variables.tf` and `outputs.tf`) and the declarative `cluster.yaml` shape
(`cluster-yaml-sot`, whose primary source is `schemas/cluster.schema.json`).
The ownership gate is right to flag them — this is not a no-behaviour-change
diff on either file.

Two of the additions are contract-relevant beyond "a key exists":

- The rejection is the module's first non-convergence guard on a Cilium input,
  and it sits deliberately on the REJECT side of the tier rule
  `module-interface-contract` already states. The distinguishing property is
  that `var.nodes` is not a guess about the environment — it is the cluster the
  module builds — so the module can decide the predicate with certainty, and
  the value lands in a create-only `inlineManifest` no later apply can correct.
- The provenance output is a new KIND of audit surface. The existing ones
  answer "what did the module bake in"; this one answers "which of several
  mechanisms decided it", which is what an operator debugging a live Deployment
  actually needs.

## What Changes

- `module-interface-contract`: the replica input's validations (integer, `>= 1`,
  and not exceeding the declared node count) join the Cilium input-validation
  requirement; the effectiveness check joins the inert-input warn requirement;
  and the resolved-count-with-provenance output joins the audit-output
  requirement.
- `cluster-yaml-sot`: `substrate.cilium` gains `operator_replicas` (integer,
  `minimum: 1`), keeping the closed object's key list accurate.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `module-interface-contract`
- `cluster-yaml-sot`

## Impact

- Specs: `module-interface-contract`, `cluster-yaml-sot`.
- Code: no change — the code landed with the Cilium-delivery change; this
  closes the ownership gate on the two specs that own the touched files.
