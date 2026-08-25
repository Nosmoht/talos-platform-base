#!/usr/bin/env bash
# release-guard-lib.sh — the single parser for the release guard's data files.
#
# Sourced by scripts/release-major-bump-guard.sh, check-release-guard-coverage.sh,
# check-release-guard-gate-bites.sh and the release.yml job-summary step. One
# parser on purpose: four independent readers of one file is the same defect
# class as four copies of the file.
#
# Not executable on its own; sourcing it defines the functions and nothing else.

# shellcheck shell=bash

RELEASE_GUARD_PATHSPEC_FILE="${RELEASE_GUARD_PATHSPEC_FILE:-.ci-release-guard-pathspec.txt}"
RELEASE_GUARD_EXEMPT_FILE="${RELEASE_GUARD_EXEMPT_FILE:-.ci-release-guard-exempt.txt}"

# rg_die <exit-code> <message…> — uniform failure channel for every consumer.
rg_die() {
  local rc="$1"; shift
  printf 'ERROR: %s\n' "$*" >&2
  exit "$rc"
}

# rg_read_lines <file> — echo the file's payload lines: whole-line `#` comments
# and blank lines removed, nothing else touched. Trailing `#` is NOT stripped,
# because a git pathspec may legitimately contain one and stripping it would
# silently rewrite the pattern; the file format forbids trailing comments and
# rg_assert_no_trailing_comment enforces that.
rg_read_lines() {
  local f="$1"
  [ -r "$f" ] || rg_die 2 "$f is missing or unreadable"
  sed -e 's/[[:space:]]*$//' -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$f"
}

# rg_assert_no_trailing_comment <file> — a payload line carrying ` #` is a
# format violation: git would read it as pattern text. Fail loudly rather than
# guess what the author meant.
rg_assert_no_trailing_comment() {
  local f="$1" bad
  bad="$(rg_read_lines "$f" | grep -n '[[:space:]]#' || true)"
  [ -z "$bad" ] || rg_die 2 "$f: trailing '#' comment on a payload line (reasons must be whole-line comments above their entry):
$bad"
}

# rg_load_pathspec — populate RG_PATHSPEC[] with the guard's git pathspec
# arguments. `set -f` for the duration so the shell cannot expand `schemas/**`
# against the working tree before git ever sees it.
rg_load_pathspec() {
  local restore_glob=1
  case "$-" in *f*) restore_glob=0 ;; esac
  set -f
  rg_assert_no_trailing_comment "$RELEASE_GUARD_PATHSPEC_FILE"
  RG_PATHSPEC=()
  local line
  while IFS= read -r line; do
    RG_PATHSPEC+=("$line")
  done < <(rg_read_lines "$RELEASE_GUARD_PATHSPEC_FILE")
  [ "$restore_glob" = 1 ] && set +f
  [ "${#RG_PATHSPEC[@]}" -gt 0 ] \
    || rg_die 2 "$RELEASE_GUARD_PATHSPEC_FILE contains no pathspec entries"
}

# rg_positive_pathspec — the entries that can match something, i.e. everything
# except `:(exclude)…`. Used where a per-entry assertion only makes sense for a
# pattern that is supposed to select files.
rg_positive_pathspec() {
  local e
  for e in "${RG_PATHSPEC[@]}"; do
    case "$e" in ':(exclude)'*) continue ;; esac
    printf '%s\n' "$e"
  done
}

# rg_load_exempt — populate RG_EXEMPT[] with the exempted tarball paths and
# RG_EXEMPT_REASON[] with each path's reason line, keyed by array index. A path
# whose preceding whole-line `# reason:` is absent is reported by the caller.
rg_load_exempt() {
  rg_assert_no_trailing_comment "$RELEASE_GUARD_EXEMPT_FILE"
  RG_EXEMPT=()
  RG_EXEMPT_REASON=()
  local line reason=""
  while IFS= read -r line; do
    line="${line%"${line##*[![:space:]]}"}"
    case "$line" in
      '# reason:'*) reason="${line#\# reason:}"; reason="${reason# }"; continue ;;
      '#'*|'') continue ;;
    esac
    RG_EXEMPT+=("$line")
    RG_EXEMPT_REASON+=("$reason")
    reason=""
  done < "$RELEASE_GUARD_EXEMPT_FILE"
}
