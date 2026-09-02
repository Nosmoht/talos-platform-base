## Context

The Helm provider can verify provenance files but has no input for a declared
SHA-256. Cilium publishes no provenance file, so the module must inspect the
archive before handing it to the existing Helm render.

## Decision

Use a small module-shipped downloader through `hashicorp/external`. It writes to
the caller's `.terraform` cache, verifies the base digest, and returns success
only after the exact file exists. The Helm data sources then render that local
archive. Do not package public chart archives or introduce a private registry.

An unpinned version is refused. The Cilium repository override remains because
an air-gap mirror can serve the same bytes and pass the same digest.

## Trade-offs

- Apply hosts gain `curl` and SHA-256 command requirements.
- A first plan needs access to the selected public repository or mirror; later
  plans verify the cached file without downloading it again.
- Container image tags and the optional Day-2 Cilium Application remain outside
  this chart-archive check.
