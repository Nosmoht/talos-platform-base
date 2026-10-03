data "talos_image_factory_extensions_versions" "per_schematic" {
  for_each = local.schematics

  talos_version = local.install_version
  filters = {
    names = each.value.extensions
  }
}

locals {
  # The provider matches extension names by substring; retain only exact canonical matches.
  official_extensions_by_schematic = {
    for h, s in local.schematics : h => [
      for ext in data.talos_image_factory_extensions_versions.per_schematic[h].extensions_info :
      ext.name if contains(s.extensions, ext.name)
    ]
  }
}

resource "talos_image_factory_schematic" "this" {
  for_each = local.schematics

  lifecycle {
    precondition {
      # Reject missing or duplicate resolutions; a count alone could hide a wrong extension.
      condition = (
        length(distinct(each.value.extensions)) == length(local.official_extensions_by_schematic[each.key]) &&
        length(local.official_extensions_by_schematic[each.key]) == length(distinct(local.official_extensions_by_schematic[each.key]))
      )
      error_message = "schematic '${each.key}': not all unioned extensions resolved to canonical Image Factory packages for Talos ${local.install_version}. Declared ${jsonencode(distinct(each.value.extensions))}, resolved ${jsonencode(local.official_extensions_by_schematic[each.key])}. Use canonical names such as 'siderolabs/gvisor'."
    }
  }

  schematic = yamlencode(merge(
    {
      customization = merge(
        {
          systemExtensions = {
            officialExtensions = local.official_extensions_by_schematic[each.key]
          }
        },
        length(each.value.kernel_args) > 0 ? { extraKernelArgs = each.value.kernel_args } : {},
      )
    },
    each.value.overlay == null ? {} : {
      overlay = merge(
        {
          name  = each.value.overlay.name
          image = each.value.overlay.image
        },
        each.value.overlay.options == null ? {} : { options = each.value.overlay.options },
      )
    },
  ))
}

data "talos_image_factory_urls" "this" {
  for_each = local.installers

  talos_version = local.install_version
  schematic_id  = talos_image_factory_schematic.this[each.value.hash].id
  platform      = "metal"
  architecture  = each.value.arch

  lifecycle {
    postcondition {
      condition     = self.urls.installer != ""
      error_message = "Image Factory returned no metal installer URL for schematic ${each.value.hash} (architecture ${each.value.arch}). Check the schematic extensions / SBC overlay coordinates."
    }
  }
}
