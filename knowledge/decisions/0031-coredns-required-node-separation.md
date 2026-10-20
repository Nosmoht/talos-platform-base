---
type: decision
title: "ADR: An opt-in module seed replaces the Talos built-in CoreDNS to require node separation"
description: "A default-off module input disables the Talos built-in CoreDNS and seeds the same objects under the same names as a controlplane inline manifest, adding a required hostname anti-affinity and a PodDisruptionBudget, so cluster DNS survives a node failure and a drain while the upgrade-k8s manifest sync updates the objects in place instead of pruning them."
status: stable
id: base:coredns-required-node-separation
decided: "2026-10-20T00:00:00Z"
deciders:
  - maintainer
consulted: []
informed: []
supersedes: []
superseded_by: []
related:
  - /decisions/0004-substrate-only-base.md
  - /decisions/0019-postfinance-kubelet-csr-approver.md
  - /decisions/0029-public-api-and-major-rule.md
tags: [adr, talos-cluster, coredns, availability, seed]
---

# ADR: An opt-in module seed replaces the Talos built-in CoreDNS to require node separation

## Context and Problem Statement

CoreDNS on a cluster built by the `talos-cluster` module is a Talos built-in
bootstrap manifest. In Talos v1.14.4 its Deployment `kube-system/coredns` runs
two replicas with only a *preferred* hostname pod anti-affinity (weight 100), and
no PodDisruptionBudget exists (`internal/app/machined/pkg/controllers/k8s/internal/k8stemplates/coredns.go`
in `siderolabs/talos`). The scheduler may place both replicas on one node, and a
single node failure then takes down every in-cluster name lookup. Issue #325
asks for replicas that never share a node and a disruption budget that lets a
drain evict one at a time.

A consumer cannot reach that state. The machine-config document
`KubeCoreDNSConfig` (legacy `cluster.coreDNS`) offers only `enabled` and `image`;
there is no replicas, affinity or budget setting. A hand edit of the Deployment
does not last: `talosctl upgrade-k8s` re-applies every bootstrap manifest by
server-side apply against the inventory `talos-bootstrap-manifests-inventory`,
and it prunes any inventoried object that left the manifest set unless
`--no-prune` is passed (`pkg/cluster/kubernetes/talos_managed.go`,
`syncManifestsSSA`). That same prune makes the naive fix dangerous: turning the
built-in off and deploying CoreDNS under other names lets the next sync delete
the `kube-dns` Service, releasing the ClusterIP every pod's resolver points at.

## Decision Drivers

- The replicas of the cluster DNS must never share a node, and a drain must
  evict them one at a time — current Kubernetes guidance treats a preferred term
  as a hint, and only a required term guarantees separation.
- The `kube-dns` Service and its ClusterIP must survive the change, because
  every kubelet writes that address into each pod's `resolv.conf`.
- DNS has to exist before Argo CD can reconcile anything, so its owner must be a
  bootstrap path.
- Existing consumers must see no change until they opt in (ADR-0029: a default
  change of behaviour is MAJOR).

## Considered Options

1. **Module seed under the built-in identities** — a default-off input disables
   the built-in and seeds, as a controlplane inline manifest, the same kinds,
   names and namespace, adding the required anti-affinity and a budget.
2. **Upstream Talos feature** — ask Talos for replicas, affinity and budget
   settings on `KubeCoreDNSConfig`.
3. **Consumer-side mutating admission policy** — a Kyverno or
   MutatingAdmissionPolicy rewrite of the built-in Deployment's affinity.
4. **Built-in off, CoreDNS through a Helm chart in Argo CD** — the consumer
   deploys the upstream chart as a Day-2 component.

## Decision Outcome

Chosen option: **1, the module seed under the built-in identities**, because it
is the only option that delivers required separation on the Talos releases the
module supports today while keeping the Service and its ClusterIP: the sync sees
the same object identities, updates them in place and prunes nothing.

