# talos-cluster: turns a set of PXE-booted Talos maintenance-mode nodes into a
# bootstrapped Kubernetes cluster, and reconciles Kubernetes version + system
# extensions on subsequent applies. Hardware provisioning and PXE boot are
# out of scope (see lifecycle/ipxe + the DHCP/next-server setup).
#
# Flow:
#   image-factory per distinct schematic (extensions+kargs -> schematic -> installer URL)
#     -> machine_secrets (PKI)
#       -> machine_configuration (per machine_type, with k8s/talos version + patches)
#         -> configuration_apply (per node, with hostname + install.image patch)
#           -> bootstrap (lowest-hostname controlplane only)
#             -> kubeconfig + talosconfig
# (Day-2 Kubernetes upgrade is OUT-OF-BAND via `talosctl upgrade-k8s` — the
#  siderolabs/talos provider ships no upgrade resource; see the Day-2 block below.)

locals {
  controlplanes = [for n in var.nodes : n if n.role == "controlplane"]

  # Bootstrap target + the node we pull kubeconfig/talosconfig from. Selected by
  # a STABLE key (lowest controlplane hostname), NOT list order — so reordering
  # var.nodes after bootstrap cannot move which node is bootstrapped
  # (talos_machine_bootstrap is pinned to this node's IP).
  controlplanes_by_hostname = { for n in local.controlplanes : n.hostname => n }
  first_controlplane        = local.controlplanes_by_hostname[sort(keys(local.controlplanes_by_hostname))[0]]

  nodes_by_hostname = { for n in var.nodes : n.hostname => n }

  # OS version running on the nodes. Defaults to talos_version (= schema-pin)
  # for new clusters; bump talos_install_version for an OS upgrade while
  # keeping talos_version fixed at bootstrap.
  install_version = var.talos_install_version != "" ? var.talos_install_version : var.talos_version

  # All caller-supplied machine-config patch strings, flattened for the SecureBoot
  # guard below. NOTE: the guard is a substring HEURISTIC (same lexical pattern as
  # the repo's tofu/** CI grep), not a complete SecureBoot detector — it catches a
  # config_patch that literally selects a `*-secureboot` installer URL (the common
  # copy-paste of the old recipe). It does NOT catch a SecureBoot image selected via
  # a schematic-level secureboot toggle or a renamed/mirrored/by-digest image whose
  # string lacks those substrings — that residual stays consumer-overlay
  # responsibility (same boundary as AGENTS.md §"Out of scope for the base").
  all_caller_patches = concat(
    var.config_patches,
    var.controlplane_config_patches,
    var.worker_config_patches,
    flatten([for n in var.nodes : n.config_patches]),
  )
  # Match the hyphenated SecureBoot installer forms (metal / installer / metal-installer
  # all share the `-secureboot` URL fragment). The full prefixed literals are
  # deliberately NOT written here — they would trip the repo's own
  # hard-constraints-check grep, which cannot tell a guard from a usage.
  secureboot_patches = [for p in local.all_caller_patches : p if can(regex("-secureboot", p))]
}

# ---------------------------------------------------------------------------
# ArgoCD delivery as a Talos cluster.inlineManifest (C4 layer model, Layer 1;
# local data.helm_template render, NO helm_release/apply).
# Comes up with the bootstrap on the first controlplane.
# ---------------------------------------------------------------------------
data "helm_template" "argocd" {
  count = var.deploy_argocd ? 1 : 0

  name         = "argocd"
  namespace    = var.argocd_namespace
  repository   = "https://argoproj.github.io/argo-helm"
  chart        = "argo-cd"
  version      = var.argocd_chart_version
  kube_version = var.kubernetes_version
  # CRDs are NOT in the inlineManifest (too large for Talos, ~1.8 MB) — applied
  # separately via kubectl server-side (null_resource.argocd_crds below).
  include_crds = false

  # Shipped base values, then the optional consumer override layered on top
  # (helm merges value files; later wins) — a merge, not a wholesale replace.
  values = var.argocd_values_override != "" ? [
    file("${path.module}/helm/argocd-values.yaml"),
    var.argocd_values_override,
  ] : [file("${path.module}/helm/argocd-values.yaml")]

  # Hard-fail at plan time (not a check block — that would only be a warning):
  # evaluated only when deploy_argocd (count=1), but it sees var.sops_age_key.
  # Without the key the ksops repoServer could not decrypt SOPS manifests.
  lifecycle {
    precondition {
      # A real age private key starts with AGE-SECRET-KEY-1 (a Bech32 body follows).
      # Prefix check (not full Bech32) is the right altitude: it rejects an empty
      # value and obvious non-keys at plan time, where the ksops repoServer would
      # otherwise only fail at runtime. The example root sets NO default for this
      # variable, so a copied example cannot silently `apply` a non-functional key —
      # `tofu plan` there requires a real key via TF_VAR_sops_age_key.
      condition     = startswith(var.sops_age_key, "AGE-SECRET-KEY-1")
      error_message = "deploy_argocd = true requires a real age private key in sops_age_key (it must start with \"AGE-SECRET-KEY-1\"; supply via TF_VAR_sops_age_key / tfvars / SOPS). The ArgoCD ksops repoServer needs it to decrypt SOPS manifests."
    }
    postcondition {
      # The render is frozen by terraform_data.argocd_render (ignore_changes), so an
      # empty/partial render would be captured once and NEVER self-healed by tofu
      # (recovery needs -replace). Fail at plan time instead of bootstrapping an
      # ArgoCD-less seed. Refs #123.
      condition     = self.manifest != ""
      error_message = "data.helm_template.argocd rendered an EMPTY manifest — refusing to freeze an empty ArgoCD seed. Check argocd_chart_version / repository / argocd_values_override."
    }
  }
}

