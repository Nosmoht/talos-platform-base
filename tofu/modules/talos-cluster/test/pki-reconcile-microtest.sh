#!/usr/bin/env bash
#
# pki-reconcile-microtest.sh — prove that the talos_version reconcile on an
# imported talos_machine_secrets is a metadata-only in-place UPDATE that
# PRESERVES the PKI bytes (it does NOT regenerate secrets).
#
# Why this exists: the adoption runbook (UPGRADING.md §"Adopting an
# already-running cluster") relies on `tofu import` of machine_secrets being
# safe even though the import sets talos_version to the provider DEFAULT
# (observed v1.3), not the value in the bundle. A consumer pinning a newer
# version therefore sees `talos_version: v1.3 -> <pin>` planned as an in-place
# `update`. This microtest proves that update keeps the machine_secrets bytes
# identical — so the "0 to destroy" gate in the runbook is sufficient.
#
# Fully self-contained: NO cluster, NO consumer root, state-only. Generates a
# THROWAWAY `talosctl gen secrets` bundle (random PKI for no cluster), imports
# it, flips the pinned version, and compares the machine_secrets hash before and
# after. The temp dir (throwaway bundle + local state) is removed on exit and on
# INT/TERM/HUP.
#
# Requirements: talosctl, tofu (>= 1.7), jq. Network access for `tofu init`
# (provider download) on first run.
#
# Usage:
#   ./pki-reconcile-microtest.sh            # default pin v1.9
#   PIN_VERSION=v1.10 ./pki-reconcile-microtest.sh
#
# Exit 0 = PKI preserved (PASS). 2 = skipped (missing tool). Other = FAIL.

set -euo pipefail
export LC_ALL=C LANG=C

PIN_VERSION="${PIN_VERSION:-v1.9}"

log()  { printf '  %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
skip() { printf 'SKIP: %s\n' "$*" >&2; exit 2; }

for tool in talosctl tofu jq; do
  command -v "$tool" >/dev/null 2>&1 || skip "missing required tool: $tool"
done

umask 077
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/talos-pki-microtest-XXXXXX")"
# shellcheck disable=SC2329  # invoked indirectly via the traps below
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT INT TERM HUP

echo "==> PKI-reconcile microtest (pin ${PIN_VERSION}) in ${WORKDIR}"

# 1. Throwaway PKI bundle — random, for no cluster; never leaves WORKDIR.
talosctl gen secrets -o "${WORKDIR}/bundle.yaml" >/dev/null
log "generated throwaway PKI bundle"

# 2. Minimal root: a single talos_machine_secrets resource, talos_version unset
#    so the import sets the provider default.
cat > "${WORKDIR}/versions.tf" <<'EOF'
terraform {
  required_version = ">= 1.9.0"
  required_providers {
    talos = {
      source  = "siderolabs/talos"
      # Tracks the module's own exact pin — the property under test is a
      # behaviour of THAT provider, not of whatever a range resolves to.
      version = "0.12.0-beta.0"
    }
  }
}
EOF
cat > "${WORKDIR}/main.tf" <<'EOF'
resource "talos_machine_secrets" "this" {}
EOF

# Extract the machine_secrets subtree from the current state. Guards against a
# provider that marks it sensitive (then `tofu show -json` emits null) — hashing
# `null` would manufacture a false PASS, so we fail loudly instead.
secrets_json() {
  tofu -chdir="${WORKDIR}" show -json \
    | jq -S '.values.root_module.resources[]
             | select(.address == "talos_machine_secrets.this")
             | .values.machine_secrets'
}
current_version() {
  tofu -chdir="${WORKDIR}" show -json \
    | jq -r '.values.root_module.resources[]
             | select(.address == "talos_machine_secrets.this")
             | .values.talos_version'
}
hash_secrets() {
  local ms="$1"
  [ -n "$ms" ] && [ "$ms" != "null" ] \
    || fail "machine_secrets is null/absent in 'tofu show -json' — provider likely marks it sensitive in this version; cannot verify PKI bytes"
  printf '%s' "$ms" | sha256sum | cut -d' ' -f1
}

tofu -chdir="${WORKDIR}" init -input=false >/dev/null
log "tofu init complete"

# 3. Import the bundle — sets talos_version to the provider default.
tofu -chdir="${WORKDIR}" import -input=false \
  talos_machine_secrets.this "${WORKDIR}/bundle.yaml" >/dev/null
V_BEFORE="$(current_version)"
H_BEFORE="$(hash_secrets "$(secrets_json)")"
log "after import:  talos_version=${V_BEFORE}  machine_secrets sha256=${H_BEFORE}"

# 4. Pin a higher talos_version and apply (state-only — no cluster).
cat > "${WORKDIR}/main.tf" <<EOF
resource "talos_machine_secrets" "this" {
  talos_version = "${PIN_VERSION}"
}
EOF
tofu -chdir="${WORKDIR}" apply -input=false -auto-approve >/dev/null
V_AFTER="$(current_version)"
H_AFTER="$(hash_secrets "$(secrets_json)")"
log "after reconcile: talos_version=${V_AFTER}  machine_secrets sha256=${H_AFTER}"

# 5. Verdict.
if [ "$V_AFTER" = "$V_BEFORE" ]; then
  fail "talos_version did not change (${V_BEFORE} -> ${V_AFTER}); test did not exercise the reconcile"
fi
if [ "$H_AFTER" = "$H_BEFORE" ]; then
  echo "PASS: talos_version ${V_BEFORE} -> ${V_AFTER} is an in-place update; machine_secrets bytes UNCHANGED (PKI preserved)."
  exit 0
fi
fail "machine_secrets CHANGED across the version reconcile (${H_BEFORE} -> ${H_AFTER}) — the reconcile REGENERATES PKI. The adoption runbook's safety claim does NOT hold; investigate before adopting any real cluster."
