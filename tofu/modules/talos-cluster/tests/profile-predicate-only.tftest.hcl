# Predicate-only profile-karg suite — the red-green binding for ADR-0016
# (knowledge/decisions/0016-capability-profiles-predicate-only.md) and the
# "Profile kernel arguments are predicate-only" requirement in
# openspec/specs/hardware-capability-composition/spec.md.
#
# Why this file exists: the ADR removed `iommu=pt` from the catalog, and no test
# asserted the literal karg set, so reverting that removal broke nothing —
# behaviour-visible only through a schematic content hash nobody diffs in CI. An
# authoring contract with no mechanical binding is a comment.
#
# Each run points at ./tests/fixtures/real-catalog via `run { module }`. That
# fixture SYMLINKS the real composition.tf + variables.tf + profiles.tf — the
# catalog under assertion is the SHIPPED one, unlike ./fixtures/colliding-catalog
# (synthetic catalog, real guards). It substitutes only versions.tf (no providers)
# and outputs.tf (composition locals, no Image-Factory data sources), so these runs
# are a pure plan over terraform_data — NO network, NO provider. That is what lets
# them run in `tofu:ci`; composition.tftest.hcl cannot, it resolves the live
# Image Factory.
#
# BINDING CAVEAT (keep this binding intact): the binding holds only while
# `local.node_effective` and `local.provisioning_profiles` stay in composition.tf
# and profiles.tf respectively. Moving either would make this fixture symlink a
# file that no longer carries it, and the runs would silently assert nothing.
#
# PORTABILITY: git symlinks; on Windows checkouts with core.symlinks=false they
# materialise as text files and tofu fails to parse them (`git config
# core.symlinks true`). CI runs Linux.

variables {
  cluster_name       = "test"
  cluster_endpoint   = "https://192.0.2.1:6443"
  talos_version      = "v1.12.6"
  kubernetes_version = "v1.35.0"

  images = {
    intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [] }
    amd   = { architecture = "amd64", cpu_vendor = "amd", extensions = [] }
  }

  hardware_capabilities = {
    virt = {
      requires_features     = ["iommu-enabled"]
      provisioning_profiles = ["iommu"]
      emits_label           = "platform.io/hardware-capability.virt"
    }
  }
}

# The authored catalog, asserted directly — independent of any node composing it.
# SET EQUALITY, not a substring or a "contains": the spec Requirement limits a
# profile's kargs to the args its atom's presence_predicate names, so ANY added
# arg violates it regardless of what that arg does. `iommu=pt` is the arg ADR-0016
# removed; `pci=noaer` stands for the next well-meant host tuning.
#
# Red-green: re-add "iommu=pt" to the intel variant in profiles.tf and this run
# fails.
run "catalog_iommu_variants_carry_exactly_their_predicate_arg" {
  command = plan
  module { source = "./tests/fixtures/real-catalog" }

  variables {
    nodes = {
      cp-1 = { ip = "192.0.2.10", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.11", role = "worker", image = "intel", hardware_capabilities = ["virt"] },
    }
  }

  assert {
    condition     = join(",", output.catalog_profile_kernel_args["iommu.intel"]) == "intel_iommu=on"
    error_message = "iommu.intel kernel_args must equal exactly [\"intel_iommu=on\"] — the arg the iommu-enabled atom's presence_predicate names (platform-hardware-features.yaml). Got: ${jsonencode(output.catalog_profile_kernel_args["iommu.intel"])}. Adding host tuning here spends a kernel-arg key the consumer cannot get back (ADR-0016)."
  }

  assert {
    condition     = join(",", output.catalog_profile_kernel_args["iommu.amd"]) == "amd_iommu=on"
    error_message = "iommu.amd kernel_args must equal exactly [\"amd_iommu=on\"]. Got: ${jsonencode(output.catalog_profile_kernel_args["iommu.amd"])}."
  }

  # The iommu profile resolves its kargs through variants; its top-level list
  # must stay empty or the vendor resolution is bypassed for non-variant paths.
  assert {
    condition     = length(output.catalog_profile_kernel_args["iommu"]) == 0
    error_message = "the iommu profile's top-level kernel_args must be empty — vendor variants carry the args. Got: ${jsonencode(output.catalog_profile_kernel_args["iommu"])}."
  }
}

# A profile that provides no atom has no presence_predicate to name an arg, so it
# may carry none. This is the spec's empty-provides scenario and it guards the
# path by which host tuning most easily re-enters: an NFD-detected profile has no
# contract to check the arg against.
#
# Red-green: add any kernel_arg to nvidia-lts or drbd in profiles.tf and this run
# fails.
run "catalog_profiles_without_predicate_args_carry_none" {
  command = plan
  module { source = "./tests/fixtures/real-catalog" }

  variables {
    nodes = {
      cp-1 = { ip = "192.0.2.10", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-1  = { ip = "192.0.2.11", role = "worker", image = "intel", hardware_capabilities = ["virt"] },
    }
  }

  # nvidia-lts provides nothing (nvidia-gpu is NFD-detected) -> no predicate -> no args.
  assert {
    condition     = length(output.catalog_profile_provides["nvidia-lts"]) == 0 && length(output.catalog_profile_kernel_args["nvidia-lts"]) == 0
    error_message = "nvidia-lts provides no atom, so no presence_predicate names a kernel arg for it — its kernel_args must be empty. Got provides=${jsonencode(output.catalog_profile_provides["nvidia-lts"])} kernel_args=${jsonencode(output.catalog_profile_kernel_args["nvidia-lts"])}."
  }

  # drbd's predicate names no kernel arg (the atom is satisfied by the extension +
  # kernel module), so the profile carries none.
  assert {
    condition     = length(output.catalog_profile_kernel_args["drbd"]) == 0
    error_message = "the drbd-kernel-module predicate names no kernel arg, so the drbd profile must carry none. Got: ${jsonencode(output.catalog_profile_kernel_args["drbd"])}."
  }
}

# The composed end state a node actually boots with — binds the union path in
# composition.tf, not just the authored catalog, so a composition change that
# injects an arg is caught too.
#
# Red-green: re-add "iommu=pt" to the intel variant and this run fails.
run "composed_node_kernel_args_carry_no_host_tuning" {
  command = plan
  module { source = "./tests/fixtures/real-catalog" }

  variables {
    nodes = {
      cp-1    = { ip = "192.0.2.10", role = "controlplane", image = "intel", hardware_capabilities = [] },
      w-intel = { ip = "192.0.2.11", role = "worker", image = "intel", hardware_capabilities = ["virt"] },
      w-amd   = { ip = "192.0.2.12", role = "worker", image = "amd", hardware_capabilities = ["virt"] },
    }
  }

  assert {
    condition     = join(",", output.node_kernel_args["w-intel"]) == "intel_iommu=on"
    error_message = "an intel node holding the iommu capability must compose exactly [\"intel_iommu=on\"]. Got: ${jsonencode(output.node_kernel_args["w-intel"])}."
  }

  assert {
    condition     = join(",", output.node_kernel_args["w-amd"]) == "amd_iommu=on"
    error_message = "an amd node holding the iommu capability must compose exactly [\"amd_iommu=on\"]. Got: ${jsonencode(output.node_kernel_args["w-amd"])}."
  }
}
