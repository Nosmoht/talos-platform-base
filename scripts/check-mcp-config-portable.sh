#!/bin/sh
set -eu

fail=0

check_file() {
  file="$1"
  [ -f "$file" ] || return 0
  awk '
    BEGIN { rc = 0 }
    # JSON: "command": "value"
    /"command"[[:space:]]*:[[:space:]]*"[^"]*"/ {
      val = $0
      sub(/.*"command"[[:space:]]*:[[:space:]]*"/, "", val)
      sub(/".*/, "", val)
      if (val == "" || val ~ /[\/~\\]/ || val ~ /^\$/ || val ~ /^\./) {
        printf "BLOCK %s:%d: %s — non-portable command (must be bare PATH identifier)\n", FILENAME, NR, val > "/dev/stderr"
        rc = 1
      }
    }
    # TOML: command = "value"
    /^[[:space:]]*command[[:space:]]*=[[:space:]]*"[^"]*"/ {
      val = $0
      sub(/.*command[[:space:]]*=[[:space:]]*"/, "", val)
      sub(/".*/, "", val)
      if (val == "" || val ~ /[\/~\\]/ || val ~ /^\$/ || val ~ /^\./) {
        printf "BLOCK %s:%d: %s — non-portable command (must be bare PATH identifier)\n", FILENAME, NR, val > "/dev/stderr"
        rc = 1
      }
    }
    END { exit rc }
  ' "$file" || return 1
}

check_file ".mcp.json" || fail=1
check_file ".codex/config.toml" || fail=1

if [ "$fail" -ne 0 ]; then
  printf "\nMCP config portability check FAILED.\n" >&2
  printf "Commands must be bare PATH identifiers (e.g. 'mcp-github-wrapper', not '/opt/homebrew/bin/...').\n" >&2
  printf "Run 'task mcp:install' to install binaries and the wrapper symlink.\n" >&2
fi

exit "$fail"
