#!/bin/sh
set -eu

work_dir=${WORK_DIR:-.work}
policy_dir=${POLICY_DIR:-policies/conftest}
rendered_list=${1:-"$work_dir/kustomize-rendered-files.txt"}
apps_list=${2:-"$work_dir/argocd-applications.txt"}
rendered_report="$work_dir/conftest-rendered.txt"
apps_report="$work_dir/conftest-applications.txt"

if [ ! -d "$policy_dir" ]; then
  echo "error: policy directory not found: $policy_dir"
  exit 1
fi

mkdir -p "$work_dir"
rm -f "$rendered_report" "$apps_report"

status=0

run_conftest_for_list() {
  label=$1
  list_file=$2
  report_file=$3
  enforce=$4   # 1 = fail CI on findings; 0 = informational only

  if [ ! -f "$list_file" ]; then
    echo "notice: $label list not found, skipping: $list_file"
    : > "$report_file"
    return
  fi

  set --
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue
    set -- "$@" "$f"
  done < "$list_file"

  if [ "$#" -eq 0 ]; then
    echo "notice: no $label files to test"
    : > "$report_file"
    return
  fi

  echo "conftest: testing $label files ($#)"
  if conftest test --all-namespaces --policy "$policy_dir" "$@" > "$report_file" 2>&1; then
    cat "$report_file"
  else
    cat "$report_file"
    if [ "$enforce" = "1" ]; then
      status=1
    else
      echo "notice: $label conftest had findings (informational, not gating)"
      echo "        rationale: rendered base components inherit upstream Helm chart"
      echo "        defaults; consumer overlays apply cluster-specific hardening"
      echo "        (resource limits, security contexts, replica counts) on top."
    fi
  fi
}

# Rendered base components: informational (upstream chart defaults).
run_conftest_for_list "rendered" "$rendered_list" "$rendered_report" 0
# ArgoCD Application CRs: enforced (we author these directly; no upstream excuse).
run_conftest_for_list "argocd application" "$apps_list" "$apps_report" 1

if [ "$status" -ne 0 ]; then
  echo "conftest policy checks failed"
  exit 1
fi

echo "conftest policy checks passed"
