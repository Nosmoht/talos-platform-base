# Cilium value computation — SEED (main.tf's frozen bootstrap render) + the
# opt-in EMITTED self-management Application (this file's cilium_self_management_app
# local, main.tf's outputs.tf output). Moved out of main.tf verbatim (issue #188)
# so BOTH consumers of the computed values (the frozen seed AND the emitted app)
# read the SAME local.cilium_computed_values map — a single observability
# data-flow, no double-application. Plan-time locals plus the two
# `check` blocks at the foot of the file (no `data`/`terraform_data` blocks) so
# this file stays symlinkable into the provider-less
# tests/fixtures/colliding-catalog offline fixture. It additionally reads
# local.nodes_checked from nodes.tf (node count -> operator replicas); that file is
# symlinked into the same fixture and is likewise provider-free, so the offline
# property is unchanged — but a new cross-file local read is a fixture obligation:
# a fixture symlinking this file must symlink nodes.tf too.
# See knowledge/decisions/0022-cilium-observability-and-argocd-self-management.md.

locals {
  # First IPv4 / IPv6 entries of pod_cidr by family (":" marks IPv6), so the
  # native-routing CIDRs are family-correct regardless of caller list order.
  cilium_pod_v4 = [for c in var.pod_cidr : c if !strcontains(c, ":")]
  cilium_pod_v6 = [for c in var.pod_cidr : c if strcontains(c, ":")]
  cilium_native_v4 = var.cilium_native_routing_cidr != "" ? var.cilium_native_routing_cidr : (
    length(local.cilium_pod_v4) > 0 ? local.cilium_pod_v4[0] : var.pod_cidr[0]
  )

  # --- Sub-maps for the two computed-layer parents that carry TWO contributors ---
  #
  # Hoisted into their own locals so each parent appears EXACTLY ONCE as a term of
  # the cilium_computed_values merge() below. That merge is SHALLOW: two terms
  # setting the same top-level key do NOT combine — the later one replaces the
  # earlier wholesale. This is the INTRA-COMPUTED half of the explicit-sub-merge
  # obligation recorded further down (see the two-engine-drift invariant comment
  # on cilium_effective_values); it is a different collision LEVEL from the
  # floor∩computed one ADR-0022 §(f) describes, and both are now live.

  # `prometheus`: cilium_agent_metrics -> .enabled, cilium_agent_metric_overrides
  # -> .metrics (the chart's +metric/-metric DELTA list against its default metric
  # set, NOT a replacement of it). Read ONLY from the cilium_agent_metrics arm
  # below, so the delta list can never surface with the scrape endpoint off — the
  # chart gates the whole `prometheus` values block on prometheus.enabled anyway
  # (verified against the pinned chart's cilium-configmap.yaml).
  cilium_prometheus_values = merge(
    { enabled = true },
    length(var.cilium_agent_metric_overrides) > 0 ? { metrics = var.cilium_agent_metric_overrides } : {},
  )

  # The effective operator replica count, or null for "leave it to the floor".
  # An explicit cilium_operator_replicas pin wins — on BOTH delivery paths, which
  # is why it is a typed input and not an override key: the module cannot
  # introspect the override, so nothing there validates the count against the
  # node set or reports which mechanism produced it. Unpinned, the node count
  # decides.
  #
  # Why 2 is the derived value at >= 2 nodes: it is the CHART'S OWN default, from
  # which the floor's 1 diverged without that ever being a multi-node decision.
  # THE RATIONALE LIVES HERE AND NOWHERE ELSE — a previous version of it was
  # copied into helm/cilium-values.yaml and a test comment, and survived the
  # correction of every narrative file because copies do not get corrected.
  #
  # Measured against the pinned chart, at the strength it was measured:
  #
  #   * Rollout availability. The rolling-update strategy varies with the replica
  #     count: maxUnavailable is 100% at one replica and 50% at two (maxSurge 25%
  #     in both). Resolved, that is "0 pods guaranteed available during a rollout"
  #     versus "1". It is NOT a claim that the incumbent always goes down first —
  #     25% of 1 rounds UP to one surge pod, so at a single replica on a
  #     multi-node cluster the controller MAY place the replacement first. The
  #     guarantee is the difference, not the observed ordering.
  #   * Recovery from a HARD node failure. The operator tolerates
  #     node.kubernetes.io/not-ready with no tolerationSeconds (an explicit
  #     toleration suppresses the 300s eviction Kubernetes adds only to pods that
  #     set none), but it does NOT tolerate node.kubernetes.io/unreachable — so a
  #     node that goes Ready=Unknown still evicts the pod on the standard 300s
  #     timer, after which it must be rescheduled and cold-started. A second
  #     replica is already running on another node (hostNetwork + the hostname
  #     anti-affinity guarantee that).
  #
  # NOT measured, so not claimed: how fast that second replica takes the WORK
  # over. The chart grants coordination.k8s.io/leases under a comment about HA
  # leader election, but it grants it at ONE replica too and sets no
  # leader-election flags — so whether the mode is replica-dependent, and what
  # the lease timings are, is operator-binary behaviour this repo has not
  # measured. Treat the recovery bullet as "a warm instance exists", not as a
  # quantified failover time.
  #
  # What a second replica does NOT buy: a node merely marked NotReady
  # (Ready=False) whose operator pod is alive and still reaching the API is not
  # a failover event at all — that pod goes on holding its lease.
  #
  # Counted over local.nodes_checked, not var.nodes: same keys by construction, but
  # the round trip runs the IP-distinctness guard first, so this cannot count a
  # node set that nodes.tf would reject.
  cilium_operator_replicas = var.cilium_operator_replicas != null ? var.cilium_operator_replicas : (
    length(local.nodes_checked) >= 2 ? 2 : null
  )

  # `operator`: cilium_operator_metrics -> .prometheus.enabled, the resolved
  # replica count -> .replicas. TWO contributors, so ONE hoisted sub-map — two
  # `operator` merge() terms would not combine, the later would replace the
  # earlier wholesale.
  #
  # A null replica count emits NO key, and the FLOOR keeps owning the value. That
  # arm is load-bearing twice over: it is the single-node-correct boundary
  # condition (the chart's operator podAntiAffinity is requiredDuringScheduling on
  # kubernetes.io/hostname, so a second replica has no node to land on), and it is
  # what keeps the floor the SOLE contributor of a key under `operator` on that
  # shape — the binding for the explicit `operator` sub-merge in
  # cilium_effective_values (mutant M2 in tests/input-validation.tftest.hcl).
  # Emitting a replica count unconditionally would make that sub-merge an
  # equivalent mutant and silently retire a live preservation assert.
  cilium_operator_values = merge(
    local.cilium_operator_replicas != null ? { replicas = local.cilium_operator_replicas } : {},
    var.cilium_operator_metrics ? { prometheus = { enabled = true } } : {},
  )

  # `hubble.metrics`: cilium_hubble_metrics -> .enabled, cilium_hubble_open_metrics
  # -> .enableOpenMetrics. Read ONLY from the cilium_hubble_enabled arm below.
  # Emitted conditionally: an unconditional `enableOpenMetrics = <bool>` would add
  # the key to the emitted self-management Application's valuesObject of every
  # existing Hubble consumer — a live-reconciled diff for someone who changed
  # nothing. (The rendered seed is unaffected either way: the chart writes
  # enable-hubble-open-metrics unconditionally once Hubble is on. The emitted
  # Application, not the frozen seed, is the path that reaches a running cluster.)
  cilium_hubble_metrics_values = merge(
    { enabled = var.cilium_hubble_metrics },
    var.cilium_hubble_open_metrics ? { enableOpenMetrics = true } : {},
  )

  # --- adr-0028 §(d) joint keys, hoisted -------------------------------------
  #
  # The three keys whose Talos-side counterpart the module writes, and which
  # var.cilium_values_override is therefore forbidden to name (variables.tf).
  # Hoisted into their own locals because they are emitted TWICE: into the
  # computed layer below (both delivery paths), and re-asserted as the LAST Helm
  # values layer of the multi-source emitted Application.
  #
  # WHY THE RE-ASSERTION EXISTS. On the multi-source arm the whole module-set
  # layer lives in a consumer-committed file. These three keys appear nowhere
  # else — not in helm/cilium-values.yaml (whose header says so) and not in the
  # chart's defaults, which are kubeProxyReplacement=false and no endpoint. So
  # any state where `$values/<values_path>` resolves empty — wrong path,
  # truncated commit, an operator setting ignoreMissingValueFiles to clear a
  # "values file not found" sync error — renders a Cilium that does NOT replace
  # kube-proxy while Talos already carries cluster.proxy.disabled: no ClusterIP
  # datapath, no cluster DNS, on a RUNNING cluster, delivered by a sync, and the
  # create-only seed does not repair it. Re-asserting them in valuesObject (the
  # last layer — verified against ArgoCD v3.5.2's repo-server, which appends it
  # after every valueFiles entry) makes that state unreachable.
  #
  # It creates no silent overwrite of a consumer value, which is the thing
  # adr-0028 exists to prevent: the override may not name these keys at all, so
  # there is never a consumer value here to overwrite. routingMode and
  # ipv4NativeRoutingCIDR are deliberately NOT re-asserted — they must stay
  # consumer-overridable, and losing them is recoverable by fixing the file and
  # resyncing.
  cilium_joint_keys_endpoint = {
    k8sServiceHost = var.cilium_k8s_service_host
    k8sServicePort = var.cilium_k8s_service_port
  }

  cilium_joint_keys = merge(
    { kubeProxyReplacement = var.cilium_kube_proxy_replacement },
    var.cilium_kube_proxy_replacement ? local.cilium_joint_keys_endpoint : {},
  )

  # Module-computed Cilium values from the typed inputs, layered between the
  # shipped floor (helm/cilium-values.yaml) and the consumer override. kube-proxy
  # replacement + the API-server endpoint are emitted HERE (not the floor), gated
  # on the toggle, so the Cilium side and Talos proxy.disabled stay in sync.
  #
  # A MAP local (not pre-yamlencoded): this is the single data-flow both the
  # frozen bootstrap seed (via cilium_computed_values_yaml, consumed by main.tf's
  # data.helm_template.cilium) AND the emitted self-management Application (via
  # cilium_effective_values below) derive from — no double-application, no
  # divergent observability layers (issue #188 steer 1 / Assumptions).
  cilium_computed_values = merge(
    {
      routingMode          = var.cilium_routing_mode
      kubeProxyReplacement = var.cilium_kube_proxy_replacement
    },
    var.cilium_kube_proxy_replacement ? local.cilium_joint_keys_endpoint : {},
    var.cilium_routing_mode == "native" ? { ipv4NativeRoutingCIDR = local.cilium_native_v4 } : {},
    (var.cilium_routing_mode == "native" && var.dual_stack && length(local.cilium_pod_v6) > 0) ? { ipv6NativeRoutingCIDR = local.cilium_pod_v6[0] } : {},
    var.dual_stack ? { ipv6 = { enabled = true } } : {},
    var.cilium_mtu > 0 ? { MTU = var.cilium_mtu } : {},
    # enableAppProtocol: Cilium routes a backend over h2c (HTTP/2 cleartext) only
    # when the Service port declares `appProtocol: kubernetes.io/h2c` AND this is on.
    # Without it the Gateway's envoy de-frames grpc-web into native gRPC over HTTP/1.1,
    # which gRPC backends (e.g. argocd-server's CLI/UI API) answer with 404 — gRPC
    # unreachable through the Gateway (#132). It is a Gateway-API setting (GEP-1911),
    # so it lives in this computed layer gated on cilium_gateway_api, NOT the floor
    # (base#133 review H1). No-op until a Service opts in via appProtocol.
    var.cilium_gateway_api ? { gatewayAPI = { enabled = true, enableAppProtocol = true } } : {},
    var.cilium_encryption.type == "wireguard" ? { encryption = { enabled = true, type = "wireguard" } } : {},
    var.cilium_encryption.type == "ipsec" ? { encryption = { enabled = true, type = "ipsec" } } : {},
    # --- Observability (issue #188; default-off, first-class inputs) ---
    # Agent + operator Prometheus metrics: independent toggles, no shared gate.
    # The agent term now carries TWO inputs (enabled + metrics) as ONE sub-map
    # (local.cilium_prometheus_values) — never as two merge() terms, which would
    # drop prometheus.enabled and leave the delta list inert.
    var.cilium_agent_metrics ? { prometheus = local.cilium_prometheus_values } : {},
    # operator: BOTH contributors fold through local.cilium_operator_values (see
    # its comment). Conditional on the sub-map being non-empty so a single-node
    # cluster with no operator metrics emits no `operator` key at all and the
    # floor's replicas=1 stays the effective value.
    length(local.cilium_operator_values) > 0 ? { operator = local.cilium_operator_values } : {},
    # Hubble: metrics-only scope (no Relay/UI — issue Non-goal), so the observer
    # gRPC API's server TLS is unnecessary and is forced OFF (tls.enabled=false).
    # CONFIRMED independent of the metrics scrape endpoint (`hubble-metrics`
    # Service, :9965, gated by hubble.enabled + a non-empty hubble.metrics.enabled;
    # since Cilium 1.16 the metrics API carries its OWN hubble.metrics.tls.enabled
    # knob) — see ADR-0022 §(g). tls.enabled=false is strictly stronger than a
    # non-regenerating TLS method: zero cert material generated at render OR
    # runtime, so this also satisfies the seed-determinism half of AC #2.
    # metrics is ONE sub-map (local.cilium_hubble_metrics_values) for the same
    # reason as `prometheus` above: a sibling merge() term carrying
    # enableOpenMetrics would replace this whole map, dropping hubble.enabled AND
    # tls.enabled=false together — the latter re-arms the chart's template-time
    # Sprig genCA path and de-determinizes the frozen seed render (ADR-0022 §g).
    var.cilium_hubble_enabled ? {
      hubble = {
        enabled = true
        metrics = local.cilium_hubble_metrics_values
        tls     = { enabled = false }
      }
    } : {},
  )

  # Pre-yamlencoded string for main.tf's data.helm_template.cilium values list
  # (the frozen bootstrap seed's ONLY consumer of this map).
  cilium_computed_values_yaml = yamlencode(local.cilium_computed_values)

  # The floor file, decoded once (shared by cilium_effective_values below; the
  # frozen seed reads the floor as a raw file() string via main.tf's values list
  # and does not need this decoded form).
  cilium_floor_values = yamldecode(file("${path.module}/helm/cilium-values.yaml"))

  # --- Emitted self-management Application's valuesObject (issue #188 §Ask-B) ---
  #
  # Bounded, module-controlled merge: floor ⊕ computed-incl-observability ONLY —
  # NO cilium_values_override term (steer 1). This is deliberately NOT an
  # arbitrary-depth recursive merge (the primary revision-2 "unbounded HCL
  # deep-merge" design was declined — see ADR-0022 §Alternatives): today's
  # floor∩computed key set has exactly ONE lossy collision under a plain
  # top-level merge() — the `operator` parent (floor sets operator.replicas=1,
  # cilium-values.yaml; local.cilium_operator_values above adds operator.prometheus
  # when cilium_operator_metrics, and operator.replicas whenever a count resolves
  # — a pin, or 2 at >= 2 nodes — where it legitimately supersedes the floor).
  # A plain merge(floor, computed) would let the
  # computed `operator` map REPLACE the floor `operator` map wholesale, dropping
  # `operator.replicas`. So this merge does a top-level merge() PLUS an explicit
  # one-level re-merge of the `operator` sub-map. `hubble` also collides (floor
  # hubble.enabled:false) but its sole floor key is INTENTIONALLY superseded, so
  # it merges cleanly under the plain top-level merge (no sub-merge needed).
  # `cgroup` and `securityContext.capabilities.ciliumAgent` are untouched by the
  # computed layer, so they pass through the top-level merge() verbatim.
  #
  # TWO-ENGINE-DRIFT INVARIANT — TWO COLLISION LEVELS, both live:
  #
  #   (A) floor∩computed, resolved HERE. Still exactly ONE lossy collision
  #       (`operator`), so the shallow merge() + one explicit sub-merge below
  #       still reproduces Helm's recursive deep-merge. The metric-override and
  #       OpenMetrics inputs did NOT add to this level: `prometheus` is absent
  #       from the floor, and `hubble` stays intentionally superseded. The
  #       resolved `operator.replicas` did not retire this level either: it is
  #       emitted only when a count actually resolves, so on an unpinned
  #       single-node cluster the floor is still the SOLE contributor of a key
  #       under `operator` and the sub-merge keeps biting. That is also why the
  #       pin does not weaken the gate — the gate's arm is the shape where NO
  #       count resolves, which no pin can enter (a pin resolves by
  #       definition). Emitting it unconditionally would make the sub-merge an
  #       equivalent mutant — M2 in tests/input-validation.tftest.hcl would go
  #       green on the very mutation it exists to catch.
  #   (B) INTRA-COMPUTED, resolved at the top of this file. Two terms of the
  #       cilium_computed_values merge() sharing a top-level key collide the same
  #       lossy way, and that merge has no floor to preserve — the loss is
  #       computed-vs-computed. Today: `prometheus` (enabled + metrics),
  #       `hubble.metrics` (enabled + enableOpenMetrics) and `operator`
  #       (replicas + prometheus), each folded into ONE term via
  #       local.cilium_prometheus_values / cilium_hubble_metrics_values /
  #       cilium_operator_values.
  #
  # ANY future key added under a parent already written by another contributor —
  # at EITHER level — MUST add (i) an explicit sub-merge for that parent (here for
  # level A, a hoisted sub-map local for level B) AND (ii) a preservation assert
  # in tests/input-validation.tftest.hcl mirroring the operator.replicas pair —
  # otherwise the change silently drops the colliding sibling with no test
  # catching it. Level B is the cheaper mistake to make: the sibling term reads
  # as an independent feature toggle right up until it eats its neighbour.
  cilium_effective_values = merge(
    local.cilium_floor_values,
    local.cilium_computed_values,
    {
      operator = merge(
        try(local.cilium_floor_values.operator, {}),
        try(local.cilium_computed_values.operator, {}),
      )
    },
  )

  # The opt-in emitted Cilium ArgoCD Application — a module OUTPUT only, never
  # cluster-side applied by the module (no live-apply resource, no CRD-ordering
  # dependency — AGENTS.md §Hard Constraints forbids the module directly applying
  # ArgoCD-managed resources). "" when the toggle is off. Deliberately carries NO syncPolicy
  # (the consumer controls sync timing for the graceful-restart-gated Hubble
  # DaemonSet roll — see README). spec.project defaults to "default" (the
  # always-present permissive AppProject — see var.cilium_self_management_project).
  # --- Multi-source arm (adr-0028 §(b)) --------------------------------------
  #
  # Whether the emitted Application reads its values layers from git instead of
  # carrying the module-set layer inline. Keyed on the values-source INPUT, never
  # on the content of cilium_values_override: the arm decides the manifest's
  # schema (spec.source vs spec.sources), which AppProject sourceRepos must
  # allow, and how many artifacts the consumer commits — a mode that big is named
  # by a mode input, not flipped by adding a character to an opaque YAML string.
  cilium_self_management_multi_source = var.cilium_self_management_values_source != null

  # Whether an override exists — declassified deliberately. var.cilium_values_override
  # is sensitive, and in OpenTofu ANY value derived from a sensitive one inherits
  # the mark, so a bare `override != ""` predicate would taint the whole emitted
  # Application and make the (secret-free) manifest output unexportable. What is
  # declassified here is one boolean: whether the string is empty. It carries no
  # part of the value, and it is already public in every other observable —
  # the presence of a second valueFiles entry, the check block below, the guard
  # message a consumer sees. nonsensitive() on the CONTENT would be the defect;
  # this is emptiness only.
  cilium_values_override_present = nonsensitive(var.cilium_values_override != "")

  # Digest of the override, declassified for the same reason and on the same
  # argument as the emptiness boolean above: it carries no part of the value.
  # It exists because marking the input sensitive removed the one plan-time
  # signal that the override CHANGED — and the override now reaches a running
  # cluster, not only a create-only seed. A digest restores "it changed" without
  # disclosing what. It is a change detector, not a secrecy claim: a digest
  # confirms a guessed document, which for a high-entropy values file carrying
  # key material is not a realistic disclosure path but is stated rather than
  # assumed. "" when there is no override, so an unset input reads as unset
  # rather than as the hash of the empty string.
  cilium_values_override_digest = local.cilium_values_override_present ? nonsensitive(sha256(var.cilium_values_override)) : ""

  # Null-safe view of the source object. Terraform's conditional evaluates BOTH
  # arms and its `||` is not documented as short-circuiting, so every attribute
  # read below goes through this local instead of behind a null check.
  cilium_values_source = coalesce(var.cilium_self_management_values_source, {
    repo_url      = ""
    revision      = ""
    values_path   = ""
    override_path = ""
  })

  # The module-set layer as the consumer commits it, and a digest over it. The
  # digest is the ONLY mechanical link between the two independently-committed
  # artifacts: ArgoCD compares neither, and a values file left behind by a later
  # typed-input change reverts module-set values into a live cluster with nothing
  # reporting it. Annotating the Application with the digest lets a consumer-side
  # gate or a reviewer catch that; it does not prevent it.
  cilium_self_management_values_digest = sha256(yamlencode(local.cilium_effective_values))

  cilium_self_management_values_file = var.cilium_self_management && local.cilium_self_management_multi_source ? join("", [
    "# GENERATED by talos-platform-base tofu/modules/talos-cluster — DO NOT EDIT.\n",
    "# Regenerate with: tofu output -raw cilium_self_management_values\n",
    "# Commit it at ${replace(local.cilium_values_source.values_path, "\n", " ")} in ${replace(local.cilium_values_source.repo_url, "\n", " ")}.\n",
    "# It is the FIRST valueFiles entry of the emitted Cilium Application; your own\n",
    "# override document is the second and wins over this file at any depth —\n",
    "# EXCEPT kubeProxyReplacement, k8sServiceHost and k8sServicePort, which the\n",
    "# Application re-asserts in helm.valuesObject as the last layer. Naming one of\n",
    "# those three in your override FILE does not take effect and is not reported:\n",
    "# the module rejects them in cilium_values_override, but it never reads the\n",
    "# file. Set them through cilium_k8s_service_host / cilium_k8s_service_port /\n",
    "# cilium_kube_proxy_replacement, which move the Talos side with them.\n",
    "# cilium chart: ${replace(var.cilium_chart_version, "\n", " ")}\n",
    "# values-digest: ${local.cilium_self_management_values_digest}\n",
    "#   (must equal the emitted Application's talos-platform-base.io/values-digest\n",
    "#   annotation — if it does not, this file is stale, re-run the output above.)\n",
    yamlencode(local.cilium_effective_values),
  ]) : ""

  # The chart source's ordered values layers. `valueFiles` is where the ORDER of
  # precedence lives, so the consumer's override wins over the module-set layer
  # without depending on any slot-precedence assumption; the override entry is
  # absent when the override is empty. ignoreMissingValueFiles stays explicitly
  # false: it is the switch that turns a wrong path from a loud sync error into a
  # silent render against chart defaults, and having it in the manifest makes
  # flipping it a reviewable git change rather than an ArgoCD-UI-only one.
  cilium_self_management_value_files = concat(
    local.cilium_self_management_multi_source ? ["$values/${local.cilium_values_source.values_path}"] : [],
    local.cilium_self_management_multi_source && local.cilium_values_override_present ? ["$values/${local.cilium_values_source.override_path}"] : [],
  )

  # metadata / spec hoisted so each arm is one readable merge() term instead of a
  # nested conditional inside yamlencode().
  cilium_self_management_metadata = merge(
    {
      name      = "cilium"
      namespace = var.argocd_namespace
      labels = {
        "app.kubernetes.io/name"       = "cilium"
        "app.kubernetes.io/instance"   = "cilium"
        "app.kubernetes.io/version"    = var.cilium_chart_version
        "app.kubernetes.io/component"  = "cni"
        "app.kubernetes.io/part-of"    = "talos-platform-base"
        "app.kubernetes.io/managed-by" = "argocd"
      }
    },
    # Annotation ONLY on the multi-source arm: it describes the values file the
    # consumer commits, which the single-source arm does not have, and adding a
    # key there would move the emitted manifest of every existing consumer.
    local.cilium_self_management_multi_source ? {
      annotations = {
        "talos-platform-base.io/values-digest" = local.cilium_self_management_values_digest
      }
    } : {},
  )

  cilium_self_management_spec = merge(
    {
      project = var.cilium_self_management_project
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.cilium_namespace
      }
    },
    # SINGLE-source arm — unchanged from before the values-source input existed:
    # the whole module-set layer rides inline in valuesObject.
    !local.cilium_self_management_multi_source ? {
      source = {
        repoURL        = var.cilium_chart_repository
        chart          = "cilium"
        targetRevision = var.cilium_chart_version
        helm = {
          valuesObject = local.cilium_effective_values
        }
      }
    } : {},
    # MULTI-SOURCE arm. sources[0] is a ref-only source: it generates no
    # manifests (ArgoCD evaluates its changes through the source referencing
    # it) and exists solely so `$values/...` resolves. sources[1] is the chart,
    # whose ORDERED valueFiles carry module-set-then-override, with the joint
    # keys re-asserted in valuesObject as the last layer.
    #
    # `source` is ABSENT rather than empty here: ArgoCD treats source and
    # sources as mutually exclusive. The module cannot remove that field from a
    # LIVE object though — whether a previously single-source Application drops
    # it depends on the consumer's apply and field-manager history, which is
    # why UPGRADING prescribes the transition order rather than assuming it.
    local.cilium_self_management_multi_source ? {
      sources = [
        {
          repoURL        = local.cilium_values_source.repo_url
          targetRevision = local.cilium_values_source.revision
          ref            = "values"
        },
        {
          repoURL        = var.cilium_chart_repository
          chart          = "cilium"
          targetRevision = var.cilium_chart_version
          helm = {
            valueFiles              = local.cilium_self_management_value_files
            ignoreMissingValueFiles = false
            valuesObject            = local.cilium_joint_keys
          }
        },
      ]
    } : {},
  )

  cilium_self_management_app = var.cilium_self_management ? yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata   = local.cilium_self_management_metadata
    spec       = local.cilium_self_management_spec
  }) : ""
}