The input is `coredns_node_separation` (default `false`), with
`coredns_replicas` (default `2`, at least `2`, below the declared node count) and
`coredns_image` (default the image Talos v1.13 and v1.14 ship). With it on, the
module writes `KubeCoreDNSConfig.enabled: false` (or
`cluster.coreDNS.disabled: true` before schema 1.14) after every caller patch,
and again after each control plane's own patches, and seeds one inline manifest
`coredns` carrying the ServiceAccount, `system:coredns` ClusterRole and binding,
the ConfigMap, the Deployment, the Service `kube-dns` and a PodDisruptionBudget
`coredns-node-separation`. The budget does not take the name `coredns`: at
boot Talos records an existing object of a seed identity in its inventory
without changing it, and the next sync then overwrites it and, on back-out,
prunes it, so a consumer-owned budget of that name would be lost. The budget
carries the annotation `talos-platform-base.io/seed-digest`, the sha256 of every
seed object, which the module also outputs as `coredns_seed_digest`: the
`99-coredns` manifest a control plane renders then shows which seed it runs.
The objects reproduce the v1.14 built-in — byte-identical Corefile, ClusterIP at
the tenth address of each service CIDR — and differ in three ways:
a required hostname anti-affinity selecting `k8s-app: kube-dns` with
`matchLabelKeys: [pod-template-hash]` (so a rolling update is not blocked by the
old ReplicaSet's pods), the budget (`maxUnavailable: 1`,
`unhealthyPodEvictionPolicy: AlwaysAllow`), and the recommended labels. The
module cannot see taints or cordons, so the node-count bound is necessary, not
sufficient; the input documentation says so. On a v1.13 line the seed also adds
the node affinity on `kubernetes.io/os` and `kubernetes.io/arch` that the v1.13
built-in lacks and v1.14 introduced; the seed has one shape for both lines.

The seed is not written again after each node's own patches, as the disable is:
the legacy `cluster.inlineManifests` list appends, and Talos rejects a second
entry named `coredns` (`ClusterInlineManifests.Validate` in
`pkg/machinery/config/types/v1alpha1/v1alpha1_validation.go`). The plan instead
fails on a per-node patch that would replace or delete the seed, and on a
`$patch` directive that would delete a guarded field or a parent.

CoreDNS stays part of the Talos pillar of ADR-0004: the seed takes over
rendering of objects Talos already delivers, it adds no component.

### Consequences

- Positive: with the input on, two CoreDNS replicas never share a node, and a
  drain of one node leaves the other serving while the evicted replica moves to
  a node without one.
- Positive: the cutover keeps every object identity, so the Service ClusterIP
  and the ConfigMap content are unchanged.
- Negative: the module, not Talos, now pins the CoreDNS image, the Corefile and
  the manifest shape. A Talos release that changes its built-in no longer
  reaches a consumer with the input on; the base has to follow by hand, and a
  consumer bumps `coredns_image` for a CoreDNS fix.
- Negative: the seed supports only the default DNS domain `cluster.local`, the
  module's `service_cidr` and `coredns_image`; the plan fails when a caller
  patch — generation-pass, worker or per-node — changes or deletes the domain
  or the subnets, or sets another CoreDNS image, when a per-node patch replaces
  the seed, and when a rendered role configuration states no service subnets.
- Negative: the cutover sync re-applies every bootstrap seed, not only CoreDNS,
  so a consumer whose Cilium or Argo CD moved past its seed has to settle that
  before cutting over (`UPGRADING.md`).
- Negative: the module counts declared nodes and cannot see taints or cordons;
  with too few schedulable nodes one replica stays Pending and the budget then
  allows no disruption of the other replica.
