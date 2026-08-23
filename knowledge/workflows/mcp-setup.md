---
type: workflow
title: MCP Setup
description: Installing and verifying the three MCP servers, and the wrapper security model that keeps the GitHub token out of shell environments.
tags: [mcp, tooling, security]
timestamp: 2026-07-11
sources:
  - resource: Taskfile.yml
  - resource: scripts/mcp-github-wrapper.sh
  - resource: .mcp.json
  - resource: scripts/check-mcp-config-portable.sh
---

# MCP Setup

Three MCP servers back agent sessions in this repo: `github`,
`kubernetes-mcp-server`, and `talos`. All are referenced by **bare
PATH-resolved command names** in `.mcp.json`; installation and verification
are owned by the `mcp:*` tasks in `Taskfile.yml`.

## Pinned versions

`Taskfile.yml` pins the server versions as vars:

| Var | Version | Binary |
| --- | --- | --- |
| `MCP_GITHUB_VERSION` | 0.33.0 | `github-mcp-server` |
| `MCP_K8S_VERSION` | 0.0.60 | `kubernetes-mcp-server` |
| `MCP_TALOS_VERSION` | 1.1.0 | `talos-mcp` (npm) |

## `task mcp:install`

Per-OS install (requires `gh`, the GitHub CLI, up front):

- **macOS** (requires `brew` and `npm`): `brew install github-mcp-server@<pin>`
  and `kubernetes-mcp-server@<pin>` — each falls
  back to the unpinned formula if the versioned one is unavailable — plus
  `npm install -g talos-mcp@<pin>`.
- **Linux** (requires `go` and `npm`): `go install
  github.com/github/github-mcp-server/cmd/github-mcp-server@v<pin>`, then
  `npm install -g kubernetes-mcp-server@<pin>` and `talos-mcp@<pin>`.

It then registers the wrapper: a symlink `$HOME/.local/bin/mcp-github-wrapper`
pointing at `scripts/mcp-github-wrapper.sh` in the repo checkout (and marks
the script executable). Printed next steps: ensure `$HOME/.local/bin` is on
`PATH`, run `gh auth login` if needed, run `task mcp:verify`, restart the
agent CLI.

## `task mcp:verify`

Checks that all five commands resolve on `PATH` — `gh`,
`github-mcp-server`, `kubernetes-mcp-server`, `talos-mcp`,
`mcp-github-wrapper` — and that `gh auth token` succeeds (keychain
accessible). Any failure prints a fix hint and exits `1`.

`task mcp:uninstall` removes only the wrapper symlink; installed binaries
stay in place.

## GitHub token security model — `scripts/mcp-github-wrapper.sh`

The wrapper exists so no GitHub token is ever stored in config or exported
into a shell:

- At spawn time it fetches the token via `gh auth token` (backed by the macOS
  Keychain / Linux libsecret credential store).
- It **fails loudly** when `gh` or `github-mcp-server` is missing, when
  `gh auth token` fails, or when the token comes back empty — preventing a
  silent anonymous-auth fallback.
- The token is injected **only into the child process**:
  `exec env GITHUB_PERSONAL_ACCESS_TOKEN="$TOKEN" "$GITHUB_MCP_BIN" stdio`.
  It is never `export`ed into the wrapper shell, so the exposure surface is
  the child's environ block only (readable by same-UID processes — accepted
  for the MCP-launch boundary).
- `GH_BIN` and `GITHUB_MCP_BIN` environment overrides let tests or
  non-standard installs point at specific binaries.

## `.mcp.json` server entries

```json
{
  "mcpServers": {
    "github": { "type": "stdio", "command": "mcp-github-wrapper", "args": [] },
    "kubernetes-mcp-server": {
      "type": "stdio",
      "command": "kubernetes-mcp-server",
      "args": ["--read-only", "--disable-multi-cluster"]
    },
    "talos": {
      "type": "stdio",
      "command": "talos-mcp",
      "args": [],
      "env": {
        "TALOS_CONTEXT": "cluster",
        "TALOS_MCP_ALLOWED_PATHS": "/proc,/sys,/var/log,/run,/usr/local/etc,/etc/os-release"
      }
    }
  }
}
```

Notable per-server settings:

- **kubernetes-mcp-server** runs with `--read-only` and
  `--disable-multi-cluster` — the agent gets observation, not mutation, and
  only the current kubecontext.
- **talos** (`talos-mcp`) is scoped by `TALOS_CONTEXT` (the talosconfig
  context name) and `TALOS_MCP_ALLOWED_PATHS`, an allowlist of node
  filesystem paths the server may read.

## Portability guard

A pre-commit hook (`check-mcp-config-portable` in `.pre-commit-config.yaml`,
implemented by `scripts/check-mcp-config-portable.sh`) blocks commits whose
`command` values in `.mcp.json` or `.codex/config.toml` are not bare PATH
identifiers — no absolute paths, `~`, `$VAR` expansions, or leading dots.
This keeps the config machine-independent: the machine-specific part lives
solely in the PATH symlink that `task mcp:install` creates.

## Related

- Session-start backlog scan that uses the `github` server:
  [issue-lifecycle](issue-lifecycle.md).
- Full runner target list: [tasks reference](../reference/tasks.md).