# --- Inert-input warnings -----------------------------------------------------
#
# `check` blocks, NOT variable validations, deliberately: a consumer may satisfy
# either prerequisite through cilium_values_override — variables.tf documents
# that as THE path for the Hubble long tail — and the module cannot introspect an
# opaque YAML string to know it. A hard reject would refuse a configuration that
# actually works. Every hard reject in this module guards against SILENT BREAKAGE
# (a dropped datapath override, a fatally-exiting approver, an Application with
# nothing to reconcile); an input that merely does nothing is a lower tier.
#
# Tier semantics differ by command, and both halves are load-bearing:
#   `tofu plan` / `apply` — WARNING. The consumer sees it and proceeds, which is
#       the whole point for the cilium_values_override case above.
#   `tofu test`           — FAILURE, and a check block is a checkable object, so
#       `expect_failures = [check.<name>]` binds it directly (see
#       tests/input-validation.tftest.hcl). No warning-only escape hatch is
#       needed to test these.
#
# One block per predicate, never merged: expect_failures matches the checkable
# object, so merging the two conditions would collapse both legs onto one
# untested predicate — the same trap ADR-0022 §Guard isolation records for the
# variable validations.

check "cilium_agent_metric_overrides_effective" {
  assert {
    condition     = length(var.cilium_agent_metric_overrides) == 0 || (var.deploy_cilium && var.cilium_agent_metrics)
    error_message = "cilium_agent_metric_overrides is set but cannot take effect: it needs deploy_cilium = true (no seed and no emitted Application otherwise) AND cilium_agent_metrics = true (the chart emits the whole `prometheus` values block only when the agent scrape endpoint is on). The delta list is dropped from both engines as configured."
  }
}

