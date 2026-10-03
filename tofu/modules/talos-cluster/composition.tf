# Provider-free capability composition; fixtures supply their own catalog.
# Use tolerant lookups so composition_guards can report invalid references.

locals {
  node_profiles = {
    for h, n in var.nodes : h => distinct(flatten([
      for c in n.hardware_capabilities : try(var.hardware_capabilities[c].provisioning_profiles, [])
    ]))
  }

  node_profile_resolved = {
    for h, n in var.nodes : h => [
      for pname in local.node_profiles[h] : {
        name           = pname
        provides       = local.provisioning_profiles[pname].provides
        extensions     = local.provisioning_profiles[pname].extensions
        kernel_modules = local.provisioning_profiles[pname].kernel_modules
        sysctls        = local.provisioning_profiles[pname].sysctls
        kernel_args = (
          length(local.provisioning_profiles[pname].variants) > 0
          ? try(local.provisioning_profiles[pname].variants[try(var.images[n.image].cpu_vendor, "")].kernel_args, [])
          : local.provisioning_profiles[pname].kernel_args
        )
      } if contains(keys(local.provisioning_profiles), pname)
    ]
  }

  node_provided_atoms = {
    for h, n in var.nodes : h => distinct(flatten([
      for p in local.node_profile_resolved[h] : p.provides
    ]))
  }

  node_effective = {
    for h, n in var.nodes : h => {
      arch    = try(var.images[n.image].architecture, "amd64")
      overlay = try(var.images[n.image].overlay, null)
      extensions = sort(distinct(concat(
        try(var.images[n.image].extensions, []),
        flatten([for p in local.node_profile_resolved[h] : p.extensions]),
      )))
      kernel_args = sort(distinct(concat(
        try(var.images[n.image].extra_kernel_args, []),
        flatten([for p in local.node_profile_resolved[h] : p.kernel_args]),
      )))
    }
  }

  # Sort parameters before grouping so equivalent modules deduplicate; guards reject conflicts.
  node_modules_raw = {
    for h, n in var.nodes : h => flatten([for p in local.node_profile_resolved[h] : p.kernel_modules])
  }
  node_modules_grouped = {
    for h, n in var.nodes : h => {
      for m in local.node_modules_raw[h] : m.name => { name = m.name, parameters = sort(m.parameters) }...
    }
  }
  node_kernel_modules = {
    for h, n in var.nodes : h => [
      for name in sort(keys(local.node_modules_grouped[h])) : local.node_modules_grouped[h][name][0]
    ]
  }

  node_sysctls = {
    for h, n in var.nodes : h => merge(concat([{}], [for p in local.node_profile_resolved[h] : p.sysctls])...)
  }

  node_labels = {
    for h, n in var.nodes : h => merge(
      { for c in n.hardware_capabilities : var.hardware_capabilities[c].emits_label => "true" if contains(keys(var.hardware_capabilities), c) },
      { for atom in local.node_provided_atoms[h] : "platform.io/hardware-feature.${atom}" => "true" },
    )
  }

  # Hash declared content before provider resolution. Architecture keys the installer, not the schematic.
  node_schematic_yaml = {
    for h, n in var.nodes : h => yamlencode(merge(
      {
        customization = merge(
          { systemExtensions = { officialExtensions = local.node_effective[h].extensions } },
          length(local.node_effective[h].kernel_args) > 0 ? { extraKernelArgs = local.node_effective[h].kernel_args } : {},
        )
      },
      local.node_effective[h].overlay == null ? {} : { overlay = local.node_effective[h].overlay },
    ))
  }
  node_hash = { for hostname, y in local.node_schematic_yaml : hostname => substr(sha256(y), 0, 16) }

  _schematics_grouped = {
    for hostname, hash in local.node_hash : hash => {
      extensions  = local.node_effective[hostname].extensions
      kernel_args = local.node_effective[hostname].kernel_args
      overlay     = local.node_effective[hostname].overlay
    }...
  }
  schematics = { for hash, descs in local._schematics_grouped : hash => descs[0] }

  _installers_grouped = {
    for hostname, hash in local.node_hash : "${hash}:${local.node_effective[hostname].arch}" => {
      hash = hash
      arch = local.node_effective[hostname].arch
    }...
  }
  installers       = { for k, g in local._installers_grouped : k => g[0] }
  node_install_key = { for hostname, hash in local.node_hash : hostname => "${hash}:${local.node_effective[hostname].arch}" }

  # Omit empty patches: a labels-only document must not clear kubelet defaults.
  node_generated_patches = {
    for h, n in var.nodes : h => local.native_config_documents ? concat(
      [for module in local.node_kernel_modules[h] : yamlencode({
        apiVersion = "v1alpha1"
        kind       = "KernelModuleConfig"
        name       = module.name
        parameters = module.parameters
      })],
      length(local.node_sysctls[h]) > 0 ? [yamlencode({
        apiVersion = "v1alpha1", kind = "SysctlConfig", params = local.node_sysctls[h]
      })] : [],
      length(local.node_labels[h]) > 0 ? [yamlencode({
        apiVersion = "v1alpha1", kind = "KubeNodeConfig", labels = local.node_labels[h]
      })] : [],
      ) : (
      length(local.node_kernel_modules[h]) == 0 && length(local.node_sysctls[h]) == 0 && length(local.node_labels[h]) == 0
      ? []
      : [yamlencode({
        machine = merge(
          length(local.node_kernel_modules[h]) > 0 ? { kernel = { modules = local.node_kernel_modules[h] } } : {},
          length(local.node_sysctls[h]) > 0 ? { sysctls = local.node_sysctls[h] } : {},
          length(local.node_labels[h]) > 0 ? { nodeLabels = local.node_labels[h] } : {},
        )
      })]
    )
  }

  undefined_images = [for h, n in var.nodes : h if !contains(keys(var.images), n.image)]
  undefined_caps = {
    for h, n in var.nodes : h => [for c in n.hardware_capabilities : c if !contains(keys(var.hardware_capabilities), c)]
  }
  undefined_profiles = {
    for h, n in var.nodes : h => [for pname in local.node_profiles[h] : pname if !contains(keys(local.provisioning_profiles), pname)]
  }
  variant_mismatches = {
    for h, n in var.nodes : h => [
      for pname in local.node_profiles[h] : pname
      if contains(keys(local.provisioning_profiles), pname)
      && length(local.provisioning_profiles[pname].variants) > 0
      && !contains(keys(local.provisioning_profiles[pname].variants), try(var.images[n.image].cpu_vendor, ""))
    ]
  }
  # Check each capability independently, including unused ones; a node union could mask asymmetry.
  capability_provided_atoms = {
    for cname, c in var.hardware_capabilities : cname => distinct(flatten([
      for pname in c.provisioning_profiles : try(local.provisioning_profiles[pname].provides, [])
    ]))
  }
  capability_forward_violations = {
    for cname, c in var.hardware_capabilities : cname => [
      for f in c.requires_features : f
      if contains(local.provisioned_atoms, f) && !contains(local.capability_provided_atoms[cname], f)
    ]
  }
  capability_inverse_violations = {
    for cname, c in var.hardware_capabilities : cname => [
      for a in local.capability_provided_atoms[cname] : a if !contains(c.requires_features, a)
    ]
  }
  module_conflicts = {
    for h, n in var.nodes : h => [
      for name, mods in local.node_modules_grouped[h] : name
      if length(distinct([for m in mods : join(",", m.parameters)])) > 1
    ]
  }
  _sysctl_by_key = {
    for h, n in var.nodes : h => {
      for pair in flatten([for p in local.node_profile_resolved[h] : [for k, v in p.sysctls : { key = k, value = v }]]) :
      pair.key => pair.value...
    }
  }
  sysctl_conflicts = {
    for h, n in var.nodes : h => [for k, vs in local._sysctl_by_key[h] : k if length(distinct(vs)) > 1]
  }
  # Guard only profile-contributed keys. Consumer-only repeatable keys remain unrestricted.
  _karg_profile_by_key = {
    for h, n in var.nodes : h => {
      for a in flatten([for p in local.node_profile_resolved[h] : p.kernel_args]) :
      element(split("=", a), 0) => (a == element(split("=", a), 0) ? "" : trimprefix(a, "${element(split("=", a), 0)}="))...
    }
  }
  _karg_image_by_key = {
    for h, n in var.nodes : h => {
      for a in try(var.images[n.image].extra_kernel_args, []) :
      element(split("=", a), 0) => (a == element(split("=", a), 0) ? "" : trimprefix(a, "${element(split("=", a), 0)}="))...
    }
  }
  # These profile keys legitimately accept multiple distinct values.
  _karg_multivalue_keys = ["console", "module_blacklist", "initcall_blacklist", "blacklist"]
  karg_conflicts = {
    for h, n in var.nodes : h => [
      for k, vs in local._karg_profile_by_key[h] : k
      if !contains(local._karg_multivalue_keys, k) && length(distinct(concat(
        vs, try(local._karg_image_by_key[h][k], [])
      ))) > 1
    ]
  }
  _karg_conflict_detail = {
    for h, n in var.nodes : h => {
      for k in local.karg_conflicts[h] : k => {
        profile = distinct(local._karg_profile_by_key[h][k])
        image   = distinct(try(local._karg_image_by_key[h][k], []))
      }
    } if length(local.karg_conflicts[h]) > 0
  }
}

