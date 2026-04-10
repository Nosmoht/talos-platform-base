#!/bin/sh
# MCP GitHub server wrapper — pulls auth token from macOS keychain via gh CLI.
# Called by Claude Code .mcp.json (and optionally Codex .codex/config.toml).
# Fails loudly on missing/empty token — prevents silent anonymous auth fallback.
set -eu

GH_BIN="${GH_BIN:-/opt/homebrew/bin/gh}"
GITHUB_MCP_BIN="${GITHUB_MCP_BIN:-/opt/homebrew/bin/github-mcp-server}"

if [ ! -x "$GH_BIN" ]; then
  echo "mcp-github-wrapper: $GH_BIN not found or not executable" >&2
  exit 1
fi
if [ ! -x "$GITHUB_MCP_BIN" ]; then
  echo "mcp-github-wrapper: $GITHUB_MCP_BIN not found or not executable" >&2
  exit 1
fi

TOKEN=$("$GH_BIN" auth token 2>/dev/null) || {
  echo "mcp-github-wrapper: 'gh auth token' failed — run 'gh auth login'" >&2
  exit 1
}
if [ -z "$TOKEN" ]; then
  echo "mcp-github-wrapper: 'gh auth token' returned empty — keychain unlock required?" >&2
  exit 1
fi

export GITHUB_PERSONAL_ACCESS_TOKEN="$TOKEN"
exec "$GITHUB_MCP_BIN" stdio