# Freeze the ArgoCD seed render in state (decouple the live render from the apply).
# data.helm_template.argocd is re-evaluated every plan and the helm provider does not
# render byte-stable manifests; consumed directly, every plan / Crossplane reconcile
# re-pushed a fresh machineConfig (#121/#123). The inlineManifest is a create-only
# SEED (Talos applies it only at bootstrap; Day-2 ArgoCD is self-management), so the
# render bytes matter only at creation: capture once, ignore subsequent drift. A fresh
# cluster (new state) captures its current render; an existing cluster never re-pushes
# from render drift. NO triggers_replace — re-capture on a live cluster is inert for a
# create-only seed and would re-introduce the churn. Deliberate re-seed = `-replace`.
resource "terraform_data" "argocd_render" {
  count = var.deploy_argocd ? 1 : 0
  input = data.helm_template.argocd[0].manifest
  lifecycle {
    ignore_changes = [input]
  }
}

locals {
  # Recommended labels + PSA floor for the module-seeded argocd namespace.
  # The module is the SOLE creator of this namespace (the former bootstrap
  # kubernetes/bootstrap/argocd/namespace.yaml is retired with the make
  # argocd-install path), so the create-only seed carries the full PSA floor +
  # the six recommended labels itself — never delivered label-less / PSA-
  # unenforced (AGENTS.md §Hard Constraints). version = the argo-cd CHART version
  # (the only version the seed knows); steady-state ownership transfers to the
  # argocd Application via SSA-merge. Exposed via output.argocd_namespace_labels
  # for audit + the composition test's PSA assertion (red-green binding).
  argocd_namespace_labels = {
    "app.kubernetes.io/name"                     = "argocd"
    "app.kubernetes.io/instance"                 = "argocd"
    "app.kubernetes.io/version"                  = var.argocd_chart_version
    "app.kubernetes.io/component"                = "bootstrap"
    "app.kubernetes.io/part-of"                  = "gitops"
    "app.kubernetes.io/managed-by"               = "opentofu"
    "pod-security.kubernetes.io/enforce"         = "baseline"
    "pod-security.kubernetes.io/enforce-version" = "latest"
    "pod-security.kubernetes.io/audit"           = "restricted"
    "pod-security.kubernetes.io/audit-version"   = "latest"
    "pod-security.kubernetes.io/warn"            = "restricted"
    "pod-security.kubernetes.io/warn-version"    = "latest"
  }

  # ArgoCD as cluster.inlineManifests, in apply order:
  #   1. argocd namespace
  #   2. sops-age-key Secret (the ksops repoServer decrypts SOPS manifests with it)
  #   3. the rendered ArgoCD manifest
  # Hooked in as an additional controlplane config_patch (only when deploy_argocd).
  argocd_controlplane_patch = var.deploy_argocd ? [yamlencode({
    cluster = {
      inlineManifests = [
        {
          name = "argocd-namespace"
          contents = yamlencode({
            apiVersion = "v1"
            kind       = "Namespace"
            metadata = {
              name = var.argocd_namespace
              # MUST stay `local.argocd_namespace_labels` (the SAME local that
              # output.argocd_namespace_labels exposes) — that shared source is
              # what binds the composition test's PSA assertion to the bytes this
              # inlineManifest actually seeds. Adding labels here directly would
              # fork the two and silently un-bind the test.
              labels = local.argocd_namespace_labels
            }
          })
        },
        {
          name = "argocd-sops-age-key"
          contents = yamlencode({
            apiVersion = "v1"
            kind       = "Secret"
            type       = "Opaque"
            metadata   = { name = "sops-age-key", namespace = var.argocd_namespace }
            stringData = { "keys.txt" = var.sops_age_key }
          })
        },
        {
          name     = "argocd"
          contents = terraform_data.argocd_render[0].output
        },
      ]
    }
  })] : []
}

