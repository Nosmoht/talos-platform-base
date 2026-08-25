#!/usr/bin/env bash
# release-major-bump-guard.sh — the blocking MAJOR-bump guard of release.yml.
#
# ADR-0020 §Decision 3 removed the manual approval Environment and made this the
# only control between a breaking base-surface change and an unattended,
# cosign-signed tag. Extracted from the workflow so it can be run locally and
# bound by scripts/check-release-guard-gate-bites.sh.
#
# The guarded set lives in .ci-release-guard-pathspec.txt (membership rule in its
# header); scripts/release-guard-lib.sh is the only parser.
#
# Contract:
#   env NEXT      the computed next version, bare semver (required unless --advisory)
#   --base <ref>  compare against <ref> instead of the highest stable tag
#   --advisory    never exit non-zero; report only (PR pre-merge signal)
#   --allow-no-tag  tolerate a repo with no stable tag (first release)
#   exit 0  a verdict was reached and it passes
#   exit 1  blocked
#   exit 2  environment error — no verdict could be reached
#
# Five verdict lines, one per exit path, all exit-2 causes sharing one. The
# bite-check asserts they are pairwise distinct: a crash must never read as a
# block, and the surface list is printed BEFORE the verdict on every path, so a
# maintainer sees what is being decided on rather than only what was decided.

set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  printf 'ERROR: not inside a git work tree\n' >&2; exit 2; }
cd "${ROOT}"

# shellcheck source=scripts/release-guard-lib.sh
. "${ROOT}/scripts/release-guard-lib.sh"

BASE=""
ADVISORY=0
ALLOW_NO_TAG=0
while [ $# -gt 0 ]; do
  case "$1" in
    --base) [ $# -ge 2 ] || rg_die 2 "--base needs a value"; BASE="$2"; shift 2 ;;
    --advisory) ADVISORY=1; shift ;;
    --allow-no-tag) ALLOW_NO_TAG=1; shift ;;
    *) printf 'ERROR: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

# say — one line to stdout and to the job summary. The summary copy is
# unconditional: the override path SUCCEEDS, so nothing else draws a human to
# it, and run logs expire while the summary is part of the run's record.
say() { printf '%s\n' "$*"; printf '%s\n' "$*" >> "${SUMMARY}"; }

# verdict <exit-code> <line> — emit the verdict, publish it for the notify job,
# and leave. Never called before the surface list has been printed.
verdict() {
  local rc="$1"; shift
  say "$*"
  [ -n "${GITHUB_OUTPUT:-}" ] && printf 'guard-verdict=%s\n' "$*" >> "${GITHUB_OUTPUT}"
  if [ "${ADVISORY}" = 1 ] && [ "$rc" != 0 ]; then exit 0; fi
  exit "$rc"
}

# fail — the single exit-2 line. In advisory mode it degrades to a loud
# "unavailable" marker rather than silence: an advisory step that swallows an
# environment error reads as "nothing guarded", which is the opposite of true.
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
  last_tag="${BASE}"
else
  # Highest STABLE semver tag by version order — not `git describe`, which
  # returns the nearest REACHABLE tag and would fail open on a non-semver or
  # prerelease nearest tag. The grep drops prereleases and stray tags.
  last_tag="$(git tag --list 'v*' --sort=-v:refname \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1 || true)"
fi

if [ -z "${last_tag}" ]; then
  [ "${ALLOW_NO_TAG}" = 1 ] \
    || fail "no stable tag matched 'vX.Y.Z' — tags were probably not fetched (pass --allow-no-tag for a genuine first release)"
  say "Surface files considered since <no prior stable tag>: (none)"
  verdict 0 "guard n/a — no prior stable tag to compare against"
fi

git rev-parse -q --verify "${last_tag}^{commit}" >/dev/null \
  || fail "cannot resolve ${last_tag} to a commit"

rg_load_pathspec

