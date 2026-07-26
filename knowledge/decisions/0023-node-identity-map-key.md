---
type: decision
title: "ADR: Node identity is the map key — one definition place, generated lists"
description: "var.nodes becomes a map keyed by node name, every Talos-facing list becomes a name-ordered projection of it, and the identity gaps the list model hid (node-key canonicality, first-label collisions, FQDN registration, odd controlplane count) become plan-time validations."
status: accepted
id: base:node-identity-map-key
timestamp: 2026-07-26
deciders:
  - maintainer
consulted: []
informed: []
supersedes: []
superseded_by: []
related:
  - /decisions/0009-node-capability-composition.md
  - /decisions/0007-cluster-yaml-sot.md
tags: [adr, talos, module-interface, cluster-yaml, breaking-change]
---

# ADR: Node identity is the map key — one definition place, generated lists

## Context and Problem Statement

`var.nodes` was `list(object({hostname, ip, role, image, …}))`, and the
Talos-facing arguments were further lists filtered out of it
(`main.tf` `talos_cluster_health.{control_plane_nodes, worker_nodes, endpoints}`,
`talos_client_configuration.{endpoints, nodes}`, `outputs.tf`
`controlplane_ips`). A list cannot express identity: position carries no
meaning, so nothing in the structure prevented a node from being declared
twice. Uniqueness rested on two added-on `validation` blocks, and
`schemas/cluster.schema.json` typed `nodes` as an `array` with no uniqueness
constraint at all — every future derivation had to remember the rules.

Reading the Talos source while specifying the node-name format surfaced three
further gaps the list model had been hiding:

- `HostnameConfigV1Alpha1.Validate()` checks hostname LENGTH only — no
  character class, no lowercasing. `NODE_01` is accepted.
- `nodename.FromHostname()` then silently rewrites whatever reaches the kubelet:
  lowercase, `_` → `-`, other runes dropped, leading/trailing `-`/`.` trimmed.
  So `NODE_01` and `node-01` are two distinct declarations arriving in
  Kubernetes as one node.
- `HostnameSpecSpec.ParseFQDN()` splits at the first dot and
  `k8s/nodename.go` registers the SHORT hostname unless
  `registerWithFQDN` is set — which the module did not expose. A dotted node
  name silently lost its domain part, and two names sharing a first label would
  put two kubelets on one Node object.

Separately, the module validated "at least one controlplane" but not parity,
leaving an even etcd membership plannable.

## Decision Drivers

- Identity belongs in the structure, not in a check a later derivation can
  forget.
- The declared name and the live name must be the same string; a platform that
  silently rewrites input is a source of drift, not a reason to inherit it.
- Consumers must be able to adopt this without a machine-config diff — the
  conversion is a data-shape change, not a behaviour change.
- The provider forbids a map at the boundary, so the model and the wire format
  must be allowed to differ.

## Considered Options

1. Keep the list; fix only the ordering of the derived lists.
2. Keep the list; add the missing validations.
3. Make `nodes` a map keyed by node name, derive every list from it, and add
   the validations the key cannot express.

## Decision Outcome

Chosen option: **3**, because it removes the defect class rather than adding
another guard against one instance of it. A duplicate node name stops being a
rejected input and becomes an unrepresentable one.

Concretely:

- `var.nodes` is `map(object({ip, role, image, hardware_capabilities?,
  config_patches?}))`. `hostname` is removed from the object — keeping it would
  recreate the second definition place the change exists to remove.
- `nodes.tf` holds the identity model: `node_name_by_ip` (the IP is the second
  identifier that must not collide, and it is a value rather than a key, so it
  gets a keyed view whose duplicate-key error is the structural backstop),
  `nodes_checked` (the node set re-keyed by name THROUGH that view, so the guard
  sits in the dependency chain rather than as a decorative reference a later
  refactor could delete), role views, and the name-ordered projections every
  Talos-facing argument now reads.
- The provider types `control_plane_nodes` / `endpoints` /`worker_nodes` /
  `nodes` as `list(string)` — verified in
  `terraform-provider-talos/pkg/talos/talos_cluster_health_data_source.go`. The
  map is therefore the model and the list is an output format. The projections
  are name-ordered **by construction, not by a `sort()` call**: an OpenTofu `for`
  expression over a map and `keys()` both yield keys lexicographically, so a
  `sort()` there would be a no-op — and a misleading one, because removing it
  would change nothing and could never be the mutant that binds the ordering
  contract. What binds it is `var.nodes` being a map at all: a map carries no
  declaration order to leak.
- Node keys must ALREADY be canonical Kubernetes node names — deliberately
  stricter than either platform accepts, because the failure mode is silent
  rewriting, not rejection.
