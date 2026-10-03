#!/usr/bin/env bash
# NEXT supplies the target version; --base selects the comparison ref; --advisory only reports.
# Verdict prefixes are consumed by the release workflow.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  printf 'ERROR: not inside a git work tree\n' >&2; exit 2; }
cd "${ROOT}"

# shellcheck source=scripts/release-guard-lib.sh
# shellcheck disable=SC1091
. "${ROOT}/scripts/release-guard-lib.sh"

BASE=""
ADVISORY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) [ $# -ge 2 ] || rg_die 2 "--base needs a value"; BASE="$2"; shift 2 ;;
    --advisory) ADVISORY=1; shift ;;
    *) printf 'ERROR: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

# shellcheck disable=SC2034  # read by rg_die() in the sourced library
RG_FAIL_HOOK=fail

say() { printf '%s\n' "$*"; printf '%s\n' "$*" >> "${SUMMARY}"; }

verdict() {
  local rc="$1"; shift
  say "$*"
  [ -n "${GITHUB_OUTPUT:-}" ] && printf 'guard-verdict=%s\n' "$*" >> "${GITHUB_OUTPUT}"
  if [ "${ADVISORY}" = 1 ] && [ "$rc" != 0 ]; then exit 0; fi
  exit "$rc"
}

fail() {
  if [ "${ADVISORY}" = 1 ]; then
    say "advisory unavailable: $*"
    exit 0
  fi
  printf '::error::guard error — %s\n' "$*"
  verdict 2 "guard error — $*"
}

[ "$(git rev-parse --is-shallow-repository)" = false ] \
  || fail "shallow clone — the guard cannot see the tag range (fetch-depth: 0 required)"

if [ -n "${BASE}" ]; then
  # Require a valid semver tag, not an arbitrary commit reference.
  if [ "${ADVISORY}" != 1 ] && ! printf '%s' "${BASE}" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
    fail "--base must be a stable vX.Y.Z tag when the guard is enforcing (got '${BASE}'); pass --advisory to report against an arbitrary ref"
  fi
  last_tag="${BASE}"
else
  last_tag="$(git tag --list 'v*' --sort=-v:refname \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)"
fi

[ -n "${last_tag}" ] \
  || fail "no stable tag matched 'vX.Y.Z' — tags were not fetched (fetch-depth: 0)"

git rev-parse -q --verify "${last_tag}^{commit}" >/dev/null \
  || fail "cannot resolve ${last_tag} to a commit"

rg_load_pathspec

# Test liveness at BASE so deletions still count as guarded changes.
dead=""
while IFS= read -r entry; do
  [ -n "$(git -c core.ignoreCase=false ls-files --with-tree="${last_tag}" -- "${entry}" | head -1)" ] \
    || dead="${dead}${dead:+, }${entry}"
done < <(rg_positive_pathspec)
[ -z "${dead}" ] \
  || fail "pathspec entries match no tracked file (renamed or removed?): ${dead}"

set +e
surface="$(git -c core.ignoreCase=false diff --name-only "${last_tag}..HEAD" -- "${RG_PATHSPEC[@]}")"
diff_rc=$?
set -e
[ "${diff_rc}" -eq 0 ] \
  || fail "git diff against ${last_tag} exited ${diff_rc} — no verdict reachable"

if [ -z "${surface}" ]; then
  say "Surface files considered since ${last_tag}: (none)"
  verdict 0 "guard n/a — no breaking base-surface change since ${last_tag}"
fi
# Encode attacker-controlled filenames before emitting workflow commands or Markdown.
say "Surface files considered since ${last_tag}:"
printf '%s\n' "${surface}" \
  | sed -e 's/%/%25/g' -e 's/^:/\\:/' -e 's/^/  /'
# shellcheck disable=SC2016  # the backticks are a Markdown fence, not a subshell
{ printf '```\n%s\n```\n' "${surface}"; } >> "${SUMMARY}"

