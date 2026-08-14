# Day-0 ArgoCD apply scope (#218).
#
# The module kubectl-applies the frozen argocd render after the health gate. Its
# data source renders the chart with NO values block, so the non-CRD half is pure
# chart defaults — bundled Dex on, argocd-cm/argocd-rbac-cm at upstream values.
# Applying that half converged the seeded app onto the wrong values and, with
# --force-conflicts, took field-manager ownership of the ConfigMaps ArgoCD
# self-management and consumer overlays own.
#
# main.tf therefore projects the render down to CustomResourceDefinition
# documents BEFORE the freeze. These runs bind that projection.
#
# Red-green: drop the `if try(yamldecode(doc).kind, "") == "CustomResourceDefinition"`
# filter from local.argocd_crd_docs and the first assert fails (the chart-default
# workloads and ConfigMaps reappear in the kind set).
#
# The projection is asserted through output.argocd_day0_apply_kinds rather than
# local_file.argocd_crds[0].content, because the frozen terraform_data output is
# unknown until apply and cannot be evaluated in a plan-only test. Completeness
# of the CRD set (all three must survive) is carried by the plan-time precondition
# on terraform_data.argocd_crds_render, not by an assert here.
#
# command = plan. deploy_argocd = true renders the argo-cd chart (NETWORK) and
# needs a prefix-valid age key — so this file belongs to the network-gated
# `task tofu:test`, not the offline `task tofu:ci`.

provider "talos" {}
provider "helm" {}

variables {
  cluster_name       = "test"
  cluster_endpoint   = "https://192.0.2.1:6443"
  talos_version      = "v1.12.6"
  kubernetes_version = "v1.35.0"
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
    error_message = "the Day-0 apply must deliver CustomResourceDefinitions and nothing else; got ${jsonencode(output.argocd_day0_apply_kinds)} — chart-default workloads/ConfigMaps leaked past the projection in main.tf (local.argocd_crd_docs) and would be applied over ArgoCD's own state"
  }
}

# deploy_argocd = false must not merely skip the apply — the projection locals
# must degrade to empty rather than erroring on the absent data source.
run "no_day0_apply_when_argocd_disabled" {
  command = plan
  variables {
    deploy_argocd = false
    sops_age_key  = ""
  }

  assert {
    condition     = length(output.argocd_day0_apply_kinds) == 0
    error_message = "with deploy_argocd = false the module must apply nothing; got ${jsonencode(output.argocd_day0_apply_kinds)}"
  }
}
