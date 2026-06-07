#!/usr/bin/env bash
#
# run-adoption-proof.sh — prove that adopting an already-running cluster via
# `tofu import` plans "0 to destroy" (no PKI roll, no re-bootstrap), per the
# adoption runbook in UPGRADING.md §"Adopting an already-running cluster".
#
# This is the reproducible form of the runbook's step-5 gate. It imports the two
# identity-bearing resources (machine_secrets, machine_bootstrap), ASSERTS both
# landed in state (the runbook's step-3 gate), then runs `tofu plan` and asserts
# the plan destroys NOTHING.
#
# SAFETY — this NEVER touches your real state backend. It copies the root's
# config into a throwaway temp dir and runs `tofu init -backend=false` there, so
# your production/remote backend is not initialised and not written. All imports
# land in local, disposable state (mode 0600 via umask). The temp dir is removed
# on EXIT and on INT/TERM/HUP. NOTE: that local proof state is UNENCRYPTED and
# holds the imported PKI — run only on a trusted workstation; a hard kill
# (kill -9 / OOM) can still leave it. The --bundle plaintext is YOURS to manage
# (see the runbook's "Plaintext hygiene"); this script does not delete it.
#
# LIMITS: refuses roots using a `cloud {}` (HCP) block — `-backend=false` does
# not neutralise it. Plan still reads the Image-Factory data sources (network to
# factory.talos.dev); it does not refresh against or mutate your cluster.
#
# Requirements: tofu (>= 1.7). Your root's input variables must resolve in the
# copy — pass `-var-file=...`/`-var ...` after `--`. Only -var/-var-file are
# allowed through; isolation/verdict-affecting flags are rejected.
#
# Usage:
#   ./run-adoption-proof.sh --root <consumer-root-dir> \
#                           --bundle <decrypted-secrets-bundle> \
#                           [--module-addr module.cluster] \
#                           [-- -var-file=proof.tfvars]
#
# Exit 0 = "0 to destroy" (PASS). Non-zero = destroy planned / error (FAIL).

set -euo pipefail
export LC_ALL=C LANG=C

# Stable, isolated tofu environment — drop ambient redirects that could break
# isolation or override our flags.
unset TF_DATA_DIR TF_WORKSPACE TF_CLI_ARGS TF_CLI_ARGS_init \
      TF_CLI_ARGS_import TF_CLI_ARGS_plan 2>/dev/null || true

ROOT_DIR="."
BUNDLE=""
MODULE_ADDR="module.cluster"
PASSTHRU=()

usage() {
  cat <<'USAGE'
run-adoption-proof.sh — reproducible "0 to destroy" adoption proof.

  --root DIR          OpenTofu root that calls the talos-cluster module (default: .)
  --bundle FILE       decrypted talos secrets bundle (required)
  --module-addr ADDR  module instance address (default: module.cluster)
  -- ARGS...          pass-through tofu args; only -var / -var-file allowed

Exit 0 = 0 to destroy (PASS). See UPGRADING.md §Adopting an already-running cluster.
USAGE
  exit "${1:-0}"
}

# Reject pass-through flags that would break isolation or skew the verdict.
reject_passthru() {
  local a
  for a in "$@"; do
    case "$a" in
      -state|-state=*|-state-out|-state-out=*|-target|-target=*|\
      -refresh|-refresh=*|-refresh-only|-backend|-backend=*|-backend-config|-backend-config=*|\
      -chdir|-chdir=*|-json|-input|-input=*|-lock|-lock=*|-lock-timeout=*)
        echo "FAIL: pass-through flag '$a' is not allowed (only -var / -var-file)" >&2
        exit 1 ;;
    esac
  done
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root)        ROOT_DIR="${2:?--root needs a dir}"; shift 2 ;;
    --bundle)      BUNDLE="${2:?--bundle needs a path}"; shift 2 ;;
    --module-addr) MODULE_ADDR="${2:?--module-addr needs a value}"; shift 2 ;;
    -h|--help)     usage 0 ;;
    --)            shift; reject_passthru "$@"; PASSTHRU=("$@"); break ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; usage 1 ;;
  esac
done

command -v tofu >/dev/null 2>&1 || { echo "FAIL: tofu not found" >&2; exit 1; }
[ -d "$ROOT_DIR" ] || { echo "FAIL: --root '$ROOT_DIR' is not a directory" >&2; exit 1; }
[ -n "$BUNDLE" ]   || { echo "FAIL: --bundle is required (decrypted secrets bundle)" >&2; exit 1; }
[ -f "$BUNDLE" ]   || { echo "FAIL: --bundle '$BUNDLE' not found" >&2; exit 1; }

# Absolute paths — the proof runs in a different working directory.
ROOT_DIR="$(cd "$ROOT_DIR" && pwd)"
BUNDLE="$(cd "$(dirname "$BUNDLE")" && pwd)/$(basename "$BUNDLE")"

umask 077
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/talos-adoption-proof-XXXXXX")"
# shellcheck disable=SC2329  # invoked indirectly via the traps below
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT INT TERM HUP

echo "==> Adoption proof for ${MODULE_ADDR} (isolated copy in ${WORKDIR}; real backend untouched)"

