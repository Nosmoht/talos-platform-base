#!/usr/bin/env bash
# release-guard-lib.sh — the single parser for the release guard's data files.
# Sourced by the guard, both release-guard checks and release.yml's summary step:
# a second reader of these files is the defect class this exists to prevent.

# shellcheck shell=bash

RELEASE_GUARD_PATHSPEC_FILE="${RELEASE_GUARD_PATHSPEC_FILE:-.ci-release-guard-pathspec.txt}"
RELEASE_GUARD_EXEMPT_FILE="${RELEASE_GUARD_EXEMPT_FILE:-.ci-release-guard-exempt.txt}"

# rg_die <exit-code> <message…> — the library's failure channel. A consumer with
# its own failure contract sets RG_FAIL_HOOK to a function taking the message;
# without it a library error exits past that contract's verdict machinery.
rg_die() {
  local rc="$1"; shift
  if [ -n "${RG_FAIL_HOOK:-}" ] && command -v "${RG_FAIL_HOOK}" >/dev/null 2>&1; then
    "${RG_FAIL_HOOK}" "$*"
  fi
  printf 'ERROR: %s\n' "$*" >&2
  exit "$rc"
}

# rg_read_lines <file> — payload lines only. A trailing `#` is deliberately NOT
# stripped: a git pathspec may legitimately contain one and stripping would
# silently rewrite the pattern. The file format forbids trailing comments instead.
rg_read_lines() {
  local f="$1"
  [ -r "$f" ] || rg_die 2 "$f is missing or unreadable"
  sed -e 's/[[:space:]]*$//' -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$f"
}

# rg_assert_no_trailing_comment <file> — a payload line carrying ` #` is a format
# violation: git reads it as pattern text.
rg_assert_no_trailing_comment() {
  local f="$1" bad
  # Asserted here, not left to rg_read_lines: its rg_die would exit only the
  # command substitution below and `|| true` would swallow the status.
  [ -r "$f" ] || rg_die 2 "$f is missing or unreadable"
  bad="$(rg_read_lines "$f" | grep -n '[[:space:]]#' || true)"
  [ -z "$bad" ] || rg_die 2 "$f: trailing '#' comment on a payload line (reasons must be whole-line comments above their entry):
$bad"
}

# rg_load_pathspec — populate RG_PATHSPEC[]. `set -f` for the duration so the
# shell cannot expand `schemas/**` against the working tree before git sees it.
rg_load_pathspec() {
  # Globbing is restored only if the CALLER had it on: release.yml and the
  # bite-check source this inside their own `set -f` and switch it off
  # themselves. An unconditional `set +f` here re-enables it under their feet.
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

rg_positive_pathspec() {
  local e
  for e in "${RG_PATHSPEC[@]}"; do
    case "$e" in ':(exclude)'*) continue ;; esac
    printf '%s\n' "$e"
  done
}

# rg_load_exempt — populate RG_EXEMPT[] and RG_EXEMPT_REASON[] under a shared
# index; a path whose `# reason:` is absent gets an empty reason for the caller.
rg_load_exempt() {
  rg_assert_no_trailing_comment "$RELEASE_GUARD_EXEMPT_FILE"
  RG_EXEMPT=()
  RG_EXEMPT_REASON=()
  local line reason=""
  while IFS= read -r line; do
    # Trailing whitespace goes before the path is stored: the coverage check
    # compares these with `grep -Fxq`, where one trailing space is a different
    # string and surfaces as a stale exemption.
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
