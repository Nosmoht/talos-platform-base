# Fixture-only outputs (NOT symlinked from the real module's outputs.tf, which
# would drag in the network-resolving Image-Factory data sources). They expose the
# composition locals the predicate-only assertions need. `node_effective` lives in
# the symlinked composition.tf and reads the symlinked REAL profiles.tf, so these
# bind to the shipped catalog — not to a synthetic stand-in.
#
# Deliberately NOT added to the module's own outputs.tf: the catalog's kernel_args
# are an internal composition detail, and widening the module's public interface to
# make one assertion possible would be the tail wagging the dog.

output "node_kernel_args" {
  description = "Per-node UNIONED effective kernel_args composed from the real catalog."
  value       = { for h, e in local.node_effective : h => e.kernel_args }
}

output "catalog_profile_kernel_args" {
  description = "Per-profile kernel_args as authored in the real catalog, variants flattened to <profile>.<variant>. Lets a run assert the authored catalog directly, independent of any node composing it."
  value = merge(
    { for id, p in local.provisioning_profiles : id => p.kernel_args },
    merge([
      for id, p in local.provisioning_profiles : {
        for vendor, v in p.variants : "${id}.${vendor}" => v.kernel_args
      }
    ]...)
  )
}

output "catalog_profile_provides" {
  description = "Per-profile `provides` list as authored in the real catalog."
  value       = { for id, p in local.provisioning_profiles : id => p.provides }
}

# MIRRORS the module's own outputs.tf:62-65 (`node_schematic_hashes`, "Known at
# plan time"). The module already exposes this; the fixture re-declares it only
# because a fixture substitutes outputs.tf WHOLESALE to keep the module's
# provider-resolving Image-Factory data sources out (versions.tf:1-6 declares no
# providers). Nothing here widens the module's public interface — local.node_hash
# lives in the symlinked composition.tf (:119) and is a pure function of the
# composed extensions/kernel_args/overlay.
output "node_schematic_hashes" {
  value = local.node_hash
}
