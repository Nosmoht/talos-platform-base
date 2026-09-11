#!/usr/bin/env bash
# check-provider-document-kinds.sh — bind the module's "any machine-config
# field" escape hatch to what the PINNED provider actually accepts and generates.
#
# WHY THIS EXISTS: the module offers four opaque `config_patches` lists, which
# reads as "every Talos machine-config field is reachable without a module
# change". That holds only for document kinds the pinned provider's bundled
# Talos machinery knows: the provider decodes every patch LOCALLY before
# rendering, so the reachable surface is bounded by the provider version, not by
# the talos_version a consumer pins. Nothing else in this repo observes that
# coupling.
#
# Case-by-case rationale, the boundary's history, and why the pin is an exact
# prerelease: knowledge/decisions/0027-talos-provider-prerelease-pin.md. Two
# cases are deliberately red-on-improvement (E's absent half, F) — that is the
# signal to revisit the 1.13.9 example pins, not a breakage to patch out.
#
# CONSTRAINT — key material. The probe renders a real (per-run, throwaway) PKI,
# and several generated documents carry it. The fixture exposes only a kind-keyed
# ALLOWLIST of documents plus the v1alpha1 `machine.install` block, so no
# assertion here can read or print key material even if a future case asks for a
# kind that does. Extend the fixture's allowlist deliberately, never by reaching
# for the whole rendered stream.
#
# The probe is LOCAL: talos_machine_secrets generates its PKI in memory and
# talos_machine_configuration renders from it, so no cluster and no Image Factory
# are involved and the gate belongs in the offline chain. `tofu init` may still
# reach the registry to fetch the provider.
#
# Usage: scripts/check-provider-document-kinds.sh [talos_version] [prev_talos_version] [k8s_version]
# Exit: 0 the boundary is where it is documented to be; 1 it moved (the message
#       names which case); 2 an environment error (missing tool, fixture, lock,
#       or an init that could not fetch the provider).
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "${ROOT}"

TALOS_PIN="${1:-v1.14.0}"
K8S_PIN="${3:-v1.37.0}"
EXAMPLE_CLUSTER_YAML="tofu/modules/talos-cluster/examples/complete/cluster.yaml"
# READ from the example rather than hardcoded: case E asserts what an unchanged
# consumer keeps receiving, and its failure text claims the examples still carry
# this pin. Moving the example to 1.14 (#252 AC 4) must move this probe with it,
# not leave it asserting absence at a version nobody uses.
TALOS_PREV_PIN="${2:-}"

FIXTURE="tofu/modules/talos-cluster/tests/fixtures/provider-document-kinds"
LOCK="tofu/modules/talos-cluster/.terraform.lock.hcl"
REJECTION="not registered"

# Every file that must carry the module's provider pin verbatim. An exact pin
# that drifts at one site does not silently resolve to the same provider the way
# the former range did — it makes `tofu init` fail there, and a stale copy in the
# README or the example ships to consumers as a broken instruction.
PIN_SITES=(
  "tofu/modules/talos-cluster/versions.tf"
  "tofu/modules/talos-cluster/examples/complete/versions.tf"
  "tofu/modules/talos-cluster/tests/fixtures/provider-document-kinds/versions.tf"
  "tofu/modules/talos-cluster/test/pki-reconcile-microtest.sh"
  "tofu/modules/talos-cluster/README.md"
)

fail() {
  echo "::error::check-provider-document-kinds: $*" >&2
  exit 1
}
envfail() {
  echo "::error::check-provider-document-kinds: $*" >&2
  exit 2
}

for bin in tofu jq; do
  command -v "${bin}" >/dev/null 2>&1 || envfail "${bin} not on PATH"
done
[ -d "${FIXTURE}" ] || envfail "${FIXTURE} not found"
[ -f "${LOCK}" ] || envfail "${LOCK} not found"

