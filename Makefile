# Makefile — RETIRED at v3.0.0.
#
# The single task runner for talos-platform-base is now the Taskfile (go-task).
# This stub remains for ONE release cycle so that an old `make <target>` habit
# produces a clear migration message instead of make's confusing
# "No rule to make target" error. It will be deleted in the next MAJOR.
#
# See docs/adr-0012-makefile-retirement.md
# (supersedes docs/adr-0008-task-runner-consolidation.md).

.DEFAULT_GOAL := _retired
.PHONY: _retired

define RETIRED_MSG
════════════════════════════════════════════════════════════════════
 The Makefile was RETIRED at v3.0.0 — use the Taskfile (go-task).
 Run 'task --list' for all targets. Migration:

   make validate-gitops      ->  task gitops:validate
   make render-component     ->  task gitops:render-component COMPONENT=<name>
   make render-all           ->  task gitops:render-all
   make verify-rendered      ->  task gitops:verify-rendered
   make argocd-bootstrap     ->  task bootstrap:argocd
   make argocd-password      ->  task bootstrap:argocd-password
   make init-cluster-yaml    ->  task cluster:init-yaml
   make oci-allowlist-check  ->  task supply-chain:oci-allowlist
   make mcp-install          ->  task mcp:install
   make mcp-verify           ->  task mcp:verify
   make mcp-uninstall        ->  task mcp:uninstall
   make install-pre-commit   ->  task dev:install-pre-commit
   make verify-tools         ->  task dev:verify-tools

 Removed (no replacement): make chart-pull, make grafana-dashboards-check.
 See docs/adr-0012-makefile-retirement.md.
════════════════════════════════════════════════════════════════════
endef
export RETIRED_MSG

_retired:
	@printf '%s\n' "$$RETIRED_MSG" >&2; exit 2

.DEFAULT:
	@printf '%s\n' "$$RETIRED_MSG" >&2; exit 2

