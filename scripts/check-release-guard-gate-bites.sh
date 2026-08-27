#!/usr/bin/env bash
# check-release-guard-gate-bites.sh — proves the release guard actually bites.
#
# Three disciplines every scenario here has to keep (the same three
# scripts/check-staleness-gate-bite.sh records):
#
#   1. Assert the git state the scenario claims to have built BEFORE reading a
#      verdict, so it cannot pass because its setup silently failed.
#   2. Assert the VERDICT LINE, not just the exit code: the guard emits exit 0 on
#      three different verdicts and exit 2 on a crash, so an exit code alone
#      cannot tell "blocked" from "died after printing the list".
#   3. Cover BOTH directions of a rule. A red case alone is satisfied by an
#      implementation that is wrong the other way -- an over-broad pathspec
#      passes every red scenario in this file.
#
# THE INTEGRITY-LOCK CHECK COMES FIRST, because the scenarios below are generated
# from the guard's own data files: deleting an entry would delete its scenario
# and the suite would stay green. The real external anchor is
# scripts/check-release-guard-coverage.sh, exercised here too since it is
# otherwise an untested oracle.
#
# Runs offline, mutates nothing outside its temp dir.
# Exit 0 = all scenarios behaved, 1 = the guard regressed, 2 = environment error.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

rc=0
scenarios=0
note() { printf 'FAIL: %s\n' "$*" >&2; rc=1; }

# ---------------------------------------------------------------------------
# 0) integrity lock — before anything else
# ---------------------------------------------------------------------------
[ -r .ci-release-guard.lock ] || { printf 'ERROR: .ci-release-guard.lock missing\n' >&2; exit 2; }
if ! grep -v '^#' .ci-release-guard.lock | grep . | shasum -a 256 -c --status -; then
  printf 'ERROR: the guard data files do not match .ci-release-guard.lock.\n' >&2
  printf 'ERROR: the scenarios below are GENERATED from those files, so an entry\n' >&2
  printf 'ERROR: removed there would silently remove its own test. If the change is\n' >&2
  printf 'ERROR: intended, re-lock deliberately: task supply-chain:relock-release-guard\n' >&2
  grep -v '^#' .ci-release-guard.lock | grep . | shasum -a 256 -c - >&2 || true
  exit 2
fi

# ---------------------------------------------------------------------------
# 1) the coverage check is an oracle too — bind it in both directions
# ---------------------------------------------------------------------------
SANDBOX=""
cov_cleanup() { [ -n "${SANDBOX}" ] && rm -rf "${SANDBOX}"; SANDBOX=""; }
trap cov_cleanup EXIT INT TERM

# cov_case <label> <expect-exit> <pattern> <mutation-command>
# The mutation is applied to a COPY: mutate-and-restore on the repo's own tracked
# data files leaves a fabricated exemption behind if it is interrupted, in the
# files that define what the release gate protects.
cov_case() {
  local label="$1" want="$2" pattern="$3" mut="$4" out got=0
  SANDBOX="$(mktemp -d)"
  cp .ci-release-guard-pathspec.txt .ci-release-guard-exempt.txt .ci-oci-tarball-expected.txt "${SANDBOX}/"
  ( cd "${SANDBOX}" && eval "$mut" ) || { note "cov setup failed: $label"; cov_cleanup; return; }
  # A scenario mutating the workflow drops a w.yml into the sandbox; the export
  # cannot travel out of the mutation subshell, so it is wired here.
  local wf=".github/workflows/release.yml"
  [ -f "${SANDBOX}/w.yml" ] && wf="${SANDBOX}/w.yml"
  out="$(RELEASE_GUARD_PATHSPEC_FILE="${SANDBOX}/.ci-release-guard-pathspec.txt" \
         RELEASE_GUARD_EXEMPT_FILE="${SANDBOX}/.ci-release-guard-exempt.txt" \
         RELEASE_GUARD_TARBALL_FIXTURE="${SANDBOX}/.ci-oci-tarball-expected.txt" \
         RELEASE_GUARD_WORKFLOW_FILE="${wf}" \
         ./scripts/check-release-guard-coverage.sh 2>&1)" || got=$?
  cov_cleanup
  scenarios=$((scenarios+1))
  if [ "$got" != "$want" ]; then
    note "$label (coverage exit $got, expected $want)"; printf '%s\n' "$out" | sed 's/^/        /' >&2; return
  fi
  printf '%s\n' "$out" | grep -q "$pattern" \
    || { note "$label (exit $got as expected, but no '$pattern' in the output)"; printf '%s\n' "$out" | sed 's/^/        /' >&2; }
}

