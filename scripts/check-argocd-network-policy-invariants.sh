#!/usr/bin/env bash
# Assert the exact ArgoCD component NetworkPolicy posture carried by a render.
#
# Usage: check-argocd-network-policy-invariants.sh <label> <render.yaml>
#
# Exit codes:
#   0  posture holds
#   1  usage / environment error
#   2  the render could not be parsed
#   3  the policy set or a selector/ingress posture changed
#
# A missing or extra policy is exit 3, not 2: unlike I1-I5 this invariant is
# POSITIVE, so the substrate's network posture disappearing IS the violation and
# not merely a precondition that would leave a negative check passing vacuously.
# Exit 2 stays reserved for a render the gate could not read, so a lost posture
# is never reported in the same channel as a `helm pull` failure — and so the
# caller accumulates it with the other invariants instead of aborting the run.
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

# The canonical posture deliberately binds apiVersion, namespace, selectors,
# ingress peers/ports and policyTypes. JSON keeps empty objects unambiguous;
# sorting whole policy lines makes document order irrelevant. Array order remains
# an explicit review surface even where Kubernetes treats the entries as a set.
#
# apiVersion and namespace are in the comparison because NetworkPolicy is
# namespaced and group-scoped: five byte-identical policies emitted into another
# namespace, or under another API group, enforce NOTHING in `argocd` while a
# name-and-spec comparison reports the posture intact. The namespace here is a
# literal in the committed render — kustomization.yaml sets no namespace
# transform — so it is hand-editable, which is exactly why it is bound.
#
# REGENERATING THIS BLOCK IS RE-DECIDING THE FLOOR, not recording a diff. On a
# chart bump the honest procedure is: read the new render's policies, decide for
# each changed peer/port whether the base wants it, and only then paste. The
# heredoc encodes WHAT is permitted, never why — the component README's I6 row
# and UPGRADING carry the why, and both move with it.
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

# No higher-precedence policy object may ride along. The comparison above filters
# on `kind == "NetworkPolicy"`, so a document of another policy kind is invisible
# to it — and an AdminNetworkPolicy Deny outranks every NetworkPolicy allow rule,
# while the substrate CNI (Cilium, deploy_cilium default true) enforces its own
# CRDs alongside the core API. A render carrying a total default-deny for the
# argocd namespace would otherwise report the floor intact.
foreign="$(yq e 'select(.kind == "AdminNetworkPolicy" or .kind == "BaselineAdminNetworkPolicy" or .kind == "CiliumNetworkPolicy" or .kind == "CiliumClusterwideNetworkPolicy") | .kind + "/" + (.metadata.name // "<no-name>")' \
  "$render" 2>/dev/null | grep -vE '^(---|\.\.\.| *)$' | sort -u || true)"
if [ -n "$foreign" ]; then
  echo "::error::[${label}] I6 violated: the render carries a policy object outside networking.k8s.io/v1 NetworkPolicy, which can outrank the posture above:" >&2
  printf '%s\n' "$foreign" | sed 's/^/      /' >&2
  exit 3
fi

# Named ports are resolved against the TARGET POD's containerPort names, not
# against the policy — so a workload that renames a port turns an allow rule into
# a rule matching nothing, i.e. a silent deny, with every NetworkPolicy document
# byte-identical. That is a cross-resource invariant the comparison above cannot
# see, so it is checked against the workloads in the same render.
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
