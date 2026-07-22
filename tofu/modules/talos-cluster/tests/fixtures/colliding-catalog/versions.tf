# Minimal version pin for the test fixture. Deliberately declares NO providers:
# the symlinked composition.tf exercises only `terraform_data.composition_guards`
# (the built-in provider) plus pure functions, so the guard plan evaluates with
# no talos/helm provider and no network — the conflict-guard runs are offline.
terraform {
  # Mirrors the real module's floor (versions.tf) — the fixture symlinks
  # variables.tf, whose cilium_self_management cross-variable validation
  # blocks need OpenTofu >= 1.9 to parse at all (issue #188).
  required_version = ">= 1.9.0"
}
