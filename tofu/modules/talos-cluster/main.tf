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
      condition     = var.sops_age_key != ""
      error_message = "deploy_argocd = true requires sops_age_key (the ArgoCD ksops repoServer needs the age key to decrypt SOPS manifests)."
    }
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
          contents = data.helm_template.argocd[0].manifest
        },
      ]
    }
  })] : []
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

resource "talos_image_factory_schematic" "per_class" {
  for_each = var.classes

  # systemExtensions for every class; overlay block only for classes that
  # declare one (SBC boards such as Raspberry Pi).
  schematic = yamlencode(merge(
    {
      customization = {
        systemExtensions = {
          officialExtensions = [
            for ext in data.talos_image_factory_extensions_versions.per_class[each.key].extensions_info :
            ext.name
          ]
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
# already-running cluster". (talos_machine_configuration_apply is not importable;
# on the first post-import apply it re-pushes the rendered machine config, which
# EMBEDS this PKI — so the imported secrets.yaml MUST be the cluster's real
# current bundle, else mismatched PKI is pushed to live nodes.)
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

# Base machine configuration per role. Cluster-specific patches are layered on
# by the caller via var.config_patches (all) and the role-specific lists.
data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version
  # ArgoCD inlineManifest (local.argocd_controlplane_patch, empty when !deploy_argocd)
  # LAST, so it merges after caller patches and is not overridden.
  config_patches = concat(
    var.config_patches,
    var.controlplane_config_patches,
    local.argocd_controlplane_patch,
  )
}

data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  kubernetes_version = var.kubernetes_version
  talos_version      = var.talos_version
  config_patches     = concat(var.config_patches, var.worker_config_patches)
}

# Apply the config to each node. Patches arrive in TWO passes:
#   Pass 1 (config generation — data.talos_machine_configuration above): all-nodes
#     (var.config_patches) then role (controlplane/worker_config_patches) are
#     baked into the base machine config that becomes machine_configuration_input.
#   Pass 2 (this apply, strategic-merge overlay, later wins): module
#     hostname + install.image, then class patches, then node patches.
# NOTE: class/node patches run AFTER the module's install.image patch, so a
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
      yamlencode({
        machine = {
          network = {
            hostname = each.value.hostname
          }
          install = {
            # Explicitly the NON-secureboot installer URL — `urls.installer`,
            # never `urls.installer_secureboot`. This is the code-level Hard
            # Constraint enforcement (AGENTS.md: no SecureBoot installer image);
            # the module cannot emit a SecureBoot installer through this path.
            image = data.talos_image_factory_urls.per_class[each.value.class].urls.installer
          }
        }
      })
    ],
    var.classes[each.value.class].config_patches,
    each.value.config_patches,
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
  content  = data.helm_template.argocd_crds[0].manifest
  filename = "${path.module}/.tmp/${var.cluster_name}-argocd.yaml"
}

resource "null_resource" "argocd_crds" {
  count      = var.deploy_argocd ? 1 : 0
  depends_on = [data.talos_cluster_health.this]

  # Re-run when the rendered manifest changes (chart/version bump).
  triggers = {
    manifest_sha = sha256(data.helm_template.argocd_crds[0].manifest)
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
# - Talos OS upgrade (var.talos_version bump): the new version flows into
#   data.talos_machine_configuration AND into the per-class installer image
#   from the Image Factory. talos_machine_configuration_apply re-renders the
#   per-node config (including install.image) and applies it rolling — Talos
#   takes care of the actual upgrade.
# - Image-Factory extension/overlay changes (var.classes edits): schematic_id
#   changes, installer_image URL changes, machine_configuration_apply re-rolls
#   nodes of the affected class.
# - System-extension version pinning: data.talos_image_factory_extensions_versions
#   is re-evaluated on every apply; new official versions become available
#   when var.talos_version changes (the factory pins extension versions to a
#   Talos release).
#
# OUT OF SCOPE for now: Kubernetes version upgrade. The siderolabs/talos
# Terraform provider does NOT ship a `talos_cluster_kubernetes_upgrade`
# resource (status: provider release used by this module). For Kubernetes
# upgrades, run `talosctl upgrade-k8s --to <version>` against the cluster —
# this is the one Day-2 op that escapes the tofu apply loop. Tracked for
# follow-up when the provider exposes the upgrade as a resource.
