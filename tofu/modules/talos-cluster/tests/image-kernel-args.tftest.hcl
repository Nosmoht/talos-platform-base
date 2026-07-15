# Consumer image extra_kernel_args regression suite (issue #169).
#
# AC2 (a changed extra_kernel_args re-images the node) and AC6 clause 1 (an
# existing consumer setting no extra_kernel_args is not re-imaged) — both
# oracles read local.node_hash, a pure plan-time function of
# extensions/kernel_args/overlay (composition.tf:108-119), so this whole file
# is a pure plan over terraform_data. OFFLINE: both fixtures symlink the real
# composition.tf/variables.tf and declare no providers (real-catalog/versions.tf,
# colliding-catalog/versions.tf), so this suite needs no network — unlike
# tests/composition.tftest.hcl (AC1), which resolves the live Image Factory.
#
# BINDING CAVEAT (same as conflict-guards.tftest.hcl): the red-green binding
# holds only while the conflict-detection locals + node_effective stay IN
# composition.tf — moving them out would make a fixture's symlink shadow or
# drop them.

variables {
  cluster_name       = "test"
  cluster_endpoint   = "https://192.0.2.1:6443"
  talos_version      = "v1.12.6"
  kubernetes_version = "v1.35.0"
}

# --- AC6 clause 1, run (a) — the order/sort() oracle (synthetic) -----------
#
# Order- and multiplicity-exact list equality. The pre-sort composed order
# comes from THIS RUN's own hardware_capabilities.console.provisioning_profiles
# list (["console_a", "console_b"]) — composition.tf:23-27 builds node_profiles
# as an order-preserving distinct(flatten(...)) over that list, and profiles.tf
# is indexed as a MAP (composition.tf:37-45), so the catalog file's own
# authoring order is never read. With this order the pre-sort flatten is
# ["console=ttyS0,115200n8", "console=tty0"] (colliding-catalog/profiles.tf:84,
# :92) — the REVERSE of sorted order. Dropping sort() from the new concat, or
# reordering this list to ["console_b", "console_a"], silently kills this
# mutant's only binding for sort() — do not "fix" the list order.
#
# No hash assert here (by design): overlay is null, extensions = [] on both
# legs, so every hash input is already pinned by the list assert + this run's
# own variables — a hash pin here would only catch a yamlencode/sha256 change.
# The hash pin lives in run (b), where it kills real mutants.
run "default_consumer_kernel_args_are_composed_order_exactly" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [] }
    }
    hardware_capabilities = {
      console = {
        requires_features     = []
        provisioning_profiles = ["console_a", "console_b"] # ORDER IS THE ORACLE
        emits_label           = "platform.io/hardware-capability.console"
      }
    }
    nodes = [
      { hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = ["console"] },
    ]
  }
  assert {
    condition     = tolist(output.node_kernel_args["cp-1"]) == tolist(["console=tty0", "console=ttyS0,115200n8"])
    error_message = "default consumer (no extra_kernel_args) composed kernel_args must equal the sorted profile-only set exactly, order and multiplicity; got ${jsonencode(output.node_kernel_args["cp-1"])}"
  }
}

# --- AC6 clause 1, run (b) — the shipped-catalog no-re-image pin -----------
#
# Binds the node class AC6's wording actually covers: a node that HAS profile
# kargs, on the REAL shipped catalog (not a synthetic stand-in — the shipped
# iommu profile is the re-image event AC6 exists to catch: real-catalog's own
# outputs.tf:1-5 states "these bind to the shipped catalog — not to a synthetic
# stand-in"). No extra_kernel_args set — this is the "existing consumer"
# shape.
#
# Re-derivation procedure for the pinned hash (per plan.md Step 5 / addenda):
# the expected schematic for w-1 is
#   {customization = {systemExtensions = {officialExtensions = []},
#                      extraKernelArgs = ["intel_iommu=on"]}}
# and the hash is substr(sha256(yamlencode(<that value>)), 0, 16) per
# composition.tf:108-119. Re-derive offline with
#   cd tofu/modules/talos-cluster && tofu console
# A MISMATCH IS A HALT, NOT A RE-CAPTURE: re-pinning from whatever the code now
# produces converts this oracle into a snapshot. If the expected schematic
# itself legitimately changed (composition.tf:108-119's merge shape), that is
# a re-image event for every consumer of this base and needs an UPGRADING.md
# section, not a silent literal edit. If the MERGE SHAPE changed (not just
# this node's values), re-derive the shape from composition.tf:108-119 first,
# then the value — this transcription is derivable from the code, not an
# independent assertion of it.
run "default_consumer_shipped_catalog_node_is_not_re_imaged" {
  command = plan
  module { source = "./tests/fixtures/real-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [] }
    }
    hardware_capabilities = {
      virt = {
        requires_features     = ["iommu-enabled"]
        provisioning_profiles = ["iommu"]
        emits_label           = "platform.io/hardware-capability.virt"
      }
    }
    nodes = [
      { hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      { hostname = "w-1", ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = ["virt"] },
    ]
  }
  assert {
    condition     = tolist(output.node_kernel_args["w-1"]) == tolist(["intel_iommu=on"])
    error_message = "existing consumer (no extra_kernel_args) on the shipped iommu profile must compose to exactly the profile's kernel_args, order and multiplicity; got ${jsonencode(output.node_kernel_args["w-1"])}"
  }
  assert {
    condition     = output.node_schematic_hashes["w-1"] == "760a1a00eabe770b" # SEE COMMENT ABOVE — mismatch is a HALT, not a re-capture
    error_message = "existing consumer's schematic content hash for w-1 changed — this is the re-image event AC6 exists to prevent for a consumer setting no extra_kernel_args. If composition.tf:108-119's merge shape or the shipped iommu profile's content legitimately changed, this needs an UPGRADING.md entry, not a silent re-pin. got ${output.node_schematic_hashes["w-1"]}"
  }
}

