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
#   too lax    — a merge that CONTRIBUTED content (hand-resolved conflict, evil
#                merge, a mode flip) inherits someone else's trailer and ships
#                an uncertified behavior change.
#
# Neither direction is observable from the repo's own history: it has one shape
# at a time. So the rule is bound here against a purpose-built throwaway repo,
# the same way `task spec:validate` binds the strict validator against a
# committed malformed fixture.
#
# Three disciplines the scenarios below follow, each of which caught a real
# defect while this file was written:
#
#   1. Every scenario asserts the git state it claims to have built BEFORE
#      reading a verdict, so it cannot pass because its setup silently failed.
#   2. Every scenario asserts the gate's VERDICT LINE, not just its exit code —
#      exit 0 is emitted both for "no violation at all" and for "violation
#      escaped", and an uncaught Python exception also exits 1.
#   3. Each direction of the rule needs a scenario on BOTH sides. A red case
#      alone is satisfied by implementations that are wrong in the other
#      direction (C2 without C3 is passed by a mode-vs-parent1 comparison).
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
# Local-only, and deliberately more than identity: every setting here is one a
# scenario's outcome depends on, so an operator's global config cannot turn a
# rule regression into a pass or a false failure.
git config user.email bite@example.invalid
git config user.name "staleness bite-check"
git config commit.gpgsign false
git config core.fileMode true          # C2/C3 compare recorded file modes
git config merge.conflictStyle merge   # D strips markers; diff3 adds |||||||

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

rc=0

edit() { # edit <line-number> <replacement-text>
  if [ "$(wc -l < src.txt)" -lt "$1" ]; then
    echo "  SETUP BROKEN: src.txt has no line $1"; rc=1; return 1
  fi
  awk -v n="$1" -v t="$2" 'NR==n{print t; next} {print}' src.txt > src.next
  mv src.next src.txt
  if git diff --quiet -- src.txt && git diff --cached --quiet -- src.txt; then
    echo "  SETUP BROKEN: editing line $1 changed nothing"; rc=1; return 1
  fi
}

assert_merge_commit() { # assert_merge_commit [expected-parent-count]
  local want="${1:-2}" got
  got=$(( $(git rev-list --parents -n1 HEAD | wc -w | tr -d ' ') - 1 ))
  if [ "$got" != "$want" ]; then
    echo "  SETUP BROKEN: HEAD has $got parent(s), expected $want"; rc=1; return 1
  fi
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "  SETUP BROKEN: unresolved index"; rc=1; return 1
  fi
}

# verdict <expected-exit> <expected-verdict-pattern> <label> [base-ref]
# The pattern pins WHICH exit-0 (or exit-1) state the gate reached:
#   'no owning spec left untouched' — no violation at all
#   'escaped per-commit'            — violation, escape granted
#   'FAIL stale spec'               — violation, escape refused
verdict() {
  local want="$1" pattern="$2" label="$3" ref="${4:-main}" got=0 out
  out="$(python3 "$gate" --base "$ref" 2>&1)" || got=$?
  if [ "$got" != "$want" ]; then
    echo "  FAIL  $label (exit $got, expected $want)"
    printf '%s\n' "$out" | sed 's/^/          /'; rc=1; return
  fi
  if ! printf '%s\n' "$out" | grep -q "$pattern"; then
    echo "  FAIL  $label (exit $got as expected, but no '$pattern' in the verdict)"
    printf '%s\n' "$out" | sed 's/^/          /'; rc=1; return
  fi
  echo "  PASS  $label (exit $got, '$pattern')"
}

sync_merge() { # sync_merge <label> [tip] — merge the base line in, conflict-free
  local tip="${2:-$main_tip}"
  if ! git merge -q --no-edit "$tip" -m "Merge into $1" >/dev/null 2>&1; then
    echo "  SETUP BROKEN: the base-sync merge conflicted"; git merge --abort || true; rc=1; return 1
  fi
}

git checkout -q main
edit 2 "line2-MAIN"
edit 20 "line20-MAIN"
git commit -qam "base branch edits lines 2 and 20"
main_tip="$(git rev-parse HEAD)"