- Negative: the budget holds only a drain that waits for the eviction API.
  `kubectl drain` retries a refused eviction until its timeout, and talosctl's
  client-side drain (`talosctl upgrade`, `talosctl reboot --drain`) stops with an
  error after `--drain-timeout`; machined's own drain behind `talosctl shutdown`,
  `talosctl reset` and `talosctl upgrade --legacy` gives up after five minutes
  and proceeds (`pkg/kubernetes/kubernetes.go` `Drain`; siderolabs/talos#9882),
  and `talosctl reboot` without `--drain` evicts nothing. Two budgets selecting
  one pod hold nothing at all: the eviction API answers HTTP 500 (Kubernetes
  `pkg/registry/core/pod/storage/eviction.go`), which the kubectl drain library
  does not retry, so every drain fails at once and machined's proceeds at once.
  With a Pending replica or two CoreDNS budgets, a Talos operation on the node
  of the last Ready replica takes cluster DNS to zero, so `UPGRADING.md` runs
  `kubectl drain` before every Talos lifecycle operation.
- Negative: on a running cluster the seed acts only through `talosctl
  upgrade-k8s`. At boot machined server-side applies each object that does not
  exist yet as field manager `talos` and records it in the inventory, records an
  existing object without changing it, and skips one already inventoried
  (`manifest_apply.go`); the sync then applies every rendered object as the same
  field manager and prunes what is inventoried but no longer rendered. Until the
  sync runs the old Deployment keeps running unchanged and only the budget
  appears; because boot and sync share the field manager, the back-out sync
  removes the seed's required term and prunes the budget, and only a field
  another manager co-owns survives it. The dry-run of that sync prints one
  line per object, a space and then `< <action> <Kind>/<namespace>/<name>` — `created`,
  `configured`, `unchanged` or `Pruned` — with a diff after every action but
  `unchanged` (`syncManifestsSSA`; `ssa.Manager.Diff` in
  `github.com/siderolabs/go-kubernetes` `kubernetes/ssa/diff.go`, v0.2.41 on
  Talos v1.14.4 and v0.2.38 on v1.13.10), which is what the stop rules of the
  cutover and the back-out read.
- Negative: a Pending CoreDNS replica fails the module's health gate. Talos's
  default cluster checks wait for every replica of the `k8s-app=kube-dns`
  Deployment to be Ready (`coredns to report ready`,
  `pkg/cluster/check/default.go`), and `talos_cluster_health` runs
  those checks, so every `tofu apply` fails after `cluster_health_timeout` until
  a free node exists or the input is turned off.
- Follow-up: file the upstream Talos request of option 2; once a supported
  Talos release carries the settings, the seed can retire in favour of them.

## Pros and Cons of the Options

### Option 1 — module seed under the built-in identities

- Pro: works on every Talos release the module supports, and the bootstrap path
  delivers DNS before Argo CD.
- Pro: the sync's in-place update keeps the ClusterIP; there is no window
  without a Service.
- Con: the maintenance burden of tracking the Talos built-in moves into the base.

### Option 2 — upstream Talos feature

- Pro: the right long-term owner; no copy of the built-in in the base.
- Con: covers no current release, and the timeline is outside this project.

### Option 3 — consumer-side mutating admission policy

- Pro: no module change.
- Con: it fights the seed owner. Every sync re-applies the built-in spec, the
  policy rewrites it again, and the field manager that owns the affinity flips
  on each pass; a policy outage silently restores the preferred-only spec.

### Option 4 — CoreDNS through a Helm chart in Argo CD

- Pro: the upstream chart already exposes affinity and a budget.
- Con: DNS must exist before Argo CD, so the cluster cannot bootstrap on it, and
  the next sync would still prune the built-in Service first, releasing the
  ClusterIP.

## Validation

`tests/coredns-seed.tftest.hcl` (56 runs, providers mocked) binds:

- the seed on both schema lines: the object identities, the required term, the
  budget and its digest annotation, `coredns_seed_digest` as the sha256 of the
  objects, the built-in disable and its position after the caller patches and
  after a control plane's own patches, the Corefile against the Talos v1.14.4
  golden file, and the Service ports, ClusterRole rules, pod scheduling and
  container fields against the v1.14.4 constructor;
- the ClusterIP for one stack, two stacks and two stacks IPv6-first; the replica
  and image inputs, a `null` image, the version label of a tagged and a
  digest-only image; and the replica and image validations;
- each guard finding in its own run, which asserts the exact finding list: on
  the controlplane render the DNS domain and the service subnets in both schema
  forms, the CoreDNS image in the native form and a render that states no
  service subnets; on the worker render the DNS domain in the native form and a
  network document without service subnets; in a node's patches the DNS domain
  in the native form, the CoreDNS image in the legacy form, a JSON6902
  operation on the root, `/cluster`, `/cluster/network`, the DNS domain, the
  service subnets, `/cluster/coreDNS` and `/cluster/inlineManifests`, a move
  from the service subnets, and one without a path, a `$patch` on the v1alpha1 document, `cluster`,
  `cluster.network` and a `KubeNetworkConfig`, an inline manifest named
  `coredns` in either form, a `$patch` entry of and on
  `cluster.inlineManifests`, the documents the guard cannot read, and a
  guarded document behind a commented and behind a CRLF separator;
- the inputs the guard passes: the default network, reordered dual-stack
  subnets, a JSON6902 operation elsewhere, another inline manifest name, a
  node's network document without service subnets, commented, bare-CRLF, blank
  and comment-only separators, and a custom network with the seed off.

`scripts/check-talos-config-validation.sh` renders the seed with the locked
provider at the pins of `scripts/fixtures/talos-supported-lines.txt`, validates
both schema lines with `talosctl validate`, and shows on both lines that the
real render yields exactly one guard finding for a caller DNS-domain or
service-subnet patch, none for a dual-stack network or a non-default
`coredns_image`, and exactly one disabled built-in setting under a re-enabling
caller patch.

`scripts/check-coredns-builtin-parity.sh`
(`task tofu:check:coredns-builtin-parity`, CI workflow
`coredns-parity-live.yml`, weekly and on pull requests touching the seed)
resolves the newest release of
each line in `talos-supported-lines.txt` at run time. It fails when that
release's CoreDNS sources leave the recorded baseline
`scripts/fixtures/coredns-builtin-parity.txt` — object identities, RBAC rules,
Corefile, the Service and Deployment constructors, the node affinity and its
architectures, the DNS service address derivation and the default image — and
when the seed's rendered objects, single- and dual-stack, differ from the
release's golden CoreDNS objects
(`internal/app/machined/pkg/controllers/k8s/internal/k8stemplates/testdata/coredns-*.yaml`)
in a copied field. The comparison leaves out the fields the seed owns: the
recommended labels, the pod anti-affinity, the budget, the image (compared with
the default image instead), the golden file's IPv6 test address (the address
derivation is compared instead) and, on a v1.13 line, the added node affinity.
Every other field of the six built-in objects is compared. It also fails
when the test oracles cite another Talos release than the newest pin. A failure
is the signal to bring the seed in line with a new Talos release. A consumer
verifies the cutover with `talosctl upgrade-k8s --dry-run`, whose stop rules in
`UPGRADING.md` allow no `< Pruned` line, and the convergence of each control
plane with `coredns_seed_digest`. This decision is wrong if a Talos release
adds the settings of option 2, or changes the built-in's object identities,
which would turn the sync's update into a prune.

## Links

- Issue #325: `https://github.com/Nosmoht/talos-platform-base/issues/325`
- `siderolabs/talos` v1.14.4 and v1.13.10: `internal/app/machined/pkg/controllers/k8s/internal/k8stemplates/coredns.go`,
  `pkg/cluster/kubernetes/talos_managed.go`,
  `internal/app/machined/pkg/controllers/k8s/manifest_apply.go`,
  `pkg/kubernetes/kubernetes.go`, `cmd/talosctl/pkg/talos/nodedrain/nodedrain.go`
- siderolabs/talos#9882: `https://github.com/siderolabs/talos/issues/9882`
- `kubernetes/kubernetes` v1.37.1: `pkg/registry/core/pod/storage/eviction.go`,
  `staging/src/k8s.io/kubectl/pkg/drain/drain.go`
