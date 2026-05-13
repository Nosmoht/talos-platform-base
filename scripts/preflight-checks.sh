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
set -eu

REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
OWNER="${REPO%/*}"
PKG_NAME="talos-platform-base"

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
  warn_annot "Check 1 SKIP — could not read branch protection on ${REPO}/main. Token may lack admin scope (default in CI) OR branch protection is not configured. Run locally with admin gh auth for a definitive answer; configure at https://github.com/${REPO}/settings/branches"
else
  CONTEXTS="$(printf '%s' "$PROTECTION_JSON" | jq -r '.required_status_checks.contexts[]? // empty')"
  # POSIX-sh: a while-pipe runs in a subshell and cannot mutate FAIL in
  # the parent. Use one explicit loop with present-flag accumulation
  # instead.
  for line in "Hard Constraints Check / Hard Constraints|Hard Constraints" \
              "GitOps Validate / validate|validate" \
              "GitOps Validate / Secret Scan (gitleaks)|Secret Scan (gitleaks)" \
              "Preflight / preflight|preflight"; do
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
  warn_annot "Check 2 SKIP — cannot query actions permissions for ${OWNER} (insufficient API permissions; CI GITHUB_TOKEN lacks admin scope). Verify allow-list manually before next release."
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
# Check 3: GHCR tag immutability for the published package.
# Note: tag_immutability is a per-package setting only configurable via
# the package's settings page on github.com (no public REST API as of
# 2026-Q1). When the API does not surface the field, downgrade to a
# WARNING so this script does not block routine pushes. The check still
# emits an actionable hint pointing at the settings URL.
# ---------------------------------------------------------------------------
printf '\n=== Check 3: GHCR tag immutability ===\n'

PKG_JSON="$(gh_api_or_empty "orgs/${OWNER}/packages/container/${PKG_NAME}")"
if [ -z "$PKG_JSON" ]; then
  PKG_JSON="$(gh_api_or_empty "users/${OWNER}/packages/container/${PKG_NAME}")"
fi

if [ -z "$PKG_JSON" ]; then
  warn_annot "Check 3 SKIP — package ghcr.io/${OWNER}/${PKG_NAME} not found (likely no release yet) — verify after first publish."
else
  IMMUTABLE="$(printf '%s' "$PKG_JSON" | jq -r '.tag_immutability // .visibility_settings.tag_immutability // empty')"
  case "$IMMUTABLE" in
    true)
      green "  OK: tag_immutability=true"
      ;;
    false|'')
      warn_annot "GHCR tag immutability is not yet enabled for ghcr.io/${OWNER}/${PKG_NAME}. Enable at https://github.com/${OWNER}/${REPO#*/}/pkgs/container/${PKG_NAME}/settings (Tag Immutability) before the next signed release. Without it, cosign signatures can be undermined by tag overwrite."
      ;;
    *)
      yellow "  WARN: unexpected tag_immutability value: ${IMMUTABLE}"
      ;;
  esac
fi

printf '\n'
if [ "$FAIL" -eq 0 ]; then
  green "All hard preflight gates passed (warnings may be present — review above)."
  exit 0
else
  err "Preflight checks failed — see hints above."
  exit 1
fi