# ---------------------------------------------------------------------------
# Cilium delivery (Layer-1 substrate). Disables the Talos default CNI (Flannel)
# and kube-proxy, then delivers Cilium as a controlplane cluster.inlineManifest
# SEED — the same local-render → inlineManifest pattern as ArgoCD. Comes up as
# the CNI with the bootstrap. inlineManifests are create-only, so this is a SEED
# (cilium_chart_version is a SEED knob, not an upgrade knob).
# ---------------------------------------------------------------------------
locals {
  # All-nodes OVERRIDABLE base patch (pod/service subnets + scheduling). Placed
  # FIRST so a caller config_patch can still override it — e.g. a migrating
  # consumer with custom subnets. Tunnel-mode Cilium reads the real podSubnets via
  # ipam:kubernetes, so a subnet override does not desync it.
  base_cluster_patch = yamlencode({
    cluster = {
      network = {
        podSubnets     = var.pod_cidr
        serviceSubnets = var.service_cidr
      }
      allowSchedulingOnControlPlanes = var.allow_scheduling_on_controlplanes
    }
  })

  # All-nodes OVERRIDABLE base patch: enable kubelet serving-cert rotation via the
  # KubeletConfiguration serverTLSBootstrap field — NOT the deprecated
  # --rotate-server-certificates extraArgs flag (repo directive: no deprecated
  # options; the flag is what Talos' metrics-server doc still shows). The kubelet
  # then requests its serving cert via a kubernetes.io/kubelet-serving CSR instead
  # of self-signing; cert-approver (seeded below) approves it. Placed FIRST in the
  # config_patches concat (like base_cluster_patch) so a consumer can opt out via
  # config_patches. extraConfig = KubeletConfiguration → genuine bool (no string
  # quoting). Applied to BOTH controlplane and worker (the serving cert is per
  # kubelet). See knowledge/decisions/0013-kubelet-serving-cert-rotation.md.
  base_kubelet_rotation_patch = yamlencode({
    machine = { kubelet = { extraConfig = { serverTLSBootstrap = true } } }
  })

  # All-nodes AUTHORITATIVE patch (cni:none + proxy.disabled), gated on Cilium
  # delivery. Placed LAST so it wins over any caller config_patch: when
  # deploy_cilium is true, Flannel must NOT come up, so cni:none is intentionally
  # NOT caller-overridable (the documented opt-out is deploy_cilium = false). A
  # stale caller `cni` stanza from the old extraManifests recipe therefore cannot
  # silently resurrect Flannel. proxy.disabled tracks the kube-proxy toggle.
  base_cni_patch = var.deploy_cilium ? [yamlencode({
    cluster = merge(
      { network = { cni = { name = "none" } } },
      var.cilium_kube_proxy_replacement ? { proxy = { disabled = true } } : {},
    )
  })] : []

  # OPT-IN bootstrap seeding of the Gateway API CRDs via cluster.extraManifests
  # (controlplane), only when cilium_gateway_api_crds_url is set non-empty. Default
  # empty -> the base seeds NO CRDs at bootstrap; CRDs are a Day-1 GitOps/apps-catalog
  # concern, which is air-gap-safe. The Cilium GatewayClass is operator-created at
  # runtime (NOT in the helm render), so it reconciles once the CRDs exist regardless
  # of source — no inline/extra ordering guarantee is relied upon. WARNING: a failed
  # extraManifests fetch is NOT graceful (Talos ExtraManifestController crashloops and
  # bootstrap does not complete cleanly) — see cilium_gateway_api_crds_url. CRDs carry
  # no key material, so the URL form is acceptable for the opt-in case (unlike Cilium).
  gateway_api_patch = (var.deploy_cilium && var.cilium_gateway_api && var.cilium_gateway_api_crds_url != "") ? [yamlencode({
    cluster = { extraManifests = [var.cilium_gateway_api_crds_url] }
  })] : []

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
  cilium_computed_values = yamlencode(merge(
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
  ))

  # Cilium (+ optional IPsec key Secret, applied first via the Namespace→CRD→other
  # sort) as controlplane inlineManifests, baked after caller patches like ArgoCD.
  cilium_controlplane_patch = var.deploy_cilium ? [yamlencode({
    cluster = {
      inlineManifests = concat(
        var.cilium_encryption.type == "ipsec" ? [{
          name = "cilium-ipsec-keys"
          contents = yamlencode({
            apiVersion = "v1"
            kind       = "Secret"
            type       = "Opaque"
            metadata   = { name = "cilium-ipsec-keys", namespace = var.cilium_namespace }
            stringData = { keys = var.cilium_ipsec_key }
          })
        }] : [],
        [{
          name     = "cilium"
          contents = terraform_data.cilium_render[0].output
        }],
      )
    }
  })] : []
}

# ---------------------------------------------------------------------------
# cert-approver (postfinance/kubelet-csr-approver) — Talos boot-glue substrate,
# delivered as a controlplane cluster.inlineManifest SEED. VENDORED-CHART-RENDER
# + TEMPLATED pattern: the postfinance chart is rendered once at pin time and
# committed at manifests/kubelet-csr-approver.yaml with the per-cluster config
# values (provider_regex / provider_ip_prefixes / replicas) re-parameterized as
# templatefile() placeholders — pure/deterministic (no data.helm_template, so
# outside the render-determinism fence). UNCONDITIONAL seed (always delivered);
# cluster.schema.json's substrate.cert_approver carries only tuning knobs, no
# disable toggle. Pairs with base_kubelet_rotation_patch — without the approver
# the serving CSRs that serverTLSBootstrap triggers stay Pending.
# ADR-0019 (supersedes ADR-0013 §D2). See knowledge/decisions/0019-postfinance-kubelet-csr-approver.md.
# ---------------------------------------------------------------------------
locals {
  # replicas > 1 opts into HA: the vendored template then also renders the
  # -leader-election arg + a NAMESPACED leases/events Role+RoleBinding (the
  # ClusterRole stays invariant at its 3 signer-scoped rules), so the default
  # replicas:1 keeps least privilege (no leases grant at all).
  cert_approver_leader_election = var.cert_approver_replicas > 1

  # The seeded manifest, rendered ONCE. Both the seed patch and the audit
  # outputs (outputs.tf) consume this — never re-render or read the file raw.
  # provider_regex / provider_ip_prefixes are injected as jsonencode() scalars
  # (safe single-line YAML); provider_ip_prefixes is comma-joined per the
  # PROVIDER_IP_PREFIXES env format the approver parses.
  cert_approver_manifest = templatefile("${path.module}/manifests/kubelet-csr-approver.yaml", {
    provider_regex       = jsonencode(var.cert_approver_provider_regex)
    provider_ip_prefixes = jsonencode(join(",", var.cert_approver_provider_ip_prefixes))
    replicas             = var.cert_approver_replicas
    leader_election      = local.cert_approver_leader_election
  })

  # PSA-restricted floor + the six recommended labels for the module-seeded
  # cert-approver namespace. The seed is the SOLE owner (no steady-state
  # Application — the ADR-0002 sole-owner case, strictly simpler than the argocd
  # two-writer transfer). restricted (NOT argocd's baseline): low-replica
  # controller, no host access. managed-by=opentofu marks the seed as creator.
  # version = the approver image tag (the SEED knob).
  cert_approver_namespace_labels = {
    "app.kubernetes.io/name"                     = "kubelet-csr-approver"
    "app.kubernetes.io/instance"                 = "kubelet-csr-approver"
    "app.kubernetes.io/version"                  = "v1.2.14"
    "app.kubernetes.io/component"                = "cert-approver"
    "app.kubernetes.io/part-of"                  = "talos-platform-base"
    "app.kubernetes.io/managed-by"               = "opentofu"
    "pod-security.kubernetes.io/enforce"         = "restricted"
    "pod-security.kubernetes.io/enforce-version" = "latest"
    "pod-security.kubernetes.io/audit"           = "restricted"
    "pod-security.kubernetes.io/audit-version"   = "latest"
    "pod-security.kubernetes.io/warn"            = "restricted"
    "pod-security.kubernetes.io/warn-version"    = "latest"
  }

  # Controlplane inlineManifest seed, in apply order: (1) the namespace as a
  # SEPARATE entry FIRST (so the namespaced SA/Deployment land into an existing
  # namespace — the same Namespace-first ordering the argocd seed relies on),
  # (2) the vendored SA + signer-restricted ClusterRole/Binding + Service +
  # Deployment. The approver is cluster-scoped → it approves serving CSRs from ALL
  # nodes (incl. workers, which carry no inlineManifest seeds). Controlplane-only,
  # like the Cilium/ArgoCD seeds. Unconditional (always seeded).
  cert_approver_controlplane_patch = [yamlencode({
    cluster = {
      inlineManifests = [
        {
          name = "kubelet-csr-approver-namespace"
          contents = yamlencode({
            apiVersion = "v1"
            kind       = "Namespace"
            metadata = {
              name   = "kubelet-csr-approver"
              labels = local.cert_approver_namespace_labels
            }
          })
        },
        {
          name     = "kubelet-csr-approver"
          contents = local.cert_approver_manifest
        },
      ]
    }
  })]
}