# --- AC2 — a changed extra_kernel_args changes the schematic id ------------
#
# hugepagesz is not contributed by any profile, so under cross-source scoping
# this plans clean. The hash keys node_install_key -> data.talos_image_factory_urls
# -> the installer URL (outputs.tf:57-65, "Known at plan time"), so a differing
# hash IS the re-image path; the URL itself is not plan-known under
# command = plan, which is why the hash is the oracle (and why this needs no
# network). This run also reds if the IMAGE leg of the node_effective concat is
# dropped — AC4's set-equality assert stays green under that mutant, so this is
# the union's image-leg binding.
# DEVIATION FROM PLAN, DOCUMENTED: the plan's Step 5 shape asserts
# `output.node_schematic_hashes["w-1"] != run.baseline_no_extra_kernel_args.node_schematic_hashes["w-1"]`
# (a cross-run reference inside an `assert` block). Verified via an isolated
# minimal reproduction (two-run module, no other content) that OpenTofu 1.11.8
# does not resolve `run.<name>.<output>` inside an `assert` block at all — every
# identifier in that expression (including the unrelated local `output.*`
# reference in the same condition) reports "Unknown variable", while the exact
# same `run.<name>.<output>` reference DOES resolve inside a `variables` block
# of a later run. This is a genuine tool constraint, not a plan or composition
# defect — cross-checked by removing the `run.*` half of the expression, which
# resolves the local `output.*` half cleanly.
#
# Equivalent-oracle fallback: both runs assert against the SAME pinned literal
# hash instead of a cross-run reference. The baseline run's assert re-derives
# and pins the pre-change hash (identical composition to
# default_consumer_shipped_catalog_node_is_not_re_imaged's w-1 — same image
# shape, same iommu capability, so the SAME literal applies and is
# independently re-derivable via `tofu console` per that run's comment above).
# The changed run then asserts inequality against that same grounded literal.
# This proves the identical fact the plan's oracle intended (a changed
# extra_kernel_args changes the hash vs. the known baseline) without relying on
# the unsupported cross-run construct.
run "baseline_no_extra_kernel_args" {
  command = plan
  module { source = "./tests/fixtures/real-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [] }
    }
    hardware_capabilities = {
      virt = {
        requires_features     = ["iommu-enabled"]
        provisioning_profiles = ["iommu"]
        emits_label           = "platform.io/hardware-capability.virt"
      }
    }
    nodes = [
      { hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      { hostname = "w-1", ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = ["virt"] },
    ]
  }
  assert {
    condition     = output.node_schematic_hashes["w-1"] == "760a1a00eabe770b" # identical composition to run (b) above — same re-derivable literal
    error_message = "baseline (no extra_kernel_args) schematic hash for w-1 must equal the pinned pre-change literal; got ${output.node_schematic_hashes["w-1"]}"
  }
}

run "changed_extra_kernel_args_change_the_schematic_id" {
  command = plan
  module { source = "./tests/fixtures/real-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [], extra_kernel_args = ["hugepagesz=1G"] }
    }
    hardware_capabilities = {
      virt = {
        requires_features     = ["iommu-enabled"]
        provisioning_profiles = ["iommu"]
        emits_label           = "platform.io/hardware-capability.virt"
      }
    }
    nodes = [
      { hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
      { hostname = "w-1", ip = "192.0.2.21", role = "worker", image = "intel", hardware_capabilities = ["virt"] },
    ]
  }
  assert {
    condition     = output.node_schematic_hashes["w-1"] != "760a1a00eabe770b" # the SAME baseline literal asserted above — proves the re-image path, not a silent no-op
    error_message = "a node whose image's extra_kernel_args changed must take the re-image path (differing schematic hash from the baseline), not silently no-op; got the SAME hash ${output.node_schematic_hashes["w-1"]}"
  }
}
