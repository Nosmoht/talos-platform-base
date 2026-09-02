# Day-0 chart integrity pins. The archives remain public and are downloaded into
# the caller's local .terraform cache; only these small declarations ship in the
# module. data.external runs the verifier before either local Helm render.
locals {
  argocd_chart_sha256 = "5cf2184bcccd3ae5bd1e3abf35342553fdba5c4ff8bee1aefdd6e76ee7b00e4d"
  cilium_chart_sha256 = "c5f013912360d1a334f44ef25f36da59ba3414cdb48f466ee12d0c4fdff27883"

  chart_cache_dir      = "${abspath(path.root)}/.terraform/talos-platform-base/charts"
  argocd_chart_archive = "${local.chart_cache_dir}/argo-cd-${var.argocd_chart_version}-${substr(local.argocd_chart_sha256, 0, 12)}.tgz"
  cilium_chart_archive = "${local.chart_cache_dir}/cilium-${var.cilium_chart_version}-${substr(local.cilium_chart_sha256, 0, 12)}.tgz"

  argocd_chart_url = "https://github.com/argoproj/argo-helm/releases/download/argo-cd-${var.argocd_chart_version}/argo-cd-${var.argocd_chart_version}.tgz"
  cilium_chart_url = "${trimsuffix(var.cilium_chart_repository, "/")}/cilium-${var.cilium_chart_version}.tgz"
}

data "external" "argocd_chart" {
  count = var.deploy_argocd ? 1 : 0

  program = [
    "${path.module}/scripts/fetch-verified-chart.sh",
    local.argocd_chart_url,
    local.argocd_chart_sha256,
    local.argocd_chart_archive,
  ]

  lifecycle {
    postcondition {
      condition     = self.result.verified == "true"
      error_message = "The downloaded argo-cd chart was not verified."
    }
  }
}

data "external" "cilium_chart" {
  count = var.deploy_cilium ? 1 : 0

  program = [
    "${path.module}/scripts/fetch-verified-chart.sh",
    local.cilium_chart_url,
    local.cilium_chart_sha256,
    local.cilium_chart_archive,
  ]

  lifecycle {
    postcondition {
      condition     = self.result.verified == "true"
      error_message = "The downloaded Cilium chart was not verified."
    }
  }
}