# Copy ONLY config inputs — never .terraform or state — into the throwaway dir.
find "$ROOT_DIR" -maxdepth 1 -type f \
  \( -name '*.tf' -o -name '*.tf.json' -o -name '*.tfvars' -o -name '*.tfvars.json' \) \
  -exec cp {} "$WORKDIR/" \;
[ -d "$ROOT_DIR/patches" ] && cp -R "$ROOT_DIR/patches" "$WORKDIR/patches"

# Refuse HCP `cloud {}` roots — `-backend=false` does NOT isolate them, so the
# proof could run against the real remote workspace.
if grep -REqs '^[[:space:]]*cloud[[:space:]]*\{' "$WORKDIR"/*.tf 2>/dev/null; then
  echo "FAIL: root uses a 'cloud {}' (HCP) block; -backend=false cannot isolate it." >&2
  echo "      Run the proof against a copy with the cloud {} block removed." >&2
  exit 1
fi

# Pass-through tofu flags (-var/-var-file after `--`) are forwarded with the
# ${PASSTHRU[@]+"${PASSTHRU[@]}"} idiom: it expands to nothing when the array is
# empty and to the quoted elements otherwise — safe under `set -u` on bash 3.2
# (macOS default), where a bare "${PASSTHRU[@]}" on an empty array aborts.
tofu_q() { tofu -chdir="$WORKDIR" "$@"; }

# -backend=false is the isolation guarantee: the consumer's real backend is
# never initialised; imports write to a local terraform.tfstate in WORKDIR.
if ! tofu_q init -input=false -backend=false >/dev/null 2>"$WORKDIR/init.err"; then
  echo "FAIL: tofu init -backend=false failed. If your root configures state" >&2
  echo "      encryption with a required passphrase var, export it first" >&2
  echo "      (e.g. TF_VAR_<name>=...). init stderr:" >&2
  sed 's/^/        /' "$WORKDIR/init.err" >&2
  exit 1
fi
echo "  init complete (local state, no backend)"

SECRETS_ADDR="${MODULE_ADDR}.talos_machine_secrets.this"
BOOTSTRAP_ADDR="${MODULE_ADDR}.talos_machine_bootstrap.this"

echo "  importing ${SECRETS_ADDR}  <- ${BUNDLE}"
tofu_q import -input=false ${PASSTHRU[@]+"${PASSTHRU[@]}"} "$SECRETS_ADDR" "$BUNDLE" >/dev/null

echo "  importing ${BOOTSTRAP_ADDR} (mark already-bootstrapped)"
tofu_q import -input=false ${PASSTHRU[@]+"${PASSTHRU[@]}"} "$BOOTSTRAP_ADDR" adopted >/dev/null

# Runbook step-3 gate: BOTH identity resources MUST be in state. A missing
# bootstrap import would otherwise plan as "to add" (a re-bootstrap on apply)
# while still showing "0 to destroy" — a false PASS the destroy-count cannot see.
STATE_LIST="$(tofu_q state list)"
for addr in "$SECRETS_ADDR" "$BOOTSTRAP_ADDR"; do
  printf '%s\n' "$STATE_LIST" | grep -qxF "$addr" \
    || { echo "FAIL: ${addr} is not in state after import — adoption incomplete." >&2; exit 1; }
done
echo "  both identity resources present in state"

echo "  planning (-refresh=false, -no-color; reads Image-Factory, no cluster refresh)"
PLAN_OUT="$WORKDIR/plan.txt"
# Critical flags LAST so a stray pass-through cannot override them.
tofu_q plan -input=false ${PASSTHRU[@]+"${PASSTHRU[@]}"} -refresh=false -no-color > "$PLAN_OUT"

# Verdict from the LAST `Plan:` summary line only. For adoption we EXPECT
# "to add" resources, so a bare "No changes." is unexpected (empty/degenerate
# copy) and is NOT treated as PASS.
SUMMARY="$(grep -E '^Plan: ' "$PLAN_OUT" | tail -1 || true)"
if printf '%s' "$SUMMARY" | grep -qE ', 0 to destroy\.$'; then
  echo
  echo "PASS: ${SUMMARY}"
  echo "      0 to destroy proves no PKI roll and no re-bootstrap — and ONLY that."
  echo "      It does NOT prove config equivalence: the machine_configuration_apply"
  echo "      resources plan as 'to add' and a real apply pushes config to the nodes."
  echo "      Diff the rendered config vs the running nodes before any apply."
  exit 0
fi

echo
if grep -qE '^No changes\.' "$PLAN_OUT"; then
  echo "FAIL: plan reports 'No changes' — expected 'to add' resources for an" >&2
  echo "      adoption. The config copy is likely incomplete; proof is inconclusive." >&2
else
  echo "FAIL: plan would DESTROY resources — adoption is NOT safe as configured." >&2
  echo "      ${SUMMARY:-<no Plan: summary line found>}" >&2
  echo "      A destroy of talos_machine_secrets = PKI regen; of talos_machine_bootstrap" >&2
  echo "      = re-bootstrap. Do NOT apply. See UPGRADING.md §Adopting an already-running cluster." >&2
fi
exit 1
