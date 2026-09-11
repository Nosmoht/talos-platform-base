#!/usr/bin/env bash
# Bite-check for the ArgoCD NetworkPolicy posture gate.
#
# Each scenario mutates a copy of the committed steady-state render and asserts
# the gate's exact verdict. This keeps the fixtures coupled to the real chart
# output while proving that selector and ingress regressions cannot pass I6.
#
# Runs offline and mutates nothing outside its temporary directory.
#
# Exit codes:
#   0  every mutation was rejected and the unmodified render stayed green
#   1  the gate missed a regression or rejected the control
#   2  environment error
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
src="${repo_root}/kubernetes/substrate/argocd/_rendered/manifests.yaml"
gate="${repo_root}/scripts/check-argocd-network-policy-invariants.sh"

command -v yq >/dev/null 2>&1 || { echo "ERROR: yq is required" >&2; exit 2; }
[ -f "$src" ] || { echo "ERROR: $src missing" >&2; exit 2; }
[ -x "$gate" ] || { echo "ERROR: $gate missing or not executable" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
rc=0

mut_empty_match_labels() {
  yq -i '
    (select(.kind == "NetworkPolicy" and .metadata.name == "argocd-redis")
      | .spec.podSelector.matchLabels) = {}
  ' "$1"
}

mut_wrong_component_selector() {
  yq -i '
    (select(.kind == "NetworkPolicy" and .metadata.name == "argocd-redis")
      | .spec.podSelector.matchLabels."app.kubernetes.io/name") = "unrelated-workload"
  ' "$1"
}

mut_open_redis_ingress() {
  yq -i '
    (select(.kind == "NetworkPolicy" and .metadata.name == "argocd-redis")
      | .spec.ingress) = [{}]
  ' "$1"
}

mut_close_server_ingress() {
  yq -i '
    (select(.kind == "NetworkPolicy" and .metadata.name == "argocd-server")
      | .spec.ingress) = [{"from": [{"namespaceSelector": {"matchLabels": {"blocked": "true"}}}]}]
  ' "$1"
}

mut_wrong_redis_port() {
  yq -i '
    (select(.kind == "NetworkPolicy" and .metadata.name == "argocd-redis")
      | .spec.ingress[0].ports[0].port) = "http"
  ' "$1"
}

mut_wrong_policy_type() {
  yq -i '
    (select(.kind == "NetworkPolicy" and .metadata.name == "argocd-redis")
      | .spec.policyTypes) = ["Egress"]
  ' "$1"
}

mut_drop_repo_server_policy() {
  yq -i '
    del(select(.kind == "NetworkPolicy" and .metadata.name == "argocd-repo-server"))
  ' "$1"
}

mut_add_sixth_policy() {
  # Growth is a posture change too, and the exact-set comparison is what catches
  # it: a sixth policy could police a component the five do not, or shadow one
  # of them, and neither shows up in a per-policy comparison of the five.
  cat >> "$1" <<'NPEOF'
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: argocd-unexpected
  namespace: argocd
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/instance: argocd
      app.kubernetes.io/name: argocd-unexpected
  policyTypes:
    - Ingress
  ingress:
    - {}
NPEOF
}

mut_wrong_namespace() {
  # NetworkPolicy is namespaced: five byte-identical policies in another namespace
  # enforce nothing in argocd, and the namespace is a hand-editable literal in the
  # committed render (kustomization.yaml applies no namespace transform).
  yq -i '
    (select(.kind == "NetworkPolicy") | .metadata.namespace) = "argocd-system"
  ' "$1"
}

mut_foreign_policy_kind() {
  # An AdminNetworkPolicy Deny outranks every NetworkPolicy allow rule, and the
  # kind filter in the comparison cannot see it.
  cat >> "$1" <<'ANPEOF'
---
apiVersion: policy.networking.k8s.io/v1alpha1
kind: AdminNetworkPolicy
metadata:
  name: argocd-deny-all
spec:
  priority: 10
  subject:
    namespaces:
      matchLabels:
        kubernetes.io/metadata.name: argocd
  ingress:
    - name: deny-all
      action: Deny
      from:
        - namespaces: {}
ANPEOF
}

mut_rename_container_port() {
  # The policy documents stay byte-identical; the allow rule silently stops
  # matching because the target pod no longer declares the named port.
  yq -i '
    (select(.kind == "Deployment" and .metadata.name == "argocd-redis")
      | .spec.template.spec.containers[0].ports[0].name) = "redis-tcp"
  ' "$1"
}

# scenario <expected-exit> <expected-output> <mutator|-> <label>
scenario() {
  local want_exit="$1" pattern="$2" mutator="$3" label="$4"
  local copy="${work}/manifests.yaml" out got=0

  cp "$src" "$copy"
  if [ "$mutator" != "-" ]; then
    if ! "$mutator" "$copy"; then
      echo "ERROR: bite-check setup failed while applying ${mutator}" >&2
      exit 2
    fi
    if cmp -s "$src" "$copy"; then
      echo "  SETUP BROKEN: ${mutator} changed nothing"
      rc=1
      return
    fi
  fi

  out="$("$gate" "bite-check" "$copy" 2>&1)" || got=$?
  if [ "$got" != "$want_exit" ]; then
    echo "  FAIL  ${label} (exit ${got}, expected ${want_exit})"
    printf '%s\n' "$out" | sed 's/^/          /'
    rc=1
    return
  fi
  if ! printf '%s\n' "$out" | grep -qF "$pattern"; then
    echo "  FAIL  ${label} (exit ${got}, but no '${pattern}' in output)"
    printf '%s\n' "$out" | sed 's/^/          /'
    rc=1
    return
  fi
  echo "  PASS  ${label}"
}

echo "== ArgoCD NetworkPolicy I6 bite-check =="
scenario 0 "NetworkPolicy posture holds" - \
  "control render satisfies the exact policy posture"
scenario 3 "selector or ingress posture changed" mut_empty_match_labels \
  "empty matchLabels cannot select every pod in argocd"
scenario 3 "selector or ingress posture changed" mut_wrong_component_selector \
  "a policy cannot select an unrelated component"
scenario 3 "selector or ingress posture changed" mut_open_redis_ingress \
  "redis cannot become open to every source"
scenario 3 "selector or ingress posture changed" mut_close_server_ingress \
  "argocd-server must remain reachable from a consumer gateway"
scenario 3 "selector or ingress posture changed" mut_wrong_redis_port \
  "redis must remain restricted to its named service port"
scenario 3 "selector or ingress posture changed" mut_wrong_policy_type \
  "the ingress-only policy type cannot drift"
scenario 3 "no longer ships exactly the chart's five" mut_drop_repo_server_policy \
  "the expected five-policy set cannot shrink"
scenario 3 "no longer ships exactly the chart's five" mut_add_sixth_policy \
  "an unexpected sixth policy cannot slip in"
scenario 3 "selector or ingress posture changed" mut_wrong_namespace \
  "the policies cannot be moved out of the argocd namespace"
scenario 3 "outside networking.k8s.io/v1 NetworkPolicy" mut_foreign_policy_kind \
  "a higher-precedence policy object cannot ride along"
scenario 3 "names a port its target workload does not declare" mut_rename_container_port \
  "a renamed containerPort cannot silently turn an allow into a deny"

if [ "$rc" = 0 ]; then
  echo "ArgoCD NetworkPolicy gate bite-check OK"
else
  echo "ERROR: ArgoCD NetworkPolicy gate bite-check failed" >&2
fi
exit "$rc"
