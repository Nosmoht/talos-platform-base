## 1. The workflow

- [x] 1.1 Retry the post-create draft lookup in `.github/workflows/oci-publish.yml`, bounded at five attempts, keeping both guards.
- [x] 1.2 Keep the published-release refusal on the first sight of one, inside the retry loop.

## 2. Bindings

- [x] 2.1 Add the `LIST_LAG` knob and a no-op `sleep` stub to `scripts/check-release-step-bites.sh`.
- [x] 2.2 Add the lag-is-retried, retry-is-bounded, and published-release-still-refused scenarios.
- [x] 2.3 Red-green: reverting the workflow hunk reds the lag scenario and the suite.

## 3. Record

- [x] 3.1 `oci-supply-chain`: the GitHub Release mirror requirement states the lookup guarantee and gains its scenario.
- [x] 3.2 `knowledge/workflows/release-process.md`: the `v14.0.0` note records the defect as fixed rather than open.
