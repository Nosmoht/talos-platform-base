.PHONY: argocd-install argocd-bootstrap argocd-password argocd-oidc

# Delegate all talos-* targets to talos/Makefile
# Usage: make talos-gen-configs, make talos-apply-node-01, etc.
talos-%:
	$(MAKE) -C talos $*

argocd-install:
	kubectl apply -f kubernetes/bootstrap/argocd/namespace.yaml
	helm upgrade --install argocd argo/argo-cd \
		--version '9.4.*' \
		--namespace argocd \
		-f kubernetes/base/infrastructure/argocd/values.yaml
	@kubectl create secret generic sops-age-key \
		--namespace argocd \
		--from-file=keys.txt=$${SOPS_AGE_KEY_FILE:-$$HOME/.config/sops/age/keys.txt} \
		--dry-run=client -o yaml | kubectl apply -f -
	kubectl wait --for=condition=available -n argocd deployment/argocd-server --timeout=300s

argocd-bootstrap: argocd-install
	kubectl apply -f kubernetes/bootstrap/argocd/root-application.yaml

argocd-password:
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

argocd-oidc:
	@OIDC_SECRET=$$(sops -d --extract '["stringData"]["argocd-oidc-client-secret"]' \
		kubernetes/overlays/homelab/infrastructure/dex/resources/secret.sops.yaml) && \
	kubectl -n argocd patch secret argocd-secret --type merge \
		-p "{\"stringData\":{\"oidc.argocd.clientSecret\":\"$$OIDC_SECRET\"}}"
