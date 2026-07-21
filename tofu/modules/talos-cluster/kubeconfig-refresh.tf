# Regeneration trigger for `talos_cluster_kubeconfig.this` (main.tf). The
# resource's own arguments (`node`/`endpoint = local.first_controlplane.ip`,
# `client_configuration`) do not change when only the advertised cluster
# endpoint moves — a VIP move, a DNS rename, or a control-plane node re-IP
# on a single-control-plane cluster where `cluster_endpoint` is expressed
# as that node's own IP (the seeder's `api_vip: ""` fallback is exactly
# this case, and is the strongest evidence this fix closes the #168/#186
# incident; on a VIP/DNS endpoint a plain node re-IP is correctly inert) —
# so the provider never re-fetches `kubeconfig_raw` and the emitted
# `server:` (which Talos derives from `var.cluster_endpoint` baked into
# the machine config at main.tf:674,684) goes stale. This marker's tracked
# `input` is `var.cluster_endpoint`; the dependent resource's
# `lifecycle.replace_triggered_by` (main.tf) keys off it so a changed
# endpoint forces a state-only destroy+recreate (re-fetch) of the
# kubeconfig. Issue #186.
#
# `input =` (not `triggers_replace`) is deliberate. Resolvable evidence,
# not a same-author citation: the `siderolabs/talos` provider schema
# (`tofu providers schema -json` for
# `registry.opentofu.org/siderolabs/talos`) shows
# `talos_cluster_kubeconfig.{endpoint,node}` carry no `ForceNew`, and its
# `Update()` only re-fetches on certificate near-expiry — so without this
# marker+lifecycle pair, an endpoint-only change is invisible to the
# resource and it never re-reads. The `input = var.x` marker plus
# `lifecycle { replace_triggered_by = [...] }` firing on a value change,
# and staying inert (marker created, dependent NOT replaced) when only
# newly added to existing state, was reproduced offline with OpenTofu
# 1.11.8 — a version-specific observation, not a semver-guaranteed
# provider property. The durable, re-runnable check for this wiring is
# scripts/check-kubeconfig-endpoint-regen.sh (wired into `task tofu:ci`),
# not this comment.
resource "terraform_data" "kubeconfig_endpoint_marker" {
  input = var.cluster_endpoint
}
