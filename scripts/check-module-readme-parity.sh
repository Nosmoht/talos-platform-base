#!/usr/bin/env bash
# Assert every module variable and output appears in its README's tables.
#
# WHY THIS EXISTS: `knowledge/reference/talos-cluster-module.md` used to carry a
# second copy of the interface. It was removed (2026-07-15) on the argument that
# an ungated copy rots — and it was measurably right: at deletion time the
# surviving README listed 11 of 19 outputs. But the survivor is a primary source
# of no spec, so `task spec:check-staleness` never fires on it, and
# `scripts/check-spec-partition.py` subtracts markdown from its universe. The
# deletion argument only holds if the copy that survives is the gated one. This
# is that gate.
#
# Scope, honestly: name-level parity only. It catches an added/removed/renamed
# variable or output that never reached the README — the drift that actually
# happened. It does NOT check that a row's prose still describes the thing
# (a changed default, a tightened validation); that stays reviewer judgment.
#
# Exit: 0 parity holds, 1 a name is missing (the assertion), 2 environment error.
set -uo pipefail

fail=0

die_env() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 2
}

command -v git >/dev/null 2>&1 || die_env "git not on PATH"

modules=$(find tofu/modules -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
[ -n "$modules" ] || die_env "no module directories under tofu/modules"

for m in $modules; do
  readme="$m/README.md"
  [ -f "$readme" ] || die_env "$m has no README.md"
  printf '%s\n' "$m"

  for kind in variable output; do
    file="$m/${kind}s.tf"
    [ -f "$file" ] || die_env "$m has no ${kind}s.tf"

    names=$(sed -n "s/^${kind} \"\([^\"]*\)\".*/\1/p" "$file" | sort)
    [ -n "$names" ] || die_env "no ${kind}s parsed from $file — parser broken, not a clean sheet"

    count=0
    for n in $names; do
      count=$((count + 1))
      # The README documents these as markdown table rows: | `name` | ...
      if ! grep -qF "| \`$n\`" "$readme"; then
        printf '  FAIL — %s `%s` is declared in %s but absent from %s\n' \
          "$kind" "$n" "$file" "$readme" >&2
        fail=1
      fi
    done
    printf '  ok   — all %s %ss present in README\n' "$count" "$kind"
  done
done

if [ "$fail" -ne 0 ]; then
  cat >&2 <<'EOF'

FAIL: a module README is out of parity with its .tf interface.

The README tables are HAND-MAINTAINED — `task tofu:docs` cannot fix this (no
module carries BEGIN_TF_DOCS markers; it refuses rather than append a second
table set). Add the missing rows by hand.
EOF
  exit 1
fi
printf '\nOK: every module variable/output appears in its README\n'
