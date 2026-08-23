#!/usr/bin/env bash
# Bite-check for the bundle-policy gate (scripts/check-bundle-policy.sh).
#
# The gate exists because a config the CLI cannot find produces exit 0 and an
# empty policy -- silence, not an error. A detector for a silent failure is
# itself worth nothing unless something proves it still discriminates, so each
# scenario below builds a throwaway bundle, puts the config somewhere, and
# asserts the VERDICT LINE rather than the exit code alone: exit 1 is emitted
# for a real miss and for an uncaught Python traceback, and those must not read
# alike.
#
# The green scenario is not decoration. A checker that fails on everything
# passes every red case, so the conforming input is what separates a working
# detector from a broken one.
#
# Scenario 7 checks a second silent failure with the same shape: the telemetry
# opt-out. It is an env var, so a release that renames or stops honouring it
# produces no error and no exit-code change -- egress simply resumes. The
# scenario is two-sided, because a one-sided assertion passes on a probe that
# could never have detected a write.
#
# Runs offline, mutates nothing outside its temp dir. Exit 0 = every scenario
# behaved, 1 = the gate regressed, 2 = environment error.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
gate="$repo_root/scripts/check-bundle-policy.sh"
[ -x "$gate" ] || { echo "ERROR: $gate missing or not executable" >&2; exit 2; }
command -v openknowledge >/dev/null 2>&1 || {
  echo "ERROR: openknowledge not installed -- run 'task knowledge:install-cli'" >&2; exit 2; }
# Scenario 7 sets this per-run; this covers the rest. Reason: Taskfile.yml env:.
export OPENKNOWLEDGE_TELEMETRY=off

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fails=0

# A minimal conforming bundle: one index, one concept, no findings of its own,
# so every verdict below is about policy discovery and nothing else.
build() {
  local root="$1"
  rm -rf "$root"; mkdir -p "$root/kb"
  printf -- '---\nokf_version: "0.2"\n---\n\n# Probe\n\n- [Alpha](alpha.md) - probe concept.\n' >"$root/kb/index.md"
  printf -- '---\ntype: reference\ntitle: Alpha\ndescription: Probe concept.\n---\n\n# Alpha\n\nbody\n' >"$root/kb/alpha.md"
}
config() { printf '[validation.rules]\nlink-target = "error"\nrule-catalog = "error"\n' >"$1"; }

# scenario <name> <expect: pass|fail> <substring the verdict must contain>
scenario() {
  local name="$1" expect="$2" needle="${3:-}" out st=0
  out="$("$gate" "$tmp/case/kb" link-target=error rule-catalog=error 2>&1)" || st=$?
  if [ "$expect" = pass ]; then
    if [ "$st" -ne 0 ]; then
      echo "FAIL: $name -- expected the gate to pass, it exited $st:"; printf '%s\n' "$out"; fails=1
    else
      echo "PASS: $name"
    fi
    return
  fi
  if [ "$st" -eq 0 ]; then
    echo "FAIL: $name -- the gate passed; it cannot detect this state"; fails=1
  elif ! printf '%s\n' "$out" | grep -qF -- "$needle"; then
    echo "FAIL: $name -- exited $st but without the expected verdict '$needle':"
    printf '%s\n' "$out"; fails=1
  else
    echo "PASS: $name"
  fi
}

# 1. Conforming input. Guards against a checker that is red on everything.
build "$tmp/case"; config "$tmp/case/kb/.openknowledge.toml"
scenario "config in the bundle, both raises present" pass

# 2. No config at all -- the shape that exits 0 with an empty policy.
build "$tmp/case"
scenario "no config anywhere" fail "is not the config in effect"

# 3. The pre-0.10 filename. This is the exact state that shipped in this repo.
build "$tmp/case"; config "$tmp/case/kb/openknowledge.toml"
scenario "legacy non-dotfile filename" fail "is not the config in effect"

# 4. Dotfile one level up. Right name, wrong place; also the shape a
#    user-level or ambient config would take.
build "$tmp/case"; config "$tmp/case/.openknowledge.toml"
scenario "dotfile outside the bundle" fail "is not the config in effect"

# 5. Config found, but a raise silently lowered. Discovery alone is not the
#    invariant -- the severities are.
build "$tmp/case"
printf '[validation.rules]\nlink-target = "error"\nrule-catalog = "warn"\n' >"$tmp/case/kb/.openknowledge.toml"
scenario "a required raise lowered to warn" fail "rule-catalog=error"

# 6. The CLI itself cannot run. Must be reported as its own cause, not
#    misdiagnosed as a discovery problem -- an unknown rule name is rejected at
#    config-parse time (measured against 0.12.0: exit 2, no JSON at all).
build "$tmp/case"
printf '[validation.rules]\nlink-target = "error"\nrule-catalog = "error"\nbogus-rule = "error"\n' >"$tmp/case/kb/.openknowledge.toml"
scenario "unparseable config is reported as itself" fail "openknowledge could not run"

# 7. The telemetry opt-out is still honoured by THIS binary. Control first: with
#    the variable empty the CLI must write its telemetry config, or the probe
#    proves nothing. Then the assertion. Both runs are pointed at a temp path so
#    neither touches the operator's real telemetry state.
#
#    Both halves drop CI from the environment. Measured: a truthy CI suppresses
#    the write on its own, which would make the control fail on a runner and the
#    assertion pass there for the wrong reason. This scenario is about the
#    variable and must not measure the runner.
probe="$tmp/telemetry.json"
telemetry_probe() {
  rm -f "$probe"
  env -u CI "OPENKNOWLEDGE_TELEMETRY=$1" "OPENKNOWLEDGE_TELEMETRY_CONFIG=$probe" \
    openknowledge version >/dev/null 2>&1 || true
  [ -e "$probe" ]
}
if ! telemetry_probe ''; then
  echo "FAIL: telemetry control -- an empty opt-out wrote no config, so the probe cannot detect one"
  fails=1
elif telemetry_probe off; then
  echo "FAIL: OPENKNOWLEDGE_TELEMETRY=off no longer suppresses telemetry -- this binary reads it as enabled"
  fails=1
else
  echo "PASS: the telemetry opt-out is honoured (control wrote a config, off did not)"
fi
rm -f "$probe"

[ "$fails" -eq 0 ] || { echo "check-knowledge-gate-bite: a silent-failure detector regressed"; exit 1; }
echo "OK: the policy gate and the telemetry opt-out bite in all $((7)) scenarios."