# Preconditions fail the plan; top-level check blocks would only warn.
resource "terraform_data" "composition_guards" {
  input = "composition-guards"

  lifecycle {
    precondition {
      condition     = length(local.undefined_images) == 0
      error_message = "node.image must be a key in var.images. Offending nodes: ${jsonencode(local.undefined_images)}. Defined images: ${jsonencode(keys(var.images))}."
    }
    precondition {
      condition     = length([for h, v in local.undefined_caps : h if length(v) > 0]) == 0
      error_message = "node.hardware_capabilities entries must be keys in var.hardware_capabilities. Offending: ${jsonencode({ for h, v in local.undefined_caps : h => v if length(v) > 0 })}. Defined: ${jsonencode(keys(var.hardware_capabilities))}."
    }
    precondition {
      condition     = length([for h, v in local.undefined_profiles : h if length(v) > 0]) == 0
      error_message = "A capability references a provisioning_profile absent from the base catalog. Offending: ${jsonencode({ for h, v in local.undefined_profiles : h => v if length(v) > 0 })}. Catalog: ${jsonencode(keys(local.provisioning_profiles))}."
    }
    precondition {
      condition     = length([for h, v in local.variant_mismatches : h if length(v) > 0]) == 0
      error_message = "A selected profile has variants but no entry for the node image's cpu_vendor. Offending (node => profiles): ${jsonencode({ for h, v in local.variant_mismatches : h => v if length(v) > 0 })}."
    }
    precondition {
      condition     = length([for c, v in local.capability_forward_violations : c if length(v) > 0]) == 0
      error_message = "A hardware capability requires a PROVISIONED feature its own provisioning_profiles do not provide (label without provisioning; checked per-capability, not per-node-union). Offending (capability => atoms): ${jsonencode({ for c, v in local.capability_forward_violations : c => v if length(v) > 0 })}."
    }
    precondition {
      condition     = length([for c, v in local.capability_inverse_violations : c if length(v) > 0]) == 0
      error_message = "A hardware capability's provisioning_profiles provide an atom it omits from requires_features (provisioned but unlabeled; per-capability). Offending (capability => atoms): ${jsonencode({ for c, v in local.capability_inverse_violations : c => v if length(v) > 0 })}."
    }
    precondition {
      condition     = length([for h, v in local.module_conflicts : h if length(v) > 0]) == 0
      error_message = "Two selected profiles contribute the same kernel module with differing parameters. Offending (node => modules): ${jsonencode({ for h, v in local.module_conflicts : h => v if length(v) > 0 })}."
    }
    precondition {
      condition     = length([for h, v in local.sysctl_conflicts : h if length(v) > 0]) == 0
      error_message = "Two selected profiles set the same sysctl to differing values. Offending (node => keys): ${jsonencode({ for h, v in local.sysctl_conflicts : h => v if length(v) > 0 })}."
    }
    precondition {
      condition     = length([for h, v in local.karg_conflicts : h if length(v) > 0]) == 0
      error_message = "Kernel-arg conflict: a single-value kernel-arg key is set to differing values. The sources may be the node's selected provisioning profiles and/or its image's extra_kernel_args. Offending (node => key => {profile, image} values): ${jsonencode(local._karg_conflict_detail)}."
    }
  }
}