# A syntactically valid pathspec that matches nothing is not an error to git, so
# a directory rename silently empties the guarded set and the guard reports "no
# change". Assert every positive entry still selects something.
dead=""
while IFS= read -r entry; do
  [ -n "$(git -c core.ignoreCase=false ls-files -- "${entry}" | head -1)" ] \
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

# AC3: disclose before deciding, on EVERY path. Indented so a contributor-chosen
# filename cannot open a GitHub workflow command in the run log.
if [ -z "${surface}" ]; then
  say "Surface files considered since ${last_tag}: (none)"
  verdict 0 "guard n/a — no breaking base-surface change since ${last_tag}"
fi
say "Surface files considered since ${last_tag}:"
printf '%s\n' "${surface}" | sed 's/^/  /' | tee -a "${SUMMARY}"

if [ "${ADVISORY}" = 1 ]; then
  verdict 0 "advisory — the listed paths are guarded; on push to main this blocks unless the release is MAJOR or the merge commit carries an 'Allow-Non-Major:' attestation"
fi

case "${NEXT:-}" in
  [0-9]*.[0-9]*.[0-9]*) : ;;
  *) fail "NEXT is missing or not a bare semantic version: '${NEXT:-}'" ;;
esac

last_major="${last_tag#v}"; last_major="${last_major%%.*}"
next_major="${NEXT%%.*}"
if [ "${next_major}" != "${last_major}" ]; then
  verdict 0 "guard satisfied — MAJOR bump (${last_tag} -> v${NEXT}) matches the base-surface change"
fi

# The override is a MAINTAINER attestation. Three properties make it one:
#   * read from the BODY only (%b): %B includes the subject, and a subject-line
#     `Allow-Non-Major:` is author-controlled under every merge method;
#   * accepted only on a MERGE commit (>=2 parents). Under merge-commit-only
#     every PR tip is a merge commit the maintainer authors; if squash or rebase
#     merge is ever re-enabled the tip is single-parent and this refuses — the
#     guard fails closed on its own premise, with no API call and no admin scope;
#   * the reason must be a real one. `Allow-Non-Major: <reason>` and
#     `Allow-Non-Major: TODO` both match a bare line-anchored regex, and the
#     recovery command is documented in three places — a copy-paste must not
#     attest anything.
parents=$(( $(git rev-list --parents -n 1 HEAD | wc -w | tr -d ' ') - 1 ))
trailer="$(git log -1 --format=%b | grep -iE '^Allow-Non-Major:' | head -1 || true)"
if [ -n "${trailer}" ]; then
  reason="$(printf '%s' "${trailer}" | sed -E 's/^[Aa][Ll][Ll][Oo][Ww]-[Nn][Oo][Nn]-[Mm][Aa][Jj][Oo][Rr]:[[:space:]]*//')"
  if [ "${parents}" -lt 2 ]; then
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

# Prior attestations in the range are reported, never honoured: the trailer is
# read from the tip only, so an ordinary push after an attested one re-arms the
# block for the same, already-attested change (documented in
# knowledge/workflows/release-process.md §When the release is blocked).
prior="$(git log "${last_tag}..HEAD" --format='%h %b' | grep -iE 'Allow-Non-Major:' | head -1 || true)"
[ -z "${prior}" ] || say "A prior attestation exists in this range but is not on the tip commit, so it does not apply: ${prior}"

printf '::error::base surface changed since %s but the computed bump is v%s (not MAJOR). Bump MAJOR with a BREAKING CHANGE: footer / type! marker, or re-merge with an attestation: gh pr merge <N> --merge --subject "<conventional subject>" --body $'"'"'<why>\\n\\nAllow-Non-Major: <a real reason naming the surface path or issue>'"'"'. Blocking files: %s\n' \
  "${last_tag}" "${NEXT}" "$(printf '%s' "${surface}" | tr '\n' ' ')"
verdict 1 "guard blocked — base surface changed since ${last_tag} but the computed bump is v${NEXT} (not MAJOR)"
