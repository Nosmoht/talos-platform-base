#!/bin/sh
# Reject SOPS filenames and top-level SOPS metadata anywhere in the base repository.

set -eu

invalid=0
hits=""

filename_matches=$(find . -type f \
  \( -name '*.sops.yaml' -o -name '*.sops.yml' -o -name '*.sops.json' \) \
  ! -path './.git/*' \
  ! -path './_release/*' \
  ! -path './vendor/*' \
  ! -path './third_party/*' \
  ! -path './.work/*' \
  ! -path './Plans/*' 2>/dev/null || true)

if [ -n "$filename_matches" ]; then
  invalid=1
  hits=$(printf '%s\n' "$filename_matches" | while IFS= read -r f; do
    [ -n "$f" ] && printf 'filename: %s\n' "$f"
  done)
fi

has_top_level_sops_yaml() {
  awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*---[[:space:]]*$/ { next }
    /^sops:[[:space:]]*$/ { found=1; exit 0 }
    END { exit(found ? 0 : 1) }
  ' "$1"
}

content_hits=""
NL='
'
while IFS= read -r file; do
  [ -n "$file" ] || continue
  if has_top_level_sops_yaml "$file"; then
    content_hits="${content_hits}content: ${file}${NL}"
  fi
done <<EOF
$(find . -type f \( -name '*.yaml' -o -name '*.yml' \) \
  ! -path './.git/*' \
  ! -path './_release/*' \
  ! -path './vendor/*' \
  ! -path './third_party/*' \
  ! -path './.work/*' \
  ! -path './Plans/*' 2>/dev/null || true)
EOF

if [ -n "$content_hits" ]; then
  invalid=1
  hits="${hits}${hits:+${NL}}${content_hits}"
fi

if [ "$invalid" -ne 0 ]; then
  echo "FAIL: SOPS material detected in base repository (forbidden per AGENTS.md hard-constraint)" >&2
  printf '%s\n' "$hits" >&2
  echo "" >&2
  echo "Fix: SOPS encryption belongs in CONSUMER cluster repos, not in this base." >&2
  echo "If a file legitimately contains a top-level 'sops:' field for parser-spec testing," >&2
  echo "either rename it to escape the pattern OR add an explicit exclude to this script's find filter." >&2
  exit 1
fi

echo "OK: no SOPS material present in base repository"
exit 0
