# Apply only CRDs after cluster health: they are too large for the inlineManifest seed.
# The apply host must provide kubectl.

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
      condition     = self.manifest != ""
      error_message = "data.helm_template.argocd_crds rendered an EMPTY manifest — refusing to freeze empty ArgoCD CRDs. Check argocd_chart_version / repository."
    }
  }
}

locals {
  # Read the live render once; freeze the CRD-only projection below.
  argocd_crd_source_docs = var.deploy_argocd ? split("\n---\n", data.helm_template.argocd_crds[0].manifest) : []

  argocd_crd_docs = [
    for doc in local.argocd_crd_source_docs :
    doc if try(yamldecode(doc).kind, "") == "CustomResourceDefinition"
  ]
  argocd_crd_manifest = join("\n---\n", local.argocd_crd_docs)

  # Reject undecodable fragments before filtering: splitting an embedded separator could truncate a CRD.
  argocd_crd_undecodable = [
    for doc in local.argocd_crd_source_docs :
    substr(trimspace(doc), 0, 80) if trimspace(doc) != "" && try(yamldecode(doc), null) == null
  ]

  # Audit the final payload, not the list used to build it.
  argocd_crd_payload_docs = split("\n---\n", local.argocd_crd_manifest)
  argocd_crd_kinds = local.argocd_crd_manifest == "" ? [] : distinct([
    for doc in local.argocd_crd_payload_docs : try(yamldecode(doc).kind, "<unparseable>")
  ])
  argocd_crd_names = local.argocd_crd_manifest == "" ? [] : sort([
    for doc in local.argocd_crd_payload_docs : try(yamldecode(doc).metadata.name, "<unparseable>")
  ])
  argocd_expected_crds = [
    "applications.argoproj.io",
    "applicationsets.argoproj.io",
    "appprojects.argoproj.io",
  ]
}

# Re-capture only when payload inputs change. Keep triggers_replace complete.
# The pinned CRD templates do not depend on Kubernetes version; recheck on chart upgrades.
resource "terraform_data" "argocd_crds_render" {
  count = var.deploy_argocd ? 1 : 0
  input = local.argocd_crd_manifest
  triggers_replace = [
    var.argocd_chart_version,
    var.argocd_namespace,
    # Bump when projection semantics change so existing state captures the new payload.
    "crd-projection-v1",
  ]
  lifecycle {
    ignore_changes = [input]
    precondition {
      condition     = alltrue([for n in local.argocd_expected_crds : contains(local.argocd_crd_names, n)])
      error_message = "argocd CRD projection is missing ${jsonencode(setsubtract(local.argocd_expected_crds, local.argocd_crd_names))} — produced ${jsonencode(local.argocd_crd_names)}; the chart render shape changed, check the split/yamldecode filter in argocd-crds.tf."
    }
    precondition {
      condition     = alltrue([for k in local.argocd_crd_kinds : k == "CustomResourceDefinition"])
      error_message = "argocd CRD projection carries non-CRD documents ${jsonencode(setsubtract(local.argocd_crd_kinds, ["CustomResourceDefinition"]))} — the Day-0 apply must deliver CustomResourceDefinitions and nothing else (knowledge/decisions/0025-argocd-crd-apply-scope.md); check the kind filter in argocd-crds.tf."
    }
    precondition {
      condition     = length(local.argocd_crd_undecodable) == 0
      error_message = "argocd CRD render contains ${length(local.argocd_crd_undecodable)} document(s) that do not parse as YAML, starting with ${jsonencode(local.argocd_crd_undecodable)} — the kind filter would drop them silently. If a CRD's embedded schema now contains a line matching the document separator, the surviving half is a TRUNCATED CRD; do not apply it."
    }
  }
}

resource "local_sensitive_file" "kubeconfig" {
  count           = var.deploy_argocd ? 1 : 0
  content         = talos_cluster_kubeconfig.this.kubeconfig_raw
  filename        = "${path.module}/.tmp/${var.cluster_name}.kubeconfig"
  file_permission = "0600"
}

resource "local_file" "argocd_crds" {
  count    = var.deploy_argocd ? 1 : 0
  content  = terraform_data.argocd_crds_render[0].output
  filename = "${path.module}/.tmp/${var.cluster_name}-argocd-crds.yaml"
}

resource "null_resource" "argocd_crds" {
  count      = var.deploy_argocd ? 1 : 0
  depends_on = [data.talos_cluster_health.this]

  triggers = {
    manifest_sha = sha256(terraform_data.argocd_crds_render[0].output)
  }

  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    environment = { KUBECONFIG = local_sensitive_file.kubeconfig[0].filename }
    # Never force conflicts: ArgoCD owns the CRDs after bootstrap. Use a dedicated field manager.
    command = "kubectl apply --server-side --field-manager=talos-platform-base-day0 -f ${local_file.argocd_crds[0].filename}"
  }
}
