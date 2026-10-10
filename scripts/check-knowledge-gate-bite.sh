#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
gate="$repo_root/scripts/check-bundle-policy.sh"
[ -x "$gate" ] || { echo "ERROR: $gate missing or not executable" >&2; exit 2; }
command -v openknowledge >/dev/null 2>&1 || {
  echo "ERROR: openknowledge not installed -- run 'mise install'" >&2; exit 2; }
export OPENKNOWLEDGE_TELEMETRY=off

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fails=0

build() {
  local root="$1"
  rm -rf "$root"; mkdir -p "$root/kb"
  printf -- '---\nokf_version: "0.2"\n---\n\n# Probe\n\n- [Alpha](alpha.md) - probe concept.\n' >"$root/kb/index.md"
  printf -- '---\ntype: reference\ntitle: Alpha\ndescription: Probe concept.\n---\n\n# Alpha\n\nbody\n' >"$root/kb/alpha.md"
}
config() { printf '[validation.rules]\nlink-target = "error"\nrule-catalog = "error"\n' >"$1"; }

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

build "$tmp/case"; config "$tmp/case/kb/.openknowledge.toml"
scenario "config in the bundle, both raises present" pass

build "$tmp/case"
scenario "no config anywhere" fail "is not the config in effect"

build "$tmp/case"; config "$tmp/case/kb/openknowledge.toml"
scenario "legacy non-dotfile filename" fail "is not the config in effect"

build "$tmp/case"; config "$tmp/case/.openknowledge.toml"
scenario "dotfile outside the bundle" fail "is not the config in effect"

build "$tmp/case"
printf '[validation.rules]\nlink-target = "error"\nrule-catalog = "warn"\n' >"$tmp/case/kb/.openknowledge.toml"
scenario "a required raise lowered to warn" fail "rule-catalog=error"

build "$tmp/case"
printf '[validation.rules]\nlink-target = "error"\nrule-catalog = "error"\nbogus-rule = "error"\n' >"$tmp/case/kb/.openknowledge.toml"
scenario "unparseable config is reported as itself" fail "openknowledge could not run"

build "$tmp/case"
printf '[validation.rules]\nlink-target = "error"\nrule-catalog = "error"\nokf-0.2-metadata = "error"\n' >"$tmp/case/kb/.openknowledge.toml"
scenario "an unquoted dotted rule key is named as such" fail "must be quoted"

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
echo "OK: the policy gate and the telemetry opt-out bite in all $((8)) scenarios."