- First labels must be unique, unconditionally; a dotted key requires the new
  `register_with_fqdn` input (default `false`).
- The controlplane count must be odd.

### Consequences

- Positive: a node cannot be declared twice in the module — a map key is unique
  by type, and the IP gets its own keyed view. The declared name is the live
  name. Declaration order is not observable in any emitted value.
- Scope limit, stated rather than implied: the SCHEMA constrains the *form* of
  node keys (`propertyNames`), which is not the same as detecting a duplicate
  one — a repeated YAML mapping key is collapsed by the parser before any schema
  keyword runs. Whether a duplicated key is reported at the file layer is a
  property of the YAML loader, not of this schema. The module-side guarantee is
  the real one.
- Scope limit: the module does not parse caller patch content, so a per-node
  `config_patches` entry can still override the module's `HostnameConfig` or the
  `registerWithFQDN` patch — the documented escape hatch cuts both ways. The
  typed inputs are the supported surface; raw patch content stays caller-owned
  (README §Notes).
- Positive: `for_each` keys are unchanged (still the hostname strings), so an
  unchanged node set converts with no state-address change and no resource
  replacement.
- Negative: breaking for every consumer — `cluster.yaml` `nodes:` becomes a
  mapping and each consumer shim must map it through. Released as MAJOR with a
  mechanical migration recipe in `UPGRADING.md`.
- Negative: growing a control plane 3 → 5 must be declared in one step; a
  transient 4-member control plane is no longer plannable. Accepted: the
  transient state is the one an operator is most likely to leave in place.
- Follow-up: consumers re-pin and convert; `talos-homelab-cluster` is the first.

## Pros and Cons of the Options

### Option 1 — order-only fix

- Pro: smallest diff, non-breaking.
- Con: leaves identity expressed by position; every added-on uniqueness rule
  stays forgettable, and the silent-rewrite gap stays open.

### Option 2 — list + more validations

- Pro: non-breaking; closes the named gaps.
- Con: grows the pile of rules that exist because the structure cannot say what
  is true. A future derivation still has to remember them.

### Option 3 — map keyed by node name

- Pro: uniqueness is structural; the remaining validations cover only what a key
  genuinely cannot express (IP collisions, parity, canonicality, first-label
  collisions, FQDN registration).
- Con: breaking; a MAJOR bump plus a consumer migration.

## Validation

- `tofu test` binds each rule red-green: removing a validation reddens the run(s)
  named in that validation's inline comment and no others. The parity rule's
  `count == 0` arm exists for exactly this — without it, parity and the
  at-least-one rule would both fire on an empty control plane and neither could
  be isolated. Positive controls (`three_controlplanes_plan_cleanly`,
  `sixty_three_character_label_plans_cleanly`, `canonical_ipv6_plans_cleanly`,
  `colliding_first_labels_are_legal_with_register_with_fqdn`,
  `distinct_fqdn_keys_with_register_with_fqdn_plan_cleanly`) stop the rules from
  degenerating into "always fails".
- The ordering contract has **no removable mutant** — see §Decision Outcome. The
  binding mutant is a type change (map → list), which
  `projections_and_bootstrap_target_follow_node_name` catches, and that run also
  pins the bootstrap target against a "lowest key overall" refactor by including
  a worker that sorts below every controlplane.
- `scripts/check-node-projection-wiring.sh` (in `tofu:ci`) covers what no
  `tofu test` can: the provider-less fixture omits `main.tf`, so nothing else
  asserts WHICH projection reaches WHICH Talos argument. Swapping two of them
  would otherwise leave the whole suite green.
- The schema side is bound by `schemas/fixtures/cluster.invalid.yaml` plus the
  per-violation assertions in `gitops-validate.yml`, which now carry a
  non-canonical node key as a distinct red case.
- The decision is wrong if a consumer's conversion produces a non-empty MACHINE-
  CONFIG plan for an unchanged node set. Two output-level diffs are expected and
  documented instead of being treated as falsification: reordered emitted lists
  for a consumer whose `nodes:` was not already name-ordered, and a moved
  bootstrap target when a lower-sorting controlplane is added
  (UPGRADING §5). `talos-homelab-cluster`'s adoption is the first observation of
  the predicate.

## Links

- Issue: Nosmoht/talos-platform-base#204
- `siderolabs/talos`: `pkg/machinery/config/types/network/hostname.go`,
  `pkg/machinery/resources/network/hostname_spec.go`,
  `internal/app/machined/pkg/controllers/k8s/nodename.go`,
  `internal/app/machined/pkg/controllers/k8s/internal/nodename/nodename.go`
- `siderolabs/terraform-provider-talos`:
  `pkg/talos/talos_cluster_health_data_source.go`
