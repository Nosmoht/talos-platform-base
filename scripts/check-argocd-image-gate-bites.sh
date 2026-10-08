#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
src="${repo_root}/kubernetes/substrate/argocd/_rendered/manifests.yaml"
lock="${repo_root}/kubernetes/substrate/argocd/chart.lock.yaml"
gate="${repo_root}/scripts/check-argocd-image-invariant.sh"

for t in helm yq; do
  command -v "$t" >/dev/null 2>&1 || { echo "ERROR: $t is required" >&2; exit 2; }
done
[ -f "$src" ] || { echo "ERROR: $src missing" >&2; exit 2; }
[ -x "$gate" ] || { echo "ERROR: $gate missing or not executable" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
rc=0

repo="$(yq -e '.chart.repo' "$lock")"
name="$(yq -e '.chart.name' "$lock")"
version="$(yq -e '.chart.version' "$lock")"
expected_sha="$(yq -e '.chart.tgz_sha256' "$lock")"
helm pull "$name" --repo "$repo" --version "$version" --destination "$work" >/dev/null 2>&1 ||
  { echo "ERROR: helm pull failed for ${name}@${version}" >&2; exit 2; }
tgz="${work}/${name}-${version}.tgz"
[ "$(shasum -a 256 "$tgz" | awk '{print $1}')" = "$expected_sha" ] ||
  { echo "ERROR: chart sha256 mismatch for ${name}@${version}" >&2; exit 2; }
pinned_image="quay.io/argoproj/argocd:$(helm show chart "$tgz" | yq -e '.appVersion')"

set_image() {
  yq -i "(select(.kind == \"$2\" and .metadata.name == \"$3\") | .spec.template.spec.$4[] | select(.name == \"$5\") | .image) = \"$6\"" "$1"
}

mut_other_tag()        { set_image "$1" Deployment argocd-repo-server containers repo-server "quay.io/argoproj/argocd:v0.0.0-mutant"; }
mut_untagged()         { set_image "$1" Deployment argocd-server containers server "quay.io/argoproj/argocd"; }
mut_digest_form()      { set_image "$1" StatefulSet argocd-application-controller containers application-controller "quay.io/argoproj/argocd@sha256:0000000000000000000000000000000000000000000000000000000000000000"; }
mut_init_container()   { set_image "$1" Deployment argocd-repo-server initContainers copyutil "ghcr.io/example/copyutil:mutant"; }

mut_renamed_container() {
  yq -i '(select(.kind == "Deployment" and .metadata.name == "argocd-server") | .spec.template.spec.containers[] | select(.name == "server")) |= (.name = "renamed" | .image = "ghcr.io/example/gitops-server:mutant")' "$1"
}

mut_extra_cronjob() {
  cat >> "$1" <<'YAML'
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: argocd-mutant
  namespace: argocd
spec:
  schedule: "0 0 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: mutant
              image: quay.io/argoproj/argocd:v2.0.0
YAML
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

  out="$("$gate" "bite" "$copy" "$tgz" 2>&1)" || got=$?
  if [ "$got" != "$want_exit" ]; then
    echo "  FAIL  ${label} (exit ${got}, expected ${want_exit})"
    printf '%s\n' "$out" | sed 's/^/          /'
    rc=1
    return
  fi
  if [ -n "$pattern" ] && ! printf '%s\n' "$out" | grep -qF -- "$pattern"; then
    echo "  FAIL  ${label} (exit ${got}, but no '${pattern}' in output)"
    printf '%s\n' "$out" | sed 's/^/          /'
    rc=1
    return
  fi
  echo "  PASS  ${label}"
}

echo "== ArgoCD image I7 bite-check =="
scenario 0 "" - \
  "control render: every image is the pinned one or a chart-declared repository"
scenario 3 "quay.io/argoproj/argocd:v0.0.0-mutant" mut_other_tag \
  "an Argo CD container cannot carry another tag"
scenario 3 "    quay.io/argoproj/argocd" mut_untagged \
  "an untagged Argo CD image cannot stand in for the pinned tag"
scenario 3 "argocd@sha256:" mut_digest_form \
  "a digest reference cannot stand in for the pinned tag"
scenario 3 "ghcr.io/example/copyutil:mutant" mut_init_container \
  "an init container cannot move to another repository"
scenario 3 "ghcr.io/example/gitops-server:mutant" mut_renamed_container \
  "a renamed container cannot move to another repository"
scenario 3 "quay.io/argoproj/argocd:v2.0.0" mut_extra_cronjob \
  "a CronJob cannot ride along with another Argo CD release"
scenario 2 "anchor: no container runs" mut_no_pinned_image \
  "a render without the pinned image fails as a shape change, not a pass"
if [ "$rc" = 0 ]; then
  echo "ArgoCD image gate bite-check OK"
else
  echo "ERROR: ArgoCD image gate bite-check failed" >&2
fi
exit "$rc"
