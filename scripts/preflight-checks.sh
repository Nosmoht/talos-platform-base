#!/bin/sh
# Preflight check — assert release-time org-policy preconditions are
# in place BEFORE remediation commits land. Converts advisory
# prerequisites into mechanical gates.
#
# Three checks, each emits an actionable remediation hint on failure:
#   1. Branch-protection required-checks include the expected names.
#   2. GitHub Actions allowlist permits the cosign + provenance actions.
#   3. GHCR tag immutability is enabled for the published package.
#
# Run locally:        bash scripts/preflight-checks.sh
# Run in CI:          via .github/workflows/preflight.yml
#
# Requires: gh (authenticated), jq.
#
# Runs from .github/workflows/policy-audit.yml with a GitHub App token holding
# Administration:read, and locally with admin gh auth. It is deliberately NOT
# attached to pull requests: it asserts account policy rather than the diff, and
# the default GITHUB_TOKEN cannot read a single one of the four settings below —
# a PR-attached run reported success without having looked at anything.
#
# Because every caller is supposed to be able to read, an unreadable setting is
# a failure here, not a warning. A green run means verified.
set -eu

REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
OWNER="${REPO%/*}"
DEFAULT_BRANCH="main"

red() { printf '\033[31m%s\033[0m\n' "$1" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }
yellow() { printf '\033[33m%s\033[0m\n' "$1"; }
err() {
  # GitHub Actions error annotation when running in CI.
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    printf '::error::%s\n' "$1"
  else
    red "FAIL: $1"
  fi
}
warn_annot() {
  # GitHub Actions warning annotation when running in CI; yellow text otherwise.
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    printf '::warning::%s\n' "$1"
  else
    yellow "WARN: $1"
  fi
}

# gh-api-or-empty <api-path> — run `gh api <path>`; print stdout iff
# exit 0; print nothing otherwise. Always returns 0 so `set -e` does
# not kill the caller when an API returns 404. Avoids the OR-chain
# stdout-pollution bug where multiple failed gh calls concatenate
# their 404 JSON bodies into the captured value and confuse jq.
gh_api_or_empty() {
  out="$(gh api "$1" 2>/dev/null || true)"
  case "$out" in
    *'"message":"Not Found"'*) ;;
    *'"message":"Resource not accessible'*) ;;
    # A scope refusal is "could not read", not "read an empty answer". Without
    # this arm the body is returned, every jq lookup yields empty, and a check
    # reports the setting as absent when it was never visible -- which is how
    # Check 3 came to claim tag immutability was off under a token lacking
    # read:packages.
    *'"status":"403"'*) ;;
    *) printf '%s' "$out" ;;
  esac
  return 0
}

FAIL=0

# ---------------------------------------------------------------------------
# Check 1: Branch protection required-checks include expected names.
# ---------------------------------------------------------------------------
printf '\n=== Check 1: branch protection required-checks ===\n'

# GitHub stores required-status-check context names as they appear in the
# `name:` field of each workflow job (or the job ID when `name:` is unset).
# The branch-protection UI displays them in the qualified "Workflow / Job"
# form, but the API typically returns the BARE job name. We accept either
# form: the bare form is canonical from the API; the qualified form is the
# UI label. Source-of-truth: workflow YAML files in .github/workflows/ —
# update both places if a workflow is renamed.
#
# The list of expected checks is inlined into the matching loop below
# ("qualified|bare" pairs).

PROTECTION_JSON="$(gh_api_or_empty "repos/${REPO}/branches/main/protection")"

if [ -z "$PROTECTION_JSON" ]; then
  # Empty response can mean (a) branch protection not configured, or
  # (b) caller lacks admin scope (default GITHUB_TOKEN in CI does NOT
  # include administration:read — that is a GitHub-App-only permission
  # not exposable via workflow `permissions`). Treat as WARN in CI; a
  # repo admin running the script locally will get a definitive
  # answer.
  err "Check 1 — could not read branch protection on ${REPO}/main. The App token needs Administration:read, or branch protection is not configured."
  FAIL=1
