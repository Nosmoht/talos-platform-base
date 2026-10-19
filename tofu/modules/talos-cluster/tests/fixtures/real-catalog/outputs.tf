# Fixture outputs; the module outputs.tf is not symlinked because it needs providers.

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

# Copy of the module output: this fixture replaces outputs.tf as a whole.
output "node_schematic_hashes" {
  value = local.node_hash
}
