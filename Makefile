CILIUM_VERSION := 1.19.0

.PHONY: argocd-install argocd-bootstrap argocd-password argocd-oidc cilium-bootstrap cilium-bootstrap-check grafana-dashboards-check talos-upgrade-k8s validate-gitops

# Delegate all talos-* targets to talos/Makefile.
# talos-upgrade-k8s is explicitly defined below with a cilium pre-check dependency.
# Usage: make talos-gen-configs, make talos-apply-node-01, etc.
talos-%:
	$(MAKE) -C talos $*

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

kubernetes/bootstrap/cilium/cilium.yaml: scripts/render-cilium-bootstrap.sh Makefile
	CILIUM_CHART_VERSION=$(CILIUM_VERSION) ./scripts/render-cilium-bootstrap.sh

cilium-bootstrap: kubernetes/bootstrap/cilium/cilium.yaml

cilium-bootstrap-check: cilium-bootstrap
	@if yq -r 'select(.kind == "Secret" and (.metadata.name == "hubble-relay-client-certs" or .metadata.name == "hubble-server-certs")) | .metadata.name' \
		kubernetes/bootstrap/cilium/cilium.yaml | rg -n '.'; then \
		echo "error: static hubble tls secrets detected in kubernetes/bootstrap/cilium/cilium.yaml"; \
		exit 1; \
	else \
		echo "ok: no static hubble tls secrets in bootstrap cilium manifest"; \
	fi

grafana-dashboards-check:
	@if rg -n '\$\{DS_[A-Z0-9_]+\}|\"__inputs\"' kubernetes/overlays/homelab/infrastructure/*/resources/dashboards/*.json; then \
		echo "error: dashboard contains import-only datasource placeholders or __inputs; use fixed datasource uid (prometheus)"; \
		exit 1; \
	else \
		echo "ok: dashboards contain no DS_* placeholders or __inputs"; \
	fi

talos-upgrade-k8s: cilium-bootstrap-check
	$(MAKE) -C talos upgrade-k8s

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