if [ "${ADVISORY}" = 1 ]; then
  verdict 0 "advisory — the listed paths are guarded; on push to main this blocks unless the release is MAJOR or the merge commit carries an 'Allow-Non-Major:' attestation"
fi

case "${NEXT:-}" in
  [0-9]*.[0-9]*.[0-9]*) : ;;
  *) fail "NEXT is missing or not a bare semantic version: '${NEXT:-}'" ;;
esac

last_major="${last_tag#v}"; last_major="${last_major%%.*}"
next_major="${NEXT%%.*}"
if [ "${next_major}" -gt "${last_major}" ]; then
  verdict 0 "guard satisfied — MAJOR bump (${last_tag} -> v${NEXT}) matches the base-surface change"
fi
if [ "${next_major}" -lt "${last_major}" ]; then
  fail "the computed version v${NEXT} is BELOW the highest stable tag ${last_tag}; refusing to reason about a downgrade"
fi

# Accept the maintainer trailer only in a merge commit’s body.
parents=$(( $(git rev-list --parents -n 1 HEAD | wc -w | tr -d ' ') - 1 ))
body="$(git log -1 --format=%b)"
trailer="$(printf '%s\n' "${body}" | grep -iE '^Allow-Non-Major:' | head -1 || true)"
# Require prose alongside the trailer so a PR title cannot masquerade as an attestation.
prose="$(printf '%s\n' "${body}" | grep -vE '^[[:space:]]*$' | grep -viE '^[A-Za-z-]+:' | head -1 || true)"
if [ -n "${trailer}" ]; then
  reason="$(printf '%s' "${trailer}" | sed -E 's/^[Aa][Ll][Ll][Oo][Ww]-[Nn][Oo][Nn]-[Mm][Aa][Jj][Oo][Rr]:[[:space:]]*//')"
  if [ -z "${prose}" ]; then
    printf '::error::the Allow-Non-Major attestation stands alone in the commit body; a maintainer attestation needs the reasoning above it (gh pr merge --merge --subject "..." --body $'"'"'<why>\\n\\nAllow-Non-Major: <reason>'"'"'). A body that is only the trailer is what a PR title produces.\n'
  elif [ "${parents}" -lt 2 ]; then
    printf '::error::an Allow-Non-Major attestation was found on a single-parent commit; it is only honoured on a merge commit (merge-commit-only is the release premise — ADR-0020 §Amendment)\n'
  elif printf '%s' "${reason}" | grep -qiE '^(<.*>|todo|fixme|reason|xxx|n/?a)$' \
    || [ "${#reason}" -lt 12 ]; then
    printf '::error::the Allow-Non-Major reason is a placeholder or too short (%s) — attest the specific change, do not paste the documented example\n' "${reason}"
  else
    printf '::warning::base surface changed since %s without a MAJOR bump (v%s); overridden by attestation\n' "${last_tag}" "${NEXT}"
    say "This attestation clears EVERY file listed above — all guarded paths changed since ${last_tag}, not only the ones this pull request touched."
    verdict 0 "guard overridden — 'Allow-Non-Major:' attestation on the merge commit: ${reason}"
  fi
fi

prior="$(git log "${last_tag}..HEAD" --format='%h %b' | grep -iE 'Allow-Non-Major:' | head -1 || true)"
[ -z "${prior}" ] || say "A prior attestation exists in this range but is not on the tip commit, so it does not apply: ${prior}"

printf '::error::base surface changed since %s but the computed bump is v%s (not MAJOR). Bump MAJOR with a BREAKING CHANGE: footer / type! marker, or re-merge with an attestation: gh pr merge <N> --merge --subject "<conventional subject>" --body $'"'"'<why>\\n\\nAllow-Non-Major: <a real reason naming the surface path or issue>'"'"'. Blocking files: %s\n' \
  "${last_tag}" "${NEXT}" "$(printf '%s' "${surface}" | sed 's/%/%25/g' | tr '\n' ' ')"
verdict 1 "guard blocked — base surface changed since ${last_tag} but the computed bump is v${NEXT} (not MAJOR)"
