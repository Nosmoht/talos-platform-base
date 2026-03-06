.PHONY: argocd-install argocd-bootstrap argocd-password argocd-oidc grafana-dashboards-check validate-gitops validate-kyverno-policies

argocd-install:
	kubectl apply -f kubernetes/bootstrap/argocd/namespace.yaml
	helm upgrade --install argocd argo/argo-cd \
		--version '9.4.5' \
		--namespace argocd \
		-f kubernetes/base/infrastructure/argocd/values.yaml
	@kubectl create secret generic sops-age-key \
		--namespace argocd \
		--from-file=keys.txt=$${SOPS_AGE_KEY_FILE:-$$HOME/.config/sops/age/keys.txt} \
		--dry-run=client -o yaml | kubectl apply -f -
	kubectl wait --for=condition=available -n argocd deployment/argocd-server --timeout=300s

argocd-bootstrap: argocd-install
	kubectl apply -f kubernetes/bootstrap/argocd/root-project.yaml
	kubectl apply -f kubernetes/bootstrap/argocd/root-application.yaml

argocd-password:
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

argocd-oidc:
	@OIDC_SECRET=$$(sops -d --extract '["stringData"]["argocd-oidc-client-secret"]' \
		kubernetes/overlays/homelab/infrastructure/dex/resources/secret.sops.yaml) && \
	kubectl -n argocd patch secret argocd-secret --type merge \
		-p "{\"stringData\":{\"oidc.argocd.clientSecret\":\"$$OIDC_SECRET\"}}"

grafana-dashboards-check:
	@if rg -n '\$\{DS_[A-Z0-9_]+\}|\"__inputs\"' kubernetes/overlays/homelab/infrastructure/*/resources/dashboards/*.json; then \
		echo "error: dashboard contains import-only datasource placeholders or __inputs; use fixed datasource uid (prometheus)"; \
		exit 1; \
	else \
		echo "ok: dashboards contain no DS_* placeholders or __inputs"; \
	fi

validate-gitops:
	./scripts/discover_kustomize_targets.sh
	./scripts/render_kustomize_safe.sh
	./scripts/discover_argocd_apps.sh
	./scripts/verify_sops_files.sh
	./scripts/run_conftest.sh
	@for f in $$(cat .work/kustomize-rendered-files.txt 2>/dev/null); do \
		echo "kubeconform: $$f"; \
		kubeconform -strict -ignore-missing-schemas "$$f"; \
	done
	trivy config --severity HIGH,CRITICAL --exit-code 1 \
		--skip-files kubernetes/bootstrap/cilium/cilium.yaml \
		--skip-files kubernetes/overlays/homelab/infrastructure/piraeus-operator/resources/storage-pool-autovg.yaml \
		.

validate-kyverno-policies:
	@echo "Server-validating Kyverno ClusterPolicies..."
	@kubectl apply --dry-run=server \
		-f kubernetes/overlays/homelab/infrastructure/platform-network-interface/resources/kyverno-clusterpolicy-pni-contract-audit.yaml \
		-f kubernetes/overlays/homelab/infrastructure/platform-network-interface/resources/kyverno-clusterpolicy-pni-reserved-labels-audit.yaml
	@echo "ok: Kyverno ClusterPolicies passed server-side validation"
