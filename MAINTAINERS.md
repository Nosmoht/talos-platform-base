# Maintainers

This file lists the people authorised to merge, tag, and publish OCI
artifacts for `talos-platform-base`. Maintainer set is intentionally
small for a single-owner platform base.

## Active maintainers

| Name | GitHub | Areas of responsibility |
|---|---|---|
| Thomas Krahn | [@nosmoht](https://github.com/nosmoht) | All — repo owner, OCI publisher, ADR steward |

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