check "cilium_operator_replicas_effective" {
  # Both ways the pin can be inert, in ONE predicate — deliberately, unlike the
  # one-block-per-predicate rule above, because they are not independently
  # reachable legs: they describe the same outcome (the pin reaches no running
  # operator) and a consumer hitting either needs the same paragraph. Splitting
  # them would fire the seed-freeze leg on the fresh-bootstrap consumer, for whom
  # the pin DOES take effect — a warning that cries wolf on the correct usage.
  #
  # The seed-freeze half cannot be a machine predicate at all: the module cannot
  # know whether this plan is a first bootstrap or the hundredth apply against a
  # live cluster. It rides in the message rather than the condition, which is why
  # the condition covers only the deploy_cilium half.
  assert {
    condition     = var.cilium_operator_replicas == null || var.deploy_cilium
    error_message = "cilium_operator_replicas is set but cannot take effect: it needs deploy_cilium = true — with Cilium off the module renders no seed and emits no self-management Application, so there is no operator Deployment for the count to reach. NOTE, separately and NOT detectable from a plan: on an ALREADY-BOOTSTRAPPED cluster with cilium_self_management = false the pin reaches only the frozen seed render, never the running Deployment — it applies at the next fresh bootstrap or after a deliberate -replace of terraform_data.cilium_render (UPGRADING, the operator-replicas section §3)."
  }
}

