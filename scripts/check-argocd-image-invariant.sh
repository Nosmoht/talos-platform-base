#!/usr/bin/env bash
# I7: every container image in the render is the chart's pinned Argo CD image or one of the
# chart's own non-Argo-CD image repositories. Exit 3 = violation, 2 = render or chart shape changed.
set -euo pipefail

[ "$#" = 3 ] || { echo "usage: $0 <label> <render.yaml> <chart.tgz>" >&2; exit 1; }
label="$1"
render="$2"
tgz="$3"

for t in helm yq; do
  command -v "$t" >/dev/null 2>&1 || { echo "::error::required tool not found on PATH: $t" >&2; exit 1; }
done
[ -f "$render" ] || { echo "::error::[${label}] render missing: $render" >&2; exit 1; }
[ -f "$tgz" ] || { echo "::error::[${label}] chart tarball missing: $tgz" >&2; exit 1; }

app_version="$(helm show chart "$tgz" 2>/dev/null | yq -e '.appVersion')" || { echo "::error::[${label}] could not read appVersion from $tgz" >&2; exit 2; }
pinned_repository="$(helm show values "$tgz" 2>/dev/null | yq -e '.global.image.repository')" || { echo "::error::[${label}] could not read global.image.repository from $tgz" >&2; exit 2; }
pinned_image="${pinned_repository}:${app_version}"
# viaductoss/ksops is the init container the base itself adds to the repo-server.
allowed_repositories="$(helm show values "$tgz" 2>/dev/null |
  yq e '.. | select(type == "!!map" and has("repository")) | .repository | select(. != "")' - |
  grep -vxF "$pinned_repository" | { cat; echo "viaductoss/ksops"; } | sort -u | paste -sd, -)"

# Every string `image` beside a `name` is a container, whatever kind or nesting carries it.
images="$(yq e '.. | select(type == "!!map" and has("image") and has("name")) | select(.image | type == "!!str") | .image' "$render" |
  grep -vE '^(---)?$' | sort -u || true)"

if ! printf '%s\n' "$images" | grep -qxF "$pinned_image"; then
  echo "::error::[${label}] anchor: no container runs ${pinned_image} — I7 would pass vacuously; the chart render shape changed." >&2
  exit 2
fi

stray="$(printf '%s\n' "$images" | awk -v img="$pinned_image" -v allowed="$allowed_repositories" '
  BEGIN {n = split(allowed, a, ","); for (i = 1; i <= n; i++) ok[a[i]] = 1}
  $0 == img {next}
  {repo = $0; sub(/@.*/, "", repo); if (match(repo, /:[^\/]*$/)) repo = substr(repo, 1, RSTART - 1)}
  !(repo in ok) {print}')"
if [ -n "$stray" ]; then
  echo "::error::[${label}] I7 violated: a container image is neither the pinned chart's ${pinned_image} nor one of the chart's other image repositories:" >&2
  printf '%s\n' "$stray" | sed 's/^/    /' >&2
  exit 3
fi