# --- Pin parity: every site carries the module's version, verbatim ------------
MODULE_PIN="$(
  awk '/source  = "siderolabs\/talos"/{f=1} f&&/version = /{gsub(/[",]/,"",$3); print $3; exit}' \
    tofu/modules/talos-cluster/versions.tf
)"
# An exact version, not a constraint fragment: a range would leave $3 as an
# OPERATOR (">=") that every site matches through its own required_version line,
# and the parity loop below would pass vacuously on the one drift it exists for.
[[ "${MODULE_PIN}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] ||
  fail "pin parity: tofu/modules/talos-cluster/versions.tf declares '${MODULE_PIN:-<unreadable>}' for siderolabs/talos, which is not an exact version. The module pins an exact prerelease on purpose (ADR-0027); a range there resolves to 0.11.0 and silently closes the Talos 1.14 document surface."
# Each site is matched on the LINE that names the provider, not anywhere in the
# file: the README also mentions the version in prose, which would keep this
# green while the example root it ships carries a stale one.
for site in "${PIN_SITES[@]}"; do
  grep -q -- "siderolabs/talos.*${MODULE_PIN}\|${MODULE_PIN}.*siderolabs/talos" "${site}" ||
    grep -A3 -- 'source *= *"siderolabs/talos"' "${site}" | grep -q -- "${MODULE_PIN}" ||
    fail "pin parity: ${site} does not declare siderolabs/talos at ${MODULE_PIN}. An exact pin that drifts breaks \`tofu init\` at that site, and the README and example ship to consumers."
done
LOCK_PIN="$(
  awk '/siderolabs\/talos/{f=1} f&&/version[[:space:]]*=/{gsub(/[",]/,"",$3); print $3; exit}' "${LOCK}"
)"
[ "${LOCK_PIN}" = "${MODULE_PIN}" ] ||
  fail "pin parity: the committed lock records ${LOCK_PIN:-<none>} but versions.tf pins ${MODULE_PIN}. Regenerate it: cd tofu/modules/talos-cluster && tofu providers lock -platform=linux_amd64 -platform=darwin_arm64 -platform=linux_arm64"

if [ -z "${TALOS_PREV_PIN}" ]; then
  [ -f "${EXAMPLE_CLUSTER_YAML}" ] || envfail "${EXAMPLE_CLUSTER_YAML} not found"
  TALOS_PREV_PIN="$(awk '/^talos:/{f=1} f&&/^  version:/{print $2; exit}' "${EXAMPLE_CLUSTER_YAML}")"
  [ -n "${TALOS_PREV_PIN}" ] ||
    envfail "could not read talos.version from ${EXAMPLE_CLUSTER_YAML}"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
cp "${FIXTURE}"/*.tf "${WORK}/"
# The lock file carries the provider's checksums; copying it is what makes the
# probe use the artifact the module resolves rather than whatever the registry
# currently serves for the pinned version.
cp "${LOCK}" "${WORK}/.terraform.lock.hcl"

if ! init_out="$( cd "${WORK}" && tofu init -input=false -no-color 2>&1 )"; then
  printf '%s\n' "${init_out}" >&2
  envfail "tofu init failed in the probe directory. Most likely the pinned provider is no longer downloadable (a prerelease can be withdrawn upstream), or the fixture's versions.tf and the copied lock disagree."
fi

PROVIDER_VERSION="$(
  awk '/siderolabs\/talos/{f=1} f&&/version[[:space:]]*=/{gsub(/[",]/,"",$3); print $3; exit}' "${LOCK}"
)"
echo "probing siderolabs/talos ${PROVIDER_VERSION:-<unknown>} at talos ${TALOS_PIN} (previous line ${TALOS_PREV_PIN}) / kubernetes ${K8S_PIN}"

# $1 = talos version, $2 = patch YAML ("" for no patch). Prints the apply
# output; returns the apply's exit status.
probe() {
  jq -n \
    --arg talos "$1" \
    --arg k8s "${K8S_PIN}" \
    --arg patch "$2" \
    '{talos_version: $talos, kubernetes_version: $k8s,
      config_patches: (if $patch == "" then [] else [$patch] end)}' \
    >"${WORK}/probe.auto.tfvars.json"
  ( cd "${WORK}" && tofu apply -auto-approve -input=false -no-color 2>&1 )
}

kinds() {
  ( cd "${WORK}" && tofu output -json document_kinds ) | jq -r '.[]'
}

# $1 = kind. Prints EVERY instance of that kind from the last render. Limited to
# the fixture's allowlist, so it can never reach a document holding key material.
document() {
  ( cd "${WORK}" && tofu output -json documents ) | jq -r --arg k "$1" '.[$k] // ""'
}

install_disk() {
  ( cd "${WORK}" && tofu output -raw v1alpha1_install_disk )
}

# --- Guard: no allowlisted document may carry key material -------------------
# The fixture's allowlist is a human judgement that these kinds hold no secrets,
# and every assertion below interpolates their bodies into failure messages that
# land in a PUBLIC repository's CI log. This turns that judgement into a check.
assert_no_key_material() {
  local kind body
  for kind in $( ( cd "${WORK}" && tofu output -json documents ) | jq -r 'keys[]' ); do
    body="$(document "${kind}")"
    printf '%s' "${body}" | grep -qiE 'PRIVATE KEY|BEGIN CERTIFICATE|(^|[^a-z])(token|secret|key|crt):' &&
      fail "guard: the rendered ${kind} document now carries something key-shaped. The fixture's allowlist assumes these documents are safe to print into CI logs — narrow the allowlist before this gate prints one."
  done
  return 0
}

# --- Case A: the patch path itself carries a kind the provider does not generate
if ! out="$(probe "${TALOS_PIN}" 'apiVersion: v1alpha1
kind: UserVolumeConfig
name: probe')"; then
  printf '%s\n' "${out}" >&2
  fail "case A: the provider rejected UserVolumeConfig, a kind it is expected to know. The probe itself is broken, or the pinned provider is not the one assumed."
fi
kinds | grep -qx 'UserVolumeConfig' ||
  fail "case A: UserVolumeConfig did not reach the rendered configuration. Kinds present: $(kinds | paste -sd, -)."
assert_no_key_material

# --- Cases B and C: the Talos 1.14 kinds are reachable, by VALUE --------------
# Both kinds are generated by default at a 1.14 pin, so presence proves nothing:
# each case patches a value the default does not carry and asserts that value.
if ! out="$(probe "${TALOS_PIN}" 'apiVersion: v1alpha1
kind: SecurityProfileConfig
workloadIsolation: false')"; then
  printf '%s\n' "${out}" >&2
  fail "case B: the pinned provider REJECTED a SecurityProfileConfig patch. Talos 1.14's workload-isolation default is no longer overridable through config_patches — the 1.14 document surface closed again; update the module README's 1.14 section before touching this gate."
fi
document SecurityProfileConfig | grep -q 'workloadIsolation: false' ||
  fail "case B: the SecurityProfileConfig patch was accepted but did not reach the rendered document. Rendered:
$(document SecurityProfileConfig)"

if ! out="$(probe "${TALOS_PIN}" 'apiVersion: v1alpha1
kind: KubeNodeConfig
labels:
  probe: "true"')"; then
  printf '%s\n' "${out}" >&2
  fail "case C: the pinned provider REJECTED a KubeNodeConfig patch. The kind that carries the 1.14 spelling of machine.nodeLabels/nodeTaints/kubelet is unreachable again, which blocks the v1alpha1 deprecation migration. NOTE: this document's field is \`labels:\`, not the v1alpha1 \`nodeLabels:\` spelling — a patch using the old key is rejected with \"unknown keys found\"."
fi
document KubeNodeConfig | grep -q 'probe: "true"' ||
  fail "case C: the KubeNodeConfig patch was accepted but its label did not merge into the generated document. Rendered:
$(document KubeNodeConfig)"

# --- Case D: an unregistered kind is still refused ---------------------------
# Without this the gate cannot distinguish a registry that knows the 1.14 kinds
# from a decode path that stopped validating patches at all.
if out="$(probe "${TALOS_PIN}" 'apiVersion: v1alpha1
kind: PlatformBaseProbeConfig
probe: true')"; then
  fail "case D: the provider ACCEPTED PlatformBaseProbeConfig, a kind that exists nowhere. config_patches are no longer validated against the provider's machinery registry, so cases A-C prove nothing about reachability any more."
fi
printf '%s\n' "${out}" | grep -q "${REJECTION}" ||
  fail "case D: the invented kind was rejected, but not with the expected \"${REJECTION}\" decode error. The failure has a different cause and the gate is no longer measuring the registry:
${out}"

# --- Case E: the 1.14 defaults, by value, and version-gated ------------------
# The claim this pin was taken for is a VALUE ("workloadIsolation is on for new
# 1.14 clusters"), so presence of the kind is not the assertion.
if ! out="$(probe "${TALOS_PIN}" '')"; then
  printf '%s\n' "${out}" >&2
  fail "case E: the pinned provider could not render an unpatched ${TALOS_PIN} configuration at all. That is a boundary move, not an environment fault — the probe reaches no network once init has run."
fi
document SecurityProfileConfig | grep -q 'workloadIsolation: true' ||
  fail "case E: a ${TALOS_PIN} pin no longer generates SecurityProfileConfig with workloadIsolation enabled. The security posture the module README and CHANGELOG promise for a fresh 1.14 cluster is gone. Rendered:
$(document SecurityProfileConfig)"
document FilesystemTrimConfig | grep -q 'interval: 168h0m0s' ||
  fail "case E: a ${TALOS_PIN} pin no longer generates FilesystemTrimConfig with a 168h interval. Rendered:
$(document FilesystemTrimConfig)"

if ! out="$(probe "${TALOS_PREV_PIN}" '')"; then
  printf '%s\n' "${out}" >&2
  fail "case E: the pinned provider could not render an unpatched ${TALOS_PREV_PIN} configuration — the line the module's own examples and fixtures still carry."
fi
# Positive control: without it the absence assertions below would also pass on a
# render that produced nothing at all.
kinds | grep -qx 'HostnameConfig' ||
  fail "case E: the ${TALOS_PREV_PIN} render carries no HostnameConfig, so it is not the document set this gate was calibrated against and the absence checks below would prove nothing. Kinds present: $(kinds | paste -sd, -)."
for absent in SecurityProfileConfig FilesystemTrimConfig; do
  if kinds | grep -qx "${absent}"; then
    fail "case E: the provider now emits ${absent} at a ${TALOS_PREV_PIN} pin. The examples and fixtures still carry that pin, so an unchanged consumer's rendered configuration changed — reconcile the module README before updating this gate."
  fi
done

# --- Case F: the generated install document ignores the module's install patch
# The module writes machine.install (v1alpha1) for every node. At a 1.14 pin the
# provider ALSO emits UnattendedInstallConfig from its own defaults, and the two
# disagree. The positive control is what separates "the provider ignores the
# patch" from "the provider stopped honouring machine.install at all".
if ! out="$(probe "${TALOS_PIN}" 'machine:
  install:
    disk: /dev/nvme0n1')"; then
  printf '%s\n' "${out}" >&2
  fail "case F: the pinned provider REJECTED a machine.install patch — the v1alpha1 install spelling the module writes for every node."
fi
[ "$(install_disk)" = "/dev/nvme0n1" ] ||
  fail "case F: the machine.install patch did not reach the rendered v1alpha1 document — machine.install.disk came back as '$(install_disk)'. The provider stopped honouring the install spelling the module writes for every node, so every install description the module emits is silently gone."
document UnattendedInstallConfig | grep -q 'diskSelector' ||
  fail "case F: a ${TALOS_PIN} pin no longer generates an UnattendedInstallConfig disk selector. The install-document conflict the README warns about is gone — drop the warning and revisit moving the pins to 1.14 (#252 AC 4)."
if document UnattendedInstallConfig | grep -q '/dev/nvme0n1'; then
  fail "case F: the generated UnattendedInstallConfig now follows the machine.install patch. The two install descriptions no longer disagree — drop the README warning and revisit moving the pins to 1.14 (#252 AC 4)."
fi

# --- Case G: the remedy the README prescribes for case F actually works -------
# README §"Talos 1.14" tells a consumer to patch the generated install document
# themselves. That instruction guards a bare-metal install, so it is measured
# here rather than assumed.
if ! out="$(probe "${TALOS_PIN}" 'apiVersion: v1alpha1
kind: UnattendedInstallConfig
provisioning:
  diskSelector:
    match: disk.dev_path == "/dev/nvme0n1"')"; then
  printf '%s\n' "${out}" >&2
  fail "case G: the pinned provider REJECTED an UnattendedInstallConfig patch. The remedy the module README prescribes for the conflicting install document does not work — correct the README before touching this gate."
fi
document UnattendedInstallConfig | grep -q '/dev/nvme0n1' ||
  fail "case G: the UnattendedInstallConfig patch was accepted but its disk selector did not reach the rendered document. Rendered:
$(document UnattendedInstallConfig)"
if [ "$(document UnattendedInstallConfig | grep -c '^kind: UnattendedInstallConfig$')" -ne 1 ]; then
  fail "case G: patching UnattendedInstallConfig produced more than one document of that kind. The README's remedy appends rather than merges, so a consumer following it ships two conflicting install descriptions. Rendered:
$(document UnattendedInstallConfig)"
fi

echo "check-provider-document-kinds: boundary unchanged — every pin site agrees, the patch path carries UserVolumeConfig, the Talos 1.14 kinds reach the rendered documents by value, an invented kind is still refused, ${TALOS_PIN} generates workloadIsolation: true and a 168h trim while ${TALOS_PREV_PIN} generates neither, the generated install document still ignores machine.install, and patching it directly still works."