check "cilium_hubble_open_metrics_effective" {
  # MEASURED against the pinned chart, and not the obvious condition: the
  # `enable-hubble-open-metrics` key is NOT emitted merely because Hubble is on.
  # It sits under the same `{{- if or .Values.hubble.metrics.enabled … }}` gate as
  # `hubble-metrics-server`, so with an EMPTY metrics list the chart renders
  # neither — the flag is inert in exactly the half-on state ADR-0022 §k blesses.
  # Gating this check on hubble.enabled alone would report an inert input as
  # effective, which is the one thing a warning tier must not do.
  assert {
    condition     = !var.cilium_hubble_open_metrics || (var.deploy_cilium && var.cilium_hubble_enabled && length(var.cilium_hubble_metrics) > 0)
    error_message = "cilium_hubble_open_metrics is true but cannot take effect: it needs deploy_cilium = true, cilium_hubble_enabled = true, AND a non-empty cilium_hubble_metrics — the chart gates the OpenMetrics key on the metrics list being non-empty, so it changes the exposition format of an endpoint that exports nothing. Disregard the Hubble half of this if you enable Hubble through cilium_values_override; the module cannot introspect that string."
  }
}

check "cilium_self_management_values_source_is_inert" {
  # A values source with self-management off reaches NOTHING: both deliverables
  # are empty, every precondition passes vacuously, and the plan is otherwise
  # silent — the consumer has configured the Day-2 path and will commit nothing.
  # Same class and same tier as the three inert-input warnings above.
  assert {
    condition     = var.cilium_self_management_values_source == null || var.cilium_self_management
    error_message = "cilium_self_management_values_source is set but cannot take effect: it needs cilium_self_management = true. With self-management off the module emits no Application and no values file, so the values source reaches nothing."
  }
}

