# Per-node capability composition (ADR base:node-capability-composition).
#
# Resolves each node's hardware_capabilities -> selected provisioning profiles ->
# a union of provisions into two sinks, then content-hash-dedups the schematics:
#
#   schematic sink:     customization.systemExtensions.officialExtensions
#                       (images.<id>.extensions baseline UNION profile extensions),
#                       customization.extraKernelArgs (UNION kernel_args),
#                       top-level overlay (from the image)
#   machine-config sink: machine.kernel.modules (UNION), machine.sysctls (UNION),
#                       machine.nodeLabels (capability emits_label + a
#                       platform.io/hardware-feature.<atom> per provided atom)
#
# Cross-variable invariants are enforced as HARD plan-time errors via the
# preconditions on terraform_data.composition_guards (top-level `check` blocks
# only warn). Tolerant locals (try/contains) keep an invalid input from raising a
# cryptic map-index error before its precondition produces a clear message.

locals {
  # --- 1. SELECT profiles (union across the node's capabilities) -------------
  # try(): an undefined capability contributes nothing; the undefined_caps
  # precondition produces the clear error.
  node_profiles = {
    for n in var.nodes : n.hostname => distinct(flatten([
      for c in n.hardware_capabilities : try(var.hardware_capabilities[c].provisioning_profiles, [])
    ]))
  }

  # --- 2. RESOLVE variants by the node image's cpu_vendor -------------------
  # Skip profiles not in the catalog (undefined_profiles precondition reports
  # them). A profile with variants uses the cpu_vendor-matched kernel_args; the
  # variant_mismatches precondition catches a missing vendor entry.
  node_profile_resolved = {
    for n in var.nodes : n.hostname => [
      for pname in local.node_profiles[n.hostname] : {
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
    for n in var.nodes : n.hostname => distinct(flatten([
      for p in local.node_profile_resolved[n.hostname] : p.provides
    ]))
  }

  # --- 3. UNION into the two sinks -----------------------------------------
  node_effective = {
    for n in var.nodes : n.hostname => {
      arch    = try(var.images[n.image].architecture, "amd64")
      overlay = try(var.images[n.image].overlay, null)
      # extensions: image baseline UNION selected-profile extensions (sorted ->
      # canonical for the content hash).
      extensions = sort(distinct(concat(
        try(var.images[n.image].extensions, []),
        flatten([for p in local.node_profile_resolved[n.hostname] : p.extensions]),
      )))
      kernel_args = sort(distinct(flatten([for p in local.node_profile_resolved[n.hostname] : p.kernel_args])))
    }
  }

  # kernel_modules: group by name (nested parameters sorted for determinism, M3),
  # dedup to the first; the module_conflicts precondition fails BEFORE this masks
  # a same-name/differing-params conflict.
  node_modules_raw = {
    for n in var.nodes : n.hostname => flatten([for p in local.node_profile_resolved[n.hostname] : p.kernel_modules])
  }
  node_modules_grouped = {
    for n in var.nodes : n.hostname => {
      for m in local.node_modules_raw[n.hostname] : m.name => { name = m.name, parameters = sort(m.parameters) }...
    }
  }
  node_kernel_modules = {
    for n in var.nodes : n.hostname => [
      for name in sort(keys(local.node_modules_grouped[n.hostname])) : local.node_modules_grouped[n.hostname][name][0]
    ]
  }

  # sysctls: merge all profile maps (sysctl_conflicts precondition fails on a
  # same-key/differing-value collision before the silent merge-last-wins).
  node_sysctls = {
    for n in var.nodes : n.hostname => merge(concat([{}], [for p in local.node_profile_resolved[n.hostname] : p.sysctls])...)
  }

  # nodeLabels: capability emits_label (defined caps only) + a Layer-C
  # hardware-feature label per PROVIDED atom (base-controlled provenance, H1).
  node_labels = {
    for n in var.nodes : n.hostname => merge(
      { for c in n.hardware_capabilities : var.hardware_capabilities[c].emits_label => "true" if contains(keys(var.hardware_capabilities), c) },
      { for atom in local.node_provided_atoms[n.hostname] : "platform.io/hardware-feature.${atom}" => "true" },
    )
  }

  # --- 4. CANONICAL schematic + content-hash dedup (M2, spike-proven) -------
  # Hash content = declared extensions + kernel_args + overlay (NOT arch; arch
  # keys the installer). The resource content (main.tf) uses the factory-RESOLVED
  # extension set, which equals the declared set when the resolution precondition
  # holds — so the declared-set hash is a sound dedup key.
  node_schematic_yaml = {
    for n in var.nodes : n.hostname => yamlencode(merge(
      {
        customization = merge(
          { systemExtensions = { officialExtensions = local.node_effective[n.hostname].extensions } },
          length(local.node_effective[n.hostname].kernel_args) > 0 ? { extraKernelArgs = local.node_effective[n.hostname].kernel_args } : {},
        )
      },
      local.node_effective[n.hostname].overlay == null ? {} : { overlay = local.node_effective[n.hostname].overlay },
    ))
  }
  node_hash = { for hostname, y in local.node_schematic_yaml : hostname => substr(sha256(y), 0, 16) }

  # distinct schematics keyed by content hash (pure value -> plan-time-known
  # for_each key); identical nodes collapse, unique nodes get unique schematics.
  _schematics_grouped = {
    for hostname, hash in local.node_hash : hash => {
      extensions  = local.node_effective[hostname].extensions
      kernel_args = local.node_effective[hostname].kernel_args
      overlay     = local.node_effective[hostname].overlay
    }...
  }
  schematics = { for hash, descs in local._schematics_grouped : hash => descs[0] }

  # distinct installers keyed "hash:arch" (a schematic shared across arches gets
  # one installer per arch, both pointing at the one schematic resource).
  _installers_grouped = {
    for hostname, hash in local.node_hash : "${hash}:${local.node_effective[hostname].arch}" => {
      hash = hash
      arch = local.node_effective[hostname].arch
    }...
  }
  installers       = { for k, g in local._installers_grouped : k => g[0] }
  node_install_key = { for hostname, hash in local.node_hash : hostname => "${hash}:${local.node_effective[hostname].arch}" }

  # --- 5. generated per-node machine-config patch (apply-pass overlay) ------
  # Emitted into the per-node apply concat BEFORE node config_patches (so a raw
  # patch still overrides — the documented escape hatch) and BEFORE base_cni_patch
  # (which stays strictly last). Empty list when the node provisions nothing.
  node_generated_patches = {
    for n in var.nodes : n.hostname => (
      length(local.node_kernel_modules[n.hostname]) == 0 && length(local.node_sysctls[n.hostname]) == 0 && length(local.node_labels[n.hostname]) == 0
      ? []
      : [yamlencode({
        machine = merge(
          length(local.node_kernel_modules[n.hostname]) > 0 ? { kernel = { modules = local.node_kernel_modules[n.hostname] } } : {},
          length(local.node_sysctls[n.hostname]) > 0 ? { sysctls = local.node_sysctls[n.hostname] } : {},
          length(local.node_labels[n.hostname]) > 0 ? { nodeLabels = local.node_labels[n.hostname] } : {},
        )
      })]
    )
  }

  # --- invariant violation sets (consumed by the guard preconditions) -------
  undefined_images = [for n in var.nodes : n.hostname if !contains(keys(var.images), n.image)]
  undefined_caps = {
    for n in var.nodes : n.hostname => [for c in n.hardware_capabilities : c if !contains(keys(var.hardware_capabilities), c)]
  }
  undefined_profiles = {
    for n in var.nodes : n.hostname => [for pname in local.node_profiles[n.hostname] : pname if !contains(keys(local.provisioning_profiles), pname)]
  }
  variant_mismatches = {
    for n in var.nodes : n.hostname => [
      for pname in local.node_profiles[n.hostname] : pname
      if contains(keys(local.provisioning_profiles), pname)
      && length(local.provisioning_profiles[pname].variants) > 0
      && !contains(keys(local.provisioning_profiles[pname].variants), try(var.images[n.image].cpu_vendor, ""))
    ]
  }
  # Per-CAPABILITY symmetry (independent of node composition): validate each
  # var.hardware_capabilities entry against its OWN provisioning_profiles. This
  # is strictly stronger than a per-node-union check: a malformed capability can
  # no longer be masked by a sibling capability that compensates it in the union
  # (Codex review finding — the union-scope hole). It also validates capabilities
  # that no node currently uses.
  capability_provided_atoms = {
    for cname, c in var.hardware_capabilities : cname => distinct(flatten([
      for pname in c.provisioning_profiles : try(local.provisioning_profiles[pname].provides, [])
    ]))
  }
  # forward: a PROVISIONED required-feature the capability's own profiles do not provide
  capability_forward_violations = {
    for cname, c in var.hardware_capabilities : cname => [
      for f in c.requires_features : f
      if contains(local.provisioned_atoms, f) && !contains(local.capability_provided_atoms[cname], f)
    ]
  }
  # inverse: a profile-provided atom the capability omits from requires_features
  capability_inverse_violations = {
    for cname, c in var.hardware_capabilities : cname => [
      for a in local.capability_provided_atoms[cname] : a if !contains(c.requires_features, a)
    ]
  }
  # conflicts (M3): same-name modules differing params; same-key sysctls/kargs differing value
  module_conflicts = {
    for n in var.nodes : n.hostname => [
      for name, mods in local.node_modules_grouped[n.hostname] : name
      if length(distinct([for m in mods : join(",", m.parameters)])) > 1
    ]
  }
  _sysctl_by_key = {
    for n in var.nodes : n.hostname => {
      for pair in flatten([for p in local.node_profile_resolved[n.hostname] : [for k, v in p.sysctls : { key = k, value = v }]]) :
      pair.key => pair.value...
    }
  }
  sysctl_conflicts = {
    for n in var.nodes : n.hostname => [for k, vs in local._sysctl_by_key[n.hostname] : k if length(distinct(vs)) > 1]
  }
  _karg_by_key = {
    for n in var.nodes : n.hostname => {
      for a in flatten([for p in local.node_profile_resolved[n.hostname] : p.kernel_args]) :
      element(split("=", a), 0) => (a == element(split("=", a), 0) ? "" : trimprefix(a, "${element(split("=", a), 0)}="))...
    }
  }
  # Kernel-arg keys that legitimately carry multiple distinct values on one
  # cmdline (multi-value): two profiles contributing different values is NOT a
  # conflict for these. Single-value keys (intel_iommu, iommu, …) still trip the
  # guard. Keeps the union correct for console=/blacklist= without false errors.
  _karg_multivalue_keys = ["console", "module_blacklist", "initcall_blacklist", "blacklist"]
  karg_conflicts = {
    for n in var.nodes : n.hostname => [
      for k, vs in local._karg_by_key[n.hostname] : k
      if length(distinct(vs)) > 1 && !contains(local._karg_multivalue_keys, k)
    ]
  }
}

# Hard plan-time invariant gate. Preconditions (not top-level `check` blocks,
# which only warn) fail the plan. All conditions are pure functions of plan-time
# inputs, so they evaluate during plan.
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
      error_message = "Two selected profiles set the same kernel arg to differing values. Offending (node => keys): ${jsonencode({ for h, v in local.karg_conflicts : h => v if length(v) > 0 })}."
    }
  }
}