# --- Controls run FIRST and need no `merge-tree`, so they still execute on a git
# --- too old for the merge probe below. A non-zero exit from any merge scenario
# --- is only evidence about attribution if the gate is otherwise working here.
echo "control-1) owning spec touched in the same diff — no trailer needed"
git checkout -q -B control-clean "$main_tip"
edit 39 "line39-BRANCH"
printf '\nchanged\n' >> openspec/specs/x/spec.md
git commit -qam "edit the source and its owning spec"
committed="$(git show --name-only --format= HEAD | sort | tr '\n' ' ')"
if [ "$committed" != "openspec/specs/x/spec.md src.txt " ]; then
  echo "  SETUP BROKEN: commit carries [$committed], expected both fixture paths"; rc=1
fi
verdict 0 "no owning spec left untouched" "gate passes when the owning spec moves with the source"

echo "control-2) uncertified source change — the gate must bite"
git checkout -q -B control-biting "$main_tip"
edit 39 "line39-BRANCH"
git commit -qam "edit the source with no trailer and no spec touch"
verdict 1 "FAIL stale spec" "gate still fails an uncertified change"

echo "control-3) trailer in the SUBJECT, not the body — must not escape"
git checkout -q -B subject-trailer "$main_tip"
edit 39 "line39-BRANCH"
git commit -qam "Spec-Impact: none"
verdict 1 "FAIL stale spec" "a subject-line trailer does not certify"

echo "control-4) trailer as a substring of a longer body line — must not escape"
git checkout -q -B substring-trailer "$main_tip"
edit 39 "line39-BRANCH"
git commit -qam "edit the source

Spec-Impact: none of the rendered output changed"
verdict 1 "FAIL stale spec" "a substring mention does not certify"

if ! git merge-tree --write-tree HEAD HEAD >/dev/null 2>&1; then
  echo "SKIP: $(git --version) has no 'merge-tree --write-tree' (needs git >= 2.38)."
  echo "SKIP: the four controls above ran; the merge-attribution scenarios did not."
  echo "SKIP: without the flag the gate treats every merge as a contributor —"
  echo "SKIP: fail-CLOSED, so it is stricter than intended here, never laxer."
  if [ -n "${CI:-}" ]; then
    echo "ERROR: CI git must support 'merge-tree --write-tree' — the merge-attribution" >&2
    echo "ERROR: rule would go unbound and nothing else in the repo binds it." >&2
    exit 2
  fi
  [ "$rc" = 0 ] && echo "staleness-gate bite-check PARTIAL: controls pass, merge scenarios skipped"
  exit "$rc"
fi

# --- Too-strict direction: base-sync merges must not void the escape.
echo "A) base-sync merge, branch edit FAR from the base's edits"
git checkout -q -B sync-far "$base"
edit 39 "line39-BRANCH"
git commit -qam "branch edits line 39

Spec-Impact: none"
if sync_merge sync-far && assert_merge_commit; then
  # A's combined diff IS empty, which is what makes the pair A/B a two-sided
  # discriminator against a `diff-tree --cc`-emptiness test rather than a
  # one-sided threshold.
  cc_far="$(git diff-tree --cc --no-commit-id HEAD -- src.txt | wc -l | tr -d ' ')"
  if [ "$cc_far" -ne 0 ]; then
    echo "  SETUP BROKEN: A's combined diff is not empty ($cc_far lines)"; rc=1
  fi
  verdict 0 "escaped per-commit" "far-apart base-sync merge keeps the escape"
fi

# B is not extra branch coverage — it runs A's code path. It is the regression
# lock against reintroducing the cheaper `diff-tree --cc`-emptiness test.
echo "B) regression lock vs --cc: base-sync merge, edits 3 lines apart, SHARED hunk"
git checkout -q -B sync-near "$base"
edit 23 "line23-BRANCH"
git commit -qam "branch edits line 23

Spec-Impact: none"
if sync_merge sync-near && assert_merge_commit; then
  cc_near="$(git diff-tree --cc --no-commit-id HEAD -- src.txt | wc -l | tr -d ' ')"
  if [ "$cc_near" -eq 0 ]; then
    echo "  SETUP BROKEN: combined diff is empty — scenario B no longer discriminates"; rc=1
  fi
  verdict 0 "escaped per-commit" "shared-hunk base-sync merge keeps the escape (--cc: $cc_near lines)"
fi

