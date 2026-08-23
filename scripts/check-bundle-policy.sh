#!/usr/bin/env bash
# Assert that an OKF bundle's `.openknowledge.toml` is actually IN EFFECT.
#
# `openknowledge validate` exits 0 with an empty policy when it cannot find a
# config, so every severity raise degrades back to the spec default and the
# gate reports green while checking nothing. That is how the pre-0.10 config
# filename went unnoticed here for seven minor releases. This script is the
# mechanical detector; scripts/check-knowledge-gate-bite.sh proves it bites.
#
# Usage: check-bundle-policy.sh <bundle-dir> <rule=severity>...
# Exit 0 = the bundle's own config is loaded and every named rule is at the
# named severity. Exit 1 = it is not, with the cause on stdout. Exit 2 =
# openknowledge could not run; its own stderr is reproduced verbatim, because
# it is the only statement of the actual cause (a TOML syntax error and an
# unknown rule name both land here, and neither is a discovery problem).

set -euo pipefail

# Runnable directly, so the Taskfile env: block does not cover it, and that
# block loses to an inherited value. Unconditional for the reason
# scripts/verify-tools.sh states. Reason for the opt-out: Taskfile.yml env:.
export OPENKNOWLEDGE_TELEMETRY=off

bundle="${1:?usage: check-bundle-policy.sh <bundle-dir> <rule=severity>...}"
shift
[ -d "$bundle" ] || { echo "ERROR: $bundle is not a directory" >&2; exit 2; }

# python3 rather than jq, for the reason dev:verify-pins states in Taskfile.yml.
command -v python3 >/dev/null 2>&1 || {
  echo "ERROR: python3 required by $0" >&2; exit 2; }

err="$(mktemp)"; raw="$(mktemp)"
trap 'rm -f "$err" "$raw"' EXIT

st=0
openknowledge validate --format json "$bundle" >"$raw" 2>"$err" || st=$?
# Exit 1 means findings, which is a verdict about content and not our concern.
# Anything higher means the run itself failed.
if [ "$st" -gt 1 ]; then
  echo "FAIL: openknowledge could not run (exit $st). Its own report:"
  cat "$err"
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

# The key is absent, not null, when discovery fails -- but compare the VALUE so
# a null, an empty string, or a config resolved from somewhere else (a
# user-level file) cannot satisfy the check. The message names what was found.
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
PY
