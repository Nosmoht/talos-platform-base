#!/bin/sh
# Preflight check — assert release-time org-policy preconditions are
# in place BEFORE remediation commits land. Converts advisory
# prerequisites into mechanical gates.
#
# Three checks, each fails with an actionable remediation hint:
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

FAIL=0

# ---------------------------------------------------------------------------
# Check 1: Branch protection required-checks include expected names.
# ---------------------------------------------------------------------------
printf '\n=== Check 1: branch protection required-checks ===\n'

# Branch-protection context names use "<workflow_name> / <job_name|job_id>".
# Job_name (line `name:` under the job key) is used when set; otherwise
# the job ID. Source-of-truth for these names: workflow YAML files in
# .github/workflows/. Update both places if a workflow is renamed.
REQUIRED_CHECKS="Hard Constraints Check / Hard Constraints
GitOps Validate / validate
GitOps Validate / Secret Scan (gitleaks)
Preflight / preflight"

PROTECTION_JSON="$(gh api "repos/${REPO}/branches/main/protection" 2>/dev/null || echo '')"

if [ -z "$PROTECTION_JSON" ]; then
  err "branch protection not configured on main, or insufficient API permissions"
  yellow "  Hint: enable branch protection at https://github.com/${REPO}/settings/branches"
  FAIL=1
else
  CONTEXTS="$(printf '%s' "$PROTECTION_JSON" | jq -r '.required_status_checks.contexts[]? // empty')"
  printf '%s\n' "$REQUIRED_CHECKS" | while IFS= read -r required; do
    [ -z "$required" ] && continue
    if printf '%s\n' "$CONTEXTS" | grep -Fxq "$required"; then
      green "  OK: required check present: ${required}"
    else
      err "missing required status check: ${required}"
      yellow "  Hint: add '${required}' to branch protection required-checks"
      FAIL=1
    fi
  done
fi

# ---------------------------------------------------------------------------
# Check 2: Allowed-actions list permits cosign-installer + attest-build-provenance.
# Skip gracefully if org is set to "allow all actions".
# ---------------------------------------------------------------------------
printf '\n=== Check 2: GitHub Actions allowlist ===\n'

# Try org-level first, fall back to repo-level (personal account).
PERMS_JSON="$(gh api "orgs/${OWNER}/actions/permissions" 2>/dev/null \
  || gh api "repos/${REPO}/actions/permissions" 2>/dev/null \
  || echo '')"

if [ -z "$PERMS_JSON" ]; then
  yellow "  SKIP: cannot query actions permissions for owner ${OWNER} (insufficient API permissions or unsupported account type)"
else
  ALLOWED="$(printf '%s' "$PERMS_JSON" | jq -r '.allowed_actions // empty')"
  case "$ALLOWED" in
    all)
      green "  OK: allowed_actions=all (no allowlist to check)"
      ;;
    selected)
      # Selected — must include our two new actions.
      SELECTED_JSON="$(gh api "orgs/${OWNER}/actions/permissions/selected-actions" 2>/dev/null \
        || gh api "repos/${REPO}/actions/permissions/selected-actions" 2>/dev/null \
        || echo '')"
      PATTERNS="$(printf '%s' "$SELECTED_JSON" | jq -r '.patterns_allowed[]? // empty')"
      for required in 'sigstore/cosign-installer@*' 'actions/attest-build-provenance@*'; do
        if printf '%s\n' "$PATTERNS" | grep -Fxq "$required"; then
          green "  OK: allowlist pattern present: ${required}"
        else
          err "allowlist missing pattern: ${required}"
          yellow "  Hint: gh api -X PUT '${SELECTED_JSON:+orgs/${OWNER}}/actions/permissions/selected-actions' -f patterns_allowed[]='${required}'"
          FAIL=1
        fi
      done
      ;;
    local_only|''|null)
      err "actions allowed_actions=${ALLOWED:-unknown} — cosign/attest-build-provenance cannot run"
      yellow "  Hint: set allowed_actions to 'all' or 'selected' (with patterns above) at https://github.com/${OWNER}/settings/actions"
      FAIL=1
      ;;
    *)
      yellow "  WARN: unknown allowed_actions value: ${ALLOWED}"
      ;;
  esac
fi

# ---------------------------------------------------------------------------
# Check 3: GHCR tag immutability for the published package.
# Note: GHCR's tag-immutability API surface changed over time; we try
# the user/org endpoints. If the package doesn't exist yet (first
# release), the check is informational, not blocking.
# ---------------------------------------------------------------------------
printf '\n=== Check 3: GHCR tag immutability ===\n'

PKG_JSON="$(gh api "orgs/${OWNER}/packages/container/${PKG_NAME}" 2>/dev/null \
  || gh api "users/${OWNER}/packages/container/${PKG_NAME}" 2>/dev/null \
  || echo '')"

if [ -z "$PKG_JSON" ]; then
  yellow "  SKIP: package ghcr.io/${OWNER}/${PKG_NAME} not found (likely no release yet) — verify after first publish"
else
  IMMUTABLE="$(printf '%s' "$PKG_JSON" | jq -r '.tag_immutability // .visibility_settings.tag_immutability // empty')"
  case "$IMMUTABLE" in
    true)
      green "  OK: tag_immutability=true"
      ;;
    false|'')
      err "GHCR tag immutability is not enabled for ghcr.io/${OWNER}/${PKG_NAME}"
      yellow "  Hint: enable at https://github.com/${OWNER}/${REPO#*/}/pkgs/container/${PKG_NAME}/settings — Tag Immutability"
      yellow "  Without this, signed tags can be overwritten — cosign integrity is undermined."
      FAIL=1
      ;;
    *)
      yellow "  WARN: unexpected tag_immutability value: ${IMMUTABLE}"
      ;;
  esac
fi

printf '\n'
if [ "$FAIL" -eq 0 ]; then
  green "All preflight checks passed."
  exit 0
else
  err "Preflight checks failed — see hints above."
  exit 1
fi
