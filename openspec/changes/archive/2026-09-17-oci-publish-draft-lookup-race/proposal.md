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

The window is real and short. A probe against this repository's own API
created a draft release, read it back by id, and the listing did not report it;
the `v14.0.0` run's own log puts its failing listing under 0.6s after the
create returned. Five attempts with a 2s backoff is sized against that, not
guessed — it is the first sample, at the moment of maximum lag probability,
that the old code had nothing after.

## What Changes

- The step addresses the release it publishes by the `html_url`
  `gh release create` printed for it, never by tag. A draft's url carries a
  per-release `untagged-<hash>` slug, so it names one release object where the
  tag names a set — and a set is what lets an inconsistent listing hand back
  somebody else's draft. This closes a pre-existing hole the retry would
  otherwise have widened: with a tag lookup, a sample showing a FOREIGN draft
  while this run's own had not landed yet would publish that foreign draft,
  immutably, under the repository's release identity, and exit 0.
- That lookup is retried when it reports nothing, bounded at five attempts with
  a 2s backoff, and retried when the listing cannot be read at all — a 5xx from
  a degraded replica leaves the identical half-released tag.
- A published release for the tag, and a SECOND draft beside ours, each still
  fail on FIRST sight. Re-sampling a set is what makes those hard stops
  load-bearing rather than tidy, and the second-draft refusal keeps the wording
  the recovery table's row is keyed to.
- `scripts/check-release-step-bites.sh` gains `LIST_LAG` and `LIST_FAIL` stub
  knobs, a recorded `sleep`, and six scenarios. The stub's lag hides only THIS
  run's release, so "a foreign draft is visible while ours is not" — the state
  that decides the whole design — is expressible.

## Rejected: reading the id from a `gh api --method POST` create

An id-based create would bind the release more directly, but it also moves the
ASSET UPLOAD off `gh release create` onto hand-rolled requests to
`uploads.github.com` — the one part of this step that has never failed, onto a
mechanism no offline harness can exercise. Getting that wrong ships a published,
immutable, asset-less release: the #251 class this suite exists to prevent. The
`html_url` returned by `gh release create` binds the release just as precisely
at no such cost.

## Impact

- Affected specs: `oci-supply-chain`.
- No consumer-visible interface change; no version bump implied. The workflow
  reaches the end state it always intended to reach, on a read timing it
  previously mistook for a missing release.
- The fix is merge-blocking-gated: the bite-check runs in `docs-lint`, which is
  a required status context and carries no path filter.
