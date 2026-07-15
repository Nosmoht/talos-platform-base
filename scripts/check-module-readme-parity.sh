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
# Scope, honestly: name-level parity, in the .tf -> README direction only.
#   * It catches an added or renamed variable/output that never reached the
#     README — the drift that actually happened (11 of 19 outputs documented).
#   * It does NOT catch a README row for a DELETED declaration: nothing walks
#     the table rows back to the .tf files. A stale row survives.
#   * It does NOT check that a row's prose still describes the thing — a changed
#     default or a tightened validation is reviewer judgment.
# The grep is scoped to the section that documents each kind. Unscoped, it
# false-passes: `cluster_endpoint` is BOTH a variable and an output, so the
# Inputs row satisfied a search for the output and deleting the Outputs row
# stayed green (verified — that is why the scoping exists).
#
# Exit: 0 parity holds, 1 a name is missing (the assertion), 2 environment error.
set -uo pipefail

fail=0

die_env() {
  printf 'ERROR: %s\n' "$1" >&2
  exit 2
}

modules=$(find tofu/modules -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
[ -n "$modules" ] || die_env "no module directories under tofu/modules"

for m in $modules; do
  readme="$m/README.md"
  [ -f "$readme" ] || die_env "$m has no README.md"
  printf '%s\n' "$m"

  for kind in variable output; do
    file="$m/${kind}s.tf"
    [ -f "$file" ] || die_env "$m has no ${kind}s.tf"

    case "$kind" in
      variable) heading="Inputs" ;;
      output)   heading="Outputs" ;;
    esac
    # Everything from `## <heading>` to the next `## ` — the tables that
    # document this kind, and nothing else.
    section=$(awk -v h="## $heading" '
      $0 == h { inside = 1; next }
      inside && /^## / { exit }
      inside { print }
    ' "$readme")
    [ -n "$section" ] || die_env "$readme has no '## $heading' section — cannot scope the $kind check"

    names=$(sed -n "s/^${kind} \"\([^\"]*\)\".*/\1/p" "$file" | sort)
    [ -n "$names" ] || die_env "no ${kind}s parsed from $file — parser broken, not a clean sheet"

    count=0
    kind_fail=0
    for n in $names; do
      count=$((count + 1))
      # Documented as a markdown table row: | `name` | ...
      if ! printf '%s\n' "$section" | grep -qF "| \`$n\`"; then
        printf '  FAIL — %s `%s` is declared in %s but absent from the ## %s section of %s\n' \
          "$kind" "$n" "$file" "$heading" "$readme" >&2
        fail=1
        kind_fail=1
      fi
    done
    # Conditional: an unconditional "ok — all N present" printed alongside the
    # FAILs above would contradict the verdict in the part of the log a CI
    # reader actually scans.
    [ "$kind_fail" -eq 0 ] && printf '  ok   — all %s %ss present in the ## %s section\n' "$count" "$kind" "$heading"
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
