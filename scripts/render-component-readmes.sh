#!/usr/bin/env bash
# render-component-readmes.sh — generate per-component README.md files
# under kubernetes/substrate/<comp>/.
#
# Per knowledge/workflows/issue-lifecycle.md issue #35: each component dir must contain
# a README with sections (Purpose, Upstream chart, Namespace,
# Helm-value overrides, Upgrade gotchas).
#
# Auto-extracted fields:
#   - chart repo/name/version  (from chart.lock.yaml when present)
#   - namespace name (from namespace.yaml)
#   - Helm top-level value keys (from values.yaml when present)
#
# Hand-curated fields live in the PURPOSE and GOTCHAS associative
# arrays below. Updating these is a deliberate doc act; the script is
# the deterministic glue, not the source of judgement.
#
# Usage:
#   scripts/render-component-readmes.sh           # write all renderable READMEs
#   scripts/render-component-readmes.sh --check   # exit 1 on drift
#   scripts/render-component-readmes.sh <comp>    # write only <comp>'s README

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFRA_DIR="$REPO_ROOT/kubernetes/substrate"
COMP_LIST="$REPO_ROOT/.ci-renderable-components.txt"

command -v yq >/dev/null 2>&1 || { echo "ERROR: yq not found in PATH" >&2; exit 2; }
[ -f "$COMP_LIST" ] || { echo "ERROR: $COMP_LIST not found" >&2; exit 2; }

# Hand-curated per-component metadata. bash 3.2 lacks `declare -A`, so
# both fields are exposed as case-statement functions instead.

purpose_of() {
  case "$1" in
    argocd) echo "ArgoCD GitOps engine — reconciles every other component in this base from git source via Multi-Source Applications." ;;
    *) echo "Cluster-agnostic Helm base for $1." ;;
  esac
}

gotchas_of() {
  case "$1" in
    argocd) cat <<'GOTEOF'
- A bare `AppProject` (sync-wave -1) must reconcile before any Application (sync-wave 0) that references it.
- The base ships the ArgoCD chart and CRDs but not the root `Application` — consumer repos own that bootstrap.
GOTEOF
      ;;
    *) echo "(none documented yet)" ;;
  esac
}

render_one() {
  local comp="$1"
  local dir="$INFRA_DIR/$comp"
  [ -d "$dir" ] || { echo "skip: $comp — no directory" >&2; return; }

  local purpose
  purpose="$(purpose_of "$comp")"
  local gotchas
  gotchas="$(gotchas_of "$comp")"

  local chart_block="This component is not Helm-based; it installs upstream YAML directly via kustomize."
  if [ -f "$dir/chart.lock.yaml" ]; then
    local repo name version
    repo="$(yq -r '.chart.repo' "$dir/chart.lock.yaml")"
    name="$(yq -r '.chart.name' "$dir/chart.lock.yaml")"
    version="$(yq -r '.chart.version' "$dir/chart.lock.yaml")"
    chart_block="- **Chart:** [\`$name\`]($repo)
- **Pinned version:** \`$version\`
- **Lock file:** [\`chart.lock.yaml\`](./chart.lock.yaml) — includes \`tgz_sha256\` for reproducible renders."
  fi

  local ns_name="(no namespace.yaml)"
  if [ -f "$dir/namespace.yaml" ]; then
    ns_name="$(yq -r '.metadata.name // "?"' "$dir/namespace.yaml")"
  fi

  local values_block="(no values.yaml — component does not override defaults)"
  if [ -f "$dir/values.yaml" ]; then
    local keys
    keys="$(yq -r 'keys | .[]' "$dir/values.yaml" 2>/dev/null | sed 's/^/- `/; s/$/`/')"
    if [ -n "$keys" ]; then
      values_block="$keys"
    fi
  fi

  cat <<EOF > "$dir/README.md"
# \`$comp\`

**Purpose:** $purpose

## Upstream chart source

$chart_block

## Namespace

Deploys into namespace \`$ns_name\`. See [\`namespace.yaml\`](./namespace.yaml) for the full PSA label set.

## Repo-specific Helm-value overrides

Top-level keys in [\`values.yaml\`](./values.yaml) — anything not listed below uses the upstream chart's default:

$values_block

## Known upgrade gotchas

$gotchas

## See also

- [\`knowledge/reference/manifest-pipeline.md\`](../../../../knowledge/reference/manifest-pipeline.md) — how this component is rendered into \`_rendered/manifests.yaml\`
- [\`UPGRADING.md\`](../../../../UPGRADING.md) — release-to-release migration steps
EOF

  echo "wrote $dir/README.md"
}

mode="write"
single=""
case "${1:-}" in
  --check) mode="check" ;;
  --help|-h) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  "") ;;
  *) single="$1" ;;
esac

if [ "$mode" = "check" ]; then
  # Render to tmpdir, diff against committed.
  fails=0
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  while IFS= read -r comp; do
    [ -n "$comp" ] || continue
    target="$INFRA_DIR/$comp/README.md"
    if [ ! -f "$target" ]; then
      echo "missing: $target" >&2
      fails=$((fails + 1))
      continue
    fi
    INFRA_DIR_BACKUP="$INFRA_DIR"
    INFRA_DIR="$tmpdir"
    mkdir -p "$tmpdir/$comp"
    cp -R "$INFRA_DIR_BACKUP/$comp"/. "$tmpdir/$comp/"
    rm -f "$tmpdir/$comp/README.md"
    render_one "$comp" >/dev/null
    if ! diff -u "$target" "$tmpdir/$comp/README.md" >&2; then
      echo "drift: $target" >&2
      fails=$((fails + 1))
    fi
    INFRA_DIR="$INFRA_DIR_BACKUP"
  done < "$COMP_LIST"
  if [ "$fails" -gt 0 ]; then
    echo "ERROR: $fails README(s) out of date" >&2
    exit 1
  fi
  echo "OK: all component READMEs match render"
  exit 0
fi

if [ -n "$single" ]; then
  render_one "$single"
  exit 0
fi

while IFS= read -r comp; do
  [ -n "$comp" ] || continue
  render_one "$comp"
done < "$COMP_LIST"
