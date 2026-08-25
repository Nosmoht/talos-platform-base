#!/usr/bin/env bash
# check-release-guard-gate-bites.sh — proves the release guard actually bites.
#
# Three disciplines, each of which caught a real defect while this was written
# (the same three scripts/check-staleness-gate-bite.sh records):
#
#   1. Every scenario asserts the git state it claims to have built BEFORE
#      reading a verdict, so it cannot pass because its setup silently failed.
#   2. Every scenario asserts the VERDICT LINE, not just the exit code. The guard
#      emits exit 0 on three different verdicts and exit 2 on a crash; an exit
#      code alone cannot tell "blocked" from "died after printing the list".
#   3. Each direction of a rule needs a scenario on BOTH sides. A red case alone
#      is satisfied by an implementation that is wrong the other way -- an
#      over-broad pathspec passes every red scenario in this file.
#
# THE FIXTURE-EQUALITY ABORT COMES FIRST. The scenarios below are generated from
# the guard's own data files, so deleting an entry would delete its scenario and
# the suite would stay green. Comparing the live files against their committed
# .expected.txt fixtures makes a narrowing a two-file deletion instead of a
# one-file pattern tightening. It is a speed bump, not a gate -- CODEOWNERS is
# documented in this repo as non-enforcing -- and the real external anchor is
# scripts/check-release-guard-coverage.sh, which is exercised here too because it
# is otherwise an untested oracle.
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
# 0) fixture equality — before anything else
# ---------------------------------------------------------------------------
for pair in ".ci-release-guard-pathspec.txt .ci-release-guard-pathspec.expected.txt" \
            ".ci-release-guard-exempt.txt .ci-release-guard-exempt.expected.txt"; do
  # shellcheck disable=SC2086
  set -- $pair
  [ -r "$1" ] && [ -r "$2" ] || { printf 'ERROR: %s or %s missing\n' "$1" "$2" >&2; exit 2; }
  if ! diff -u "$2" "$1" >/dev/null; then
    printf 'ERROR: %s differs from its committed fixture %s.\n' "$1" "$2" >&2
    printf 'ERROR: the scenarios below are generated from %s, so an entry removed\n' "$1" >&2
    printf 'ERROR: there would silently remove its own test. Update BOTH files, on purpose.\n' >&2
    diff -u "$2" "$1" >&2 || true
    exit 2
  fi
done

