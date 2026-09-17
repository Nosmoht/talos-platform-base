## Why

`v14.0.0` shipped half-released. The publish job pushed the OCI artifact,
signed it, attached SLSA provenance and the CycloneDX SBOM and moved `:latest`
— and then failed on its last step, because the release listing it queried did
not yet report the draft the same step had just created.

The id was derived by searching for it. `gh release create` returns before
`GET /repos/{repo}/releases` is consistent with it, and the step treated
"not there yet" and "not there" as the same fact. Everything the run existed to
produce was already in place; only the `draft=false` flip never happened.

The cost of that conflation is asymmetric. The documented recovery for a
half-released tag is a workflow re-run, which is explicitly non-idempotent: it
pushes a new digest, remaps the tag, mints a second signature and a second
provenance, and moves `:latest` again, so every consumer who pinned the digest
must re-pin for a release whose content never changed.

## What Changes

- The post-create draft lookup in `.github/workflows/oci-publish.yml` retries a
  listing that does not yet report the draft, bounded at five attempts.
- Only ABSENCE is retried. A published release for the tag still fails on first
  sight: that is a real interleaving, and waiting cannot improve it.
- Both existing guards are preserved — the published-release refusal and the
  exactly-one-draft requirement — and the bounded exhaustion still fails
  without publishing anything.
- `scripts/check-release-step-bites.sh` gains a `LIST_LAG` stub knob and three
  scenarios: the lagging listing is retried through to a published release, an
  unbounded lag exhausts the retry without publishing, and a release published
  mid-run is refused even while the listing lags.

## Impact

- Affected specs: `oci-supply-chain`.
- No consumer-visible interface change; no version bump implied. The workflow
  reaches the end state it always intended to reach, on a read timing it
  previously mistook for a missing release.
- The fix is merge-blocking-gated: the bite-check runs in `docs-lint`, which is
  a required status context and carries no path filter.