echo "C3) base side flips the MODE, branch does not — the sync merge must be skipped"
# C2's green counterpart, and the reason it exists: without it, a comparison of
# `mode vs parent1` instead of `mode vs the mechanical merge` passes every other
# scenario, yet would count every open PR's forced base-sync merge as a
# contributor the moment main fixes an exec bit on a spec-owned source.
# The mode flip must land ON the base ref, not on a side branch: a commit inside
# `base..HEAD` needs its own trailer, so putting it on a branch would make this
# scenario fail for a reason that has nothing to do with mode attribution.
git checkout -q -B modebase "$main_tip"
chmod +x src.txt
git add src.txt
git commit -qm "base side makes the source executable"
modebase_tip="$(git rev-parse HEAD)"
git branch -f mode-main "$modebase_tip"
git checkout -q -B modebase-branch "$main_tip"
edit 39 "line39-BRANCH"
git commit -qam "branch edits line 39

Spec-Impact: none"
if sync_merge modebase-branch "$modebase_tip" && assert_merge_commit; then
  m_head="$(git ls-tree HEAD -- src.txt | awk '{print $1}')"
  m_p1="$(git ls-tree HEAD^1 -- src.txt | awk '{print $1}')"
  if [ "$m_head" != "100755" ] || [ "$m_p1" != "100644" ]; then
    echo "  SETUP BROKEN: expected 100755 at HEAD over 100644 at parent1, got $m_head over $m_p1"; rc=1
  fi
  verdict 0 "escaped per-commit" "mode propagated from the base side keeps the escape ($m_p1 -> $m_head)" mode-main
fi

# --- Too-lax direction: a merge that contributed content certifies itself.
echo "C) evil merge — clean auto-merge, then the merge invents an unrelated line"
git checkout -q -B evil "$base"
edit 39 "line39-BRANCH"
git commit -qam "branch edits line 39

Spec-Impact: none"
if git merge --no-commit --no-ff "$main_tip" >/dev/null 2>&1; then
  edit 10 "line10-INVENTED-BY-THE-MERGE"
  git add src.txt
  git commit -qm "Merge branch 'main' into evil"
  assert_merge_commit && verdict 1 "FAIL stale spec" "evil merge must not inherit another commit's trailer"
else
  echo "  SETUP BROKEN: expected a clean auto-merge"; git merge --abort || true; rc=1
fi

echo "C2) merge flips only the FILE MODE — same blob id, different tree entry"
git checkout -q -B modeflip "$base"
edit 39 "line39-BRANCH"
git commit -qam "branch edits line 39

Spec-Impact: none"
if git merge --no-commit --no-ff "$main_tip" >/dev/null 2>&1; then
  chmod +x src.txt
  git add src.txt
  git commit -qm "Merge branch 'main' into modeflip"
  if assert_merge_commit; then
    mode_now="$(git ls-tree HEAD -- src.txt | awk '{print $1}')"
    mode_parent="$(git ls-tree HEAD^1 -- src.txt | awk '{print $1}')"
    if [ "$mode_now" = "$mode_parent" ]; then
      echo "  SETUP BROKEN: the merge did not change the file mode ($mode_now)"; rc=1
    fi
    verdict 1 "FAIL stale spec" "a mode-only merge contribution certifies itself ($mode_parent -> $mode_now)"
  fi
else
  echo "  SETUP BROKEN: expected a clean auto-merge"; git merge --abort || true; rc=1
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
  # Rebuild the resolution from the base file rather than editing the conflicted
  # one by line number: stripping marker lines shifts every later line, so
  # NR-based edits land on the wrong content.
  git show "${base}:src.txt" | awk 'NR==2  {print "line2-MAIN";   next}
                                    NR==20 {print "line20-MAIN";  next}
                                    NR==39 {print "line39-BRANCH"; next}
                                    {print}' > src.next
  mv src.next src.txt
  git add src.txt
  git commit -qm "Merge branch 'main' into resolved"
  if assert_merge_commit; then
    # Assert the resolution positively: leftover conflict markers would satisfy
    # a mere "differs from the base side" check while the label claims a real
    # resolution.
    if [ "$(awk 'NR==20' src.txt)" != "line20-MAIN" ] ||
       [ "$(awk 'NR==39' src.txt)" != "line39-BRANCH" ] ||
       grep -qE '^(<<<<<<<|\|\|\|\|\|\|\||=======|>>>>>>>)' src.txt; then
      echo "  SETUP BROKEN: the resolution is not the one this scenario claims"; rc=1
    fi
    verdict 1 "FAIL stale spec" "a hand-resolved conflict is a contribution and certifies itself"
  fi
fi

