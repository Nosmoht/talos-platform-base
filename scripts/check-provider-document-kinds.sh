#!/usr/bin/env bash
# check-provider-document-kinds.sh — bind the module's "any machine-config
# field" escape hatch to what the PINNED provider actually accepts.
#
# WHY THIS EXISTS: the module offers four opaque `config_patches` lists, which
# reads as "every Talos machine-config field is reachable without a module
# change". That holds only for multi-document kinds the pinned provider's
# bundled Talos machinery knows. The provider decodes every patch LOCALLY before
# rendering, so a kind newer than that machinery is a hard plan-time error, not a
# passthrough — the reachable surface is bounded by the provider version, not by
# the talos_version a consumer pins. Nothing else in this repo observes that
# coupling; knowledge/decisions/0026-machine-config-apply-mode.md records the
# same unbound-mirror problem for apply_mode and leaves it unbuilt.
#
# It is an EXPIRY ALARM as much as a regression guard. Cases B and C assert a
# REJECTION, so the day a provider release inside the module's declared range
# starts accepting the Talos 1.14 kinds, this gate turns red — and that is the
# signal to reopen the deprecation migration and close the 1.14 default gap, not
# a breakage to patch out.
#
# SCOPE: three probe kinds, not an enumeration. UserVolumeConfig is the green
# half of the red-green binding (a registered kind must survive the patch path,
# so a rejection below is about the registry and not about the plumbing);
# SecurityProfileConfig is the consequential 1.14 kind (Talos 1.14 generates it
# with workloadIsolation enabled for every new cluster, and a module-bootstrapped
# cluster cannot opt in while this gate passes); KubeNodeConfig is the kind that
# blocks the v1alpha1 deprecation migration, since Talos 1.14 moves
# machine.nodeLabels, machine.nodeTaints and the kubelet fields into it and the
# module writes all three today.
#
# The probe is LOCAL: talos_machine_secrets generates its PKI in memory and
# talos_machine_configuration renders from it, so no cluster and no Image
# Factory are involved and the gate belongs in the offline chain. The provider
# version comes from the module's own .terraform.lock.hcl, so the gate describes
# the provider the module actually resolves; `tofu init` may still reach the
# registry to fetch it.
#
# Usage: scripts/check-provider-document-kinds.sh [talos_version] [k8s_version]
# Exit: 0 the boundary is where it is documented to be; 1 it moved (the message
#       names which case); 2 an environment error.
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "${ROOT}"

TALOS_PIN="${1:-v1.14.0}"
K8S_PIN="${2:-v1.37.0}"

FIXTURE="tofu/modules/talos-cluster/tests/fixtures/provider-document-kinds"
LOCK="tofu/modules/talos-cluster/.terraform.lock.hcl"
REJECTION="not registered"

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

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT
cp "${FIXTURE}"/*.tf "${WORK}/"
# The lock file is what pins the probe to the module's own provider selection;
# without it `tofu init` would resolve the newest release in the declared range
# and the gate would describe a provider the module does not use.
cp "${LOCK}" "${WORK}/.terraform.lock.hcl"

( cd "${WORK}" && tofu init -input=false -no-color >/dev/null 2>&1 ) ||
  envfail "tofu init failed in the probe directory"

PROVIDER_VERSION="$(
  awk '/siderolabs\/talos/{f=1} f&&/version[[:space:]]*=/{gsub(/[",]/,"",$3); print $3; exit}' "${LOCK}"
)"
echo "probing siderolabs/talos ${PROVIDER_VERSION:-<unknown>} at talos ${TALOS_PIN} / kubernetes ${K8S_PIN}"

# $1 = patch YAML ("" for no patch). Prints the apply output; returns the
# apply's exit status.
probe() {
  jq -n \
    --arg talos "${TALOS_PIN}" \
    --arg k8s "${K8S_PIN}" \
    --arg patch "$1" \
    '{talos_version: $talos, kubernetes_version: $k8s,
      config_patches: (if $patch == "" then [] else [$patch] end)}' \
    >"${WORK}/probe.auto.tfvars.json"
  ( cd "${WORK}" && tofu apply -auto-approve -input=false -no-color 2>&1 )
}

kinds() {
  ( cd "${WORK}" && tofu output -json document_kinds ) | jq -r '.[]'
}

# --- Case A: a registered kind must survive the patch path -------------------
if ! out="$(probe 'apiVersion: v1alpha1
kind: UserVolumeConfig
name: probe')"; then
  printf '%s\n' "${out}" >&2
  fail "case A: the provider rejected UserVolumeConfig, a kind it is expected to know. The probe itself is broken, or the pinned provider is older than assumed."
fi
kinds | grep -qx 'UserVolumeConfig' ||
  fail "case A: UserVolumeConfig did not reach the rendered configuration. Kinds present: $(kinds | paste -sd, -)."

# --- Cases B and C: the Talos 1.14 kinds must still be rejected --------------
for case_kind in \
  'B|SecurityProfileConfig|apiVersion: v1alpha1
kind: SecurityProfileConfig
workloadIsolation: true' \
  'C|KubeNodeConfig|apiVersion: v1alpha1
kind: KubeNodeConfig
nodeLabels:
  probe: "true"'; do
  label="${case_kind%%|*}"
  rest="${case_kind#*|}"
  kind="${rest%%|*}"
  patch="${rest#*|}"

  if out="$(probe "${patch}")"; then
    fail "case ${label}: the pinned provider now ACCEPTS ${kind}. The Talos 1.14 document surface has opened up — reopen the deprecation migration and the 1.14 default gap, then update this gate and the module README."
  fi
  printf '%s\n' "${out}" | grep -q "${REJECTION}" ||
    fail "case ${label}: ${kind} was rejected, but not with the expected \"${REJECTION}\" decode error. The failure has a different cause and the gate is no longer measuring the registry:
${out}"
done

# --- Case D: the 1.14 default documents are absent from a 1.14 pin -----------
if ! out="$(probe '')"; then
  printf '%s\n' "${out}" >&2
  envfail "case D: generating an unpatched configuration failed"
fi
for absent in SecurityProfileConfig FilesystemTrimConfig; do
  if kinds | grep -qx "${absent}"; then
    fail "case D: the provider now emits ${absent} at a ${TALOS_PIN} pin. That closes one half of the 1.14 default gap — update the module README and this gate."
  fi
done

echo "check-provider-document-kinds: boundary unchanged — registered kinds pass, the Talos 1.14 kinds are rejected, and a ${TALOS_PIN} pin yields none of the 1.14 default documents."
