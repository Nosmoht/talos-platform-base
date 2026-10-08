#!/usr/bin/env bash
# I7: every Argo CD container runs the pinned chart's image. Exit 3 = violation, 2 = render shape changed.
set -euo pipefail

[ "$#" = 4 ] || { echo "usage: $0 <label> <render.yaml> <pinned-image> <workload/container,...>" >&2; exit 1; }
label="$1"
render="$2"
pinned_image="$3"
argocd_containers="$4"

command -v yq >/dev/null 2>&1 || { echo "::error::required tool not found on PATH: yq" >&2; exit 1; }
[ -f "$render" ] || { echo "::error::[${label}] render missing: $render" >&2; exit 1; }
[ -n "$argocd_containers" ] || { echo "::error::[${label}] empty Argo CD container list — I7 has no oracle" >&2; exit 2; }

listing="$(yq e 'select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job") | .metadata.name as $w | ((.spec.template.spec.initContainers // []) + (.spec.template.spec.containers // [])) | .[] | $w + "/" + .name + " " + .image' "$render" |
  grep -vE '^(---)?$' || true)"

if ! printf '%s\n' "$listing" | awk -v img="$pinned_image" '$2 == img {found=1} END {exit !found}'; then
  echo "::error::[${label}] anchor: no container runs ${pinned_image} — I7 would pass vacuously; the chart render shape changed." >&2
  exit 2
fi

# A container is Argo CD's when the chart-default render runs it on the pinned image, or when its
# image names an argocd repository under any registry, tag or digest.
stray="$(printf '%s\n' "$listing" | awk -v img="$pinned_image" -v known="$argocd_containers" '
  BEGIN {n = split(known, k, ","); for (i = 1; i <= n; i++) argocd[k[i]] = 1}
  $2 != img && (($1 in argocd) || $2 ~ /(^|\/)argocd[:@]/) {print}')"
if [ -n "$stray" ]; then
  echo "::error::[${label}] I7 violated: an Argo CD container does not run the pinned chart's image ${pinned_image}:" >&2
  printf '%s\n' "$stray" | sed 's/^/    /' >&2
  exit 3
fi