echo "D2) conflict 'resolved' by committing the markers verbatim — must not escape"
# This is what binds the `rc != 0` guard in merge_invented_content. Verified:
# on a conflict `merge-tree --write-tree` exits 1 but still PRINTS a valid tree,
# so without that guard the comparison would run against the conflict-marker
# blob — and this merge records exactly that blob, so it would compare EQUAL and
# be skipped. A careless resolution is the realistic path to it.
git checkout -q -B markers "$base"
edit 20 "line20-BRANCH"
git commit -qam "branch edits line 20

Spec-Impact: none"
if git merge --no-commit --no-ff "$main_tip" >/dev/null 2>&1; then
  echo "  SETUP BROKEN: expected a conflict on line 20"; rc=1
else
  git add src.txt   # stage the conflicted content as-is
  git commit -qm "Merge branch 'main' into markers"
  if assert_merge_commit; then
    if ! grep -qE '^(<<<<<<<|=======|>>>>>>>)' src.txt; then
      echo "  SETUP BROKEN: no conflict markers were committed"; rc=1
    fi
    verdict 1 "FAIL stale spec" "committed conflict markers do not inherit a trailer"
  fi
fi

echo "E) delete/modify merge, resolved by keeping the file AND changing it further"
# The delete dimension: the path is absent on one side of the mechanical merge.
#
# Two facts constrain what this scenario can be. First, git's mechanical
# resolution of delete/modify KEEPS the modified file, so merely keeping it
# contributes nothing and is correctly escaped — the earlier version of this
# scenario expected FAIL and was wrong, not the gate. Second, a resolution that
# instead DELETES the file is TREESAME to the deleting parent, so `git log`
# prunes the merge and the comparison never runs. A pure None-vs-entry
# comparison therefore looks structurally unreachable; what is reachable, and
# what this asserts, is keep-plus-modify.
git checkout -q -B deleter "$main_tip"
git rm -q src.txt
git commit -qm "base side deletes the source"
deleter_tip="$(git rev-parse HEAD)"
git checkout -q -B undelete "$main_tip"
edit 39 "line39-BRANCH"
git commit -qam "branch edits line 39

Spec-Impact: none"
if git merge --no-commit --no-ff "$deleter_tip" >/dev/null 2>&1; then
  echo "  SETUP BROKEN: expected a delete/modify conflict"; rc=1
else
  git checkout -q --ours -- src.txt 2>/dev/null || true
  edit 12 "line12-ADDED-BY-THE-RESOLUTION"
  git add src.txt
  git commit -qm "Merge the deletion, keeping the file and editing it"
  if assert_merge_commit; then
    if [ -z "$(git ls-tree HEAD -- src.txt)" ] || [ -n "$(git ls-tree HEAD^2 -- src.txt)" ]; then
      echo "  SETUP BROKEN: expected the path present at HEAD and absent on parent2"; rc=1
    fi
    verdict 1 "FAIL stale spec" "a resolution that keeps AND edits a deleted source certifies itself"
  fi
fi

echo "F) source name git would read as pathspec MAGIC, clean base-sync merge"
# A source whose name starts with ':' is a legal path and `diff --name-only`
# prints it unquoted, so it reaches the ownership map — but read as pathspec
# magic, `log -- <path>` matches no commit and the escape is refused on a merge
# that deserved it. Fail-closed, so the symptom is an unexplainable FAIL.
git checkout -q -B magic "$base"
printf -- '---\nsources:\n  primary:\n    - :magic.txt\n---\n\n# m\n' > openspec/specs/x/spec.md
seq 1 40 | sed 's/^/line/' > ':magic.txt'
git add -A >/dev/null 2>&1
git commit -qm "fixture: a source git would read as pathspec magic"
magic_base="$(git rev-parse HEAD)"
awk 'NR==20{print "line20-MAIN"; next} {print}' ':magic.txt' > m.next && mv m.next ':magic.txt'
git commit -qam "base edits line 20 of the magic-named source"
git branch -f magic-main HEAD
git checkout -q -B magic-branch "$magic_base"
awk 'NR==39{print "line39-BRANCH"; next} {print}' ':magic.txt' > m.next && mv m.next ':magic.txt'
git commit -qam "branch edits line 39 of the magic-named source

Spec-Impact: none"
if sync_merge magic-branch magic-main && assert_merge_commit; then
  verdict 0 "escaped per-commit" "a magic-named source is treated as a literal path" magic-main
fi

if [ "$rc" = 0 ]; then
  echo "staleness-gate bite-check OK: merge attribution holds in both directions"
else
  echo "ERROR: staleness-gate bite-check — the merge-attribution rule regressed" >&2
fi
exit "$rc"