# Cilium chart rendered locally into the inlineManifest (NO helm_release/apply).
# Floor values + module-computed install-time values + optional consumer override.
data "helm_template" "cilium" {
  count = var.deploy_cilium ? 1 : 0

  name         = "cilium"
  namespace    = var.cilium_namespace
  repository   = var.cilium_chart_repository
  chart        = "cilium"
  version      = var.cilium_chart_version
  kube_version = var.kubernetes_version
  # Cilium ships no CRDs that need the separate large-CRD treatment ArgoCD needs;
  # the chart's own CRDs render inline within the size budget (~66 KB total).
  include_crds = true

  values = compact([
    file("${path.module}/helm/cilium-values.yaml"),
    local.cilium_computed_values,
    var.cilium_values_override,
  ])

  # IPsec needs the pre-shared key (wireguard is keyless). Fail at plan time.
  lifecycle {
    precondition {
      condition     = var.cilium_encryption.type != "ipsec" || var.cilium_ipsec_key != ""
      error_message = "cilium_encryption.type = \"ipsec\" requires cilium_ipsec_key (the cilium-ipsec-keys Secret material)."
    }
    # native routing needs an IPv4 CIDR (the ipv4NativeRoutingCIDR field). Reject
    # native mode with an IPv6-only pod_cidr and no explicit cilium_native_routing_cidr,
    # rather than silently writing a v6 value into the v4 field.
    precondition {
      condition     = var.cilium_routing_mode != "native" || var.cilium_native_routing_cidr != "" || length(local.cilium_pod_v4) > 0
      error_message = "cilium_routing_mode = \"native\" needs an IPv4 CIDR: set cilium_native_routing_cidr or include an IPv4 entry in pod_cidr."
    }
    postcondition {
      # The render is frozen by terraform_data.cilium_render (ignore_changes), so an
      # empty/partial render would be captured once and NEVER self-healed by tofu
      # (recovery needs -replace) — a CNI-less control plane. Fail at plan time. #123.
      condition     = self.manifest != ""
      error_message = "data.helm_template.cilium rendered an EMPTY manifest — refusing to freeze an empty Cilium seed (would bootstrap a CNI-less cluster). Check cilium_chart_version / cilium_chart_repository / values."
    }
  }
}

# Freeze the Cilium seed render in state — same rationale as terraform_data.argocd_render
# (create-only inlineManifest seed; the helm render is not byte-stable; #121/#123). The
# Cilium chart additionally carries off-by-default Sprig genCA paths (clustermesh-apiserver
# TLS auto, SPIRE mutual-auth) that a consumer override could enable — freezing the consumed
# render fences those at the apply boundary too, regardless of override values. NO
# triggers_replace (create-only seed). Deliberate re-seed = `-replace`.
resource "terraform_data" "cilium_render" {
  count = var.deploy_cilium ? 1 : 0
  input = data.helm_template.cilium[0].manifest
  lifecycle {
    ignore_changes = [input]
  }
}

# ---------------------------------------------------------------------------
# Image-Factory: per distinct-schematic custom installer image
# ---------------------------------------------------------------------------
# Per distinct composed schematic (content-hashed in composition.tf), resolve the
# extension package names against the Talos Image Factory (concrete versions for
# the install version), commit them to a schematic (extensions + extraKernelArgs +
# optional SBC overlay), and derive the metal-installer URL per (schematic, arch).
# Empty extension sets yield the default Talos installer (no system extensions).
#
# Hard Constraint (base AGENTS.md): never use the SecureBoot installer image.
# secure_boot defaults to false in talos_image_factory_urls — we keep it that
# way. ARM single-board computers (e.g. Raspberry Pi) use architecture =
# "arm64" plus an overlay; the platform stays "metal".

# Per DISTINCT schematic (content-hash from local.schematics, composition.tf), not
# per class: identical nodes share one schematic + installer (auto-dedup), unique
# nodes get unique images — no 2^N hand-authored classes.
data "talos_image_factory_extensions_versions" "per_schematic" {
  for_each = local.schematics

  # Use the OS version actually being installed — extension package versions
  # are pinned per Talos release in the factory.
  talos_version = local.install_version
  filters = {
    names = each.value.extensions
  }
}

