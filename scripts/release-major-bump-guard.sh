#!/usr/bin/env bash
# release-major-bump-guard.sh — the blocking MAJOR-bump guard of release.yml.
#
# The guarded set lives in .ci-release-guard-pathspec.txt (membership rule in its
# header); scripts/release-guard-lib.sh is the only parser.
#
# Contract:
#   env NEXT      the computed next version, bare semver (required unless --advisory)
#   --base <ref>  compare against <ref> instead of the highest stable tag
#   --advisory    never exit non-zero; report only (PR pre-merge signal)
#   exit 0  a verdict was reached and it passes
#   exit 1  blocked
#   exit 2  environment error — no verdict could be reached
#
# The verdict lines are a contract, not log text: `notify` in release.yml matches
# the first two prefixes, and they must stay pairwise distinct so that a crash
# can never read as a block.
#   guard blocked — …      (exit 1)
#   guard error — …        (exit 2, every environment cause shares this line)
#   guard n/a — …          (exit 0, nothing guarded changed)
#   guard satisfied — …    (exit 0, the bump is MAJOR)
#   guard overridden — …   (exit 0, a maintainer attestation)

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

# Library errors take this script's failure contract, not the library's.
# shellcheck disable=SC2034  # read by rg_die() in the sourced library
RG_FAIL_HOOK=fail

# say — one line to stdout and to the job summary. The summary copy is
# unconditional because the override path SUCCEEDS: nothing else draws a human to
# it, and run logs expire while the summary is part of the run's record.
say() { printf '%s\n' "$*"; printf '%s\n' "$*" >> "${SUMMARY}"; }

# verdict <exit-code> <line> — never called before the surface list is printed.
verdict() {
  local rc="$1"; shift
  say "$*"
  [ -n "${GITHUB_OUTPUT:-}" ] && printf 'guard-verdict=%s\n' "$*" >> "${GITHUB_OUTPUT}"
  if [ "${ADVISORY}" = 1 ] && [ "$rc" != 0 ]; then exit 0; fi
  exit "$rc"
}

# fail — the single exit-2 line. Advisory mode degrades to a loud "unavailable"
# marker rather than silence: a swallowed environment error reads as "nothing
# guarded", the opposite of what is true.
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
  # The MAJOR comparison below derives last_major from this value, so a commit
  # SHA would make it a hex string that never equals the next major and the guard
  # would report "satisfied" on any changed surface. Advisory runs skip the
  # comparison entirely, so they may pass a merge-base.
  if [ "${ADVISORY}" != 1 ] && ! printf '%s' "${BASE}" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
    fail "--base must be a stable vX.Y.Z tag when the guard is enforcing (got '${BASE}'); pass --advisory to report against an arbitrary ref"
  fi
  last_tag="${BASE}"
else
  # Highest STABLE semver tag by version order — not `git describe`, which
  # returns the nearest REACHABLE tag and would fail open on a non-semver or
  # prerelease nearest tag.
  last_tag="$(git tag --list 'v*' --sort=-v:refname \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)"
fi

# With a release on record this can only mean tags were not fetched; a genuine
# first release would need it relaxed deliberately.
[ -n "${last_tag}" ] \
  || fail "no stable tag matched 'vX.Y.Z' — tags were not fetched (fetch-depth: 0)"

git rev-parse -q --verify "${last_tag}^{commit}" >/dev/null \
  || fail "cannot resolve ${last_tag} to a commit"

rg_load_pathspec

# A pathspec matching nothing is not an error to git, so a directory rename would
# silently empty the guarded set. Liveness is asserted AT THE BASE, not at HEAD:
# an entry that matched at ${last_tag} and matches nothing now describes a
# deletion inside the range, which the diff must report as a surface change.
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

# Disclose before deciding, on EVERY path.
if [ -z "${surface}" ]; then
  say "Surface files considered since ${last_tag}: (none)"
  verdict 0 "guard n/a — no breaking base-surface change since ${last_tag}"
fi
# Paths are contributor-chosen, and the two output channels have two hazards: the
# run log parses `::`-prefixed lines as workflow commands and percent-decodes
# %0A/%0D, the job summary renders Markdown. Indentation closes neither, hence
# the escaping on stdout and the fence in the summary.
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
# Greater-than, not inequality: `!=` accepts a DOWNGRADE as a MAJOR bump, so one
# mistyped or aborted-release tag would disarm the guard for every later release.
if [ "${next_major}" -gt "${last_major}" ]; then
  verdict 0 "guard satisfied — MAJOR bump (${last_tag} -> v${NEXT}) matches the base-surface change"
fi
if [ "${next_major}" -lt "${last_major}" ]; then
  fail "the computed version v${NEXT} is BELOW the highest stable tag ${last_tag}; refusing to reason about a downgrade"
fi

# The override is a MAINTAINER attestation, and three properties make it one:
#   * BODY only (%b): %B includes the subject, which is author-controlled under
#     every merge method;
#   * merge commit only (>=2 parents), so a re-enabled squash or rebase merge
#     makes the tip single-parent and this refuses — fail-closed on its own
#     premise, with no API call and no admin scope;
#   * a real reason: the documented recovery command is repeated in three
#     documents, and a copy-paste must not attest anything.
parents=$(( $(git rev-list --parents -n 1 HEAD | wc -w | tr -d ' ') - 1 ))
body="$(git log -1 --format=%b)"
trailer="$(printf '%s\n' "${body}" | grep -iE '^Allow-Non-Major:' | head -1 || true)"
# Prose above the trailer is the control that does NOT depend on a repository
# setting -- which matters because the default GITHUB_TOKEN reads those settings
# back as `null`. With merge_commit_message=PR_TITLE the merge body IS the PR
# title: one contributor-authored line on a two-parent commit, where the
# merge-commit rule cannot discriminate. A body that is only the trailer is
# therefore refused; the documented form is `<why>\n\nAllow-Non-Major: <reason>`.
# EVERY `Word:` line counts as a trailer here, not just this one: a body made of
# nothing but trailers is not maintainer prose either.
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

# Reported, never honoured: the trailer is read from the tip only, so an ordinary
# push after an attested one re-arms the block for the same change.
prior="$(git log "${last_tag}..HEAD" --format='%h %b' | grep -iE 'Allow-Non-Major:' | head -1 || true)"
[ -z "${prior}" ] || say "A prior attestation exists in this range but is not on the tip commit, so it does not apply: ${prior}"

printf '::error::base surface changed since %s but the computed bump is v%s (not MAJOR). Bump MAJOR with a BREAKING CHANGE: footer / type! marker, or re-merge with an attestation: gh pr merge <N> --merge --subject "<conventional subject>" --body $'"'"'<why>\\n\\nAllow-Non-Major: <a real reason naming the surface path or issue>'"'"'. Blocking files: %s\n' \
  "${last_tag}" "${NEXT}" "$(printf '%s' "${surface}" | sed 's/%/%25/g' | tr '\n' ' ')"
verdict 1 "guard blocked — base surface changed since ${last_tag} but the computed bump is v${NEXT} (not MAJOR)"
