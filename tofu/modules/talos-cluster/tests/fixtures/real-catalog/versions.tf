# Minimal version pin for the test fixture. Deliberately declares NO providers:
# the symlinked composition.tf exercises only `terraform_data.composition_guards`
# (the built-in provider) plus pure functions, so the composition plan evaluates
# with no talos/helm provider and no network. This is what lets the real catalog
# be asserted offline, in `tofu:ci`, rather than only in the network-dependent
# composition.tftest.hcl suite.
terraform {
  required_version = ">= 1.6.0"
}
