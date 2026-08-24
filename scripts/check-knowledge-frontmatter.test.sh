#!/usr/bin/env bash
# Bite-check for scripts/check-knowledge-frontmatter.sh.
#
# Same argument as scripts/check-knowledge-gate-bite.sh makes for the policy
# gate: a detector for a silent failure is worth nothing without proof that it
# still discriminates. Each scenario copies the real bundle to a temp tree,
# applies ONE mutation, and asserts the checker fails with the right message —
# then a conforming run must pass, so a checker that always fails cannot score.
#
# The real bundle is never written to.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
gate="$repo_root/scripts/check-knowledge-frontmatter.sh"
cd "$repo_root"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fails=0
n=0

scenario() { # name expect(pass|fail) [needle]
  n=$((n + 1))
  local name="$1" expect="$2" needle="${3:-}" out st=0
  out="$("$gate" "$tmp/kb" 2>&1)" || st=$?
  if [ "$expect" = pass ]; then
    if [ "$st" -ne 0 ]; then
      echo "FAIL: [$name] expected pass, got exit $st"; echo "$out" | sed 's/^/      /'; fails=1
    else
      echo "PASS: $name"
    fi
  else
    if [ "$st" -eq 0 ]; then
      echo "FAIL: [$name] expected failure, the checker was silent"; fails=1
    elif [ -n "$needle" ] && ! printf '%s' "$out" | grep -qF -- "$needle"; then
      echo "FAIL: [$name] failed for the wrong reason (wanted '$needle')"
      echo "$out" | sed 's/^/      /'; fails=1
    else
      echo "PASS: $name"
    fi
  fi
}

reset() { rm -rf "$tmp/kb"; cp -R knowledge "$tmp/kb"; }
edit() { perl -pi -e "$1" "$tmp/kb/$2"; }

reset; scenario "the real bundle conforms" pass

reset; edit 's|^  - resource: AGENTS\.md$|  - resource: does-not-exist.md|' glossary.md
scenario "resource path does not resolve" fail "resource does not exist"

reset; edit 's|^  - resource: AGENTS\.md$|  - resource: ../outside.md|' glossary.md
scenario "resource escapes the repo" fail "must be repo-relative"

reset; edit 's|^  - resource: AGENTS\.md$|  - resource: /etc/hosts|' glossary.md
scenario "resource is absolute" fail "must be repo-relative"

reset; edit 's|^decided: ".*"$|decided: banana|' decisions/0001-multi-repo-platform-split.md
scenario "decided is not a datetime" fail "decided is not a quoted ISO 8601 datetime"

reset; edit 's|^decided: "\d{4}|decided: "2999|' decisions/0001-multi-repo-platform-split.md
scenario "decided is in the future" fail "is in the future"

reset; perl -ni -e 'print unless /^generated:/' "$tmp/kb/glossary.md"
scenario "sourced concept without generated" fail "carries no 'generated'"

reset; edit 's|^tags: \[glossary, vocabulary, platform\]$|tags: [glossary]\ntimestamp: 2026-08-23|' glossary.md
scenario "timestamp re-introduced" fail "'timestamp' is retired"

reset; perl -ni -e 'print unless /^okf_version:/' "$tmp/kb/index.md"
scenario "okf_version deleted" fail "okf_version must be declared"

reset; edit 's|^okf_version: "0.2"$|okf_version: "0.1"|' index.md
scenario "okf_version drifted" fail "okf_version must be declared"

reset; perl -ni -e 'print unless /^decided:/' "$tmp/kb/decisions/0001-multi-repo-platform-split.md"
scenario "decision concept without decided" fail "must carry 'decided'"

reset; edit 's|^decided: (".*")$|decided: $1\nsources:\n  - resource: AGENTS.md|' decisions/0001-multi-repo-platform-split.md
scenario "decision concept carrying sources" fail "must not carry 'sources'"

reset; edit 's|^  - \{ by: human:nosmoht, at: "(\d{4}-\d\d-\d\d)T00:00:00Z" \}$|  - { by: human:nosmoht, at: "$1" }|' reference/cluster-yaml.md
scenario "verified date is date-only" fail "verified[].at is not a quoted ISO 8601 datetime"

reset; scenario "the real bundle still conforms after every mutation was reverted" pass

if [ "$fails" -ne 0 ]; then
  echo "FAIL: the frontmatter gate does not discriminate in every scenario."
  exit 1
fi
echo "OK: the frontmatter gate bites in all $n scenarios."
