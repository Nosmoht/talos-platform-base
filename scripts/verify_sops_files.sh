#!/bin/sh
# Negative SOPS-presence gate — fails if ANY SOPS material exists in
# this base repository.
#
# AGENTS.md "Hard Constraints" §Tool-Agnostic Safety Invariants states:
#   "Keep secret material out of base — there is no `*.sops.yaml` in
#    this repo."
#
# The previous form of this script *validated* SOPS metadata IF SOPS
# files were found. With zero SOPS files in tree, it exited 0 with
# "discovered: 0" — false assurance. An accidentally committed
# `dummy.sops.yaml` with the `sops:` block stripped would NOT have
# tripped the gate.
#
# This inverted form makes the invariant mechanically enforced:
#   - filename match: *.sops.yaml, *.sops.yml, *.sops.json
#   - content match: any YAML file containing a top-level `sops:` key
# Either condition fires → fail.
#
# Run from repo root.

set -eu

invalid=0
hits=""

# Filename match — explicit SOPS-convention suffixes.
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

# Content match — top-level `sops:` key in any .yaml/.yml (NOT .toml;
# TOML files like .gitleaks.toml use [sops] as a table header which
# is a different shape).
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