else
  CONTEXTS="$(printf '%s' "$PROTECTION_JSON" | jq -r '.required_status_checks.contexts[]? // empty')"
  # POSIX-sh: a while-pipe runs in a subshell and cannot mutate FAIL in
  # the parent. Use one explicit loop with present-flag accumulation
  # instead.
  for line in "Hard Constraints Check / Hard Constraints|Hard Constraints" \
              "GitOps Validate / validate|validate" \
              "GitOps Validate / Secret Scan (gitleaks)|Secret Scan (gitleaks)" \
              "docs-lint / docs-lint|docs-lint" \
              "Commit Lint / lint-pr-title|lint-pr-title"; do
    qualified="${line%|*}"
    bare="${line#*|}"
    if printf '%s\n' "$CONTEXTS" | grep -Fxq "$qualified"; then
      green "  OK: required check present (qualified form): ${qualified}"
    elif printf '%s\n' "$CONTEXTS" | grep -Fxq "$bare"; then
      green "  OK: required check present (bare form):      ${bare}"
    else
      err "missing required status check: ${qualified} (or bare '${bare}')"
      yellow "  Hint: add either form to branch protection required-checks at https://github.com/${REPO}/settings/branches"
      FAIL=1
    fi
  done
fi

# ---------------------------------------------------------------------------
# Check 2: Allowed-actions list permits cosign-installer + attest-build-provenance.
# Skip gracefully if the API is unavailable (limited token, personal account).
# ---------------------------------------------------------------------------
printf '\n=== Check 2: GitHub Actions allowlist ===\n'

# Try org-level first, fall back to repo-level. Use the explicit
# gh_api_or_empty helper so a 404 from one endpoint does not pollute
# the captured stdout of the other.
PERMS_JSON="$(gh_api_or_empty "orgs/${OWNER}/actions/permissions")"
if [ -z "$PERMS_JSON" ]; then
  PERMS_JSON="$(gh_api_or_empty "repos/${REPO}/actions/permissions")"
fi

if [ -z "$PERMS_JSON" ]; then
  err "Check 2 — cannot read the Actions permissions for ${OWNER}. The App token needs Administration:read."
  FAIL=1
else
  ALLOWED="$(printf '%s' "$PERMS_JSON" | jq -r '.allowed_actions // empty')"
  case "$ALLOWED" in
    all)
      green "  OK: allowed_actions=all (no allowlist to check)"
      ;;
    selected)
      SELECTED_JSON="$(gh_api_or_empty "orgs/${OWNER}/actions/permissions/selected-actions")"
      if [ -z "$SELECTED_JSON" ]; then
        SELECTED_JSON="$(gh_api_or_empty "repos/${REPO}/actions/permissions/selected-actions")"
      fi
      PATTERNS="$(printf '%s' "$SELECTED_JSON" | jq -r '.patterns_allowed[]? // empty')"
      for required in 'sigstore/cosign-installer@*' 'actions/attest-build-provenance@*'; do
        if printf '%s\n' "$PATTERNS" | grep -Fxq "$required"; then
          green "  OK: allowlist pattern present: ${required}"
        else
          err "allowlist missing pattern: ${required}"
          yellow "  Hint: configure at https://github.com/${OWNER}/${REPO#*/}/settings/actions"
          FAIL=1
        fi
      done
      ;;
    local_only|''|null)
      # `unknown` (empty/null) on a personal account typically means the
      # repo accepts all actions by default (no allowlist enforcement);
      # downgrade to warning rather than failing the gate, but flag for
      # manual confirmation.
      warn_annot "Check 2 SKIP — allowed_actions=${ALLOWED:-unknown}. Personal-account default usually permits cosign/attest-build-provenance; confirm at https://github.com/${OWNER}/${REPO#*/}/settings/actions before next release."
      ;;
    *)
      yellow "  WARN: unknown allowed_actions value: ${ALLOWED}"
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# Check 3: repository release immutability.
#
# This check used to assert a per-package "tag immutability" setting on the
# GHCR package. No such setting exists -- it is absent from the package
# settings page and from the API -- so the check could never pass, and read it
# as disabled. What GitHub does offer is release immutability: a published
# release and its git tag cannot be replaced or deleted.
#
# Scope, stated plainly: this protects the release object, NOT the container
# image. A `v*` tag in GHCR can still be moved onto a different image, so
# consumers pin the digest, per knowledge/workflows/verify-release.md.
# ---------------------------------------------------------------------------
printf '\n=== Check 3: release immutability ===\n'

IMM_JSON="$(gh_api_or_empty "repos/${REPO}/immutable-releases")"
if [ -z "$IMM_JSON" ]; then
  err "Check 3 — could not read release immutability for ${REPO}. The App token needs Administration:read."
  FAIL=1
else
  IMMUTABLE="$(printf '%s' "$IMM_JSON" | jq -r '.enabled')"
  if [ "$IMMUTABLE" = "true" ]; then
    green "  OK: release immutability is enabled"
  else
    err "release immutability is disabled — a published release and its tag can be replaced, so a signed release can be swapped after the fact"
    yellow "  Hint: gh api -X PUT repos/${REPO}/immutable-releases"
    FAIL=1
  fi
