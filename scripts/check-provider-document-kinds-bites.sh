#!/usr/bin/env bash
# check-provider-document-kinds-bites.sh — prove that
# scripts/check-provider-document-kinds.sh actually bites.
#
# WHY THIS EXISTS: that fence has one exit code for many assertions, and its
# verdict depends on text rendered by an external provider plus a jq extraction.
# A fence whose assertion silently stopped matching — a renamed output, an
# extraction that returns empty, an expectation that can no longer fail — reports
# OK forever and is indistinguishable from a working one. The same argument, and
# the two near-misses that motivated it, are in scripts/check-argocd-gate-bites.sh;
# this is that discipline applied to a fence whose input is a provider render.
#
# Each scenario mutates a COPY of the fence — its expectation, or the patch it
# sends — runs it, and asserts the fence fails with the MESSAGE that case owns,
# not merely with a non-zero exit. A control run of the unmutated fence must pass.
#
# NOT every `fail` in the fence is covered. A branch that fires only when the
# PROVIDER behaves differently — each case's rejection branch, case D's
# wrong-message branch, the two render-failure branches — cannot be reached by
# mutating an expectation, so it is unbound here and named as such rather than
# claimed. What is bound is every assertion whose expectation this script can
# falsify: the list below is the coverage statement.
#
# Cost: each scenario runs the fence end to end (~8s warm), so this target is
# roughly two minutes. The provider is downloaded once into a shared plugin
# cache rather than per scenario. That cost is why it is a separate task rather
# than more cases inside the fence.
#
# Exit: 0 every scenario bites and the control passes; 1 one did not (or an
#       anchor no longer matches the fence); 2 an environment error, including a
#       mutant that failed on its environment rather than on its assertion.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "${ROOT}"

