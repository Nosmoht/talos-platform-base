# Node identity model.
#
# var.nodes IS the node set, keyed by node name — one node, one definition
# place, uniqueness by construction rather than by an added-on check. Everything
# Talos-facing below is a generated VIEW of that map, never a second container.
#
# Provider-less by design (pure var.*-derived locals), so a test fixture can
# symlink this file and assert the projections offline — same reason
# cilium-values.tf is its own file.

locals {
  # The IP is the second identifier that must not collide: it is what talosctl
  # targets and what fills every Talos-facing argument. But it is a VALUE, not a
  # key, so it gets its own keyed view — two nodes sharing an IP produce a
  # plan-time "Duplicate object key" here.
  #
  # It maps IP -> node NAME, and every hostname-keyed view below is derived
  # THROUGH it. That is deliberate: the guard sits in the dependency chain, so it
  # cannot be reduced to an unreferenced local (which OpenTofu would never
  # evaluate) by a later "simplify redundant indexing" refactor. var.nodes' own
  # ip-distinct validation still fires first with a readable message; this is the
  # structural backstop behind it.
  node_name_by_ip = { for h, n in var.nodes : n.ip => h }

  # The node set, re-keyed by name THROUGH the IP guard. Same keys and values as
  # var.nodes — the round trip exists so both identifiers are checked before
  # anything downstream reads a node.
  nodes_checked = { for ip, h in local.node_name_by_ip : h => var.nodes[h] }

  # Role views, NOT containers. `role` is single-valued and enum-validated, so
  # controlplanes and workers are disjoint by construction: no IP can appear in
  # both control_plane_nodes and worker_nodes.
  controlplanes_by_hostname = { for h, n in local.nodes_checked : h => n if n.role == "controlplane" }
  workers_by_hostname       = { for h, n in local.nodes_checked : h => n if n.role == "worker" }

  # Bootstrap target + the node we pull kubeconfig/talosconfig from: the
  # lowest-named controlplane. A STABLE key, so re-declaring the node set cannot
  # move which node is bootstrapped (talos_machine_bootstrap is pinned to this
  # node's IP). NOTE: it moves if a controlplane sorting BELOW the incumbent is
  # ADDED — see README §Notes and UPGRADING before growing a control plane.
  first_controlplane = local.controlplanes_by_hostname[keys(local.controlplanes_by_hostname)[0]]

  # Generated lists for the provider boundary. The talos provider types
  # control_plane_nodes / worker_nodes / endpoints / nodes as list(string)
  # (ListAttribute, element type StringType) — a map is impossible AT the
  # boundary. So the map is the MODEL and these are its projections.
  #
  # They are ordered by node name BY CONSTRUCTION, not by a sort() call: an
  # OpenTofu `for` expression over a map yields keys in lexicographic order, and
  # `keys()` likewise. A sort() here would be a no-op — and a misleading one,
  # since removing it would change nothing and so could never be the mutant that
  # binds the ordering contract. What binds it is the map type of var.nodes
  # itself: a map has no declaration order to leak.
  controlplane_ips = [for h, n in local.controlplanes_by_hostname : n.ip]
  worker_ips       = [for h, n in local.workers_by_hostname : n.ip]
  node_ips         = [for h, n in local.nodes_checked : n.ip]

  # All-nodes patch, emitted ONLY when register_with_fqdn is on. Talos splits a
  # dotted hostname at the first dot and registers the SHORT hostname with
  # Kubernetes by default; this flips the kubelet to the FQDN. Emitted as a patch
  # rather than unconditionally so an off-by-default module produces byte-identical
  # machine config to before this input existed.
  #
  # CAVEAT (documented, not enforceable here): this is an ordinary machine-config
  # patch, so a caller's own config_patches — which the module does not parse —
  # can override it in either direction, exactly like they can override the
  # module's HostnameConfig. The typed input is the supported surface; raw patch
  # content is caller-owned. See README §Notes.
  register_with_fqdn_patch = var.register_with_fqdn ? [yamlencode({
    machine = { kubelet = { registerWithFQDN = true } }
  })] : []
}
