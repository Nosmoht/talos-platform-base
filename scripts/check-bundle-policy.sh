#!/usr/bin/env bash
# Assert that an OKF bundle's `.openknowledge.toml` is actually IN EFFECT.
#
# `openknowledge validate` exits 0 with an empty policy when it cannot find a
# config, so every severity raise degrades back to the spec default and the
# gate reports green while checking nothing. scripts/check-knowledge-gate-bite.sh
# proves this detector bites.
#
# Usage: check-bundle-policy.sh <bundle-dir> <rule=severity>...
# Exit 0 = the bundle's own config is loaded and every named rule is at the
# named severity. Exit 1 = it is not, with the cause on stdout. Exit 2 =
# openknowledge could not run; its own stderr is reproduced verbatim, since a
# TOML syntax error and an unknown rule name both land here and neither is a
# discovery problem.

set -euo pipefail

# Runnable outside go-task, and go-task's env: block loses to an inherited
# value, so this has to be unconditional.
export OPENKNOWLEDGE_TELEMETRY=off

bundle="${1:?usage: check-bundle-policy.sh <bundle-dir> [--spec <v>] <rule=severity>...}"
shift
[ -d "$bundle" ] || { echo "ERROR: $bundle is not a directory" >&2; exit 2; }

# Forwarded so this gate certifies the policy under the SAME spec resolution as
# the run it gates.
spec=()
if [ "${1:-}" = "--spec" ]; then
  [ -n "${2:-}" ] || { echo "ERROR: --spec needs a value" >&2; exit 2; }
  spec=(--spec "$2"); shift 2
fi

# python3 rather than jq, for the reason dev:verify-pins states in Taskfile.yml.
command -v python3 >/dev/null 2>&1 || {
  echo "ERROR: python3 required by $0" >&2; exit 2; }

err="$(mktemp)"; raw="$(mktemp)"
trap 'rm -f "$err" "$raw"' EXIT

st=0
openknowledge validate "${spec[@]}" --format json "$bundle" >"$raw" 2>"$err" || st=$?
# Exit 1 means findings, which is a verdict about content and not our concern.
# Anything higher means the run itself failed.
if [ "$st" -gt 1 ]; then
  echo "FAIL: openknowledge could not run (exit $st). Its own report:"
  cat "$err"
  # The CLI's own wording for an unquoted rule key names neither the key nor the
  # fix, and the whole file is lost rather than the one rule.
  if grep -q "unhandled kv part" "$err"; then
    echo "HINT: a rule key containing a dot must be quoted in the config —"
    echo "      \"okf-0.2-metadata\" = \"error\", not okf-0.2-metadata = \"error\"."
    echo "      Unquoted it parses as a TOML dotted key and every rule in the"
    echo "      file is dropped, not just that one."
  fi
  exit 2
fi

python3 - "$raw" "$bundle" "$@" <<'PY'
import json, os, sys

raw, bundle, *wanted = sys.argv[1:]
expected = os.path.realpath(os.path.join(bundle, ".openknowledge.toml"))

try:
    with open(raw) as fh:
        policy = json.load(fh).get("policy") or {}
except (OSError, ValueError) as exc:
    print(f"FAIL: openknowledge --format json produced no parseable output ({exc}).")
    sys.exit(1)

# Compare the VALUE, not the key's presence: a config resolved from elsewhere
# (a user-level file) must not satisfy the check.
found = policy.get("configPath")
if not found or os.path.realpath(found) != expected:
    print(f"FAIL: {expected} is not the config in effect (in effect: {found!r}).")
    print("      Every raise has degraded to the spec default, so this gate")
    print("      checks nothing. See that file's header for the discovery rules.")
    sys.exit(1)

overrides = policy.get("overrides") or {}
missing = [w for w in wanted if overrides.get(w.split("=", 1)[0]) != w.split("=", 1)[1]]
if missing:
    print(f"FAIL: raised rules not in effect: {', '.join(missing)}.")
    print(f"      Policy actually in effect: {overrides}")
    sys.exit(1)

# Parity, the other direction: the caller must demand everything the config
# raises.
asked = {w.split("=", 1)[0] for w in wanted}
unasked = sorted(r for r, sev in overrides.items() if sev == "error" and r not in asked)
if unasked:
    print(f"FAIL: the config raises rules the caller does not demand: {', '.join(unasked)}.")
    print("      Add them to the argument list, or lower them in the config —")
    print("      a raise nothing asserts is a raise nothing keeps.")
    sys.exit(1)
PY