FENCE="scripts/check-provider-document-kinds.sh"
[ -f "${FENCE}" ] || { echo "::error::${FENCE} not found" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
FAILURES=0
# One download for all 13 fence runs; each run inits a fresh temp dir otherwise.
export TF_PLUGIN_CACHE_DIR="${WORK}/plugin-cache"
mkdir -p "${TF_PLUGIN_CACHE_DIR}"

# $1 label, $2 expected message substring, $3 literal to replace, $4 replacement
bite() {
  local label="$1" expect="$2" from="$3" to="$4"
  local mutant="${WORK}/mutant.sh"
  rm -f "${mutant}"
  python3 - "${FENCE}" "${mutant}" "${from}" "${to}" <<'PY' || true
import sys, pathlib
src, dst, frm, to = sys.argv[1:5]
s = pathlib.Path(src).read_text()
if s.count(frm) != 1:
    sys.stderr.write("anchor matched %d times, expected 1: %r\n" % (s.count(frm), frm))
    sys.exit(3)
pathlib.Path(dst).write_text(s.replace(frm, to))
PY
  if [ ! -f "${mutant}" ]; then
    echo "  FAIL  ${label} — its anchor no longer matches ${FENCE}; update the anchor in this file"
    FAILURES=$((FAILURES + 1))
    return 0
  fi
  chmod +x "${mutant}"
  local out status
  set +e
  out="$(bash "${mutant}" 2>&1)"
  status=$?
  set -e
  if [ "${status}" -eq 2 ]; then
    echo "::error::check-provider-document-kinds-bites: ${label} — the mutated fence hit an ENVIRONMENT error (exit 2), not an assertion. Nothing is proven about this assertion; re-run on a transient registry blip, investigate otherwise:" >&2
    printf '%s\n' "${out}" | tail -3 >&2
    exit 2
  fi
  if [ "${status}" -eq 0 ]; then
    echo "  FAIL  ${label} — the mutated fence PASSED; the assertion cannot fail"
    FAILURES=$((FAILURES + 1))
  elif ! printf '%s' "${out}" | grep -q -- "${expect}"; then
    echo "  FAIL  ${label} — failed (exit ${status}) but not with \"${expect}\":"
    printf '%s\n' "${out}" | tail -3 | sed 's/^/        /'
    FAILURES=$((FAILURES + 1))
  else
    echo "  PASS  ${label}"
  fi
}

echo "== control: the unmutated fence passes =="
set +e
control_out="$(bash "${FENCE}" 2>&1)"
control_status=$?
set -e
if [ "${control_status}" -eq 0 ]; then
  echo "  PASS  the real fence is green"
else
  # Print what the fence said. tofu:ci runs this target BEFORE the fence, so this
  # is the only place its ::error:: lines reach the log, and its exit class (1 =
  # the boundary moved, 2 = environment) is propagated rather than flattened.
  printf '%s\n' "${control_out}" >&2
  echo "  FAIL  the real fence is already red — fix that first; every bite below is meaningless" >&2
  exit "${control_status}"
fi

echo "== each assertion bites =="

bite "pin parity catches a site that lost the pin" \
  "pin parity:" \
  '  "tofu/modules/talos-cluster/README.md"' \
  '  "Taskfile.yml"'

bite "pin parity refuses a range, the drift it exists for" \
  "which is not an exact version" \
  'MODULE_PIN="$(' \
  'MODULE_PIN=">= 0.7.0, < 1.0.0"; unused="$('

bite "pin parity catches a lock that disagrees with the pin" \
  "Regenerate it" \
  '[ "${LOCK_PIN}" = "${MODULE_PIN}" ] ||' \
  '[ "${LOCK_PIN}" = "${MODULE_PIN}zz" ] ||'

bite "case A catches a kind that never reached the render" \
  "case A: UserVolumeConfig did not reach" \
  "kinds | grep -qx 'UserVolumeConfig' ||" \
  "kinds | grep -qx 'UserVolumeConfigZ' ||"

bite "case B measures the patch, not the generated default" \
  "case B: the SecurityProfileConfig patch was accepted but did not reach" \
  'kind: SecurityProfileConfig
workloadIsolation: false' \
  'kind: SecurityProfileConfig
workloadIsolation: true'

bite "case C catches a label that did not merge" \
  "case C: the KubeNodeConfig patch was accepted but its label did not merge" \
  'kind: KubeNodeConfig
labels:
  probe: "true"' \
  'kind: KubeNodeConfig
labels:
  other: "true"'

bite "case D catches a registry that stopped refusing" \
  "case D: the provider ACCEPTED" \
  'kind: PlatformBaseProbeConfig
probe: true' \
  'kind: UserVolumeConfig
name: probe'

bite "case E asserts the workload-isolation VALUE, not the kind" \
  "no longer generates SecurityProfileConfig with workloadIsolation enabled" \
  "document SecurityProfileConfig | grep -q 'workloadIsolation: true' ||" \
  "document SecurityProfileConfig | grep -q 'workloadIsolation: probe' ||"

bite "case E asserts the trim interval, not the kind" \
  "no longer generates FilesystemTrimConfig with a 168h interval" \
  "document FilesystemTrimConfig | grep -q 'interval: 168h0m0s' ||" \
  "document FilesystemTrimConfig | grep -q 'interval: 999h0m0s' ||"

bite "case E's positive control catches an unrecognisable prev-line render" \
  "the absence checks below would prove nothing" \
  "kinds | grep -qx 'HostnameConfig' ||" \
  "kinds | grep -qx 'HostnameConfigZ' ||"

bite "case E catches the 1.14 documents reaching the previous line" \
  "case E: the provider now emits" \
  'TALOS_PREV_PIN="${2:-}"' \
  'TALOS_PREV_PIN="${2:-v1.14.0}"'

bite "case F's positive control catches an install patch that did not land" \
  "the machine.install patch did not reach the rendered v1alpha1 document" \
  '[ "$(install_disk)" = "/dev/nvme0n1" ] ||' \
  '[ "$(install_disk)" = "/dev/probe0n1" ] ||'

bite "case F catches the generated install document following the patch" \
  "case F: the generated UnattendedInstallConfig now follows" \
  "if document UnattendedInstallConfig | grep -q '/dev/nvme0n1'; then" \
  "if document UnattendedInstallConfig | grep -q '/dev/sda'; then"

bite "case G catches a remedy patch that did not land" \
  "case G: the UnattendedInstallConfig patch was accepted but its disk selector did not reach" \
  'kind: UnattendedInstallConfig
provisioning:
  diskSelector:
    match: disk.dev_path == "/dev/nvme0n1"' \
  'kind: UnattendedInstallConfig
provisioning:
  diskSelector:
    match: disk.dev_path == "/dev/sdz"'

if [ "${FAILURES}" -ne 0 ]; then
  echo "::error::check-provider-document-kinds-bites: ${FAILURES} assertion(s) do not bite, or their anchors no longer match ${FENCE}. Each FAIL line above names the scenario: fix the fence's assertion, or update that scenario's anchor in this file if the fence's wording moved." >&2
  exit 1
fi
echo "check-provider-document-kinds-bites: OK — every expectation this script can falsify fails on its own mutation, and the real fence stays green"
