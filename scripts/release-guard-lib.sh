#!/usr/bin/env bash

# shellcheck shell=bash

RELEASE_GUARD_PATHSPEC_FILE="${RELEASE_GUARD_PATHSPEC_FILE:-.ci-release-guard-pathspec.txt}"
RELEASE_GUARD_EXEMPT_FILE="${RELEASE_GUARD_EXEMPT_FILE:-.ci-release-guard-exempt.txt}"

# RG_FAIL_HOOK lets callers preserve their own failure-reporting contract.
rg_die() {
  local rc="$1"; shift
  if [ -n "${RG_FAIL_HOOK:-}" ] && command -v "${RG_FAIL_HOOK}" >/dev/null 2>&1; then
    "${RG_FAIL_HOOK}" "$*"
  fi
  printf 'ERROR: %s\n' "$*" >&2
  exit "$rc"
}

# A trailing # can be pathspec content; never strip it as an inline comment.
rg_read_lines() {
  local f="$1"
  [ -r "$f" ] || rg_die 2 "$f is missing or unreadable"
  sed -e 's/[[:space:]]*$//' -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$f"
}

rg_assert_no_trailing_comment() {
  local f="$1" bad
  # Check readability outside the substitution, where || true would swallow failure.
  [ -r "$f" ] || rg_die 2 "$f is missing or unreadable"
  bad="$(rg_read_lines "$f" | grep -n '[[:space:]]#' || true)"
  [ -z "$bad" ] || rg_die 2 "$f: trailing '#' comment on a payload line (reasons must be whole-line comments above their entry):
$bad"
}

rg_load_pathspec() {
  # Restore the caller’s globbing setting.
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

# RG_EXEMPT and RG_EXEMPT_REASON share indices; missing reasons are empty.
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
