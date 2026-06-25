#!/bin/sh
set -eu

# ksops-detection (is_dir_unsafe below) uses `rg` because of its
# faster recursive search. If rg is absent the find/-exec invocation
# would silently fail open — the directory gets treated as SAFE and
# any ksops-encrypted manifest would be rendered as plaintext.
# Fail loudly instead.
if ! command -v rg >/dev/null 2>&1; then
  echo "FATAL: ripgrep (rg) is required for ksops detection in render_kustomize_safe.sh" >&2
  echo "Install: brew install ripgrep   (or apt install ripgrep)" >&2
  exit 2
fi

work_dir=${WORK_DIR:-.work}
targets_file=${1:-"$work_dir/kustomize-targets.txt"}
safe_file="$work_dir/kustomize-safe-targets.txt"
unsafe_file="$work_dir/kustomize-unsafe-targets.txt"
rendered_file="$work_dir/kustomize-rendered-files.txt"
render_dir="$work_dir/rendered"

mkdir -p "$work_dir" "$render_dir"
: > "$safe_file"
: > "$unsafe_file"
: > "$rendered_file"

if [ ! -f "$targets_file" ]; then
  ./scripts/discover_kustomize_targets.sh "$targets_file"
fi

has_top_level_sops_yaml() {
  file=$1
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*---[[:space:]]*$/ { next }
    /^sops:[[:space:]]*$/ { found=1; exit 0 }
    END { exit(found ? 0 : 1) }
  ' "$file"
}

is_dir_unsafe() {
  dir=$1

  if find "$dir" -maxdepth 1 -type f \( -iname 'kustomization.yaml' -o -iname 'kustomization' \) -exec rg -qi 'ksops|sops-generator|viaduct\.ai/v1' {} +; then
    echo "kustomization contains ksops/sops generator references"
    return 0
  fi

  tmp_yaml_list=$(mktemp)
  find "$dir" -type f \( -name '*.yaml' -o -name '*.yml' \) > "$tmp_yaml_list"

  while IFS= read -r yaml_file; do
    [ -n "$yaml_file" ] || continue
    if has_top_level_sops_yaml "$yaml_file"; then
      rm -f "$tmp_yaml_list"
      echo "directory contains encrypted sops file: $yaml_file"
      return 0
    fi
  done < "$tmp_yaml_list"

  rm -f "$tmp_yaml_list"
  return 1
}

render_fail=0
safe_count=0
unsafe_count=0

while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  [ -d "$dir" ] || continue

  if reason=$(is_dir_unsafe "$dir"); then
    unsafe_count=$((unsafe_count + 1))
    printf '%s|%s\n' "$dir" "$reason" >> "$unsafe_file"
    echo "skip unsafe: $dir ($reason)"
    continue
  fi

  safe_count=$((safe_count + 1))
  printf '%s\n' "$dir" >> "$safe_file"

  slug=$(printf '%s' "$dir" | sed 's#/#__#g')
  out_yaml="$render_dir/$slug.yaml"
  out_log="$render_dir/$slug.log"

  echo "rendering: $dir"
  if kustomize build --enable-helm "$dir" > "$out_yaml" 2> "$out_log"; then
    printf '%s\n' "$out_yaml" >> "$rendered_file"
    rm -f "$out_log"
  else
    echo "error: kustomize build failed for $dir (see $out_log)"
    render_fail=1
  fi
done < "$targets_file"

echo "safe targets: $safe_count"
echo "unsafe targets: $unsafe_count"
echo "safe target list: $safe_file"
echo "unsafe target list: $unsafe_file"
echo "rendered files list: $rendered_file"

if [ "$render_fail" -ne 0 ]; then
  exit 1
fi