check "cilium_self_management_values_source_on_permissive_project" {
  # The values source decides where ArgoCD FETCHES the Helm values for a
  # privileged, host-networked DaemonSet from. spec.project is what bounds that:
  # the always-present "default" AppProject carries `sourceRepos: ['*']`, so it
  # accepts any repo the manifest names, and a cluster.yaml edit pointing
  # repo_url at a foreign repo then delivers arbitrary Cilium values with nothing
  # rejecting it. A scoped project listing exactly cilium_chart_repository and the
  # consumer's own repo turns that edit into a sync error.
  #
  # Warning rather than rejection, and on the PERMISSIVE shape rather than the
  # hardened one: "default" is the documented starting point and the module cannot
  # know whether a scoped project exists in the cluster yet. But the single-source
  # arm names no repo of its own, so this is a boundary the multi-source arm adds,
  # and it must not be the quiet half.
  assert {
    condition     = var.cilium_self_management_values_source == null || !var.cilium_self_management || var.cilium_self_management_project != "default"
    error_message = "cilium_self_management_values_source is set while cilium_self_management_project is \"default\": that AppProject allows every source repo (sourceRepos: ['*']), so nothing but PR review stops a repo_url edit from feeding attacker-chosen Helm values to the privileged cilium DaemonSet. Scope the Application to a dedicated AppProject whose sourceRepos lists exactly cilium_chart_repository and this values repo (README, the Cilium Self-Management section)."
  }
}

