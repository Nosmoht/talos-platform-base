# Cilium value computation — SEED (main.tf's frozen bootstrap render) + the
# opt-in EMITTED self-management Application (this file's cilium_self_management_app
# local, main.tf's outputs.tf output). Moved out of main.tf verbatim (issue #188)
# so BOTH consumers of the computed values (the frozen seed AND the emitted app)
# read the SAME local.cilium_computed_values map — a single observability
# data-flow, no double-application. Pure `var.*`-derived locals only (no `data`/
# `terraform_data` blocks) so this file is symlinkable into the provider-less
# tests/fixtures/colliding-catalog offline fixture.
# See knowledge/decisions/0021-cilium-observability-and-argocd-self-management.md.

locals {
  # First IPv4 / IPv6 entries of pod_cidr by family (":" marks IPv6), so the
  # native-routing CIDRs are family-correct regardless of caller list order.
  cilium_pod_v4 = [for c in var.pod_cidr : c if !strcontains(c, ":")]
  cilium_pod_v6 = [for c in var.pod_cidr : c if strcontains(c, ":")]
  cilium_native_v4 = var.cilium_native_routing_cidr != "" ? var.cilium_native_routing_cidr : (
    length(local.cilium_pod_v4) > 0 ? local.cilium_pod_v4[0] : var.pod_cidr[0]
  )

  # Module-computed Cilium values from the typed inputs, layered between the
  # shipped floor (helm/cilium-values.yaml) and the consumer override. kube-proxy
  # replacement + the KubePrism host/port are emitted HERE (not the floor), gated
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
    var.cilium_kube_proxy_replacement ? { k8sServiceHost = "localhost", k8sServicePort = "7445" } : {},
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
    var.cilium_agent_metrics ? { prometheus = { enabled = true } } : {},
    var.cilium_operator_metrics ? { operator = { prometheus = { enabled = true } } } : {},
    # Hubble: metrics-only scope (no Relay/UI — issue Non-goal), so the observer
    # gRPC API's server TLS is unnecessary and is forced OFF (tls.enabled=false).
    # CONFIRMED independent of the metrics scrape endpoint (`hubble-metrics`
    # Service, :9965, gated by hubble.enabled + a non-empty hubble.metrics.enabled;
    # since Cilium 1.16 the metrics API carries its OWN hubble.metrics.tls.enabled
    # knob) — see ADR-0021 §(g). tls.enabled=false is strictly stronger than a
    # non-regenerating TLS method: zero cert material generated at render OR
    # runtime, so this also satisfies the seed-determinism half of AC #2.
    var.cilium_hubble_enabled ? {
      hubble = {
        enabled = true
        metrics = { enabled = var.cilium_hubble_metrics }
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
  # deep-merge" design was declined — see ADR-0021 §Alternatives): today's
  # floor∩computed key set has exactly ONE lossy collision under a plain
  # top-level merge() — the `operator` parent (floor sets operator.replicas=1,
  # cilium-values.yaml; the observability layer above adds operator.prometheus
  # when cilium_operator_metrics). A plain merge(floor, computed) would let the
  # computed `operator` map REPLACE the floor `operator` map wholesale, dropping
  # `operator.replicas`. So this merge does a top-level merge() PLUS an explicit
  # one-level re-merge of the `operator` sub-map. `hubble` also collides (floor
  # hubble.enabled:false) but its sole floor key is INTENTIONALLY superseded, so
  # it merges cleanly under the plain top-level merge (no sub-merge needed).
  # `cgroup` and `securityContext.capabilities.ciliumAgent` are untouched by the
  # computed layer, so they pass through the top-level merge() verbatim.
  #
  # TWO-ENGINE-DRIFT INVARIANT (recorded, not code today — no second collision
  # exists to bind): this shallow merge() + explicit `operator` sub-merge
  # reproduces Helm's recursive deep-merge ONLY because today's floor∩computed
  # key set has exactly this one lossy collision. ANY future computed-or-floor
  # key added under a shared parent MUST add (i) an explicit sub-merge for that
  # parent here AND (ii) a floor-preservation collision assert in
  # tests/input-validation.tftest.hcl mirroring the operator.replicas pair
  # (run 5) — otherwise a future change silently drops the colliding sibling
  # with no test catching it.
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
  cilium_self_management_app = var.cilium_self_management ? yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
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
    }
    spec = {
      project = var.cilium_self_management_project
      source = {
        repoURL        = var.cilium_chart_repository
        chart          = "cilium"
        targetRevision = var.cilium_chart_version
        helm = {
          valuesObject = local.cilium_effective_values
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = var.cilium_namespace
      }
    }
  }) : ""
}
