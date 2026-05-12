# OCI Artifact Verification

This document describes how downstream consumer cluster repos verify
the integrity and provenance of `ghcr.io/<OWNER>/talos-platform-base`
OCI artifacts before vendoring them into `vendor/base/`.

## Trust chain

Each release (`v0.1.1` and later) is:

1. Built and pushed via `.github/workflows/oci-publish.yml`
2. **Signed by cosign with keyless GitHub OIDC** — no long-lived keys,
   no secret rotation. The signer identity is the workflow's GitHub
   OIDC token, which encodes the workflow file, the repository, and
   the tag pattern.
3. **Accompanied by SLSA build provenance** via
   `actions/attest-build-provenance@v1` — proves the artifact was
   built by this workflow run, in this repository, at this commit.
4. **Pushed under an immutable tag** (GHCR tag-immutability policy
   prevents overwrite).

A consumer who verifies cosign + provenance and reads the immutable
content has a cryptographic chain back to this repository's commit
at the time of release.

## Verifying with cosign

### Released tags (`v0.1.1`, `v0.2.0`, …)

Substitute `OWNER` with the GitHub owner of this repository (the
literal token `OWNER` appears in the snippet below — replace before
use):

```bash
cosign verify \
  --certificate-identity-regexp \
    '^https://github.com/OWNER/talos-platform-base/\.github/workflows/oci-publish\.yml@refs/tags/v[0-9]+\.[0-9]+\.[0-9]+$' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  ghcr.io/OWNER/talos-platform-base:<TAG>
```

### Pre-release tags (`v0.1.1-rc1`, `v0.2.0-alpha.1`, …)

```bash
cosign verify \
  --certificate-identity-regexp \
    '^https://github.com/OWNER/talos-platform-base/\.github/workflows/oci-publish\.yml@refs/tags/v[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  ghcr.io/OWNER/talos-platform-base:<TAG>
```

The two identity regexes differ only in whether the trailing
`-<prerelease>` suffix is permitted. The released-tag regex is the
stricter form — use it for production consumers; use the pre-release
regex only for explicit testing of RC artifacts.

The identity regex is bound to:

- The repository (`OWNER/talos-platform-base`)
- The workflow file (`.github/workflows/oci-publish.yml`)
- The tag pattern (`refs/tags/v…`)

This means a malicious workflow run *inside this repository* using a
different workflow file cannot produce a signature accepted by this
regex. On repository rename or transfer, both regexes must be updated
and downstream consumers notified via CHANGELOG.

## Verifying SLSA provenance with the GitHub CLI

```bash
gh attestation verify \
  oci://ghcr.io/OWNER/talos-platform-base@<DIGEST> \
  --owner OWNER
```

`<DIGEST>` is the `sha256:…` value returned by:

```bash
oras manifest fetch --descriptor \
  ghcr.io/OWNER/talos-platform-base:<TAG> | jq -r .digest
```

## Full end-to-end consumer verification

```bash
TAG=v0.1.1
OWNER=Nosmoht   # adjust if the repo is renamed

# 1. Pull and verify signature
cosign verify \
  --certificate-identity-regexp \
    "^https://github.com/${OWNER}/talos-platform-base/\\.github/workflows/oci-publish\\.yml@refs/tags/v[0-9]+\\.[0-9]+\\.[0-9]+$" \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  "ghcr.io/${OWNER}/talos-platform-base:${TAG}"

# 2. Capture digest and verify SLSA provenance
DIGEST=$(oras manifest fetch --descriptor \
  "ghcr.io/${OWNER}/talos-platform-base:${TAG}" | jq -r .digest)
gh attestation verify \
  "oci://ghcr.io/${OWNER}/talos-platform-base@${DIGEST}" \
  --owner "${OWNER}"

# 3. Pull the artifact
oras pull "ghcr.io/${OWNER}/talos-platform-base:${TAG}"

# 4. Verify the in-tarball checksums
sha256sum -c checksums.txt
```

All four steps must succeed. If any step fails, the artifact MUST NOT
be vendored into a consumer cluster's `vendor/base/` directory.

## Placeholder substitution

The literal token `OWNER` in this document is a placeholder. The
CHANGELOG entry for each release includes a fully-rendered version of
the verify command with `OWNER` substituted to the actual owner at
release time, so users copy-pasting from CHANGELOG get a working
command without manual substitution.

## Operational requirements (release-side)

Documented in `Plans/` — operational gates verified by the `Preflight`
workflow:

- GHCR tag immutability enabled on `talos-platform-base` package
- GitHub Actions allowlist (when used) permits
  `sigstore/cosign-installer@*` and `actions/attest-build-provenance@*`
- Branch protection includes `Preflight / preflight` as a required
  status check