echo "coverage) control — the committed tree conforms"
cov_case "coverage passes on the real tree" 0 'release-guard coverage OK' 'true'

echo "coverage) a published path guarded by nothing"
cov_case "an unguarded published path is named" 1 'neither guarded by' \
  "printf './a-brand-new-published-path.txt\n' >> .ci-oci-tarball-expected.txt"

echo "coverage) a shipped Helm-value floor moved into the exempt file"
cov_case "the hard pin refuses a Helm-value floor" 1 'may never be exempt' \
  "printf '# reason: ADR-0020 convenience\ntofu/modules/talos-cluster/helm/cilium-values.yaml\n' >> .ci-release-guard-exempt.txt"

echo "coverage) an exemption with no reason"
cov_case "a reasonless exemption is refused" 1 'has no' \
  "printf 'tofu/modules/talos-cluster/main.tf\n' >> .ci-release-guard-exempt.txt"

echo "coverage) an exemption whose reason is a placeholder"
cov_case "a placeholder reason is refused" 1 'placeholder' \
  "printf '# reason: TODO\ntofu/modules/talos-cluster/outputs.tf\n' >> .ci-release-guard-exempt.txt"

echo "coverage) the workflow stops invoking the guard"
cov_case "a removed guard invocation is caught" 1 "must run exactly" \
  "cp \"${ROOT}/.github/workflows/release.yml\" w.yml && perl -ni -e 'print unless m{^\\s+run: \\./scripts/release-major-bump-guard\\.sh\\s*\$}' w.yml"

echo "coverage) a pathspec literal re-inlined into the workflow"
cov_case "a re-inlined surface literal is caught" 1 "carries the surface literal" \
  "cp \"${ROOT}/.github/workflows/release.yml\" w.yml && printf '        run: git -c core.ignoreCase=false diff --name-only x -- schemas/**\\n' >> w.yml"

echo "coverage) a stale exemption (not a tarball member)"
cov_case "a stale exemption is refused" 1 'stale exemption' \
  "printf '# reason: ADR-0020 §Consequences — module interface.\ntofu/modules/talos-cluster/not-shipped.tf\n' >> .ci-release-guard-exempt.txt"

