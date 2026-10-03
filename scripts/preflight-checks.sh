#!/bin/sh
# Read repository policy through an authenticated GitHub account with admin visibility.
set -eu

REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
OWNER="${REPO%/*}"
DEFAULT_BRANCH="main"

red() { printf '\033[31m%s\033[0m\n' "$1" >&2; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }
yellow() { printf '\033[33m%s\033[0m\n' "$1"; }
err() {
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    printf '::error::%s\n' "$1"
  else
    red "FAIL: $1"
  fi
}
warn_annot() {
  if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
    printf '::warning::%s\n' "$1"
  else
    yellow "WARN: $1"
  fi
}

gh_api_or_empty() {
  out="$(gh api "$1" 2>/dev/null || true)"
  case "$out" in
    *'"message":"Not Found"'*) ;;
    *'"message":"Resource not accessible'*) ;;
    # Treat unreadable policy as an error, not evidence of absence.
    *'"status":"403"'*) ;;
    *) printf '%s' "$out" ;;
  esac
  return 0
}

FAIL=0

printf '\n=== Check 1: branch protection required-checks ===\n'

PROTECTION_JSON="$(gh_api_or_empty "repos/${REPO}/branches/main/protection")"

if [ -z "$PROTECTION_JSON" ]; then
  err "Check 1 — could not read branch protection on ${REPO}/main. The App token needs Administration:read, or branch protection is not configured."
  FAIL=1
else
  CONTEXTS="$(printf '%s' "$PROTECTION_JSON" | jq -r '.required_status_checks.contexts[]? // empty')"
  # Avoid a subshell: FAIL must survive the loop.
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

printf '\n=== Check 2: GitHub Actions allowlist ===\n'

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
      warn_annot "Check 2 SKIP — allowed_actions=${ALLOWED:-unknown}. Personal-account default usually permits cosign/attest-build-provenance; confirm at https://github.com/${OWNER}/${REPO#*/}/settings/actions before next release."
      ;;
    *)
      yellow "  WARN: unknown allowed_actions value: ${ALLOWED}"
      ;;
  esac
fi

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

printf '\n=== Check 4: merge methods (release-guard attestation premise) ===\n'

REPO_JSON="$(gh_api_or_empty "repos/${REPO}")"
if [ -z "$REPO_JSON" ]; then
  err "Check 4 — could not read the repository object for ${REPO}."
  FAIL=1
else
  # A blank default merge body prevents contributor text from supplying attestations.
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
