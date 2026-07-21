# Regeneration trigger for `talos_cluster_kubeconfig.this` (main.tf). The
# resource's own arguments (`node`/`endpoint = local.first_controlplane.ip`,
# `client_configuration`) do not change when only the advertised cluster
# endpoint moves (VIP move, DNS rename, or a single-node re-IP the consumer
# also reflects into `cluster_endpoint`), so the provider never re-fetches
# `kubeconfig_raw` and the emitted `server:` (which Talos derives from
# `var.cluster_endpoint` baked into the machine config at main.tf:674,684)
# goes stale. This marker's tracked `input` is `var.cluster_endpoint`; the
# dependent resource's `lifecycle.replace_triggered_by` (main.tf) keys off it
# so a changed endpoint forces a state-only destroy+recreate (re-fetch) of
# the kubeconfig. Issue #186.
#
# `input =` (not `triggers_replace`) is deliberate and empirically confirmed:
# with the built-in `terraform_data` resource, `input = var.x` on the marker
# plus `lifecycle { replace_triggered_by = [...] }` on the dependent fires a
# replace when `var.x` changes, and creates the marker with NO dependent
# replacement when only newly added to existing state (endpoint unchanged) —
# see CHANGELOG.md (Unreleased, this entry) for the resolvable citation.
resource "terraform_data" "kubeconfig_endpoint_marker" {
  input = var.cluster_endpoint
}
