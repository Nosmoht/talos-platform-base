## 1. The workflow

- [x] 1.1 Address the release by the `html_url` `gh release create` printed, via a `find_created()` beside the tag-scoped `find_releases()`.
- [x] 1.2 Retry that lookup when it reports nothing or cannot be read, bounded at five attempts with a 2s backoff.
- [x] 1.3 Keep the published-release refusal and the second-draft refusal on FIRST sight, the latter with the wording the recovery table is keyed to.
- [x] 1.4 Fail when `gh release create` printed no url, rather than publishing something unidentified.

## 2. Bindings

- [x] 2.1 Add `LIST_LAG`, `LIST_FAIL`, a recorded `sleep` and a printed create url to the stub in `scripts/check-release-step-bites.sh`; the lag hides only this run's own release.
- [x] 2.2 Scenarios: lag retried through to publish, retry bounded, listing error retried, published release refused without sleeping, foreign draft never published, second draft refused by name.
- [x] 2.3 Assert the PATCH targets the created release id, and that the backoff actually ran.
- [x] 2.4 Raise the anti-narrowing floor from 25 to 47 so the new coverage cannot be deleted silently.
- [x] 2.5 Mutation-test each guard: tag lookup instead of `html_url`, deleted backoff, dropped second-draft stop — each reds a named scenario.

## 3. Record

- [x] 3.1 `oci-supply-chain`: the requirement states the identity rule, what is retried and what is terminal, plus both scenarios.
- [x] 3.2 `knowledge/workflows/release-process.md`: the `v14.0.0` note records the defect as fixed.
