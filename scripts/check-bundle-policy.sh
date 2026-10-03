#!/usr/bin/env bash
# An absent config can produce a successful validation with no policy loaded.
# Usage: check-bundle-policy.sh <bundle-dir> <rule=severity>...

set -euo pipefail

export OPENKNOWLEDGE_TELEMETRY=off

bundle="${1:?usage: check-bundle-policy.sh <bundle-dir> [--spec <v>] <rule=severity>...}"
shift
[ -d "$bundle" ] || { echo "ERROR: $bundle is not a directory" >&2; exit 2; }

spec=()
if [ "${1:-}" = "--spec" ]; then
  [ -n "${2:-}" ] || { echo "ERROR: --spec needs a value" >&2; exit 2; }
  spec=(--spec "$2"); shift 2
fi

command -v python3 >/dev/null 2>&1 || {
  echo "ERROR: python3 required by $0" >&2; exit 2; }

err="$(mktemp)"; raw="$(mktemp)"
trap 'rm -f "$err" "$raw"' EXIT

st=0
openknowledge validate "${spec[@]}" --format json "$bundle" >"$raw" 2>"$err" || st=$?
# Exit 1 reports content findings; this check only verifies policy loading.
if [ "$st" -gt 1 ]; then
  echo "FAIL: openknowledge could not run (exit $st). Its own report:"
  cat "$err"
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
