#!/usr/bin/env bash
# check-release-guard-coverage.sh — the release guard's EXTERNAL anchor.
#
# The bite-check derives its scenarios from the guard's own data files and so
# cannot notice those files being narrowed. This check can: it walks
# .ci-oci-tarball-expected.txt, a list that exists for another reason entirely,
# and requires every published path to be guarded or exempt-with-reason.
#
# Membership is decided by GIT's matcher, never a shell glob: `:(exclude)` and
# `:(glob)` have no shell equivalent, and passing entries one at a time would
# make an all-exclusion invocation a fatal error. core.ignoreCase is forced false
# so a macOS laptop and a Linux runner reach the same verdict.
#
# Exit 0 = conforming, 1 = a coverage or hygiene violation, 2 = environment error.

set -euo pipefail

ROOT="${RELEASE_GUARD_ROOT:-$(git rev-parse --show-toplevel)}"
cd "${ROOT}"
# shellcheck source=scripts/release-guard-lib.sh
# shellcheck disable=SC1091
. "${ROOT}/scripts/release-guard-lib.sh"

# Overridable so the bite-check can exercise this script against a sandbox copy
# rather than mutating the repo's own tracked data files.
FIXTURE="${RELEASE_GUARD_TARBALL_FIXTURE:-.ci-oci-tarball-expected.txt}"
WORKFLOW="${RELEASE_GUARD_WORKFLOW_FILE:-.github/workflows/release.yml}"
GUARD="scripts/release-major-bump-guard.sh"
# AGENTS.md makes a breaking Helm-value change a MAJOR, so exempting either of
# the two shipped floors would un-guard the guard's own charter class.
HARD_PINNED="tofu/modules/talos-cluster/helm/argocd-values.yaml
tofu/modules/talos-cluster/helm/cilium-values.yaml"

for f in "${FIXTURE}" "${GUARD}" "${WORKFLOW}" "${RELEASE_GUARD_PATHSPEC_FILE}" "${RELEASE_GUARD_EXEMPT_FILE}"; do
  [ -r "$f" ] || rg_die 2 "$f is missing"
done

fail=0
note() { printf 'FAIL: %s\n' "$*" >&2; fail=1; }

rg_load_pathspec
rg_load_exempt

guarded="$(git -c core.ignoreCase=false ls-files -- "${RG_PATHSPEC[@]}")"

# 1) every published path is guarded or exempt
while IFS= read -r line; do
  [ -n "${line}" ] || continue
  p="${line#./}"
  printf '%s\n' "${guarded}" | grep -Fxq "${p}" && continue
  printf '%s\n' "${RG_EXEMPT[@]}" | grep -Fxq "${p}" && continue
  note "${p} is a published tarball member but is neither guarded by ${RELEASE_GUARD_PATHSPEC_FILE} nor listed in ${RELEASE_GUARD_EXEMPT_FILE}"
done < "${FIXTURE}"

# 2) exemption hygiene: no stale entry, no placeholder reason, no hard-pinned path
i=0
for p in "${RG_EXEMPT[@]}"; do
  reason="${RG_EXEMPT_REASON[$i]}"; i=$((i+1))
  grep -Fxq "./${p}" "${FIXTURE}" \
    || note "${p} is exempt but is not a published tarball member — stale exemption"
  printf '%s\n' "${HARD_PINNED}" | grep -Fxq "${p}" \
    && note "${p} is a shipped base Helm-value floor and may never be exempt (AGENTS.md: a breaking Helm-value change is a MAJOR)"
  [ -n "${reason}" ] \
    || note "${p} has no '# reason:' line above it in ${RELEASE_GUARD_EXEMPT_FILE}"
  printf '%s' "${reason}" | grep -qiE '^(<.*>|todo|fixme|reason|xxx|n/?a)\.?$' \
    && note "${p}: '# reason:' is a placeholder (${reason})"
  case "${reason}" in *ADR-*) : ;; *) note "${p}: '# reason:' must cite the ADR clause that admits it (got: ${reason})" ;; esac
  # Same floor the guard applies to an attestation reason: the two gates that
  # reject a copy-paste must not disagree, and this one governs the file that
  # un-guards a path permanently.
  [ "${#reason}" -ge 12 ] \
    || note "${p}: '# reason:' is too short to be one (${reason})"
done

# 3) the workflow actually enforces the guard. Asserted STRUCTURALLY, because
#    release.yml's comment block names the script too and a plain grep stays
#    green when the `run:` step is deleted. Matching the step's whole `run:`
#    value also proves no neutering flag was appended, so no knob list can go
#    stale.
[ -x "${GUARD}" ] || note "${GUARD} is not executable — release.yml invokes it directly"
if command -v yq >/dev/null 2>&1; then
  runs="$(yq -r '.jobs.plan.steps[] | select(.id == "guard") | .run' "${WORKFLOW}" 2>/dev/null | sed 's/[[:space:]]*$//')"
  [ "${runs}" = "./${GUARD}" ] \
    || note "${WORKFLOW} job 'plan' step id 'guard' must run exactly './${GUARD}' (got: '${runs:-<no such step>}'). Any argument here — --base or --advisory above all — neuters the release gate."
else
  grep -Eq "^[[:space:]]*run:[[:space:]]*\./${GUARD//\//\\/}[[:space:]]*$" "${WORKFLOW}" \
    || note "${WORKFLOW} has no bare 'run: ./${GUARD}' line — install yq for the structural check"
fi

# 4) the de-duplication stays done. Three copies of the surface globs in one file
#    is what let the guard and the job summary disagree (#234). Comments are
#    stripped first, since they legitimately quote these paths; the match is on a
#    pathspec literal anywhere on a remaining line rather than on a command
#    spelling, which varies.
lits=".ci-oci-tarball- schemas/ contracts/ kubernetes/substrate/ kubernetes/bootstrap/ platform-hardware-features"
for lit in ${lits}; do
  sed 's/#.*//' "${WORKFLOW}" | grep -Fq -- "${lit}" \
    && note "${WORKFLOW} carries the surface literal '${lit}' outside a comment — the definition belongs in ${RELEASE_GUARD_PATHSPEC_FILE}, read via scripts/release-guard-lib.sh"
done

if [ "${fail}" != 0 ]; then
  cat >&2 <<'HINT'

To un-guard a published path, MOVE it — do not delete it:
  1. .ci-oci-tarball-include.txt        (only if membership itself changes)
  2. .ci-oci-tarball-expected.txt       (1+2 are `primary` sources of
     openspec/specs/oci-supply-chain/spec.md — needs a spec touch or a
     `Spec-Impact: none` trailer on every contributing commit)
  3. .ci-release-guard-pathspec.txt  OR  .ci-release-guard-exempt.txt
  4. task supply-chain:relock-release-guard
  5. re-run `task supply-chain:check-release-guard`
HINT
  exit 1
fi
printf 'release-guard coverage OK (%s published paths, %s guarded patterns, %s exempt)\n' \
  "$(grep -c . "${FIXTURE}")" "${#RG_PATHSPEC[@]}" "${#RG_EXEMPT[@]}"
