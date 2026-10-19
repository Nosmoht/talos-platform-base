# No providers: the fixture plans offline.
terraform {
  # Same floor as the module: the symlinked variables.tf needs OpenTofu >= 1.9.
  required_version = ">= 1.9.0"
}
