# Minimal version pin for the test fixture. Deliberately declares NO providers:
# the symlinked composition.tf exercises only `terraform_data.composition_guards`
# (the built-in provider) plus pure functions, so the guard plan evaluates with
# no talos/helm provider and no network — the conflict-guard runs are offline.
terraform {
  required_version = ">= 1.6.0"
}
