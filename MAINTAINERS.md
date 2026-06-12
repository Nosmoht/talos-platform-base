# Maintainers

This file lists the people authorised to merge and approve releases for
`talos-platform-base`. Maintainer set is intentionally small for a
single-owner platform base.

Releases are tagged and published automatically by semantic-release from
the conventional-commit history; a maintainer's role is to **approve the
release** in the `release` GitHub Environment (the gate before anything is
signed and `:latest` advances). The manual hand-tag path remains as the
fallback. See [`docs/release-automation.md`](docs/release-automation.md).

## Active maintainers

| Name | GitHub | Areas of responsibility |
|---|---|---|
| Thomas Krahn | [@nosmoht](https://github.com/nosmoht) | All — repo owner, OCI publisher, ADR maintainer |

## Emeritus maintainers

_None._

## Decision authority

- **Hard-constraint changes** (AGENTS.md §Hard Constraints): owner only,
  requires ADR.
- **PNI vocabulary changes** (reserved labels, registry schema): owner
  only, requires ADR.
- **New base components**: owner approval + green CI.
- **Documentation**: any approved contributor with green CI.

## Routing

For PR routing per path, see [`CODEOWNERS`](CODEOWNERS).

## How to reach a maintainer

- Open a GitHub issue (preferred — public record).
- For security: see [`SECURITY.md`](SECURITY.md) — private channel.
