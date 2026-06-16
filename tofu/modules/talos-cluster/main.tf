# talos-cluster: turns a set of PXE-booted Talos maintenance-mode nodes into a
# bootstrapped Kubernetes cluster, and reconciles Kubernetes version + system
# extensions on subsequent applies. Hardware provisioning and PXE boot are
# out of scope (see lifecycle/ipxe + the DHCP/next-server setup).
#
# Flow:
#   image-factory per class (extensions -> schematic -> installer URL)
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

  # Node classes actually referenced by var.nodes. Used to verify each class
  # has a matching entry in var.classes before installer URLs are looked up.
  used_classes = distinct([for n in var.nodes : n.class])

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
    flatten([for c in var.classes : c.config_patches]),
    flatten([for n in var.nodes : n.config_patches]),
  )
  # Match the hyphenated SecureBoot installer forms (metal / installer / metal-installer
  # all share the `-secureboot` URL fragment). The full prefixed literals are
  # deliberately NOT written here — they would trip the repo's own
  # hard-constraints-check grep, which cannot tell a guard from a usage.
  secureboot_patches = [for p in local.all_caller_patches : p if can(regex("-secureboot", p))]
}

# Defensive cross-check: every class referenced by a node must be defined in
# var.classes. Failing here gives a clearer error than a missing map key.
check "node_class_defined" {
  assert {
    condition = alltrue([
      for c in local.used_classes : contains(keys(var.classes), c)
    ])
    error_message = format(
      "Every node.class must be a key in var.classes. Used by nodes: %v. Defined in classes: %v.",
      local.used_classes, keys(var.classes),
    )
  }
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
            metadata   = { name = var.argocd_namespace }
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
    var.cilium_gateway_api ? { gatewayAPI = { enabled = true } } : {},
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
# Image-Factory: per-class custom installer image
# ---------------------------------------------------------------------------
# Per class, resolve the extension package names against the Talos Image
# Factory (gets concrete versions for var.talos_version), commit them to a
# schematic (with an optional SBC board overlay), and derive the
# metal-installer URL at the class's architecture. Empty extension lists yield
# the default Talos installer (no system extensions) for that class.
#
# Hard Constraint (base AGENTS.md): never use the SecureBoot installer image.
# secure_boot defaults to false in talos_image_factory_urls — we keep it that
# way. ARM single-board computers (e.g. Raspberry Pi) use architecture =
# "arm64" plus an overlay; the platform stays "metal".

data "talos_image_factory_extensions_versions" "per_class" {
  for_each = var.classes

  # Use the OS version actually being installed — extension package versions
  # are pinned per Talos release in the factory.
  talos_version = local.install_version
  filters = {
    names = each.value.extensions
  }
}

locals {
  # Exact-match the provider's substring-matching extension resolution back to
  # the declared set: `filters.names` matches by substring, so a filter of
  # `siderolabs/gvisor` also resolves `siderolabs/gvisor-debug`. Intersecting
  # with the declared names bakes exactly what each class asked for. An empty
  # class `extensions` list yields [] (contains over an empty set is always
  # false), so no explicit length guard is needed.
  official_extensions_by_class = {
    for k, c in var.classes : k => [
      for ext in data.talos_image_factory_extensions_versions.per_class[k].extensions_info :
      ext.name if contains(c.extensions, ext.name)
    ]
  }
}

resource "talos_image_factory_schematic" "per_class" {
  for_each = var.classes

  # A declared extension that does not resolve to an exactly-matching canonical
  # Image Factory package — a typo, or a non-canonical short name like `gvisor`
  # that the substring filter expands but the exact intersection drops — would
  # otherwise silently bake an empty/partial extension set. Fail loudly instead.
  lifecycle {
    precondition {
      condition     = length(distinct(each.value.extensions)) == length(local.official_extensions_by_class[each.key])
      error_message = "class '${each.key}': not all declared extensions resolved to canonical Image Factory packages for Talos ${local.install_version}. Declared ${jsonencode(distinct(each.value.extensions))}, resolved ${jsonencode(local.official_extensions_by_class[each.key])}. Use canonical names such as 'siderolabs/gvisor'."
    }
  }

  # systemExtensions for every class; overlay block only for classes that
  # declare one (SBC boards such as Raspberry Pi).
  schematic = yamlencode(merge(
    {
      customization = {
        systemExtensions = {
          # Resolved + exact-matched in local.official_extensions_by_class (see
          # the locals block above): the provider's filters.names substring match
          # would otherwise pull in unrequested extensions such as gvisor-debug.
          # An empty class `extensions` list yields [] (bakes no extensions).
          officialExtensions = local.official_extensions_by_class[each.key]
        }
      }
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

data "talos_image_factory_urls" "per_class" {
  for_each = var.classes

  # Installer image tag = the OS version we want running. Schema-version
  # `talos_version` stays out of this URL on purpose. Architecture is per-class
  # so amd64 and arm64 (SBC) classes coexist in one cluster.
  talos_version = local.install_version
  schematic_id  = talos_image_factory_schematic.per_class[each.key].id
  platform      = "metal"
  architecture  = each.value.architecture

  # `tofu validate` does not resolve this data source, so an arch/overlay/
  # extension combination the Image Factory does not produce a metal installer
  # for (notably an arm64 SBC schematic) would otherwise surface as a silent
  # empty `machine.install.image`. Fail at PLAN time with a clear message.
  lifecycle {
    postcondition {
      condition     = self.urls.installer != ""
      error_message = "Image Factory returned no metal installer URL for class '${each.key}' (architecture ${each.value.architecture}). Check the schematic extensions / SBC overlay coordinates."
    }
  }
}

# Cluster PKI + shared secrets. Generated once and stored in Tofu state — so
# the caller MUST use an encrypted state backend. NOTE: this generates fresh
# PKI. To adopt an ALREADY-RUNNING cluster without re-bootstrapping, do NOT
# apply blind — import this resource (and talos_machine_bootstrap.this) from the
# existing secrets first: `tofu import module.<name>.talos_machine_secrets.this
# <path-to-secrets.yaml>`. Full runbook: UPGRADING.md §"Adopting an
# already-running cluster". (talos_machine is not importable; on the first
# post-import apply it re-pushes the rendered machine config, which EMBEDS this
# PKI — so the imported secrets.yaml MUST be the cluster's real current bundle,
# else mismatched PKI is pushed to live nodes.)
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
    # Fail clearly on a typo'd node.class before the cryptic installer-URL map-index
    # error (the existing check block only warns).
    precondition {
      condition     = alltrue([for n in var.nodes : contains(keys(var.classes), n.class)])
      error_message = "A node references an undefined class (typo?). Every node.class must be a key in var.classes. Defined: ${join(", ", keys(var.classes))}."
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

locals {
  # Drain only makes sense with more than one node: you cannot drain the sole
  # node of a single-node cluster and keep it healthy. So auto-upgrade clusters
  # with >1 node drain+uncordon each node around the reboot; single-node clusters
  # (e.g. the seeder) upgrade in place without drain. Gated on auto_os_upgrade so
  # the ephemeral kubeconfig below only materialises when tofu drives upgrades.
  drain_on_upgrade = var.auto_os_upgrade && length(var.nodes) > 1
}

# Per-node machine configuration. The talos_machine resource (provider >= 0.12)
# consumes the FULLY-RENDERED machine_configuration and has no config_patches of
# its own — unlike the retired talos_machine_configuration_apply. So the former
# TWO-PASS layering (one role-level data source + a per-node apply patch pass)
# COLLAPSES into this single per-node render: role/all-node patches AND the
# per-node install.image + HostnameConfig + class/node patches are folded into
# one config_patches list. Strategic-merge order is preserved from the two-pass
# era — base_cluster FIRST (caller-overridable), then caller all-node + role
# patches, then the module install.image, then class then node patches (so a
# class/node patch can still override install.image, as before), then the
# controlplane-only inlineManifest seeds, and base_cni_patch LAST so the
# authoritative cni:none + proxy always win over any class/node patch.
data "talos_machine_configuration" "per_node" {
  for_each = local.nodes_by_hostname

  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = each.value.role
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version

  config_patches = concat(
    [local.base_cluster_patch],
    var.config_patches,
    each.value.role == "controlplane" ? var.controlplane_config_patches : var.worker_config_patches,
    [
      # install.image stays v1alpha1 (Hard Constraint: non-secureboot installer).
      # Explicitly the NON-secureboot installer URL — `urls.installer`, never
      # `urls.installer_secureboot`. This is the code-level Hard Constraint
      # enforcement (AGENTS.md: no SecureBoot installer image); the module cannot
      # emit a SecureBoot installer through this path. This is what Talos uses at
      # install time regardless of auto_os_upgrade; the talos_machine `image`
      # argument below governs only the in-place UPGRADE on a version bump.
      yamlencode({
        machine = {
          install = {
            image = data.talos_image_factory_urls.per_class[each.value.class].urls.installer
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
    var.classes[each.value.class].config_patches,
    each.value.config_patches,
    # Controlplane-only inlineManifest seeds (Gateway API CRDs + ArgoCD + Cilium).
    # Workers carry none. These merge after caller patches and are not overridden.
    each.value.role == "controlplane" ? concat(
      local.gateway_api_patch,
      local.argocd_controlplane_patch,
      local.cilium_controlplane_patch,
    ) : [],
    # base_cni_patch LAST so cni:none + proxy win over any class/node patch (when
    # deploy_cilium is true, Flannel must NOT come up via any patch vector).
    local.base_cni_patch,
  )
}

# Apply the config to each node AND keep the OS version in sync. talos_machine
# (provider >= 0.12) replaces talos_machine_configuration_apply: on every refresh
# it reads the running Talos version + active config hash from the node and, on
# the next apply, reconciles drift — re-applying config or upgrading the OS.
resource "talos_machine" "this" {
  for_each = local.nodes_by_hostname

  node                  = each.value.ip
  endpoint              = each.value.ip
  client_configuration  = talos_machine_secrets.this.client_configuration
  machine_configuration = data.talos_machine_configuration.per_node[each.key].machine_configuration

  # OS-version management is OPT-IN (var.auto_os_upgrade):
  #   false (default) → image omitted → talos_machine does NOT manage the OS
  #     version. Initial install still uses machine.install.image from the config
  #     above; OS upgrades stay the consumer's controlled `task talos:upgrade:
  #     cluster` (laptop/TeamCity) path — unchanged from the apply era.
  #   true → image = the per-class non-secureboot installer → bumping
  #     talos_install_version drives an in-place OS upgrade on the next apply
  #     (fully GitOps/Crossplane-driven; no talosctl, no manual reboot).
  image = var.auto_os_upgrade ? data.talos_image_factory_urls.per_class[each.value.class].urls.installer : null

  # Multi-node: drain + uncordon around the reboot (needs a kubeconfig). The
  # ephemeral kubeconfig below is derived from machine_secrets WITHOUT depending
  # on the running cluster, so it breaks the bootstrap cycle (talos_cluster_
  # kubeconfig.this depends on bootstrap depends on talos_machine). Single-node:
  # drain disabled, no kubeconfig needed.
  drain_on_upgrade = local.drain_on_upgrade
  kubeconfig_wo    = local.drain_on_upgrade ? ephemeral.talos_cluster_kubeconfig.drain[0].kubeconfig_raw : null

  # NOTE: multi-node parallel upgrades risk losing etcd quorum. talos_machine is
  # for_each'd here (no inter-node depends_on chain), so multi-node consumers must
  # run upgrades with `-parallelism=1`, or a future revision adds explicit
  # sequencing. Single-node (seeder) is unaffected. See PR discussion.
}

# Ephemeral kubeconfig for the drain path only (multi-node auto-upgrade). Derived
# from machine_secrets, so it exists before the cluster is up and avoids a cycle.
# Write-only (kubeconfig_wo) + ephemeral both require OpenTofu >= 1.11.
ephemeral "talos_cluster_kubeconfig" "drain" {
  count = local.drain_on_upgrade ? 1 : 0

  machine_secrets = talos_machine_secrets.this.machine_secrets
  cluster_name    = var.cluster_name
  endpoint        = local.first_controlplane.ip
}

# Bootstrap etcd on the first controlplane only. Must run after the config is
# applied; bootstrapping more than one node would split-brain etcd.
resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine.this]

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
    talos_machine.this,
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
# docs/adr-opentofu-cluster-lifecycle.md (2026-06-03 amendment) and the README.
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
#   new version flows through local.install_version into the per-class
#   Image-Factory installer URL and the machine.install.image patch. tofu
#   RENDERS the new installer URL and writes install.image into the machine
#   config, but apply-config alone does NOT re-image a node. The actual rolling
#   OS upgrade is out-of-band: the consumer's `task talos:upgrade:cluster` reads
#   the new installer URL + version from tfplan JSON (outputs installer_images +
#   talos_install_version) and runs `talosctl upgrade --image …:<version>`
#   idempotently per node; Talos rolls each node (cordon/drain + reboot). The
#   siderolabs/talos provider ships no OS-upgrade resource (same as k8s below).
#   See README §"Versions: schema-pin vs install-pin".
# - Image-Factory extension/overlay changes (var.classes edits): schematic_id
#   and the installer_image URL change; apply-config writes the new
#   install.image, and the same out-of-band `talosctl upgrade` step re-images
#   the affected class's nodes (apply-config alone does not).
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