# ---------------------------------------------------------------------------
# 2) the guard, in a throwaway repo
# ---------------------------------------------------------------------------
command -v git >/dev/null || { echo "ERROR: git required" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'cd /; rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null   # versionsort.* and friends must not leak in
export GIT_CONFIG_SYSTEM=/dev/null

# Every path the scenarios touch, materialised so `git ls-files -- <entry>`
# behaves in the fixture the way it does in the real repo. The exempt file is
# read through the library, never an ad-hoc grep: a second reader that differs on
# whitespace or the `# reason:` grammar materialises paths the guard never sees.
# `mapfile` is bash 4 only and macOS ships 3.2, so read in a loop.
# shellcheck source=scripts/release-guard-lib.sh
# shellcheck disable=SC1091
. "${ROOT}/scripts/release-guard-lib.sh"
rg_load_exempt
EXEMPT_PATHS=("${RG_EXEMPT[@]}")
FIXTURE_PATHS=()
while IFS= read -r line; do
  [ -n "$line" ] && FIXTURE_PATHS+=("${line#./}")
done < <(sed -e 's/[[:space:]]*$//' "${ROOT}/.ci-oci-tarball-expected.txt" | grep .)
EXTRA_PATHS=(
  schemas/cluster.schema.json
  schemas/fixtures/cluster.invalid.yaml
  schemas/fixtures/bootstrap/valid.yaml
  contracts/primitive-contract.md
  kubernetes/substrate/argocd/values.yaml
  kubernetes/substrate/argocd/chart.lock.yaml
  kubernetes/substrate/argocd/_rendered-overlay/kustomization.yaml
  kubernetes/substrate/argocd/charts/vendored-1.2.3/values.yaml
  knowledge/decisions/0001-x.md
  policies/x.rego
  scripts/unrelated.sh
  openspec/specs/x/spec.md
)

cd "$WORK"
git init -q -b main .
git config user.email bite@example.invalid
git config user.name  "release-guard bite-check"
git config commit.gpgsign false
git config tag.gpgsign false
git config core.ignoreCase false          # macOS defaults true, Linux CI false

mkdir -p scripts .github/workflows
cp "${ROOT}/scripts/release-guard-lib.sh" "${ROOT}/scripts/release-major-bump-guard.sh" scripts/
cp "${ROOT}/.ci-release-guard-pathspec.txt" "${ROOT}/.ci-release-guard-exempt.txt" .
printf 'run: ./scripts/release-major-bump-guard.sh\n' > .github/workflows/release.yml
# The two allowlist files are guarded entries in their own right: without them in
# the fixture, every entry-liveness check reports them dead.
cp "${ROOT}/.ci-oci-tarball-include.txt" "${ROOT}/.ci-oci-tarball-expected.txt" .
for p in "${FIXTURE_PATHS[@]}" "${EXEMPT_PATHS[@]}" "${EXTRA_PATHS[@]}"; do
  mkdir -p "$(dirname "$p")"; printf 'seed\n' > "$p"
done
git add -A >/dev/null
git commit -qm "fixture base"
BASE_SHA="$(git rev-parse HEAD)"
git tag v8.0.0
git tag v9.1.0
git tag v10.0.0-rc.1
git tag nightly-2026
[ -x scripts/release-major-bump-guard.sh ] \
  || { echo "ERROR: the guard lost its exec bit on copy" >&2; exit 2; }

# assert the fixture repo starts clean: no scenario may pass on ambient state
if NEXT=9.2.0 ./scripts/release-major-bump-guard.sh 2>/dev/null | grep -v '(none)' | grep -q '^  '; then
  echo "ERROR: the fixture repo has a non-empty surface before any mutation" >&2; exit 2
fi

# Refs are restored too: a swallowed `git checkout main` failure would otherwise
# leave a scenario branch checked out and `git reset --hard` would reset THAT
# branch, running every later scenario somewhere else.
reset_tree() {
  git checkout -q main 2>/dev/null || note "SETUP BROKEN: could not check out main"
  [ "$(git rev-parse --abbrev-ref HEAD)" = main ] || note "SETUP BROKEN: HEAD is not main after reset"
  git reset -q --hard "$BASE_SHA"
  # `|| true` on both: with only `main` present the grep finds nothing and, under
  # `set -e`, the failing pipeline takes the whole suite down mid-run.
  { git for-each-ref --format='%(refname:short)' refs/heads | grep -v '^main$' || true; } \
    | while IFS= read -r b; do [ -n "$b" ] && git branch -q -D "$b" >/dev/null 2>&1 || true; done
  { git for-each-ref --format='%(refname:short)' refs/tags || true; } \
    | while IFS= read -r t; do [ -n "$t" ] && git tag -d "$t" >/dev/null 2>&1 || true; done
  for t in v8.0.0 v9.1.0 v10.0.0-rc.1 nightly-2026; do git tag "$t" "$BASE_SHA" >/dev/null 2>&1 || true; done
}

# touch_commit <path> [trailer-body] — one single-parent commit changing <path>
touch_commit() {
  local p="$1" body="${2:-}"
  printf 'changed\n' >> "$p"
  git add -A >/dev/null
  if [ -n "$body" ]; then git commit -q -m "touch $p" -m "$body"; else git commit -q -m "touch $p"; fi
  git diff --quiet "$BASE_SHA" -- "$p" && { note "SETUP BROKEN: $p unchanged vs base"; return 1; }
  return 0
}

# guard <expect-exit> <verdict-pattern> <label> [env NEXT] [args…]
guard() {
  local want="$1" pattern="$2" label="$3"; shift 3
  local out got=0
  # `-`, not `:-`: a scenario sets NEXT_OVERRIDE="" to exercise the empty-NEXT
  # environment error, and `:-` would quietly substitute the default instead.
  out="$(NEXT="${NEXT_OVERRIDE-9.2.0}" ./scripts/release-major-bump-guard.sh "$@" 2>&1)" || got=$?
  scenarios=$((scenarios+1))
  if [ "$got" != "$want" ]; then
    note "$label (exit $got, expected $want)"; printf '%s\n' "$out" | sed 's/^/        /' >&2; return 1
  fi
  if ! printf '%s\n' "$out" | grep -q -- "$pattern"; then
    note "$label (exit $got as expected, but no '$pattern' in the verdict)"; printf '%s\n' "$out" | sed 's/^/        /' >&2; return 1
  fi
  # The verdict line the guard actually emitted -- comparing literals this file
  # wrote would compare it against itself.
  VERDICTS="${VERDICTS}$(printf '%s\n' "$out" | grep -oE '^guard (blocked|error|n/a|satisfied|overridden) —.*' | head -1)
"
  # The list header appears exactly once, above the verdict -- on the paths that
  # reached one. An exit-2 environment error can happen before the range is even
  # computable, so there is no surface to name.
  [ "$want" = 2 ] && return 0
  local hdr_n hdr_line verdict_line
  hdr_n="$(printf '%s\n' "$out" | grep -c '^Surface files considered' || true)"
  [ "$hdr_n" = 1 ] || { note "$label: surface header appears $hdr_n times, expected exactly 1"; return 1; }
  hdr_line="$(printf '%s\n' "$out" | grep -n '^Surface files considered' | head -1 | cut -d: -f1)"
  verdict_line="$(printf '%s\n' "$out" | grep -n -- "$pattern" | tail -1 | cut -d: -f1)"
  [ "$hdr_line" -lt "$verdict_line" ] \
    || { note "$label: the surface list (line $hdr_line) is not above the verdict (line $verdict_line)"; return 1; }
  return 0
}

VERDICTS=""

echo "guard) red — every published path that is not exempt must block"
for p in "${FIXTURE_PATHS[@]}"; do
  printf '%s\n' "${EXEMPT_PATHS[@]}" | grep -Fxq "$p" && continue
  reset_tree; touch_commit "$p" || continue
  guard 1 'guard blocked' "a change to published $p blocks" || true
done

echo "guard) red — one representative per positive pathspec entry"
# shellcheck source=scripts/release-guard-lib.sh
# shellcheck disable=SC1091
set -f; . ./scripts/release-guard-lib.sh; rg_load_pathspec; set +f
while IFS= read -r entry; do
  # The full pathspec, not the single entry: with only `schemas/**` the
  # representative could be an EXCLUDED path, and the scenario would assert
  # "blocked" against input the guard correctly passes.
  rep="$(git -c core.ignoreCase=false ls-files -- "$entry" "${RG_PATHSPEC[@]}" | head -1)"
  [ -n "$rep" ] || { note "pathspec entry matches nothing in the fixture: $entry"; continue; }
  reset_tree; touch_commit "$rep" || continue
  guard 1 'guard blocked' "entry $entry blocks via $rep" || true
done < <(rg_positive_pathspec)

echo "guard) green — exempt tarball members must not block"
for p in "${EXEMPT_PATHS[@]}"; do
  reset_tree; touch_commit "$p" || continue
  guard 0 'guard n/a' "exempt $p does not block" || true
done

echo "guard) green — the paths the depth limits and the exclusion keep out"
for p in schemas/fixtures/cluster.invalid.yaml \
         schemas/fixtures/bootstrap/valid.yaml \
         kubernetes/substrate/argocd/_rendered-overlay/kustomization.yaml \
         kubernetes/substrate/argocd/charts/vendored-1.2.3/values.yaml \
         knowledge/decisions/0001-x.md policies/x.rego scripts/unrelated.sh \
         openspec/specs/x/spec.md; do
  reset_tree; touch_commit "$p" || continue
  guard 0 'guard n/a' "unguarded $p does not block" || true
done

echo "guard) green — a MAJOR bump satisfies the guard"
reset_tree; touch_commit schemas/cluster.schema.json
NEXT_OVERRIDE=10.0.0 guard 0 'guard satisfied' "a MAJOR bump satisfies the guard" || true

echo "guard) tag selection without --base"
reset_tree; touch_commit schemas/cluster.schema.json
out="$(NEXT=9.2.0 ./scripts/release-major-bump-guard.sh 2>&1 || true)"
scenarios=$((scenarios+1))
printf '%s\n' "$out" | grep -q 'since v9.1.0' \
  || note "tag selection: expected v9.1.0 (not v8.0.0, the prerelease, or the non-semver tag); got: $(printf '%s' "$out" | head -1)"

echo "guard) exit 2 — environment errors, all sharing one verdict line"
reset_tree; touch_commit schemas/cluster.schema.json
NEXT_OVERRIDE="" guard 2 'guard error' "empty NEXT is an environment error, not a pass" || true
NEXT_OVERRIDE="notaversion" guard 2 'guard error' "a non-semver NEXT is an environment error" || true
( unset NEXT; out="$(./scripts/release-major-bump-guard.sh 2>&1 || true)"
  printf '%s\n' "$out" | grep -q 'guard error' || exit 1 ) \
  || note "an unset NEXT must be an environment error"
scenarios=$((scenarios+1))
reset_tree; touch_commit schemas/cluster.schema.json
( git tag -d v9.1.0 >/dev/null; git tag -d v8.0.0 >/dev/null
  out="$(NEXT=9.2.0 ./scripts/release-major-bump-guard.sh 2>&1 || true)"
  printf '%s\n' "$out" | grep -q 'guard error' || exit 1 ) \
  || note "a repo with no stable tag must be an environment error, never 'guard n/a'"
scenarios=$((scenarios+1))
reset_tree

echo "guard) exit 2 — a downgrade is not a MAJOR bump"
# The stray tag must NOT be at HEAD: a tag at the tip empties the range and the
# guard correctly reports "guard n/a" before any version comparison runs.
reset_tree
git tag v10.0.0 "$BASE_SHA" >/dev/null 2>&1 || true
touch_commit schemas/cluster.schema.json
NEXT_OVERRIDE=9.2.0 guard 2 'guard error' "a computed version below the highest tag is refused" || true
reset_tree

echo "guard) --base must be a stable tag while enforcing, any ref while advisory"
reset_tree; touch_commit schemas/cluster.schema.json
sha="$(git rev-parse HEAD~1)"
NEXT_OVERRIDE=9.2.0 guard 2 'guard error' "--base with a commit SHA is refused when enforcing" --base "$sha" || true
NEXT_OVERRIDE=9.2.0 guard 1 'guard blocked' "--base with a stable tag still blocks" --base v9.1.0 || true
out="$(NEXT='' ./scripts/release-major-bump-guard.sh --advisory --base "$sha" 2>&1 || true)"
scenarios=$((scenarios+1))
printf '%s\n' "$out" | grep -q '  schemas/cluster.schema.json' \
  || note "--advisory --base <sha> must report against that ref (the docs-lint job's shape)"
reset_tree

echo "guard) exit 2 — a shallow clone cannot reach a verdict"
sc="$(mktemp -d)"
if git clone -q --depth 1 "file://$WORK" "$sc/c" 2>/dev/null; then
  ( cd "$sc/c" && cp -R "$WORK/scripts" . 2>/dev/null || true
    out="$(NEXT=9.2.0 ./scripts/release-major-bump-guard.sh 2>&1 || true)"
    printf '%s\n' "$out" | grep -qE 'guard error' || exit 1 ) \
    || note "a shallow clone must be an environment error"
  scenarios=$((scenarios+1))
fi
rm -rf "$sc"

echo "guard) the CI-facing outputs carry the verdict and the list"
reset_tree; touch_commit schemas/cluster.schema.json
go="$WORK/gh_out"; gs="$WORK/gh_sum"; : > "$go"; : > "$gs"
GITHUB_OUTPUT="$go" GITHUB_STEP_SUMMARY="$gs" NEXT=9.2.0 \
  ./scripts/release-major-bump-guard.sh >/dev/null 2>&1 || true
scenarios=$((scenarios+1))
grep -q '^guard-verdict=guard blocked' "$go" \
  || note "the guard must publish guard-verdict= to GITHUB_OUTPUT — release.yml's notify job gates on it"
grep -q 'schemas/cluster.schema.json' "$gs" \
  || note "the job summary must carry the surface list"
sum_hdr="$(grep -n 'Surface files considered' "$gs" | head -1 | cut -d: -f1)"
sum_vrd="$(grep -n 'guard blocked' "$gs" | head -1 | cut -d: -f1)"
[ -n "$sum_hdr" ] && [ -n "$sum_vrd" ] && [ "$sum_hdr" -lt "$sum_vrd" ] \
  || note "the job summary must show the surface list above the verdict too"
reset_tree

echo "guard) exit 2 — a pathspec entry dead AT THE BASE"
# What must be an environment error is an entry already dead when the range
# opened -- a directory renamed in an earlier release, leaving a valid pathspec
# that silently guards nothing. An entry that dies INSIDE the range is a deletion
# the diff reports instead (scenario below).
reset_tree
mv contracts contracts-renamed
git add -A >/dev/null; git commit -qm "rename a guarded directory"
git tag -f v9.9.0 HEAD >/dev/null
printf 'later\n' >> schemas/cluster.schema.json
git add -A >/dev/null; git commit -qm "a later change"
out="$(NEXT=9.9.1 ./scripts/release-major-bump-guard.sh 2>&1 || true)"
scenarios=$((scenarios+1))
printf '%s\n' "$out" | grep -q 'match no tracked file' \
  || note "a pathspec entry dead at the base must be an environment error, not an empty surface"
git tag -d v9.9.0 >/dev/null 2>&1 || true
reset_tree

echo "guard) red — deleting and renaming a published path still blocks"
reset_tree; git rm -q kubernetes/substrate/argocd/namespace.yaml; git commit -qm "delete a published path"
guard 1 'guard blocked' "deleting a published path blocks" || true
reset_tree; git mv kubernetes/substrate/argocd/namespace.yaml kubernetes/substrate/argocd/ns.yaml
git commit -qm "rename a published path"
guard 1 'guard blocked' "renaming a published path blocks" || true

echo "guard) the override — merge commit, two files, real reason"
reset_tree
git checkout -q -b side
printf 'changed\n' >> kubernetes/bootstrap/cilium/extras.yaml
git commit -qam "side: touch a second guarded file"
git checkout -q main
printf 'changed\n' >> schemas/cluster.schema.json
git commit -qam "main: touch a guarded file"
git merge -q --no-ff side -m "Merge side" -m "Reviewed the cilium substrate object: the new key is optional and nothing that validated before stops validating.

Allow-Non-Major: additive optional key in the cilium substrate object, no consumer contract narrows" >/dev/null
parents=$(( $(git rev-list --parents -n 1 HEAD | wc -w | tr -d ' ') - 1 ))
[ "$parents" = 2 ] || note "SETUP BROKEN: expected a merge commit, got $parents parent(s)"
guard 0 'guard overridden' "a merge-commit attestation with a real reason overrides" || true
out="$(NEXT=9.2.0 ./scripts/release-major-bump-guard.sh 2>&1 || true)"
for f in schemas/cluster.schema.json kubernetes/bootstrap/cilium/extras.yaml; do
  printf '%s\n' "$out" | grep -q "  $f" \
    || note "the override output must name every cleared file, missing: $f"
done
printf '%s\n' "$out" | grep -q 'clears EVERY file listed above' \
  || note "the override must state that it clears more than the merger's own files"

# merge_with_body <branch> <body> — a two-parent tip whose BODY is <body>, so a
# rejection can only come from the reason rules, not from the two-parent rule.
merge_with_body() {
  local br="$1" body="$2"
  git checkout -q -b "$br"; printf 'x\n' >> kubernetes/bootstrap/cilium/extras.yaml
  git commit -qam "$br side"; git checkout -q main
  printf 'x\n' >> schemas/cluster.schema.json; git commit -qam "$br main"
  git merge -q --no-ff "$br" -m "Merge $br" -m "maintainer reasoning line

$body" >/dev/null
  local n; n=$(( $(git rev-list --parents -n 1 HEAD | wc -w | tr -d ' ') - 1 ))
  [ "$n" = 2 ] || { note "SETUP BROKEN: $br produced $n parent(s)"; return 1; }
}

echo "guard) the override is refused off a merge commit and on a bad reason"
reset_tree
touch_commit schemas/cluster.schema.json "Allow-Non-Major: additive optional key, no consumer contract narrows"
guard 1 'guard blocked' "a single-parent tip cannot attest (squash/rebase re-enabled)" || true
reset_tree
merge_with_body side2 "Allow-Non-Major: <reason>" \
  && guard 1 'guard blocked' "the short placeholder reason cannot attest" || true
# The long placeholder isolates the regex from the length floor. It is the string
# the guard's own recovery command prints, so a copy-paste must not attest.
reset_tree
merge_with_body side2b "Allow-Non-Major: <a real reason naming the surface path or issue>" \
  && guard 1 'guard blocked' "the long placeholder reason cannot attest (regex, not length)" || true
# And a short non-placeholder isolates the length floor from the regex.
reset_tree
merge_with_body side2c "Allow-Non-Major: typo fix" \
  && guard 1 'guard blocked' "a too-short reason cannot attest (length, not regex)" || true

echo "guard) an attestation standing alone in the body is not a maintainer's"
# The shape merge_commit_message=PR_TITLE produces: a two-parent commit whose
# entire body is one contributor-authored line. No in-CI check can read that
# setting back, so this is the control that holds without it.
reset_tree
git checkout -q -b side6; printf 'x\n' >> kubernetes/bootstrap/cilium/extras.yaml
git commit -qam "side6"; git checkout -q main
printf 'x\n' >> schemas/cluster.schema.json; git commit -qam "main6"
git merge -q --no-ff side6 -m "Merge side6" -m "Allow-Non-Major: an otherwise perfectly good reason naming schemas/cluster.schema.json" >/dev/null
guard 1 'guard blocked' "a body that is only the trailer cannot attest" || true

echo "guard) the trailer is read from the body only"
# A MERGE commit whose SUBJECT carries the trailer and whose body does not: on a
# single-parent commit the two-parent rule would refuse it anyway, so the
# scenario would pass against `%B` too and discriminate nothing.
reset_tree
git checkout -q -b side3; printf 'x\n' >> kubernetes/bootstrap/cilium/extras.yaml
git commit -qam "side3"; git checkout -q main
printf 'x\n' >> schemas/cluster.schema.json; git commit -qam "main3"
git merge -q --no-ff side3 -m "Allow-Non-Major: an otherwise valid reason naming schemas/cluster.schema.json" >/dev/null
parents=$(( $(git rev-list --parents -n 1 HEAD | wc -w | tr -d ' ') - 1 ))
[ "$parents" = 2 ] || note "SETUP BROKEN: subject-line scenario needs a merge commit, got $parents parent(s)"
[ -z "$(git log -1 --format=%b | grep -i '^Allow-Non-Major:' || true)" ] \
  || note "SETUP BROKEN: the trailer must be in the subject only, not the body"
guard 1 'guard blocked' "a subject-line trailer cannot attest, even on a merge commit" || true
git branch -D side3 >/dev/null 2>&1 || true
reset_tree
printf 'changed\n' >> schemas/cluster.schema.json
git add -A >/dev/null; git commit -q -m "Allow-Non-Major: subject-line attempt"
guard 1 'guard blocked' "a subject-line trailer on a single-parent tip cannot attest" || true
# On a MERGE commit, so the two-parent rule cannot supply the rejection: only the
# `^` anchor can.
reset_tree
merge_with_body side4 "we considered Allow-Non-Major: but did not use it" \
  && guard 1 'guard blocked' "a mid-line mention cannot attest, even on a merge commit" || true

echo "guard) a prior attestation in the range is reported but not honoured"
reset_tree
if merge_with_body side5 "Allow-Non-Major: the only guarded change is an additive optional schema key"; then
  printf 'later\n' >> kubernetes/substrate/argocd/namespace.yaml
  git add -A >/dev/null; git commit -qm "an ordinary commit after the attestation"
  out="$(NEXT=9.2.0 ./scripts/release-major-bump-guard.sh 2>&1 || true)"
  scenarios=$((scenarios+1))
  printf '%s\n' "$out" | grep -q 'guard blocked' \
    || note "an attestation must not survive a later push"
  printf '%s\n' "$out" | grep -q 'A prior attestation exists in this range' \
    || note "the guard must report the prior attestation it found"
fi

echo "guard) --advisory never exits non-zero and never goes silent"
reset_tree; touch_commit schemas/cluster.schema.json
out="$(NEXT='' ./scripts/release-major-bump-guard.sh --advisory 2>&1)" || note "--advisory must exit 0"
scenarios=$((scenarios+1))
printf '%s\n' "$out" | grep -q '  schemas/cluster.schema.json' \
  || note "--advisory must still print the guarded files it found"
reset_tree
out="$(NEXT='' ./scripts/release-major-bump-guard.sh --advisory 2>&1)" || note "--advisory must exit 0 with no surface"
printf '%s\n' "$out" | grep -q '(none)' || note "--advisory must print (none) rather than nothing"
scenarios=$((scenarios+1))
( git tag -d v9.1.0 >/dev/null; git tag -d v8.0.0 >/dev/null
  out="$(NEXT='' ./scripts/release-major-bump-guard.sh --advisory 2>&1)"
  printf '%s\n' "$out" | grep -q 'advisory unavailable' || exit 1 ) \
  || note "--advisory must say 'advisory unavailable' on an environment error, never stay silent"
scenarios=$((scenarios+1))
git tag -f v8.0.0 "$BASE_SHA" >/dev/null 2>&1 || true
git tag -f v9.1.0 "$BASE_SHA" >/dev/null 2>&1 || true

echo "guard) the five verdict classes were observed, and no prefix shadows another"
scenarios=$((scenarios+1))
classes="$(printf '%s\n' "$VERDICTS" | grep -oE '^guard (blocked|error|n/a|satisfied|overridden)' | sort -u)"
n_classes="$(printf '%s\n' "$classes" | grep -c . || true)"
[ "$n_classes" = 5 ] \
  || note "expected all five verdict classes to be observed in the guard's own output, saw $n_classes: $(printf '%s' "$classes" | tr '\n' ' ')"
# release.yml's notify job matches on the `guard blocked` / `guard error`
# prefixes, so no observed verdict may contain another class's prefix.
printf '%s\n' "$VERDICTS" | grep . | while IFS= read -r v; do
  for other in blocked error n/a satisfied overridden; do
    case "$v" in
      "guard ${other} "*) : ;;
      *"guard ${other} "*) printf 'FAIL: verdict line contains another class prefix: %s\n' "$v" >&2 ;;
    esac
  done
done

cd "${ROOT}"
# A floor, not just a count: the marker exists to reject a suite edited into
# running nothing, which a bare count satisfies trivially. Raise it deliberately
# when scenarios are added; never lower it to make a run pass.
SCENARIO_FLOOR=78
if [ "$scenarios" -lt "$SCENARIO_FLOOR" ]; then
  printf 'ERROR: only %s scenarios ran, floor is %s — the suite was narrowed\n' "$scenarios" "$SCENARIO_FLOOR" >&2
  rc=1
fi
if [ "$rc" = 0 ]; then
  printf 'release-guard bite-check OK (%s scenarios)\n' "$scenarios"
else
  printf 'ERROR: release-guard bite-check — the guard regressed (%s scenarios run)\n' "$scenarios" >&2
fi
exit "$rc"