fi

# ---------------------------------------------------------------------------
# Check 4: merge methods. The release guard's `Allow-Non-Major:` attestation is
# a MAINTAINER attestation, and that holds only while the merge commit body is
# maintainer-authored. Squash-merge concatenates the branch commit bodies into
# it; rebase-merge makes the tip an author-authored commit. Either one makes the
# attestation forgeable by any contributor.
#
# Two ways to check it, because the settings are not readable from CI. Measured
# 2026-08-31: neither the default GITHUB_TOKEN nor an App token with
# Administration:read + Contents:read gets these fields — they come back null,
# and only an admin-scoped credential fills them in.
#
# So: read the settings when the credential can (local admin run), and otherwise
# check the EFFECT on main — the newest merge commit must have two parents.
# Squash and rebase both produce a single-parent tip, so a one-parent newest
# merge means one of them was re-enabled. That is the half of the setting the
# attack actually needs: squash concatenates contributor commit bodies into the
# tip the guard parses. The body itself is not checkable this way, because a
# maintainer-typed body is legitimate — it is where Allow-Non-Major goes.
#
# The effect check is one merge behind by construction: it sees a reverted
# setting only after a merge happened under it.
# ---------------------------------------------------------------------------
printf '\n=== Check 4: merge methods (release-guard attestation premise) ===\n'

REPO_JSON="$(gh_api_or_empty "repos/${REPO}")"
if [ -z "$REPO_JSON" ]; then
  err "Check 4 — could not read the repository object for ${REPO}."
  FAIL=1
else
  # merge_commit_message=BLANK, not PR_TITLE: with PR_TITLE the merge commit BODY
  # is the PR title -- contributor-authored text in the exact field the guard
  # parses, on a two-parent commit where its merge-commit rule cannot
  # discriminate. BLANK removes that channel rather than filtering it.
  #
  # merge_commit_title=PR_TITLE, not MERGE_MESSAGE: GitHub accepts only three
  # title/message combinations -- PR_TITLE+PR_BODY, PR_TITLE+BLANK,
  # MERGE_MESSAGE+PR_TITLE -- and rejects MERGE_MESSAGE+BLANK with
  # invalid_merge_commit_setting_combo. PR_TITLE+BLANK is the only accepted pair
  # that leaves the body empty, and the subject it uses is itself constrained by
  # the required lint-pr-title check.
  for pair in "allow_squash_merge|false" "allow_rebase_merge|false" \
              "merge_commit_message|BLANK" "merge_commit_title|PR_TITLE"; do
    key="${pair%|*}"; want="${pair#*|}"
    got="$(printf '%s' "$REPO_JSON" | jq -r ".${key}")"
    if [ "$got" = "$want" ]; then
      green "  OK: ${key}=${got}"
    elif [ "$got" = "null" ]; then
      UNREADABLE=1
    else
      err "${key} is '${got}', expected '${want}' — the Allow-Non-Major attestation is only maintainer-owned under merge-commit-only"
      yellow "  Hint: https://github.com/${REPO}/settings — Pull Requests, merge button options"
      FAIL=1
    fi
  done

  if [ "${UNREADABLE:-0}" = "1" ]; then
    yellow "  NOTE: merge settings not readable with this credential — checking the effect on the default branch instead."
    HEAD_JSON="$(gh_api_or_empty "repos/${REPO}/commits/${DEFAULT_BRANCH}")"
    if [ -z "$HEAD_JSON" ]; then
      err "Check 4 — could not read ${DEFAULT_BRANCH} to check the merge effect."
      FAIL=1
    else
      PARENTS="$(printf '%s' "$HEAD_JSON" | jq -r '.parents | length')"
      SUBJECT="$(printf '%s' "$HEAD_JSON" | jq -r '.commit.message' | head -1)"
      if [ "$PARENTS" -ge 2 ]; then
        green "  OK: newest commit on ${DEFAULT_BRANCH} is a merge commit (${PARENTS} parents): ${SUBJECT}"
      else
        err "newest commit on ${DEFAULT_BRANCH} has ${PARENTS} parent — squash or rebase merging is enabled again, which lets a contributor's commit body reach the tip the release guard parses"
        yellow "  Hint: https://github.com/${REPO}/settings — Pull Requests, merge button options"
        FAIL=1
      fi
    fi
  fi
fi

printf '\n'
if [ "$FAIL" -eq 0 ]; then
  green "All hard preflight gates passed (warnings may be present — review above)."
  exit 0
else
  err "Preflight checks failed — see hints above."
  exit 1
fi