# ---------------------------------------------------------------------------
# 1) the coverage check is an oracle too — bind it in both directions
# ---------------------------------------------------------------------------
cov_case() { # cov_case <label> <expect-exit> <pattern> <mutation-command>
  local label="$1" want="$2" pattern="$3" mut="$4" out got=0 tmp
  tmp="$(mktemp -d)"
  cp .ci-release-guard-pathspec.txt .ci-release-guard-exempt.txt .ci-oci-tarball-expected.txt "$tmp/"
  ( eval "$mut" ) || { note "cov setup failed: $label"; rm -rf "$tmp"; return; }
  out="$(./scripts/check-release-guard-coverage.sh 2>&1)" || got=$?
  cp "$tmp/.ci-release-guard-pathspec.txt" "$tmp/.ci-release-guard-exempt.txt" "$tmp/.ci-oci-tarball-expected.txt" .
  rm -rf "$tmp"
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
# behaves in the fixture the way it does in the real repo.
mapfile -t FIXTURE_PATHS < <(sed 's|^\./||' "${ROOT}/.ci-oci-tarball-expected.txt" | grep .)
mapfile -t EXEMPT_PATHS  < <(grep -v '^[[:space:]]*#' "${ROOT}/.ci-release-guard-exempt.txt" | grep .)
EXTRA_PATHS=(
  schemas/cluster.schema.json
  schemas/fixtures/cluster.invalid.yaml
  schemas/fixtures/bootstrap/valid.yaml
  contracts/primitive-contract.md
  kubernetes/substrate/argocd/values.yaml
  kubernetes/substrate/argocd/chart.lock.yaml
  kubernetes/substrate/argocd/_rendered-overlay/kustomization.yaml
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
# The two allowlist files are guarded entries in their own right, so the fixture
# has to carry them or every entry-liveness check reports them dead.
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
if [ -n "$(NEXT=9.2.0 ./scripts/release-major-bump-guard.sh 2>/dev/null | grep -v '(none)' | grep '^  ')" ]; then
  echo "ERROR: the fixture repo has a non-empty surface before any mutation" >&2; exit 2
fi

reset_tree() { git checkout -q main 2>/dev/null || true; git reset -q --hard "$BASE_SHA"; }

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
  out="$(NEXT="${NEXT_OVERRIDE-9.2.0}" ./scripts/release-major-bump-guard.sh "$@" 2>&1)" || got=$?
  scenarios=$((scenarios+1))
  if [ "$got" != "$want" ]; then
    note "$label (exit $got, expected $want)"; printf '%s\n' "$out" | sed 's/^/        /' >&2; return 1
  fi
  if ! printf '%s\n' "$out" | grep -q -- "$pattern"; then
    note "$label (exit $got as expected, but no '$pattern' in the verdict)"; printf '%s\n' "$out" | sed 's/^/        /' >&2; return 1
  fi
  # AC3: the list header appears exactly once, above the verdict -- on the paths
  # that reached a verdict. An exit-2 environment error can happen before the
  # range is even computable, so there is no surface to name.
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
record_verdict() { VERDICTS="${VERDICTS}$1
"; }

echo "guard) red — every published path that is not exempt must block"
for p in "${FIXTURE_PATHS[@]}"; do
  printf '%s\n' "${EXEMPT_PATHS[@]}" | grep -Fxq "$p" && continue
  reset_tree; touch_commit "$p" || continue
  guard 1 'guard blocked' "a change to published $p blocks" || true
done
record_verdict "guard blocked"

echo "guard) red — one representative per positive pathspec entry"
# shellcheck source=/dev/null
set -f; . ./scripts/release-guard-lib.sh; rg_load_pathspec; set +f
while IFS= read -r entry; do
  rep="$(git -c core.ignoreCase=false ls-files -- "$entry" | head -1)"
  [ -n "$rep" ] || { note "pathspec entry matches nothing in the fixture: $entry"; continue; }
  reset_tree; touch_commit "$rep" || continue
  guard 1 'guard blocked' "entry $entry blocks via $rep" || true
done < <(rg_positive_pathspec)

echo "guard) green — exempt tarball members must not block"
for p in "${EXEMPT_PATHS[@]}"; do
  reset_tree; touch_commit "$p" || continue
  guard 0 'guard n/a' "exempt $p does not block" || true
done
record_verdict "guard n/a"

echo "guard) green — the paths the depth limits and the exclusion keep out"
for p in schemas/fixtures/cluster.invalid.yaml \
         schemas/fixtures/bootstrap/valid.yaml \
         kubernetes/substrate/argocd/_rendered-overlay/kustomization.yaml \
         knowledge/decisions/0001-x.md policies/x.rego scripts/unrelated.sh \
         openspec/specs/x/spec.md; do
  reset_tree; touch_commit "$p" || continue
  guard 0 'guard n/a' "unguarded $p does not block" || true
done

echo "guard) green — a MAJOR bump satisfies the guard"
reset_tree; touch_commit schemas/cluster.schema.json
NEXT_OVERRIDE=10.0.0 guard 0 'guard satisfied' "a MAJOR bump satisfies the guard" || true
record_verdict "guard satisfied"

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
record_verdict "guard error"
( unset NEXT; out="$(./scripts/release-major-bump-guard.sh 2>&1 || true)"
  printf '%s\n' "$out" | grep -q 'guard error' || exit 1 ) \
  || note "an unset NEXT must be an environment error"
scenarios=$((scenarios+1))
reset_tree; touch_commit schemas/cluster.schema.json
( git tag -d v9.1.0 >/dev/null; git tag -d v8.0.0 >/dev/null
  out="$(NEXT=9.2.0 ./scripts/release-major-bump-guard.sh 2>&1 || true)"
  printf '%s\n' "$out" | grep -q 'guard error' || exit 1 ) \
  || note "a repo with no stable tag must be an environment error without --allow-no-tag"
scenarios=$((scenarios+1))
git tag -f v8.0.0 "$BASE_SHA" >/dev/null 2>&1 || true
git tag -f v9.1.0 "$BASE_SHA" >/dev/null 2>&1 || true

echo "guard) exit 2 — a pathspec entry dead AT THE BASE"
# The liveness check runs against the base tree on purpose: an entry that matched
# at the tag and matches nothing now is a DELETION inside the range, which the
# diff must report (asserted below). What must be an environment error is an
# entry that was already dead when the range opened -- a directory renamed in an
# earlier release, leaving a valid pathspec that silently guards nothing.
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
git merge -q --no-ff side -m "Merge side" -m "Allow-Non-Major: additive optional key in the cilium substrate object, no consumer contract narrows" >/dev/null
parents=$(( $(git rev-list --parents -n 1 HEAD | wc -w | tr -d ' ') - 1 ))
[ "$parents" = 2 ] || note "SETUP BROKEN: expected a merge commit, got $parents parent(s)"
out="$(NEXT=9.2.0 ./scripts/release-major-bump-guard.sh 2>&1)" || note "the override must exit 0 on a merge commit"
scenarios=$((scenarios+1))
printf '%s\n' "$out" | grep -q 'guard overridden' || note "expected 'guard overridden'"
record_verdict "guard overridden"
for f in schemas/cluster.schema.json kubernetes/bootstrap/cilium/extras.yaml; do
  printf '%s\n' "$out" | grep -q "  $f" \
    || note "the override output must name every cleared file, missing: $f"
done
printf '%s\n' "$out" | grep -q 'clears EVERY file listed above' \
  || note "the override must state that it clears more than the merger's own files"

echo "guard) the override is refused off a merge commit and on a placeholder reason"
reset_tree
touch_commit schemas/cluster.schema.json "Allow-Non-Major: additive optional key, no consumer contract narrows"
guard 1 'guard blocked' "a single-parent tip cannot attest (squash/rebase re-enabled)" || true
reset_tree
git checkout -q -b side2; printf 'x\n' >> kubernetes/bootstrap/cilium/extras.yaml
git commit -qam "side2"; git checkout -q main
printf 'x\n' >> schemas/cluster.schema.json; git commit -qam "main2"
git merge -q --no-ff side2 -m "Merge side2" -m "Allow-Non-Major: <reason>" >/dev/null
guard 1 'guard blocked' "the documented placeholder reason cannot attest" || true
reset_tree
git branch -D side side2 >/dev/null 2>&1 || true

echo "guard) the trailer is read from the body only"
reset_tree
printf 'changed\n' >> schemas/cluster.schema.json
git add -A >/dev/null; git commit -q -m "Allow-Non-Major: subject-line attempt"
guard 1 'guard blocked' "a subject-line trailer cannot attest" || true
reset_tree
touch_commit schemas/cluster.schema.json "Allow-Non-Major: none of this is breaking" >/dev/null
reset_tree
touch_commit schemas/cluster.schema.json "we considered Allow-Non-Major: but did not use it"
guard 1 'guard blocked' "a mid-line mention cannot attest" || true

echo "guard) --advisory never exits non-zero and never goes silent"
reset_tree; touch_commit schemas/cluster.schema.json
out="$(NEXT= ./scripts/release-major-bump-guard.sh --advisory 2>&1)" || note "--advisory must exit 0"
scenarios=$((scenarios+1))
printf '%s\n' "$out" | grep -q '  schemas/cluster.schema.json' \
  || note "--advisory must still print the guarded files it found"
reset_tree
out="$(NEXT= ./scripts/release-major-bump-guard.sh --advisory 2>&1)" || note "--advisory must exit 0 with no surface"
printf '%s\n' "$out" | grep -q '(none)' || note "--advisory must print (none) rather than nothing"
scenarios=$((scenarios+1))
( git tag -d v9.1.0 >/dev/null; git tag -d v8.0.0 >/dev/null
  out="$(NEXT= ./scripts/release-major-bump-guard.sh --advisory 2>&1)"
  printf '%s\n' "$out" | grep -q 'advisory unavailable' || exit 1 ) \
  || note "--advisory must say 'advisory unavailable' on an environment error, never stay silent"
scenarios=$((scenarios+1))
git tag -f v8.0.0 "$BASE_SHA" >/dev/null 2>&1 || true
git tag -f v9.1.0 "$BASE_SHA" >/dev/null 2>&1 || true

echo "guard) the five verdict lines are pairwise distinct"
scenarios=$((scenarios+1))
n_all="$(printf '%s' "$VERDICTS" | grep -c . || true)"
n_uniq="$(printf '%s' "$VERDICTS" | grep . | sort -u | wc -l | tr -d ' ')"
[ "$n_all" = 5 ] || note "expected 5 verdict classes exercised, saw $n_all"
[ "$n_all" = "$n_uniq" ] || note "the verdict lines are not pairwise distinct ($n_uniq unique of $n_all)"

cd "${ROOT}"
if [ "$rc" = 0 ]; then
  printf 'release-guard bite-check OK (%s scenarios)\n' "$scenarios"
else
  printf 'ERROR: release-guard bite-check — the guard regressed (%s scenarios run)\n' "$scenarios" >&2
fi
exit "$rc"
