#!/usr/bin/env bash
# Bite-check for the spec-staleness gate (scripts/check-spec-staleness.py).
#
# The gate's verdict hinges on WHICH commits must carry the `Spec-Impact: none`
# trailer, and that attribution rule has two failure directions:
#
#   too strict — a base-sync merge (forced on every PR, because branch
#                protection requires up-to-date branches) is counted as a
#                contributor, voiding an otherwise valid escape and leaving
#                history rewriting as the only remedy;
#   too lax    — a merge that INVENTED content (hand-resolved conflict, evil
#                merge) inherits someone else's trailer and ships an
#                uncertified behavior change.
#
# Neither direction is observable from the repo's own history: it has one shape
# at a time. So the rule is bound here against a purpose-built throwaway repo,
# the same way `task spec:validate` binds the strict validator against a
# committed malformed fixture. Every scenario asserts the git state it claims to
# have built BEFORE reading the gate's verdict, so a scenario cannot pass
# because its setup silently failed.
#
# Runs offline, mutates nothing outside its temp dir. Exit 0 = all scenarios
# behaved, 1 = the attribution rule regressed, 2 = environment error.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
gate="$repo_root/scripts/check-spec-staleness.py"
[ -f "$gate" ] || { echo "ERROR: $gate missing" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"

git init -q -b main . >/dev/null
# Local-only identity: CI runners and fresh clones may have none configured,
# and signing must not be inherited from the operator's global config.
git config user.email bite@example.invalid
git config user.name "staleness bite-check"
git config commit.gpgsign false

# The gate resolves ownership from `openspec/specs/*/spec.md` frontmatter
# relative to the CWD, so the fixture repo mirrors that layout.
mkdir -p openspec/specs/x
printf -- '---\nsources:\n  primary:\n    - src.txt\n---\n\n# x\n' > openspec/specs/x/spec.md
# 40 lines so "far apart" and "close enough to share a diff hunk" are both
# expressible; line distance is what discriminates scenario B.
seq 1 40 | sed 's/^/line/' > src.txt
git add -A
git commit -qm "fixture base"
base="$(git rev-parse HEAD)"

if ! git merge-tree --write-tree HEAD HEAD >/dev/null 2>&1; then
  echo "SKIP: $(git --version) has no 'merge-tree --write-tree' (needs git >= 2.38)."
  echo "SKIP: without it the gate treats every merge as a contributor — fail-CLOSED,"
  echo "SKIP: so the gate is stricter than intended here, never laxer. CI's git has it."
  exit 0
fi

rc=0

edit() { # edit <line-number> <replacement-text>
  awk -v n="$1" -v t="$2" 'NR==n{print t; next} {print}' src.txt > src.next
  mv src.next src.txt
}

assert_merge_commit() {
  if [ "$(git rev-list --parents -n1 HEAD | wc -w | tr -d ' ')" != 3 ]; then
    echo "  SETUP BROKEN: HEAD is not a two-parent merge"; rc=1; return 1
  fi
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "  SETUP BROKEN: unresolved index"; rc=1; return 1
  fi
}

verdict() { # verdict <expected-exit> <label>
  local want="$1" label="$2" got=0 out
  out="$(python3 "$gate" --base main 2>&1)" || got=$?
  if [ "$got" = "$want" ]; then
    echo "  PASS  $label (exit $got)"
  else
    echo "  FAIL  $label (exit $got, expected $want)"
    printf '%s\n' "$out" | sed 's/^/          /'
    rc=1
  fi
}

git checkout -q main
edit 2 "line2-MAIN"
edit 20 "line20-MAIN"
git commit -qam "base branch edits lines 2 and 20"
main_tip="$(git rev-parse HEAD)"

# --- Controls first. A non-zero exit from the merge scenarios below is only
# --- evidence about merge attribution if the gate is otherwise working: it must
# --- pass a clean case and fail an uncertified one in this same environment.
echo "control-1) owning spec touched in the same diff — no trailer needed"
git checkout -q -B control-clean "$main_tip"
edit 39 "line39-BRANCH"
printf '\nchanged\n' >> openspec/specs/x/spec.md
git commit -qam "edit the source and its owning spec"
verdict 0 "gate passes when the owning spec moves with the source"

echo "control-2) uncertified source change — the gate must bite"
git checkout -q -B control-biting "$main_tip"
edit 39 "line39-BRANCH"
git commit -qam "edit the source with no trailer and no spec touch"
verdict 1 "gate still fails an uncertified change"

# --- Too-strict direction: base-sync merges must not void the escape.
echo "A) base-sync merge, branch edit FAR from the base's edits"
git checkout -q -B sync-far "$base"
edit 39 "line39-BRANCH"
git commit -qam "branch edits line 39

Spec-Impact: none"
sync_merge() { # sync_merge <label> — merge the base in, must be conflict-free
  if ! git merge -q --no-edit "$main_tip" -m "Merge branch 'main' into $1" >/dev/null 2>&1; then
    echo "  SETUP BROKEN: the base-sync merge conflicted"; git merge --abort || true; rc=1; return 1
  fi
}
sync_merge sync-far && assert_merge_commit && verdict 0 "far-apart base-sync merge keeps the escape"

# B is not extra branch coverage — it runs the same path as A. It is a
# regression lock against reintroducing the cheaper `diff-tree --cc`-emptiness
# test, which the comment below explains and which measurement rejected.
echo "B) regression lock vs --cc: base-sync merge, edits 3 lines apart, SHARED hunk"
git checkout -q -B sync-near "$base"
edit 23 "line23-BRANCH"
git commit -qam "branch edits line 23

Spec-Impact: none"
if sync_merge sync-near && assert_merge_commit; then
  # This is why the gate re-runs the merge instead of reading `diff-tree --cc`:
  # --cc compresses per HUNK, so this CLEAN auto-merge still prints hunks and a
  # --cc-emptiness test would misread it as invented content. Asserted, so the
  # scenario cannot quietly stop discriminating if git's diff context changes.
  cc_lines="$(git diff-tree --cc --no-commit-id HEAD -- src.txt | wc -l | tr -d ' ')"
  if [ "$cc_lines" -eq 0 ]; then
    echo "  SETUP BROKEN: combined diff is empty — scenario B no longer discriminates"; rc=1
  fi
  verdict 0 "shared-hunk base-sync merge keeps the escape (combined diff: $cc_lines lines)"
fi

# --- Too-lax direction: a merge that contributed content certifies itself.
echo "C) evil merge — clean auto-merge, then the merge invents an unrelated line"
git checkout -q -B evil "$base"
edit 39 "line39-BRANCH"
git commit -qam "branch edits line 39

Spec-Impact: none"
git merge --no-commit --no-ff "$main_tip" >/dev/null 2>&1
edit 10 "line10-INVENTED-BY-THE-MERGE"
git add src.txt
git commit -qm "Merge branch 'main' into evil"
assert_merge_commit && verdict 1 "evil merge must not inherit another commit's trailer"

echo "C2) merge flips only the FILE MODE — same blob id, different tree entry"
git checkout -q -B modeflip "$base"
edit 39 "line39-BRANCH"
git commit -qam "branch edits line 39

Spec-Impact: none"
git merge --no-commit --no-ff "$main_tip" >/dev/null 2>&1
chmod +x src.txt
git add src.txt
git commit -qm "Merge branch 'main' into modeflip"
if assert_merge_commit; then
  # The mode change is the merge's own contribution, and the blob id is
  # unchanged — so a blob-id-only comparison reports "replayed the parents" and
  # hands the merge someone else's trailer. Two spec-owned primary sources in
  # this repo are shell scripts CI runs with no interpreter prefix, so a dropped
  # exec bit on one of them is a behavior change of exactly this shape.
  mode_now="$(git ls-tree HEAD -- src.txt | awk '{print $1}')"
  mode_parent="$(git ls-tree HEAD^1 -- src.txt | awk '{print $1}')"
  if [ "$mode_now" = "$mode_parent" ]; then
    echo "  SETUP BROKEN: the merge did not change the file mode ($mode_now)"; rc=1
  fi
  verdict 1 "a mode-only merge contribution certifies itself ($mode_parent -> $mode_now)"
fi

echo "D) hand-resolved conflict — resolution keeps one branch change alive"
git checkout -q -B resolved "$base"
edit 20 "line20-BRANCH"
edit 39 "line39-BRANCH"
git commit -qam "branch edits lines 20 and 39

Spec-Impact: none"
if git merge --no-commit --no-ff "$main_tip" >/dev/null 2>&1; then
  echo "  SETUP BROKEN: expected a conflict on line 20"; rc=1
else
  # Take the base's line 20 but keep the branch's line 39, so the file still
  # differs from the base and the violation still has something to fire on.
  awk 'NR==20 {print "line20-MAIN"; next}
       NR==39 {print "line39-BRANCH"; next}
       /^(<<<<<<<|=======|>>>>>>>)/ {next}
       {print}' src.txt > src.next
  mv src.next src.txt
  git add src.txt
  git commit -qm "Merge branch 'main' into resolved"
  if assert_merge_commit; then
    if git diff --quiet "$main_tip" HEAD -- src.txt; then
      echo "  SETUP BROKEN: the resolution discarded every branch change"; rc=1
    fi
    verdict 1 "a hand-resolved conflict is a contribution and certifies itself"
  fi
fi

echo "E) source name that git would read as pathspec MAGIC, clean base-sync merge"
# A source whose name starts with ':' is a legal path, and `diff --name-only`
# prints it unquoted so it reaches the ownership map — but without
# GIT_LITERAL_PATHSPECS git reads it as pathspec magic, `log -- <path>` matches
# no commit, and the escape is refused on a merge that deserved it. The gate is
# fail-closed there, so the symptom is a FAIL nobody can explain, not a leak.
git checkout -q -B magic "$base"
printf -- '---\nsources:\n  primary:\n    - :magic.txt\n---\n\n# m\n' > openspec/specs/x/spec.md
seq 1 40 | sed 's/^/line/' > ':magic.txt'
git add -A >/dev/null 2>&1
git commit -qm "fixture: a source git would read as pathspec magic"
magic_base="$(git rev-parse HEAD)"
awk 'NR==20{print "line20-MAIN"; next} {print}' ':magic.txt' > src.next && mv src.next ':magic.txt'
git commit -qam "base edits line 20 of the magic-named source"
magic_main="$(git rev-parse HEAD)"
git checkout -q -B magic-branch "$magic_base"
awk 'NR==39{print "line39-BRANCH"; next} {print}' ':magic.txt' > src.next && mv src.next ':magic.txt'
git commit -qam "branch edits line 39 of the magic-named source

Spec-Impact: none"
if git merge -q --no-edit "$magic_main" -m "Merge into magic-branch" >/dev/null 2>&1; then
  if [ "$(git rev-list --parents -n1 HEAD | wc -w | tr -d ' ')" != 3 ]; then
    echo "  SETUP BROKEN: HEAD is not a two-parent merge"; rc=1
  else
    # `--base` needs a ref, and this scenario's base line is not `main`.
    git branch -f magic-main "$magic_main"
    got=0
    out="$(python3 "$gate" --base magic-main 2>&1)" || got=$?
    if [ "$got" = 0 ]; then
      echo "  PASS  a magic-named source is treated as a literal path (exit 0)"
    else
      echo "  FAIL  a magic-named source is treated as a literal path (exit $got, expected 0)"
      printf '%s\n' "$out" | sed 's/^/          /'
      rc=1
    fi
  fi
else
  echo "  SETUP BROKEN: the base-sync merge conflicted"; git merge --abort || true; rc=1
fi

if [ "$rc" = 0 ]; then
  echo "staleness-gate bite-check OK: merge attribution holds in both directions"
else
  echo "ERROR: staleness-gate bite-check — the merge-attribution rule regressed" >&2
fi
exit "$rc"
