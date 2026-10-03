#!/usr/bin/env bash
set -euo pipefail

[ "$#" = 2 ] || { echo "usage: $0 <label> <render.yaml>" >&2; exit 1; }
label="$1"
render="$2"

command -v yq >/dev/null 2>&1 || { echo "::error::required tool not found on PATH: yq" >&2; exit 1; }
[ -f "$render" ] || { echo "::error::[${label}] render missing: $render" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
names_out="$tmp/names"
names_err="$tmp/names.err"

expected_names='argocd-application-controller
argocd-notifications-controller
argocd-redis
argocd-repo-server
argocd-server'

if ! yq e 'select(.kind == "NetworkPolicy") | .metadata.name' "$render" > "$names_out" 2> "$names_err"; then
  echo "::error::[${label}] yq could not list the render's NetworkPolicy names" >&2
  sed 's/^/    /' "$names_err" >&2
  exit 2
fi
found="$(grep -vE '^(---|\.\.\.| *)$' "$names_out" | sort -u || true)"
if [ "$found" != "$expected_names" ]; then
  echo "::error::[${label}] I6 violated: the substrate no longer ships exactly the chart's five per-component NetworkPolicies — its network posture changed, or an override disabled global.networkPolicy.create:" >&2
  echo "    expected:" >&2
  printf '%s\n' "$expected_names" | sed 's/^/      /' >&2
  echo "    found:" >&2
  printf '%s\n' "${found:-<none>}" | sed 's/^/      /' >&2
  exit 3
fi

# Changing expected peers or ports requires policy review before updating this fixture.
cat > "$tmp/expected" <<'EOF'
{"apiVersion":"networking.k8s.io/v1","name":"argocd-application-controller","namespace":"argocd","spec":{"ingress":[{"from":[{"namespaceSelector":{}}],"ports":[{"port":"metrics"}]}],"podSelector":{"matchLabels":{"app.kubernetes.io/instance":"argocd","app.kubernetes.io/name":"argocd-application-controller"}},"policyTypes":["Ingress"]}}
{"apiVersion":"networking.k8s.io/v1","name":"argocd-notifications-controller","namespace":"argocd","spec":{"ingress":[{"from":[{"namespaceSelector":{}}],"ports":[{"port":"metrics"}]}],"podSelector":{"matchLabels":{"app.kubernetes.io/instance":"argocd","app.kubernetes.io/name":"argocd-notifications-controller"}},"policyTypes":["Ingress"]}}
{"apiVersion":"networking.k8s.io/v1","name":"argocd-redis","namespace":"argocd","spec":{"ingress":[{"from":[{"podSelector":{"matchLabels":{"app.kubernetes.io/instance":"argocd","app.kubernetes.io/name":"argocd-server"}}},{"podSelector":{"matchLabels":{"app.kubernetes.io/instance":"argocd","app.kubernetes.io/name":"argocd-repo-server"}}},{"podSelector":{"matchLabels":{"app.kubernetes.io/instance":"argocd","app.kubernetes.io/name":"argocd-application-controller"}}}],"ports":[{"port":"redis","protocol":"TCP"}]}],"podSelector":{"matchLabels":{"app.kubernetes.io/instance":"argocd","app.kubernetes.io/name":"argocd-redis"}},"policyTypes":["Ingress"]}}
{"apiVersion":"networking.k8s.io/v1","name":"argocd-repo-server","namespace":"argocd","spec":{"ingress":[{"from":[{"podSelector":{"matchLabels":{"app.kubernetes.io/instance":"argocd","app.kubernetes.io/name":"argocd-server"}}},{"podSelector":{"matchLabels":{"app.kubernetes.io/instance":"argocd","app.kubernetes.io/name":"argocd-application-controller"}}},{"podSelector":{"matchLabels":{"app.kubernetes.io/instance":"argocd","app.kubernetes.io/name":"argocd-notifications-controller"}}},{"podSelector":{"matchLabels":{"app.kubernetes.io/instance":"argocd","app.kubernetes.io/name":"argocd-applicationset-controller"}}}],"ports":[{"port":"repo-server","protocol":"TCP"}]},{"from":[{"namespaceSelector":{}}],"ports":[{"port":"metrics"}]}],"podSelector":{"matchLabels":{"app.kubernetes.io/instance":"argocd","app.kubernetes.io/name":"argocd-repo-server"}},"policyTypes":["Ingress"]}}
{"apiVersion":"networking.k8s.io/v1","name":"argocd-server","namespace":"argocd","spec":{"ingress":[{}],"podSelector":{"matchLabels":{"app.kubernetes.io/instance":"argocd","app.kubernetes.io/name":"argocd-server"}},"policyTypes":["Ingress"]}}
EOF

if ! yq -o=json -I=0 \
  'select(.kind == "NetworkPolicy") | {"apiVersion": .apiVersion, "namespace": .metadata.namespace, "name": .metadata.name, "spec": .spec} | sort_keys(..)' \
  "$render" > "$tmp/actual" 2> "$tmp/yq.err"; then
  echo "::error::[${label}] yq could not parse the NetworkPolicy render" >&2
  sed 's/^/    /' "$tmp/yq.err" >&2
  exit 2
fi

LC_ALL=C sort -o "$tmp/expected" "$tmp/expected"
LC_ALL=C sort -o "$tmp/actual" "$tmp/actual"

if ! cmp -s "$tmp/expected" "$tmp/actual"; then
  echo "::error::[${label}] I6 violated: an ArgoCD NetworkPolicy selector or ingress posture changed." >&2
  diff -u "$tmp/expected" "$tmp/actual" >&2 || true
  exit 3
fi

foreign="$(yq e 'select(.kind == "AdminNetworkPolicy" or .kind == "BaselineAdminNetworkPolicy" or .kind == "CiliumNetworkPolicy" or .kind == "CiliumClusterwideNetworkPolicy") | .kind + "/" + (.metadata.name // "<no-name>")' \
  "$render" 2>/dev/null | grep -vE '^(---|\.\.\.| *)$' | sort -u || true)"
if [ -n "$foreign" ]; then
  echo "::error::[${label}] I6 violated: the render carries a policy object outside networking.k8s.io/v1 NetworkPolicy, which can outrank the posture above:" >&2
  printf '%s\n' "$foreign" | sed 's/^/      /' >&2
  exit 3
fi

yq e 'select(.kind == "NetworkPolicy") | (.spec.podSelector.matchLabels."app.kubernetes.io/name") as $c | .spec.ingress[]?.ports[]?.port | select(tag == "!!str") | $c + " " + .' \
  "$render" 2>/dev/null | grep -vE '^(---|\.\.\.| *)$' | sort -u > "$tmp/wanted-ports" || true
yq e 'select(.kind == "Deployment" or .kind == "StatefulSet") | (.metadata.labels."app.kubernetes.io/name") as $c | .spec.template.spec.containers[].ports[]?.name | $c + " " + .' \
  "$render" 2>/dev/null | grep -vE '^(---|\.\.\.| *)$' | sort -u > "$tmp/declared-ports" || true
unresolved="$(LC_ALL=C comm -23 "$tmp/wanted-ports" "$tmp/declared-ports")"
if [ -n "$unresolved" ]; then
  echo "::error::[${label}] I6 violated: a NetworkPolicy names a port its target workload does not declare, so the rule matches nothing and the allow becomes a silent deny:" >&2
  printf '%s\n' "$unresolved" | sed 's/^/      /' >&2
  exit 3
fi

echo "OK: [${label}] ArgoCD NetworkPolicy posture holds"