locals {
  # Exact-match the provider's substring-matching extension resolution back to
  # the declared (unioned) set: `filters.names` matches by substring, so a filter
  # of `siderolabs/gvisor` also resolves `siderolabs/gvisor-debug`. Intersecting
  # with the declared names bakes exactly what the union asked for. An empty
  # extension set yields [] (contains over an empty set is always false).
  official_extensions_by_schematic = {
    for h, s in local.schematics : h => [
      for ext in data.talos_image_factory_extensions_versions.per_schematic[h].extensions_info :
      ext.name if contains(s.extensions, ext.name)
    ]
  }
}

resource "talos_image_factory_schematic" "this" {
  for_each = local.schematics

  # A unioned extension that does not resolve to an exactly-matching canonical
  # Image Factory package — a typo, or a non-canonical short name like `gvisor`
  # that the substring filter expands but the exact intersection drops — would
  # otherwise silently bake an empty/partial extension set. Fail loudly instead.
  lifecycle {
    precondition {
      # Set-equality (not just count): declared is already distinct, the resolver
      # filters to declared (resolved ⊆ declared), so count-match PLUS resolved
      # having no duplicates ⟹ resolved set == declared set. The no-dup clause
      # closes the team-red hole where a duplicate canonical name balances the
      # count while a declared extension is silently dropped.
      condition = (
        length(distinct(each.value.extensions)) == length(local.official_extensions_by_schematic[each.key]) &&
        length(local.official_extensions_by_schematic[each.key]) == length(distinct(local.official_extensions_by_schematic[each.key]))
      )
      error_message = "schematic '${each.key}': not all unioned extensions resolved to canonical Image Factory packages for Talos ${local.install_version}. Declared ${jsonencode(distinct(each.value.extensions))}, resolved ${jsonencode(local.official_extensions_by_schematic[each.key])}. Use canonical names such as 'siderolabs/gvisor'."
    }
  }

  # systemExtensions (resolved exact-match) + extraKernelArgs (the v1.10+
  # UKI-correct boot-arg sink, only when non-empty) + overlay (only when present).
  schematic = yamlencode(merge(
    {
      customization = merge(
        {
          systemExtensions = {
            # Resolved + exact-matched in local.official_extensions_by_schematic:
            # the provider's filters.names substring match would otherwise pull in
            # unrequested extensions such as gvisor-debug. Empty set bakes nothing.
            officialExtensions = local.official_extensions_by_schematic[each.key]
          }
        },
        length(each.value.kernel_args) > 0 ? { extraKernelArgs = each.value.kernel_args } : {},
      )
    },
    each.value.overlay == null ? {} : {
      overlay = merge(
        {
          name  = each.value.overlay.name
          image = each.value.overlay.image
        },
        each.value.overlay.options == null ? {} : { options = each.value.overlay.options },
      )
    },
  ))
}

data "talos_image_factory_urls" "this" {
  for_each = local.installers

  # Installer image tag = the OS version we want running. Schema-version
  # `talos_version` stays out of this URL on purpose. One installer per
  # (schematic-hash, architecture); schematic_id is read as a VALUE, never as the
  # for_each key (which would be an unknown-at-plan resource attribute).
  talos_version = local.install_version
  schematic_id  = talos_image_factory_schematic.this[each.value.hash].id
  platform      = "metal"
  architecture  = each.value.arch

  # `tofu validate` does not resolve this data source, so an arch/overlay/
  # extension combination the Image Factory does not produce a metal installer
  # for (notably an arm64 SBC schematic) would otherwise surface as a silent
  # empty `machine.install.image`. Fail at PLAN time with a clear message.
  lifecycle {
    postcondition {
      condition     = self.urls.installer != ""
      error_message = "Image Factory returned no metal installer URL for schematic ${each.value.hash} (architecture ${each.value.arch}). Check the schematic extensions / SBC overlay coordinates."
    }
  }
}

# Cluster PKI + shared secrets. Generated once and stored in Tofu state — so
# the caller MUST use an encrypted state backend. NOTE: this generates fresh
# PKI. To adopt an ALREADY-RUNNING cluster without re-bootstrapping, do NOT
# apply blind — import this resource (and talos_machine_bootstrap.this) from the
# existing secrets first: `tofu import module.<name>.talos_machine_secrets.this
# <path-to-secrets.yaml>`. Full runbook: UPGRADING.md §"Adopting an
# already-running cluster". (talos_machine_configuration_apply is not importable;
# on the first post-import apply it re-pushes the rendered machine config, which
# EMBEDS this PKI — so the imported secrets.yaml MUST be the cluster's real
# current bundle, else mismatched PKI is pushed to live nodes.)
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version

  lifecycle {
    # Best-effort substring guard for the no-SecureBoot Hard Constraint (boot loops).
    # The module never emits a SecureBoot installer; this catches the common case of
    # a caller config_patch literally selecting one. It is a heuristic, not complete
    # enforcement (see the local.all_caller_patches note) — schematic-level/renamed
    # SecureBoot is consumer-overlay responsibility.
    precondition {
      condition     = length(local.secureboot_patches) == 0
      error_message = "A config_patch selects a SecureBoot installer image (a *-secureboot reference). The base Hard Constraint forbids SecureBoot (boot loops) — use the non-secureboot installer."
    }
    # Talos podSubnets/serviceSubnets carry the FULL pod_cidr/service_cidr lists,
    # but the Cilium seed enables ipv6 ONLY when var.dual_stack (the `ipv6.enabled`
    # key downstream). So the IP family of the CIDRs and the dual_stack flag must
    # agree in BOTH directions, else Talos and Cilium silently disagree:
    #   dual_stack = true  -> each list MUST carry a v4 AND a v6 entry
    #   dual_stack = false -> each list MUST be v4-only (a v6 entry needs dual_stack;
    #                         the module's Cilium seed has no v6-only single-stack path)
    # ":" marks IPv6, matching local.cilium_pod_v4/v6. The per-variable validation
    # (length + cidrhost format) cannot see dual_stack — this is the cross-field guard,
    # bidirectional so neither mismatch direction slips through.
    # SCOPE (best-effort, like the SecureBoot guard above): this guards the TYPED
    # inputs only. It does NOT inspect var.config_patches — a caller that overrides
    # cluster.network.podSubnets via a raw config_patch can still desync Talos from
    # the Cilium seed; raw-patch correctness is consumer-overlay responsibility
    # (AGENTS.md "Out of scope for the base"). It also checks family PRESENCE, not
    # count — Kubernetes/Talos enforce the one-CIDR-per-family dual-stack rule at apply.
    precondition {
      condition = var.dual_stack ? (
        anytrue([for c in var.pod_cidr : !strcontains(c, ":")]) &&
        anytrue([for c in var.pod_cidr : strcontains(c, ":")]) &&
        anytrue([for c in var.service_cidr : !strcontains(c, ":")]) &&
        anytrue([for c in var.service_cidr : strcontains(c, ":")])
        ) : (
        !anytrue([for c in var.pod_cidr : strcontains(c, ":")]) &&
        !anytrue([for c in var.service_cidr : strcontains(c, ":")])
      )
      error_message = "pod_cidr/service_cidr IP families must match dual_stack: dual_stack = true requires each to carry both an IPv4 and an IPv6 CIDR; dual_stack = false requires each to be IPv4-only (a \":\"-bearing IPv6 entry needs dual_stack = true; v6-only single-stack is unsupported). Got dual_stack=${var.dual_stack}, pod_cidr=${jsonencode(var.pod_cidr)}, service_cidr=${jsonencode(var.service_cidr)}."
    }
  }
}

