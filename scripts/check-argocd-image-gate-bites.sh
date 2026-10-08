#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
src="${repo_root}/kubernetes/substrate/argocd/_rendered/manifests.yaml"
gate="${repo_root}/scripts/check-argocd-image-invariant.sh"

command -v yq >/dev/null 2>&1 || { echo "ERROR: yq is required" >&2; exit 2; }
[ -f "$src" ] || { echo "ERROR: $src missing" >&2; exit 2; }
[ -x "$gate" ] || { echo "ERROR: $gate missing or not executable" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
rc=0

# Gate bites are measured against the committed render's own image and container set;
# the substrate invariant gate derives both from the pinned chart instead.
pinned_image="$(yq e '(select(.kind == "Deployment" and .metadata.name == "argocd-server") | .spec.template.spec.containers[] | select(.name == "server") | .image)' "$src" | grep -v '^---$')"
case "$pinned_image" in
  quay.io/argoproj/argocd:*) ;;
  *) echo "ERROR: could not read the argocd-server image from $src" >&2; exit 2 ;;
esac
argocd_containers="$(yq e 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "Job") | .metadata.name as $w | ((.spec.template.spec.initContainers // []) + .spec.template.spec.containers) | .[] | select(.image == "'"${pinned_image}"'") | $w + "/" + .name' "$src" | grep -vE '^(---)?$' | sort -u | paste -sd, -)"

mut_other_tag() {
  yq -i '(select(.kind == "Deployment" and .metadata.name == "argocd-repo-server") | .spec.template.spec.containers[] | select(.name == "repo-server") | .image) = "quay.io/argoproj/argocd:v0.0.0-mutant"' "$1"
}

mut_other_repository() {
  yq -i '(select(.kind == "Deployment" and .metadata.name == "argocd-server") | .spec.template.spec.containers[] | select(.name == "server") | .image) = "ghcr.io/example/gitops-server:mutant"' "$1"
}

mut_digest_form() {
  yq -i '(select(.kind == "StatefulSet" and .metadata.name == "argocd-application-controller") | .spec.template.spec.containers[] | select(.name == "application-controller") | .image) = "quay.io/argoproj/argocd@sha256:0000000000000000000000000000000000000000000000000000000000000000"' "$1"
}

mut_no_pinned_image() {
  local spec='select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "Job") | .spec.template.spec'
  yq -i "(${spec} | .containers[] | select(.image == \"${pinned_image}\") | .image) = \"ghcr.io/example/other:mutant\"" "$1"
  yq -i "(${spec} | .initContainers[]? | select(.image == \"${pinned_image}\") | .image) = \"ghcr.io/example/other:mutant\"" "$1"
}

# scenario <expected-exit> <expected-output-pattern> <mutator|-> <label>
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

  out="$("$gate" "bite" "$copy" "$pinned_image" "$argocd_containers" 2>&1)" || got=$?
  if [ "$got" != "$want_exit" ]; then
    echo "  FAIL  ${label} (exit ${got}, expected ${want_exit})"
    printf '%s\n' "$out" | sed 's/^/          /'
    rc=1
    return
  fi
  if [ -n "$pattern" ] && ! printf '%s\n' "$out" | grep -qF "$pattern"; then
    echo "  FAIL  ${label} (exit ${got}, but no '${pattern}' in output)"
    printf '%s\n' "$out" | sed 's/^/          /'
    rc=1
    return
  fi
  echo "  PASS  ${label}"
}

echo "== ArgoCD image I7 bite-check =="
scenario 0 "" - \
  "control render runs the pinned image in every Argo CD container"
scenario 3 "argocd-repo-server/repo-server" mut_other_tag \
  "an Argo CD container cannot carry another tag"
scenario 3 "argocd-server/server" mut_other_repository \
  "an Argo CD container cannot move to another repository"
scenario 3 "argocd-application-controller/application-controller" mut_digest_form \
  "a digest reference cannot stand in for the pinned tag"
scenario 2 "anchor: no container runs" mut_no_pinned_image \
  "a render without the pinned image fails as a shape change, not a pass"
if [ "$rc" = 0 ]; then
  echo "ArgoCD image gate bite-check OK"
else
  echo "ERROR: ArgoCD image gate bite-check failed" >&2
fi
exit "$rc"