check "cilium_values_override_emptied_while_day2_wired" {
  # The silent-revert direction of the removed hard reject. Emptying the override
  # is an ordinary cluster.yaml edit, and it drops the second valueFiles entry
  # from the emitted Application: at the next sync ArgoCD reconciles Cilium
  # WITHOUT the Day-2 config the override was carrying. Nothing else in the plan
  # says so — the manifest diff is one list element.
  #
  # Gated on override_path being SET, not merely on the values source existing:
  # "multi-source arm with the module-set layer only" is a supported shape with
  # its own spec scenario and test leg, and warning on it would cry wolf on
  # correct usage — the one thing this tier must not do (see the operator-replicas
  # block above). An override_path configured with no override is the state that
  # actually says an override was REMOVED rather than never authored.
  assert {
    condition     = !(var.cilium_self_management && trimspace(try(var.cilium_self_management_values_source.override_path, "")) != "" && !local.cilium_values_override_present)
    error_message = "cilium_values_override is empty while cilium_self_management_values_source is still set: the emitted Application drops its override valueFiles entry, so the next ArgoCD sync reconciles Cilium WITHOUT the Day-2 values the override carried. If that is the intent, this is expected — otherwise restore the override, or unset cilium_self_management_values_source to return to the single-source shape deliberately. See UPGRADING, the Cilium self-management rollback section."
  }
}