# Base machine configuration per role. Cluster-specific patches are layered on
# by the caller via var.config_patches (all) and the role-specific lists.
#
# Patch ORDER (both roles): base_cluster_patch + base_kubelet_rotation_patch
# (both overridable) FIRST so caller patches can override; base_cni_patch
# (authoritative cni:none + proxy) + the inlineManifest seeds LAST so they merge
# after caller patches and are not overridden. Rotation is all-nodes (the serving
# cert is per kubelet); the cert-approver seed is controlplane-only (workers carry
# no inlineManifest seeds — the controlplane approver approves worker serving CSRs
# cluster-wide). Extracted into named locals so the composition test binds to the
# EXACT list each data source receives (red-green: drop a patch and the matching
# output flips).
#
# SENSITIVITY SPLIT: the controlplane list is assembled as a NON-sensitive base
# (controlplane_base_patches) + the argocd/cilium seeds, which embed the
# sops-age-key / cilium-ipsec-key Secrets (sensitive). OpenTofu taints any
# expression derived from a sensitive value, so a contains() membership check over
# the full list would taint the wiring booleans and a (non-sensitive) root output
# would be rejected. The composition test therefore asserts wiring against
# controlplane_base_patches (non-sensitive), and the real data-source list is
# DERIVED from it so the red-green binding still holds. Talos COMBINES the
# cluster.inlineManifests from multiple config_patches (append/merge, NOT
# last-wins-replace — the pre-existing argocd+cilium two-seed arrangement proves
# that in prod: both come up), and each seed here carries a UNIQUE manifest name,
# so the seed ORDER among argocd/cilium/cert-approver does not affect correctness.
# (The exact append-vs-merge-by-name semantic is a homelab-apply predicate, but
# correctness holds under both; only last-wins-replace would break it, and prod
# falsifies that.)
locals {
  controlplane_base_patches = concat(
    [local.base_cluster_patch],
    [local.base_kubelet_rotation_patch],
    var.config_patches,
    var.controlplane_config_patches,
    local.base_cni_patch,
    local.gateway_api_patch,
    local.cert_approver_controlplane_patch,
  )
  controlplane_machine_config_patches = concat(
    local.controlplane_base_patches,
    local.argocd_controlplane_patch,
    local.cilium_controlplane_patch,
  )
  worker_machine_config_patches = concat(
    [local.base_cluster_patch],
    [local.base_kubelet_rotation_patch],
    var.config_patches,
    var.worker_config_patches,
    local.base_cni_patch,
  )
}

data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version
  config_patches     = local.controlplane_machine_config_patches
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version
  config_patches     = local.worker_machine_config_patches
}

