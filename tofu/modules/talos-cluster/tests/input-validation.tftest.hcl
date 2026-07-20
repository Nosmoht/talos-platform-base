# Input-validation regression suite — fully anchored version patterns.
#
# The talos_version / talos_install_version / kubernetes_version validations in
# variables.tf are `$`-anchored so trailing garbage after the PATCH segment is
# rejected (a `-`/`+` pre-release/build suffix stays accepted; mirrored by
# schemas/cluster.schema.json — the schema side is bound red-green via
# schemas/fixtures/cluster.invalid.yaml in gitops-validate.yml). Each run below
# feeds one malformed value and expects exactly that variable's validation to
# fail. Red-green: revert a `$` anchor in variables.tf and the matching run
# stops failing ("Missing expected failure").
#
# Uses the ./tests/fixtures/colliding-catalog stand-in module (symlinked real
# variables.tf) for the same reason as conflict-guards.tftest.hcl: pure plan
# over terraform_data — NO network, NO provider (unlike composition.tftest.hcl).

variables {
  cluster_name       = "test"
  cluster_endpoint   = "https://192.0.2.1:6443"
  talos_version      = "v1.12.6"
  kubernetes_version = "v1.35.0"

  images = {
    intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [] }
  }

  nodes = [
    { hostname = "cp-1", ip = "192.0.2.11", role = "controlplane", image = "intel", hardware_capabilities = [] },
  ]
}

run "talos_version_rejects_trailing_garbage" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    talos_version = "v1.12.6.4"
  }
  expect_failures = [var.talos_version]
}

run "talos_install_version_rejects_trailing_garbage" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    talos_install_version = "v1.12.7garbage"
  }
  expect_failures = [var.talos_install_version]
}

run "kubernetes_version_rejects_trailing_garbage" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    kubernetes_version = "v1.35.0.1"
  }
  expect_failures = [var.kubernetes_version]
}

run "prerelease_suffix_is_accepted" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    talos_version         = "v1.13.0-beta.1"
    talos_install_version = "v1.13.0-beta.1"
  }
}

# --- AC9: var.images[*].extra_kernel_args lexical rules (issue #169) -------
#
# One malformed element per run, each expecting a var.images validation
# failure, each fixture valid against the OTHER six var.images validations
# (traced per-rule so each isolates the ONE rule under test — see plan.md
# Step 7 for the trace). The
# debugfs fixture uses a NON-forbidden value ("debugfs=on"): the rule matches
# the KEY, so this tests the rule without writing the AGENTS.md §Hard
# Constraints forbidden value literal into any tofu/** file (that constraint;
# hard-constraints-check.yml greps changed-file content at HEAD).

run "image_extra_kernel_args_rejects_whitespace" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [], extra_kernel_args = ["hugepagesz=1G intel_iommu=off"] }
    }
  }
  expect_failures = [var.images]
}

run "image_extra_kernel_args_rejects_removal_spelling" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [], extra_kernel_args = ["-intel_iommu"] }
    }
  }
  expect_failures = [var.images]
}

run "image_extra_kernel_args_rejects_an_empty_key" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [], extra_kernel_args = [""] }
    }
  }
  expect_failures = [var.images]
}

run "image_extra_kernel_args_rejects_the_debugfs_key" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [], extra_kernel_args = ["debugfs=on"] }
    }
  }
  expect_failures = [var.images]
}

# Positive control: binds the spec delta's "accepted well-formed list"
# scenario and proves the bare-key form (quiet, no "=") is accepted. NOT a
# minimal pair with the four negative fixtures above (its list shares no
# element with any of them) — it proves its OWN list is valid against all
# seven validations, not that each negative fixture is valid against the
# other six (that per-fixture isolation is authoring-time reasoning, traced in
# the plan; see plan.md §Verification disclosure 8 for the declined
# per-rule-minimal-pair alternative and its cost/benefit).
run "image_extra_kernel_args_accepts_a_well_formed_list" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    images = {
      intel = { architecture = "amd64", cpu_vendor = "intel", extensions = [], extra_kernel_args = ["hugepagesz=1G", "mitigations=off", "quiet"] }
    }
  }
}

# --- cert-approver per-cluster config validations (adr-0019) ---
# Red-green: delete the matching validation in variables.tf and the run stops
# failing ("Missing expected failure").

run "cert_approver_provider_ip_prefixes_rejects_empty" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cert_approver_provider_ip_prefixes = []
  }
  # Empty set denies every CSR carrying an IP SAN (source-verified WhitelistedIPCheck)
  # — the deny-all footgun the non-empty guard exists to prevent.
  expect_failures = [var.cert_approver_provider_ip_prefixes]
}

run "cert_approver_provider_ip_prefixes_rejects_non_cidr" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cert_approver_provider_ip_prefixes = ["not-a-cidr"]
  }
  expect_failures = [var.cert_approver_provider_ip_prefixes]
}

run "cert_approver_provider_regex_rejects_empty" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cert_approver_provider_regex = ""
  }
  # postfinance v1.2.14 exits fatally at startup on an empty PROVIDER_REGEX
  # (source-verified internal/cmd/cmd.go) — the guard prevents a CrashLoop seed.
  expect_failures = [var.cert_approver_provider_regex]
}

run "cert_approver_provider_regex_rejects_whitespace_only" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cert_approver_provider_regex = " "
  }
  # A whitespace-only regex is not caught by the empty-string check but compiles
  # to a deny-all pattern (matches no DNS SAN) — the trimspace() guard rejects it.
  expect_failures = [var.cert_approver_provider_regex]
}

run "cert_approver_provider_regex_rejects_document_separator" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cert_approver_provider_regex = "a---b"
  }
  # A compilable regex containing "---" would corrupt the split("---") audit outputs.
  expect_failures = [var.cert_approver_provider_regex]
}

run "cert_approver_provider_regex_rejects_uncompilable" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cert_approver_provider_regex = "[unterminated"
  }
  expect_failures = [var.cert_approver_provider_regex]
}

run "cert_approver_replicas_rejects_zero" {
  command = plan
  module { source = "./tests/fixtures/colliding-catalog" }
  variables {
    cert_approver_replicas = 0
  }
  expect_failures = [var.cert_approver_replicas]
}
