#!/usr/bin/env bash
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
      if ! printf '%s\n' "$section" | grep -F "| \`$n\`" >/dev/null; then
        printf '  FAIL — %s `%s` is declared in %s but absent from the ## %s section of %s\n' \
          "$kind" "$n" "$file" "$heading" "$readme" >&2
        fail=1
        kind_fail=1
      fi
    done
    [ "$kind_fail" -eq 0 ] && printf '  ok   — all %s %ss present in the ## %s section\n' "$count" "$kind" "$heading"
  done
done

if [ "$fail" -ne 0 ]; then
  cat >&2 <<'EOF'

FAIL: a module README is out of parity with its .tf interface.

The README tables are HAND-MAINTAINED. Add the missing rows by hand.
EOF
  exit 1
fi
printf '\nOK: every module variable/output appears in its README\n'
