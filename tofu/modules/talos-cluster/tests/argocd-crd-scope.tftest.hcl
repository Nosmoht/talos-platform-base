# Network-bound (renders the argo-cd chart): runs under `task tofu:test` only.
# The frozen render is unknown at plan, so the projection is asserted through
# output.argocd_day0_apply_kinds.

provider "talos" {}
provider "helm" {}

# Keeps the Image Factory out of this suite; its image requests no extensions.
override_data {
  target = data.talos_image_factory_extensions_versions.per_schematic
  values = {
    extensions_info = []
  }
}

variables {
  cluster_name       = "test"
  cluster_endpoint   = "https://192.0.2.1:6443"
  talos_version      = "v1.13.9"
  kubernetes_version = "v1.36.3"
  deploy_argocd      = true
  deploy_cilium      = false
  sops_age_key       = "AGE-SECRET-KEY-1TESTONLYPLACEHOLDERNOTAREALKEY00000000000000000000000000000"

  images = {
    intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [] }
  }
  hardware_capabilities = {}
  nodes = {
    cp-1 = { ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
  }
}

run "day0_apply_manifest_carries_crds_only" {
  command = plan

  # length + contains rather than ==: the output is a list and the literal a
  # tuple, so a direct comparison fails on type even when the elements match.
  assert {
    condition = (
      length(output.argocd_day0_apply_kinds) == 1 &&
      contains(output.argocd_day0_apply_kinds, "CustomResourceDefinition")
    )
    error_message = "the Day-0 apply must deliver CustomResourceDefinitions and nothing else; got ${jsonencode(output.argocd_day0_apply_kinds)} — chart-default workloads/ConfigMaps leaked past the projection in argocd-crds.tf (local.argocd_crd_docs) and would be applied over ArgoCD's own state"
  }

  # distinct() collapses one and three CRDs to the same kind set; assert by name.
  assert {
    condition = alltrue([
      for n in ["applications.argoproj.io", "applicationsets.argoproj.io", "appprojects.argoproj.io"] :
      contains(output.argocd_day0_apply_crd_names, n)
    ])
    error_message = "the Day-0 apply must deliver all three ArgoCD CRDs; got ${jsonencode(output.argocd_day0_apply_crd_names)}"
  }

  assert {
    condition = !(
      contains(output.argocd_day0_apply_kinds, "<unparseable>") ||
      contains(output.argocd_day0_apply_crd_names, "<unparseable>")
    )
    error_message = "a document in the applied manifest does not decode as YAML — the \"\\n---\\n\" split cut inside a document (an embedded OpenAPI schema line that is exactly ---, say), so the payload carries a truncated CRD"
  }
}

# triggers_replace omits kubernetes_version, so the CRD set must not depend on it.
run "crd_payload_structure_is_independent_of_kubernetes_version" {
  command = plan
  variables {
    kubernetes_version = "v1.31.0"
  }

  assert {
    condition = (
      length(output.argocd_day0_apply_kinds) == 1 &&
      contains(output.argocd_day0_apply_kinds, "CustomResourceDefinition") &&
      alltrue([
        for n in ["applications.argoproj.io", "applicationsets.argoproj.io", "appprojects.argoproj.io"] :
        contains(output.argocd_day0_apply_crd_names, n)
      ])
    )
    error_message = "the CRD payload changed shape at a different Kubernetes version — kinds ${jsonencode(output.argocd_day0_apply_kinds)} names ${jsonencode(output.argocd_day0_apply_crd_names)}. The chart now templates its CRDs, so kubernetes_version must go back into terraform_data.argocd_crds_render.triggers_replace (argocd-crds.tf) or an intended bump will not re-apply."
  }
}

run "no_day0_apply_when_argocd_disabled" {
  command = plan
  variables {
    deploy_argocd = false
    sops_age_key  = ""
  }

  assert {
    condition = (
      length(output.argocd_day0_apply_kinds) == 0 &&
      length(output.argocd_day0_apply_crd_names) == 0
    )
    error_message = "with deploy_argocd = false the module must apply nothing; got kinds ${jsonencode(output.argocd_day0_apply_kinds)} names ${jsonencode(output.argocd_day0_apply_crd_names)}"
  }
}