# Apply the config to each node. Patches arrive in TWO passes:
#   Pass 1 (config generation — data.talos_machine_configuration above): all-nodes
#     (var.config_patches) then role (controlplane/worker_config_patches) are
#     baked into the base machine config that becomes machine_configuration_input.
#   Pass 2 (this apply, strategic-merge overlay, later wins): module
#     install.image + hostname (HostnameConfig, Talos >= 1.12), then the
#     module-generated capability patch, then node patches.
# NOTE: generated/node patches run AFTER the module's install.image patch, so a
# caller patch CAN override machine.install.image. The module selecting
# urls.installer (never urls.installer_secureboot) guarantees the MODULE itself
# never emits a SecureBoot installer. Caller-supplied patch CONTENT is the
# caller's responsibility: within this base repo, a SecureBoot installer string
# in any tofu/** file is caught by hard-constraints-check; a CONSUMER's own root
# and patch files live outside this repo's gate, and enforcing no-SecureBoot
# (incl. schematic-level secureboot toggles the URL grep cannot see) there is the
# consumer overlay's job — same substrate-only boundary as AGENTS.md
# §"Out of scope for the base".
resource "talos_machine_configuration_apply" "this" {
  for_each = local.nodes_by_hostname

  client_configuration = talos_machine_secrets.this.client_configuration
  machine_configuration_input = (
    each.value.role == "controlplane"
    ? data.talos_machine_configuration.controlplane.machine_configuration
    : data.talos_machine_configuration.worker.machine_configuration
  )
  node = each.value.ip

  config_patches = concat(
    [
      # install.image stays v1alpha1 (Hard Constraint: non-secureboot installer).
      yamlencode({
        machine = {
          install = {
            # Explicitly the NON-secureboot installer URL — `urls.installer`,
            # never `urls.installer_secureboot`. This is the code-level Hard
            # Constraint enforcement (AGENTS.md: no SecureBoot installer image);
            # the module cannot emit a SecureBoot installer through this path.
            image = data.talos_image_factory_urls.this[local.node_install_key[each.value.hostname]].urls.installer
          }
        }
      }),
      # Hostname via the Talos >= 1.12 HostnameConfig document. The legacy
      # machine.network.hostname (v1alpha1) conflicts with the provider-generated
      # HostnameConfig{auto: stable} ("static hostname is already set in v1alpha1
      # config"). Set the static hostname and delete the generated `auto`
      # (hostname/auto are mutually exclusive). Refs: siderolabs/talos#12541,#12573
      # (smira: "add auto: off"); siderolabs/terraform-provider-talos#296 ($patch
      # delete avoids the YAML off->false coercion that bites `auto: off`).
      yamlencode({
        apiVersion = "v1alpha1"
        kind       = "HostnameConfig"
        hostname   = each.value.hostname
        auto       = { "$patch" = "delete" }
      }),
    ],
    # Module-generated capability patch (machine.kernel.modules / sysctls /
    # nodeLabels from the node's hardware_capabilities). BEFORE node patches so a
    # raw per-node patch can still override a generated value (documented escape
    # hatch); base_cni_patch stays strictly last.
    local.node_generated_patches[each.value.hostname],
    each.value.config_patches,
    # base_cni_patch re-applied LAST in the apply pass too, so cni:none + proxy
    # win over a generated/node patch as well (not just the all-nodes/role patches of
    # pass 1). When deploy_cilium is true, Flannel must NOT come up via any patch
    # vector. install.image is intentionally NOT re-pinned here — per-node installer
    # override stays allowed, and the SecureBoot guard (a substring heuristic, see
    # talos_machine_secrets preconditions) covers the common recipe; schematic-level
    # SecureBoot remains consumer-overlay responsibility.
    local.base_cni_patch,
  )
}

# Bootstrap etcd on the first controlplane only. Must run after the config is
# applied; bootstrapping more than one node would split-brain etcd.
resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.this]

  node                 = local.first_controlplane.ip
  endpoint             = local.first_controlplane.ip
  client_configuration = talos_machine_secrets.this.client_configuration
}

# Pull the admin kubeconfig once the cluster is bootstrapped. Resource (not
# data source) per the talos provider >= 0.7 deprecation — the data source is
# scheduled for removal.
resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  node                 = local.first_controlplane.ip
  endpoint             = local.first_controlplane.ip
  client_configuration = talos_machine_secrets.this.client_configuration

  # Force a re-fetch (state-only destroy+recreate) when the advertised
  # cluster endpoint changes — kubeconfig-refresh.tf, issue #186. `node`/
  # `endpoint` above stay the Talos-API (talosclient, port 50000) dial
  # target and are intentionally NOT repointed at var.cluster_endpoint.
  lifecycle {
    replace_triggered_by = [terraform_data.kubeconfig_endpoint_marker]
  }
}

# talosconfig for day-2 talosctl access. Endpoints = controlplanes, nodes = all.
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for n in local.controlplanes : n.ip]
  nodes                = [for n in var.nodes : n.ip]
}

# BLOCK until the cluster is genuinely healthy: etcd quorum established, all
# nodes Ready, kubelet + apiserver responding. Without this `tofu apply` returns
# right after the bootstrap call — the apiserver isn't reachable yet and ArgoCD
# (inlineManifest) hasn't rolled out its pods. This health data source polls
# until healthy (or timeout); only afterwards does downstream tooling consider
# the cluster "online". depends_on the kubeconfig pull ensures the bootstrap has
# completed before we check.
data "talos_cluster_health" "this" {
  depends_on = [
    talos_machine_configuration_apply.this,
    talos_machine_bootstrap.this,
    talos_cluster_kubeconfig.this,
  ]

  client_configuration = talos_machine_secrets.this.client_configuration
  control_plane_nodes  = [for n in local.controlplanes : n.ip]
  worker_nodes         = [for n in var.nodes : n.ip if n.role == "worker"]
  endpoints            = [for n in local.controlplanes : n.ip]

  timeouts = {
    read = var.cluster_health_timeout
  }
}

# ---------------------------------------------------------------------------
# ArgoCD CRDs — applied via kubectl server-side, NOT in the inlineManifest
# ---------------------------------------------------------------------------
# The three ArgoCD CRDs (Application/ApplicationSet/AppProject) render to ~1.8 MB
# — far too large for a Talos inlineManifest (the app render is only ~109 KB, and
# Talos inlineManifests must stay minimal). So the inlineManifest carries only
# the namespace + sops-age-key + the ArgoCD app; the CRDs are applied here, by
# tofu, via kubectl server-side once the cluster is healthy (the health gate
# above is the depends_on). Server-side apply also sidesteps the >262 KB
# client-side last-applied-config annotation limit the ApplicationSet CRD trips.
#
# DECISION (#104, accepted 2026-06-03): kubectl-via-local-exec is the accepted
# apply mechanism. A declarative provider apply was considered and rejected — a
# hashicorp/kubernetes `kubernetes_manifest` needs API access at PLAN time, but
# the cluster does not exist until this same apply runs (it cannot bootstrap
# itself); a third-party `kubectl_manifest` provider trades a kubectl binary for a
# third-party provider dependency + ~1.8 MB of state bloat in a substrate module
# (worse footprint). Full rationale + alternatives:
# knowledge/decisions/0006-opentofu-cluster-lifecycle.md (2026-06-03 amendment) and the README.
# CONTRACT: every apply host MUST ship `kubectl` — a workstation has it via
# devbox; the Crossplane provider-terraform runner image MUST include it.
# OPEN: #104 item 2 (boot proof — CP boots, ArgoCD pods Ready once CRDs land)
# still needs a throwaway-cluster apply.

