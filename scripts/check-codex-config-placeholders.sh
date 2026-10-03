#!/bin/bash

set -euo pipefail

CONFIG="${1:-.codex/config.toml}"

if [ ! -f "$CONFIG" ]; then
  echo "check-codex-config-placeholders: $CONFIG not found, skipping."
  exit 0
fi

FAIL=0

while IFS= read -r line; do
  [[ "$line" =~ ^[[:space:]]*# ]] && continue
  [[ -z "${line// /}" ]] && continue

  while IFS= read -r kv; do
    value=$(echo "$kv" | sed -n 's/^[^=]*=[[:space:]]*"\([^"]*\)".*/\1/p')
    [ -z "$value" ] && continue

    if [[ "$value" != \$\{* ]]; then
      echo "ERROR: Literal value found in $CONFIG env block: $kv" >&2
      echo "       Replace with a \${ENV_VAR} placeholder to avoid committing secrets." >&2
      FAIL=1
    fi
  done < <(echo "$line" | grep -oE '[A-Za-z_][A-Za-z0-9_-]*[[:space:]]*=[[:space:]]*"[^"]*"' || true)

done < "$CONFIG"

if [ "$FAIL" -ne 0 ]; then
  echo "check-codex-config-placeholders: FAILED — literal tokens detected in $CONFIG" >&2
  exit 1
fi

echo "check-codex-config-placeholders: OK — all env values use \${VAR} placeholders"
exit 0