data "helm_template" "argocd_crds" {
  count = var.deploy_argocd ? 1 : 0

  name         = "argocd"
  namespace    = var.argocd_namespace
  repository   = "https://argoproj.github.io/argo-helm"
  chart        = "argo-cd"
  version      = var.argocd_chart_version
  kube_version = var.kubernetes_version
  include_crds = true
  set {
    name  = "crds.install"
    value = "true"
  }

  lifecycle {
    postcondition {
      # Frozen by terraform_data.argocd_crds_render — an empty CRD render would be
      # kubectl-applied as nothing and frozen until -replace. Fail at plan time. #123.
      condition     = self.manifest != ""
      error_message = "data.helm_template.argocd_crds rendered an EMPTY manifest — refusing to freeze empty ArgoCD CRDs. Check argocd_chart_version / repository."
    }
  }
}

# Freeze the ArgoCD CRD render — same decoupling as the seed renders, BUT this path is
# NOT create-only: the null_resource below is a deliberate Day-2 convergence that
# kubectl-applies the CRDs and SHOULD re-run on an intended chart/version bump. So unlike
# the seed freezes, this one carries triggers_replace.
#
# INVARIANT: triggers_replace MUST mirror EVERY render-affecting input of
# data.helm_template.argocd_crds, or an intended bump silently won't re-apply (the
# ignore_changes swallows the render delta). Today that data source reads only
# argocd_chart_version, argocd_namespace, kubernetes_version (no values block — unlike
# the argocd *seed*, which also layers argocd_values_override). Keep this list in sync
# if an input is ever added. check-render-determinism.sh asserts triggers_replace is
# PRESENT, not COMPLETE; this comment is the completeness binding. Result: re-capture +
# re-apply on an intended bump; no re-apply / local_file churn from pure render drift
# at identical inputs (#123).
resource "terraform_data" "argocd_crds_render" {
  count = var.deploy_argocd ? 1 : 0
  input = data.helm_template.argocd_crds[0].manifest
  triggers_replace = [
    var.argocd_chart_version,
    var.argocd_namespace,
    var.kubernetes_version,
  ]
  lifecycle {
    ignore_changes = [input]
  }
}

# kubeconfig on disk for the kubectl apply. Written under the module's .tmp/
# (gitignored); sensitive (admin kubeconfig).
resource "local_sensitive_file" "kubeconfig" {
  count           = var.deploy_argocd ? 1 : 0
  content         = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename        = "${path.module}/.tmp/${var.cluster_name}.kubeconfig"
  file_permission = "0600"
}

resource "local_file" "argocd_crds" {
  count    = var.deploy_argocd ? 1 : 0
  content  = terraform_data.argocd_crds_render[0].output
  filename = "${path.module}/.tmp/${var.cluster_name}-argocd.yaml"
}

resource "null_resource" "argocd_crds" {
  count      = var.deploy_argocd ? 1 : 0
  depends_on = [data.talos_cluster_health.this]

  # Re-run on an intended chart/version/namespace bump (the frozen render's
  # triggers_replace inputs), NOT on non-deterministic helm render drift (#123).
  triggers = {
    manifest_sha = sha256(terraform_data.argocd_crds_render[0].output)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    environment = { KUBECONFIG = local_sensitive_file.kubeconfig[0].filename }
    # Full ArgoCD render (app + CRDs) applied server-side: ensures the CRDs land
    # and converges the app the inlineManifest seeded at boot. Idempotent.
    command = "kubectl apply --server-side --force-conflicts -f ${local_file.argocd_crds[0].filename}"
  }
}

# ---------------------------------------------------------------------------
# Day-2 reconciliation — what the module handles and what stays out-of-band
# ---------------------------------------------------------------------------
# - Talos OS upgrade (talos_install_version bump — NOT talos_version, which is
#   the bootstrap schema-pin and stays fixed for the cluster's lifetime): the
#   new version flows through local.install_version into the per-node composed
#   Image-Factory installer URL and the machine.install.image patch. tofu
#   RENDERS the new installer URL and writes install.image into the machine
#   config, but apply-config alone does NOT re-image a node. The actual rolling
#   OS upgrade is out-of-band: the consumer's `task talos:upgrade:cluster` reads
#   the new installer URL + version from tfplan JSON (outputs installer_images +
#   talos_install_version) and runs `talosctl upgrade --image …:<version>`
#   idempotently per node; Talos rolls each node (cordon/drain + reboot). The
#   siderolabs/talos provider ships no OS-upgrade resource (same as k8s below).
#   See README §"Versions: schema-pin vs install-pin".
# - Image-Factory extension/overlay changes (images / hardware_capabilities /
#   profile-catalog edits): schematic_id and the installer_image URL change;
#   apply-config writes the new install.image, and the same out-of-band
#   `talosctl upgrade` step re-images the affected nodes (apply-config alone does not).
# - System-extension version pinning: data.talos_image_factory_extensions_versions
#   is re-evaluated on every apply against local.install_version; new official
#   versions become available when talos_install_version changes (the factory
#   pins extension versions to a Talos release).
#
# OUT OF SCOPE for now: Kubernetes version upgrade. The siderolabs/talos
# Terraform provider does NOT ship a `talos_cluster_kubernetes_upgrade`
# resource (status: provider release used by this module). For Kubernetes
# upgrades, run `talosctl upgrade-k8s --to <version>` against the cluster —
# this is the one Day-2 op that escapes the tofu apply loop. Tracked for
# follow-up when the provider exposes the upgrade as a resource.
